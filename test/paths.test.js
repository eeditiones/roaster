const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect
const fs = require('fs')

describe('Request methods on api/$op-er+ation*! route', function () {
    const route = 'api/$op-er+ation*!'
    const expectNotAllowed = (err) => expect(err.response.status).to.equal(405)
    const expectNotAllowedOrNotImplented = (err) => expect(err.response.status).to.be.oneOf([405, 501])

    const fail = (res) => expect.fail(res)

    it('should handle defined GET request', function () {
        return util.axios
            .get(route)
            .then((r) => expect(r.status).to.equal(200))
            .catch(fail)
    })

    it('should handle defined POST request', function () {
        return util.axios
            .post(route, {})
            .then((r) => expect(r.status).to.equal(200))
            .catch(fail)
    })

    it('should reject a HEAD request', function () {
        return util.axios.head(route).then(fail).catch(expectNotAllowed)
    })

    it('should reject a PUT request', function () {
        return util.axios.put(route).then(fail).catch(expectNotAllowed)
    })

    it('should reject a DELETE request', function () {
        return util.axios.delete(route).then(fail).catch(expectNotAllowed)
    })

    // please note that HTTP PATCH is available in
    // exist since v5.3.0 and after
    it('should reject a PATCH request', function () {
        return util.axios.patch(route).then(fail).catch(expectNotAllowedOrNotImplented)
    })

    // OPTIONS request is handled by Jetty and will not reach your controller,
    // nor roaster API
    it('should handle OPTIONS request ', function () {
        return util.axios
            .options(route)
            .then((r) => expect(r.status).to.equal(200))
            .catch(fail)
    })

    // exist DB does not handle custom request methods, which is why this will
    // return with error 501 instead
    it('should reject a request with method "wibbley-wobbley"', function () {
        return util.axios
            .request({
                url: 'api/$op-er+ation*!',
                method: 'wibbley-wobbley'
            })
            .then(fail)
            .catch(expectNotAllowedOrNotImplented)
    })
})

describe('Prefixed known path', function () {
    it('should return a not found error', function () {
        return util.axios
            .get('not/api/parameters')
            .then((response) => {
                throw { response }
            })
            .catch((error) => {
                expect(error.response.status).to.equal(404)
            })
    })
})

describe('Request body', function () {
    it('uploads string in body', async function () {
        const res = await util.axios.post('api/$op-er+ation*!')
        expect(res.status).to.equal(200)
    })
})

describe('Query parameters in GET request', function () {
    const params = {
        num: 165.75,
        int: 776,
        bool: true,
        string: '&a=2 2'
    }
    const headers = {
        'X-start': 22
    }

    let res, parameters

    before(async function () {
        res = await util.axios.get('api/parameters', {
            params,
            headers
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

    it('handles date parameters', async function () {
        const res = await util.axios.get('api/dates', {
            params: {
                date: '2020-11-24Z',
                dateTime: '2020-11-24T20:22:41.975Z'
            }
        })
        expect(res.status).to.equal(200)
        expect(res.data).to.be.true
    })
})

describe('Query parameters with an empty value', function () {
    const getError = async (request) => {
        try {
            await request
        } catch (e) {
            return e.response
        }
        expect.fail('request should have been rejected')
    }

    const getEmpty = (params) => util.axios.get('api/parameters/empty', { params })

    it('treats an empty value as unused when allowEmptyValue is true', async function () {
        const res = await getEmpty({ unusedString: '', unusedInt: '', unusedArray: '' })
        expect(res.status).to.equal(200)
        const { parameters } = res.data
        expect(parameters.unusedString).to.equal('abcdefg')
        expect(parameters.unusedInt).to.be.null
        expect(parameters.unusedArray).to.deep.equal([1])
    })

    it('treats repeated empty values as unused when allowEmptyValue is true', async function () {
        const res = await util.axios.get('api/parameters/empty?unusedArray=&unusedArray=')
        expect(res.status).to.equal(200)
        expect(res.data.parameters.unusedArray).to.deep.equal([1])
    })

    it('passes non-empty values when allowEmptyValue is true', async function () {
        const res = await getEmpty({ unusedString: 'xyz', unusedInt: 3 })
        expect(res.status).to.equal(200)
        expect(res.data.parameters.unusedString).to.equal('xyz')
        expect(res.data.parameters.unusedInt).to.equal(3)
    })

    it('ignores allowEmptyValue for styles that cannot serialize an empty value', async function () {
        const res = await getEmpty({ spaceArray: '' })
        expect(res.status).to.equal(200)
        // the default would apply if the empty value counted as unused
        expect(res.data.parameters.spaceArray).to.be.null
    })

    it('passes an empty string when allowEmptyValue is not set', async function () {
        const res = await getEmpty({ emptyString: '' })
        expect(res.status).to.equal(200)
        expect(res.data.parameters.emptyString).to.equal('')
    })

    it('rejects an empty integer when allowEmptyValue is not set', async function () {
        const res = await getError(getEmpty({ emptyInt: '' }))
        expect(res.status).to.equal(400)
        expect(res.data.description).to.include('query-parameter "emptyInt" could not be cast to integer')
    })

    it('rejects an empty value for a required parameter when allowEmptyValue is true', async function () {
        const res = await getError(util.axios.get('api/parameters/empty/required', { params: { required: '' } }))
        expect(res.status).to.equal(400)
        expect(res.data.description).to.include('Required query-parameter "required" missing or empty.')
    })
})

describe('Parameter locations', function () {
    const getError = async (request) => {
        try {
            await request
        } catch (e) {
            return e.response
        }
        expect.fail('request should have been rejected')
    }

    it('rejects a location not defined by the specification', async function () {
        const res = await getError(util.axios.get('api/parameters/location/unknown', { params: { misplaced: 'a' } }))
        expect(res.status).to.equal(500)
        expect(res.data.description).to.include('Unknown location "body" for parameter "misplaced".')
    })

    it('reports the querystring location as not implemented', async function () {
        const res = await getError(util.axios.get('api/parameters/location/querystring?a=b'))
        expect(res.status).to.equal(501)
        expect(res.data.description).to.include('Unsupported location "querystring" for parameter "whole".')
    })
})

describe('Date-time and HTTP-date parameters', function () {
    const getError = async (request) => {
        try {
            await request
        } catch (e) {
            return e.response
        }
        expect.fail('request should have been rejected')
    }

    const ifModifiedSince = (value) =>
        util.axios.get('api/if-modified-since', {
            headers: { 'If-Modified-Since': value }
        })

    it('parses an HTTP-date header into xs:dateTime', async function () {
        const res = await ifModifiedSince('Tue, 24 Nov 2020 20:22:41 GMT')
        expect(res.status).to.equal(200)
        expect(res.data).to.equal('2020-11-24T20:22:41Z')
    })

    it('rejects gibberish in an HTTP-date header with 400', async function () {
        const res = await getError(ifModifiedSince('not a date at all'))
        expect(res.status).to.equal(400)
        expect(res.data.description).to.include('header-parameter "If-Modified-Since" could not be cast to http-date')
    })

    it('rejects an HTTP-date in a date-time parameter with 400', async function () {
        const res = await getError(
            util.axios.get('api/dates', {
                params: {
                    date: '2020-11-24Z',
                    dateTime: 'Tue, 24 Nov 2020 20:22:41 GMT'
                }
            })
        )
        expect(res.status).to.equal(400)
        expect(res.data.description).to.include('query-parameter "dateTime" could not be cast to date-time')
    })
})

describe('Query parameters in POST request', function () {
    const params = {
        num: 165.75,
        int: 776,
        bool: true,
        string: '&a=2 2'
    }
    const headers = {
        'X-start': 22
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

describe('Route regex anchoring (regression for #122)', function () {
    const getError = async (request) => {
        try {
            await request
        } catch (e) {
            return e.response
        }
        expect.fail('request should have been rejected')
    }

    it('matches the exact route', async function () {
        const res = await util.axios.get('api/patients')
        expect(res.status).to.equal(200)
    })

    it('matches the exact route with a trailing slash', async function () {
        const res = await util.axios.get('api/patients/')
        expect(res.status).to.equal(200)
    })

    it('does not match a request path with a superfluous suffix', async function () {
        const res = await getError(util.axios.get('api/patients12345'))
        expect(res.status).to.equal(404)
    })

    it('does not match a deeper sub-path of an exact route', async function () {
        const res = await getError(util.axios.get('api/dates/v0.2'))
        expect(res.status).to.equal(404)
    })

    it('lets the sibling parameterized route win for /api/patients/123', async function () {
        const res = await util.axios.get('api/patients/123')
        expect(res.status).to.equal(200)
        expect(res.data.parameters.id).to.equal('123')
    })

    it('rejects a fixed-suffix route with a superfluous suffix (/api/{test}/test)', async function () {
        const res = await getError(util.axios.get('api/foo/testXXX'))
        expect(res.status).to.equal(404)
    })

    it('still allows the greedy last path parameter to match embedded slashes', async function () {
        // this must fail inside the handler (file not found), not at the router level
        const res = await getError(util.axios.get('api/paths/sub/dir/file.txt'))
        expect(res.status).to.equal(404)
        expect(res.data.description).to.not.contain('No route matches pattern')
    })
})
