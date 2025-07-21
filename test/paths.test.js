const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect
const fs = require('fs')

describe('Request methods on api/$op-er+ation*! route', function (){
    const route = 'api/$op-er+ation*!'
    const expectNotAllowed = err => expect(err.response.status).to.equal(405)
    const expectNotAllowedOrNotImplented = err => expect(err.response.status).to.be.oneOf([405, 501])

    const fail = res => expect.fail(res)

    it('should handle defined GET request', function () {
        return util.axios.get(route)
            .then(r => expect(r.status).to.equal(200))
            .catch(fail)
    })

    it('should handle defined POST request', function () {
        return util.axios.post(route, {})
            .then(r => expect(r.status).to.equal(200))
            .catch(fail)
    })

    it('should reject a HEAD request', function () {
        return util.axios.head(route)
            .then(fail)
            .catch(expectNotAllowed)
    })

    it('should reject a PUT request', function () {
        return util.axios.put(route)
            .then(fail)
            .catch(expectNotAllowed)
    })

    it('should reject a DELETE request', function () {
        return util.axios.delete(route)
            .then(fail)
            .catch(expectNotAllowed)
    })

    // please note that HTTP PATCH is available in 
    // exist since v5.3.0 and after
    it('should reject a PATCH request', function () {
        return util.axios.patch(route)
            .then(fail)
            .catch(expectNotAllowedOrNotImplented)
    })

    // OPTIONS request is handled by Jetty and will not reach your controller,
    // nor roaster API
    it('should handle OPTIONS request ', function () {
        return util.axios.options(route)
            .then(r => expect(r.status).to.equal(200))
            .catch(fail)
    })

    // exist DB does not handle custom request methods, which is why this will
    // return with error 501 instead
    it('should reject a request with method "wibbley-wobbley"', function () {
        return util.axios.request({
            url: 'api/$op-er+ation*!',
            method: 'wibbley-wobbley'
        })
            .then(fail)
            .catch(expectNotAllowedOrNotImplented)
    })
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
    const contents = fs.readFileSync("./dist/roasted.xar")

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

describe('Query parameters in GET request', function () {
    const params = {
        'num': 165.75,
        'int': 776,
        'bool': true,
        'string': '&a=2 2',
        'array-string-form-not-explode' : 'blue,black',
        'array-string-form-explode' : ['green', 'red'],
        'array-integer-form-not-explode' : '1,2',
        'array-integer-form-explode' : ['10', '20']
    }
    const headers = {
        "X-start": 22
    }

    let res, parameters

    before(async function () {
        res = await util.axios.get('api/parameters', {
            params,
            headers,
            paramsSerializer: {
                indexes: null // by default: false
              }
        })
        parameters = res?.data?.parameters
    })

    it('the query succeeds', async function () {
        expect(res.status).to.equal(200)
    })

    it('passes query parameters', async function () {
        expect(parameters.num).to.be.a('number')
        expect(parameters.num).to.equal(params.num)
        expect(parameters.bool).to.be.a('boolean')
        expect(parameters.bool).to.equal(params.bool)
        expect(parameters.int).to.be.a('number')
        expect(parameters.int).to.equal(params.int)
        expect(parameters.string).to.equal(params.string)
    })

    it('passes header', async function () {
        expect(parameters['X-start']).to.equal(headers['X-start'])
    })

    it('adds default parameter', async function () {
        expect(parameters.defaultParam).to.equal('abcdefg')
    })

    it('paremeter array-string-form-not-explode is parsed correctly', async function () {
        const p = parameters['array-string-form-not-explode']
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['blue','black'])
    })

    it('paremeter array-string-form-explode is parsed correctly', async function () {
        const p = parameters['array-string-form-explode']
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['green','red'])
    })

    it('paremeter array-integer-form-not-explode is parsed correctly', async function () {
        const p = parameters['array-integer-form-not-explode']
        expect(p).to.be.an('array')
        expect(p).to.deep.equal([1,2])
    })

    it('paremeter array-integer-form-explode is parsed correctly', async function () {
        const p = parameters['array-integer-form-explode']
        expect(p).to.be.an('array')
        expect(p).to.deep.equal([10,20])
    })

    it('handles date parameters', async function () {
        const res = await util.axios.get('api/dates', {
            params: {
                date: "2020-11-24Z",
                dateTime: "2020-11-24T20:22:41.975Z"
            }
        })
        expect(res.status).to.equal(200)
        expect(res.data).to.be.true
    })

});

describe('Query parameters in POST request', function () {
    const params = {
        'num': 165.75,
        'int': 776,
        'bool': true,
        'string': '&a=2 2',
        'array-string-form-not-explode' : 'blue,black',
        'array-string-form-explode' : ['green', 'red'],
        'array-integer-form-not-explode' : '1,2',
        'array-integer-form-explode' : ['10', '20']
    }
    const headers = {
        "X-start": 22
    }

    let res, parameters

    before(async function () {
        res = await util.axios.request({
            url: 'api/parameters',
            method: 'post',
            params,
            headers
        })
        parameters = res?.data?.parameters
    })

    it('the query succeeds', async function () {
        expect(res.status).to.equal(200)
    })

    it('passes body parameters', async function () {
        expect(parameters.num).to.be.a('number')
        expect(parameters.num).to.equal(params.num)
        expect(parameters.bool).to.be.a('boolean')
        expect(parameters.bool).to.equal(params.bool)
        expect(parameters.int).to.be.a('number')
        expect(parameters.int).to.equal(params.int)
        expect(parameters.string).to.equal(params.string)
    })

    it('passes header', async function () {
        expect(parameters['X-start']).to.equal(headers['X-start'])
    })

    it('adds default parameter', async function () {
        expect(parameters.defaultParam).to.equal('abcdefg')
    })
})

describe('with percent encoded value in path', function () {
    const url = 'api/test%20and%20test/test'
    let res

    before(async function () {
        res = await util.axios.get(url)
    })

    it('URL + "' + url + '" resolves', async function () {
        expect(res.status).to.equal(200)
    })

    it('passes query parameters in GET', async function () {
        expect(res.data.parameters.test).to.equal('test and test')
    })
})
