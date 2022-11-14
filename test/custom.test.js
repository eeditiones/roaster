const util = require('./util.js');
const path = require('path');
const fs = require('fs');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator').default;

const spec = path.resolve("./test/app/api-jwt.json");
chai.use(chaiResponseValidator(spec));

describe('public route with custom middleware', function () {
    const pathParameter = '1/2/this/is/just/a/test'
    let publicRouteResult

    before(async function () {
        publicRouteResult = await util.axios.get('jwt/public/' + pathParameter)
    })

    it('should return with status 200', function () {
        expect(publicRouteResult.status).to.equal(200);
    })

    it('should return with header x-beep', function () {
        expect(publicRouteResult.headers['x-beep']).to.equal('boop');
    })

    it('should return with access control headers', function () {
        expect(publicRouteResult.headers['access-control-allow-origin']).to
            .equal('*')
        expect(publicRouteResult.headers['access-control-allow-credentials']).to
            .equal('true')
        expect(publicRouteResult.headers['access-control-allow-methods']).to
            .equal('GET, POST, DELETE, PUT, PATCH, OPTIONS')
        expect(publicRouteResult.headers['access-control-allow-headers']).to
            .equal('Accept, Content-Type, Authorization, X-Auth-Token')
    })

})

describe('request authorization token without credentials', function () {
    it('should return unauthorized', function () {
        return util.axios.get('jwt/test/is-dba')
            .then(response => { throw {response} })
            .catch(error => {
                expect(error.response.status).to.equal(401)
            });
    });
});

describe('jwt authorization with an empty token', function () {
    let authorizeWithEmptyTokenResponse

    before(function () {
        return util.axios.get('jwt/test/is-dba', {
            headers: { 'X-Auth-Token': "" }
        })
        .then(response => { throw {response} })
        .catch(error => {
            authorizeWithEmptyTokenResponse = error.response
        });

    })

    it('should return status code for bad request', function () {
        expect(authorizeWithEmptyTokenResponse.status).to.equal(400)
    })
    it('should have failed in authentication module', function () {
        expect(authorizeWithEmptyTokenResponse.data.module).to.equal('/db/apps/roasted/modules/jwt-auth.xqm')
    })
    it('should return status code for bad request', function () {
        expect(authorizeWithEmptyTokenResponse.data.description).to.contain('token invalid')
    })

});

describe('jwt authorization with an invalid token', function () {
    let authorizeWithEmptyTokenResponse

    before(function () {
        return util.axios.get('jwt/test/is-dba', {
            headers: { 'X-Auth-Token': "asdfas3aesfl34.asdfas" }
        })
        .then(response => { throw {response} })
        .catch(error => {
            authorizeWithEmptyTokenResponse = error.response
        });

    })

    it('should return status code for bad request', function () {
        expect(authorizeWithEmptyTokenResponse.status).to.equal(400)
    })
    it('should have failed in authentication module', function () {
        expect(authorizeWithEmptyTokenResponse.data.module).to.equal('/db/apps/roasted/modules/jwt-auth.xqm')
    })
    it('should return status code for bad request', function () {
        expect(authorizeWithEmptyTokenResponse.data.description).to.contain('token invalid')
    })

});

describe("requesting a token as admin", function () {
    let token
    let tokenRequestResponse
    let authenticationBody = util.adminCredentials

    before(async function () {
        tokenRequestResponse = await util.axios.post('jwt/token', authenticationBody)
        token = tokenRequestResponse.data.token
    })

    it('should return with status 201', function () {
        expect(tokenRequestResponse.status).to.equal(201)
    });
    it('should return a token', function () {
        expect(tokenRequestResponse.data.token).to.have.length.greaterThan(0)
    });
    it('should return claims', function () {
        expect(tokenRequestResponse.data.user).to.be.a("Object")
        expect(tokenRequestResponse.data.user.name).to.equal(authenticationBody.username)
    });

    describe("authorize with obtained token", function () {
        let authorizationTestResult

        before(async function () {
            authorizationTestResult = await util.axios.get('jwt/test/is-dba', {
                headers: { 'X-Auth-Token': token }
            });
        })

        it('should return with status 200', function () {
            expect(authorizationTestResult.status).to.equal(200);
        })
        it('should echo the authorized user in the response', function () {
            expect(authorizationTestResult.data.user.name).to.equal(authenticationBody.username);
        })
        it('authorized user should be member od DBA', function () {
            expect(authorizationTestResult.data.user.groups).to.contain('dba');
        })
        it('should also return with header x-beep', function () {
            expect(authorizationTestResult.headers['x-beep']).to.equal('boop');
        })
    
    })
});

describe("requesting a token as guest", function () {
    let guestToken
    let guestTokenRequestResponse
    let guestCredentials = { username: "guest", password: "guest" }

    before(async function () {
        guestTokenRequestResponse = await util.axios.post('jwt/token', guestCredentials)
        guestToken = guestTokenRequestResponse.data.token
    })

    it('should return with status 201', function () {
        expect(guestTokenRequestResponse.status).to.equal(201)
    });
    it('should return a token', function () {
        expect(guestTokenRequestResponse.data.token).to.have.length.greaterThan(0)
    });
    it('should return claims', function () {
        expect(guestTokenRequestResponse.data.user).to.be.a("Object")
        expect(guestTokenRequestResponse.data.user.name).to.equal(guestCredentials.username)
    });

    describe("authorize guest with obtained token on route constrained to members of DBA", function () {
        let authorizationAsGuestResult

        before(async function () {
            return util.axios.get('jwt/test/is-dba', {
                headers: { 'X-Auth-Token': guestToken }
            })
            .then(response => { throw {response} })
            .catch(error => {
                authorizationAsGuestResult = error.response
            });
        })

        // TODO: should probably be forbidden 403 instead
        it('should not allow the request', function () {
            expect(authorizationAsGuestResult.status).to.equal(401);
        })

        it('should fail in auth library module', function () {
            expect(authorizationAsGuestResult.data.module).to.contain('content/auth.xql');
        })
        it('should fail with a useful error message', function () {
            expect(authorizationAsGuestResult.data.description).to.contain('Access denied');
        })

        // authorization failure happens before middleware is evaluated
        it('does not include header x-beep', function () {
            expect(authorizationAsGuestResult.headers['x-beep']).to.be.undefined;
        })
    
    })
});
