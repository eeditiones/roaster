const util = require('./util.js');
const path = require('path');
const fs = require('fs');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator');

const spec = path.resolve("./test/app/api.json");
chai.use(chaiResponseValidator(spec));

describe('Requesting a static file from the server', function () {
    it('will download the resource', async function () {
        const res = await util.axios.get('static/roaster-router-logo.png');
        expect(res.status).to.equal(200);
    });
});

describe('Path parameters', function () {
    it('handles get of path including $', async function () {
        const res = await util.axios.get('api/$op-er+ation*!');
        expect(res.status).to.equal(200);
        // expect(res).to.satisfyApiSpec;
    });
});

describe('Request methods on api/$op-er+ation*! route', function (){
    const route = 'api/$op-er+ation*!'
    const expect405 = err => expect(err.response.status).to.equal(405)
    const fail = res => expect.fail(res)

    it('should handle defined GET request', function () {
        return util.axios.get(route)
            .then(r => expect(r.status).to.equal(200))
            .catch(fail)
    });

    it('should handle defined POST request', function () {
        return util.axios.post(route, {})
            .then(r => expect(r.status).to.equal(200))
            .catch(fail)
    });

    it('should reject a HEAD request', function () {
        return util.axios.head(route)
            .then(fail)
            .catch(expect405)
    });

    it('should reject a PUT request', function () {
        return util.axios.put(route)
            .then(fail)
            .catch(expect405)
    });

    it('should reject a DELETE request', function () {
        return util.axios.delete(route)
            .then(fail)
            .catch(expect405)
    });

    it('should reject a PATCH request', function () {
        return util.axios.patch(route)
            .then(fail)
            .catch(expect405)
    });

    // OPTIONS request is handled by Jetty and will not reach your controller,
    // nor roaster API
    it('should handle OPTIONS request ', function () {
        return util.axios.options(route)
            .then(r => expect(r.status).to.equal(200))
            .catch(fail)
    });

    // exist DB does not handle custom request methods, which is why this will
    // return with error 501 instead
    it('should reject a request with method "wibbley-wobbley"', function () {
        return util.axios.request({
            url: 'api/$op-er+ation*!',
            method: 'wibbley-wobbley'
        })
            .then(fail)
            .catch(err => expect(err.response.status).to.equal(501))
    });
})

describe('Prefixed known path', function () {
    it('should return a not found error', function () {
        return util.axios.get('not/api/parameters')
            .then(response => { throw {response} })
            .catch(error => {
                expect(error.response.status).to.equal(404)
            });
    });
});

describe("Binary up and download", function () {
    const contents = fs.readFileSync("./roasted.xar")

    describe("using basic authentication", function () {
        it('handles post of binary data', async function () {
            const res = await util.axios.post('api/paths/roasted.xar', contents, {
                headers: {
                    'Content-Type': 'application/octet-stream',
                    'Authorization': 'Basic YWRtaW46'
                }
            });
            expect(res.status).to.equal(201);
            expect(res.data).to.equal('/db/apps/roasted/roasted.xar');
        });
        it('passes parameter in last component of path', async function () {
            const res = await util.axios.get('api/paths/roasted.xar', { responseType: 'arraybuffer' });
            expect(res.status).to.equal(200);
            expect(res.data).to.eql(contents);

            // expect(res).to.satisfyApiSpec;
        });
    })

    describe("using cookie authentication", function () {
        const filename = "roasted2.xar"
        before(async function () {
            await util.login()
        })
        after(function () {
            return util.logout()
        })

        it('handles post of binary data', async function () {
            const res = await util.axios.post('api/paths/' + filename, contents, {
                headers: { 'Content-Type': 'application/octet-stream' }
            });
            expect(res.status).to.equal(201);
            expect(res.data).to.equal('/db/apps/roasted/' + filename);
        });
        it('passes parameter in last component of path', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' });
            expect(res.status).to.equal(200);
            expect(res.data).to.eql(contents);

            // expect(res).to.satisfyApiSpec;
        });
    })
});

describe("body with content-type application/xml", function () {
    before(async function () {
        await util.login()
    })
    after(function () {
        return util.logout()
    })

    describe("with valid content", function () {
        let uploadResponse
        before(function () {
            return util.axios.post('api/paths/valid.xml', Buffer.from('<root/>'), {
                headers: { 'Content-Type': 'application/xml' }
            })
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is accepted", function () {
            expect(uploadResponse.status).to.equal(201)
        })    
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(async function () {
            return util.axios.post('api/paths/invalid.xml', Buffer.from('<invalid>asdf'), {
                headers: { 'Content-Type': 'application/xml' }
            })
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is rejected", function () {
            expect(uploadResponse.status).to.equal(500)
        })        
    })
})

describe("body with content-type application/json", function () {
    before(async function () {
        await util.login()
    })
    after(function () {
        return util.logout()
    })

    describe("with valid content", function () {
        let uploadResponse
        before(function () {
            return util.axios.post(
                'api/paths/valid.txt', 
`
[{
    "valid": "json",
    "valid1": "json",
    "valid2": "json",
    "valid3": "json",
    "valid4": "json",
    "valid5": "json"
}]
`, 
                { headers: { 'Content-Type': 'application/octet-stream'} }
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is accepted", function () {
            console.log(uploadResponse)
            expect(uploadResponse.status).to.equal(201)
        })    
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(async function () {
            return util.axios.post('api/paths/invalid.json', '{ "invalid: ()}', {
                headers: { 'Content-Type': 'application/json' }
            })
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is rejected", function () {
            expect(uploadResponse.status).to.equal(500)
        })        
    })
})

describe('On Login', function () {
    let response

    before(async function () {
        await util.login()
        response = await util.axios.get('api/parameters', {})
    })

    it('public route can be called', function () {
        expect(response.status).to.equal(200);
    })

    it('user property is set on request map', function () {
        expect(response.data.user).to.be.a('object')
        expect(response.data.user.name).to.equal("admin")
        expect(response.data.user.dba).to.equal(true)
    })

    describe('On logout', function () {
        let logoutResponse
        let guestResponse
        before(async function () {
            logoutResponse = await util.axios.get('logout')
            guestResponse = await util.axios.get('api/parameters', {})
        })
        it('request returns true', function () {
            expect(logoutResponse.status).to.equal(200)
            expect(logoutResponse.data.success).to.equal(true)
        })
        it('public route sets guest as user', function () {
            expect(guestResponse.status).to.equal(200)
            expect(guestResponse.data.user.name).to.equal("guest")
            expect(guestResponse.data.user.dba).to.equal(false)
        })

    })
})

describe('Request body', function() {
    it('uploads string in body', async function() {
        const res = await util.axios.post('api/$op-er+ation*!');
        expect(res.status).to.equal(200);
    })
});

describe('Query parameters', function () {
    it('passes query parameters in GET', async function () {
        const res = await util.axios.get('api/parameters', {
            params: {
                num: 165.75,
                int: 776,
                bool: true,
                string: '&a=22'
            },
            headers: {
                "X-start": 22
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data.parameters.num).to.be.a('number');
        expect(res.data.parameters.num).to.equal(165.75);
        expect(res.data.parameters.bool).to.be.a('boolean');
        expect(res.data.parameters.bool).to.be.true;
        expect(res.data.parameters.int).to.be.a('number');
        expect(res.data.parameters.int).to.equal(776);
        expect(res.data.parameters.string).to.equal('&a=22');
        expect(res.data.parameters.defaultParam).to.equal('abcdefg');
        expect(res.data.parameters['X-start']).to.equal(22);
    });

    it('passes query parameters in POST', async function () {
        const res = await util.axios.request({
            url: 'api/parameters',
            method: 'post',
            params: {
                'num': 165.75,
                'int': 776,
                'bool': true,
                'string': '&a=22'
            },
            headers: {
                "X-start": 22
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data.method).to.equal('post');
        expect(res.data.parameters.num).to.be.a('number');
        expect(res.data.parameters.num).to.equal(165.75);
        expect(res.data.parameters.bool).to.be.a('boolean');
        expect(res.data.parameters.bool).to.be.true;
        expect(res.data.parameters.int).to.be.a('number');
        expect(res.data.parameters.int).to.equal(776);
        expect(res.data.parameters.string).to.equal('&a=22');
        expect(res.data.parameters.defaultParam).to.equal('abcdefg');
        expect(res.data.parameters['X-start']).to.equal(22);
    });

    it('handles date parameters', async function () {
        const res = await util.axios.get('api/dates', {
            params: {
                date: "2020-11-24Z",
                dateTime: "2020-11-24T20:22:41.975Z"
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data).to.be.true;
    });
});

describe('Error reporting', function() {
    it('receives error report', function() {
        return util.axios.get('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(404);
                expect(error.response.data.description).to.equal('document not found');
                expect(error.response.data.value).to.equal('error details');
            });
    });

    it('receives dynamic XQuery error', function() {
        return util.axios.post('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(500);
                expect(error.response.data.line).to.match(/\d+/);
                expect(error.response.data.description).to.contain('$undefined');
            });
    });

    it('receives explicit error', function() {
        return util.axios.delete('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(403);
                expect(error.response.headers['content-type']).to.equal('application/xml');
                expect(error.response.data).to.equal('<forbidden/>');
            });
    });

    it('calls error handler', function() {
        return util.axios.get('api/errors/handle')
            .catch(function(error) {
                expect(error.response.status).to.equal(500);
                expect(error.response.headers['content-type']).to.equal('text/html');
                expect(error.response.data).to.contain('$undefined');
            });
    });
});
