const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

// Regression test for eXist-db/exist#6491 (map keys compare by op:same-key, no cross-family coercion).
//
// router:get-content-type-for-code looks up the OpenAPI responses map - whose keys are strings
// ("200", "default") because it is parsed from the OpenAPI definition - by the integer status $code.
// Before #6491, eXist coerced the integer lookup key to the map's string key type, so 200 matched
// "200"; after #6491 it does not, so the lookup must use string($code). If this regresses, the
// response definition comes back empty, the content type falls back to application/xml, output:method
// is set to "xml", and a JSON response body (a map) is serialized as XML - surfacing as SENR0001.
//
// api:arrays-get returns a bare map { "parameters": ... } with no explicit response type, so the
// content type is negotiated solely from the numeric status code via get-content-type-for-code -
// exactly the path the bug breaks.
describe('response content type negotiated from the numeric status code (#6491 regression)', function () {
    let res
    before(async function () {
        res = await util.axios.get('api/arrays', {
            params: { piped: 'one|two' },
            paramsSerializer: { indexes: null }
        })
    })

    it('responds 200', function () {
        expect(res.status).to.equal(200)
    })

    it('negotiates application/json from the "200" response (not the application/xml fallback)', function () {
        expect(res.headers['content-type']).to.match(/application\/json/)
    })

    it('returns a parsed JSON object, not a map serialized as XML', function () {
        expect(res.data).to.be.an('object')
        expect(res.data.parameters).to.be.an('object')
    })
})
