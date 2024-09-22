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

describe('Request body', function() {
    it('uploads string in body', async function() {
        const res = await util.axios.post('api/$op-er+ation*!');
        expect(res.status).to.equal(200);
    })
});

describe('Query parameters', function () {
    const params = {
        'num': 165.75,
        'int': 776,
        'bool': true,
        'string': '&a=2 2'
    }
    const headers = {
        "X-start": 22
    }


    it('passes query parameters in GET', async function () {
        const res = await util.axios.get('api/parameters', {
            params,
            headers
        })
        expect(res.status).to.equal(200)
        expect(res.data.parameters.num).to.be.a('number')
        expect(res.data.parameters.num).to.equal(params.num)
        expect(res.data.parameters.bool).to.be.a('boolean')
        expect(res.data.parameters.bool).to.equal(params.bool)
        expect(res.data.parameters.int).to.be.a('number')
        expect(res.data.parameters.int).to.equal(params.int)
        expect(res.data.parameters.string).to.equal(params.string)

        expect(res.data.parameters['X-start']).to.equal(headers['X-start'])

        expect(res.data.parameters.defaultParam).to.equal('abcdefg')
    })

    it('passes query parameters in POST', async function () {
        const res = await util.axios.request({
            url: 'api/parameters',
            method: 'post',
            params,
            headers: {
                "X-start": 22
            }
        })

        expect(res.status).to.equal(200)
        expect(res.data.method).to.equal('post')
        expect(res.data.parameters.num).to.be.a('number')
        expect(res.data.parameters.num).to.equal(params.num)
        expect(res.data.parameters.bool).to.be.a('boolean')
        expect(res.data.parameters.bool).to.equal(params.bool)
        expect(res.data.parameters.int).to.be.a('number')
        expect(res.data.parameters.int).to.equal(params.int)
        expect(res.data.parameters.string).to.equal(params.string)

        expect(res.data.parameters['X-start']).to.equal(headers['X-start'])

        expect(res.data.parameters.defaultParam).to.equal('abcdefg')
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
