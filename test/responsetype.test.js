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

describe('Undeclared response status content-type resolution (#127)', function () {
    describe('operation declares only a success (200/application/json) response', function () {
        it('borrows the success content type when body is a map', function () {
            return util.axios.get('api/response-type/map').catch(function (error) {
                expect(error.response.status).to.equal(500)
                expect(error.response.headers['content-type']).to.equal('application/json')
                expect(error.response.data).to.deep.equal({ error: 'boom' })
            })
        })

        it('borrows the success content type when body is an array', function () {
            return util.axios.get('api/response-type/array').catch(function (error) {
                expect(error.response.status).to.equal(500)
                expect(error.response.headers['content-type']).to.equal('application/json')
                expect(error.response.data).to.deep.equal([1, 2, 3])
            })
        })

        it('borrows the success content type when body is a plain string', function () {
            // a bare string serializes fine under either method, so nothing
            // forces a fallback away from the operation's declared JSON success
            // response -- unlike the old hardcoded application/xml default,
            // this is no longer an arbitrary/coincidental choice.
            return util.axios.get('api/response-type/string').catch(function (error) {
                expect(error.response.status).to.equal(500)
                expect(error.response.headers['content-type']).to.equal('application/json')
            })
        })

        it('wraps an element body as {"error": ...} to keep the borrowed JSON content type', function () {
            // a node() body can't be serialized under the json output method
            // (it would silently atomize to a bare string, discarding the
            // markup), but reverting the whole response to XML would abandon
            // the content type the operation actually declared/negotiated.
            // Instead the markup is preserved, serialized, and wrapped under
            // a single "error" key -- still valid, parseable JSON.
            return util.axios.get('api/response-type/element').catch(function (error) {
                expect(error.response.status).to.equal(500)
                expect(error.response.headers['content-type']).to.equal('application/json')
                expect(error.response.data).to.deep.equal({ error: '<error>boom</error>' })
            })
        })

        it('still fails when an explicit XML media type is used with a map body', function () {
            // explicit media type always wins and is never reconciled against
            // the body: asking to serialize a map as XML remains a
            // deliberate, uncaught server error (eXist raises SENR0001 after
            // the response status/headers are already committed), so
            // roaster's JSON error envelope is never produced here. We only
            // assert this does NOT succeed and the map body is not delivered.
            // The content type is not asserted: eXist 7 (Jetty 12) renders its
            // own error page negotiated against the Accept header, which is
            // JSON for axios' default Accept.
            return util.axios
                .get('api/response-type/explicit-xml')
                .then(function () {
                    throw new Error('expected request to fail')
                })
                .catch(function (error) {
                    expect(error.response).to.exist
                    expect(error.response.status).to.not.equal(200)
                    const body = error.response.data
                    expect(typeof body === 'object' && body !== null && body.error === 'boom').to.be.false
                })
        })
    })

    describe('operation declares no responses at all', function () {
        it('negotiates application/xml when the client accepts anything (the default preference)', function () {
            return util.axios
                .get('api/response-type-no-spec/string', {
                    headers: { Accept: '*/*' }
                })
                .catch(function (error) {
                    expect(error.response.status).to.equal(500)
                    expect(error.response.headers['content-type']).to.equal('application/xml; charset=UTF-8')
                })
        })

        it('negotiates application/json when the client asks for it', function () {
            return util.axios
                .get('api/response-type-no-spec/string', {
                    headers: { Accept: 'application/json' }
                })
                .catch(function (error) {
                    expect(error.response.status).to.equal(500)
                    expect(error.response.headers['content-type']).to.equal('application/json')
                })
        })

        it('negotiates text/plain as a last resort when the client asks for it', function () {
            return util.axios
                .get('api/response-type-no-spec/string', {
                    headers: { Accept: 'text/plain' }
                })
                .catch(function (error) {
                    expect(error.response.status).to.equal(500)
                    expect(error.response.headers['content-type']).to.equal('text/plain;charset=utf-8')
                })
        })

        it('still reconciles to JSON for a map body even when negotiation would otherwise pick XML', function () {
            // Accept: */* now negotiates to application/xml by default, but a
            // map body can't be serialized with the xml output method, so it
            // is reconciled back to application/json regardless.
            return util.axios
                .get('api/response-type-no-spec/map', {
                    headers: { Accept: '*/*' }
                })
                .catch(function (error) {
                    expect(error.response.status).to.equal(500)
                    expect(error.response.headers['content-type']).to.equal('application/json')
                    expect(error.response.data).to.deep.equal({ error: 'boom' })
                })
        })

        it('serves an element body as plain XML when negotiation itself picks XML (now the default)', function () {
            // negotiation picks application/xml (the default when nothing is
            // declared and the client accepts anything) and the body is a
            // node(), so there is no mismatch to reconcile at all -- the
            // element is served as-is, unwrapped.
            return util.axios
                .get('api/response-type-no-spec/element', {
                    headers: { Accept: '*/*' }
                })
                .catch(function (error) {
                    expect(error.response.status).to.equal(500)
                    expect(error.response.headers['content-type']).to.equal('application/xml; charset=UTF-8')
                    expect(error.response.data).to.equal('<error>boom</error>')
                })
        })

        it('wraps an element body as {"error": ...} when negotiation picks JSON', function () {
            // negotiation picks application/json (the client asked for it
            // explicitly), which the node() body can't be serialized under
            // directly -- same reconciliation as the declared-success case
            // above.
            return util.axios
                .get('api/response-type-no-spec/element', {
                    headers: { Accept: 'application/json' }
                })
                .catch(function (error) {
                    expect(error.response.status).to.equal(500)
                    expect(error.response.headers['content-type']).to.equal('application/json')
                    expect(error.response.data).to.deep.equal({ error: '<error>boom</error>' })
                })
        })
    })

    describe('operation declares only an error response, no success response', function () {
        it('borrows the declared error response content type for a different undeclared code', function () {
            // DELETE /api/errors declares only "500": application/xml. The
            // handler actually returns 403 (undeclared, with an element
            // body), which has no success response to borrow from -- it
            // falls through to this declared error response instead of the
            // negotiated default.
            return util.axios.delete('api/errors').catch(function (error) {
                expect(error.response.status).to.equal(403)
                expect(error.response.headers['content-type']).to.equal('application/xml; charset=UTF-8')
                expect(error.response.data).to.equal('<forbidden/>')
            })
        })
    })
})
