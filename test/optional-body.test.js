const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

// a POST with no body and no Content-Type, as a browser's fetch() sends it: axios
// would otherwise add application/x-www-form-urlencoded to an empty POST
const noBody = { headers: { 'Content-Type': false } }

// A request body the route declares optional ("required": false, OpenAPI's
// default) may be left out altogether. Such a request has no Content-Type, and
// must not be rejected as a body of a media type the route does not allow.
describe('An optional request body', function () {
    describe('when no body is sent', function () {
        let res
        before(async function () {
            res = await util.axios.post('api/optional-body', undefined, noBody)
        })
        it('is accepted', function () {
            expect(res.status).to.equal(200)
        })
        it('reaches the handler as no body', function () {
            expect(res.data.sent).to.equal(false)
        })
    })

    describe('when a body of an allowed media type is sent', function () {
        let res
        before(async function () {
            res = await util.axios.post('api/optional-body', { greeting: 'hello' }, {
                headers: { 'Content-Type': 'application/json' }
            })
        })
        it('is parsed as before', function () {
            expect(res.status).to.equal(200)
            expect(res.data.sent).to.equal(true)
            expect(res.data.body.greeting).to.equal('hello')
        })
    })

    describe('when a body of another media type is sent', function () {
        let error
        before(async function () {
            error = await util.axios.post('api/optional-body', 'hello', {
                headers: { 'Content-Type': 'text/plain' }
            }).catch(e => e)
        })
        it('is still rejected', function () {
            expect(error.response.status).to.equal(400)
            expect(error.response.data.code).to.equal('errors:BODY_CONTENT_TYPE')
        })
    })
})

describe('A required request body', function () {
    describe('when no body is sent', function () {
        let error
        before(async function () {
            error = await util.axios.post('api/login', undefined, noBody).catch(e => e)
        })
        it('is still rejected', function () {
            expect(error.response.status).to.equal(400)
            expect(error.response.data.code).to.equal('errors:BODY_CONTENT_TYPE')
        })
    })
})

// TEI Publisher's pb-login asks who is logged in by POSTing to /api/login with
// no body at all; roaster's auth:login answers that from the session's cookie.
describe('A session check: a login route with an optional body, posted no body', function () {
    describe('when nobody is logged in', function () {
        let res
        before(async function () {
            res = await util.axios.post('api/session', undefined, noBody)
        })
        it('is accepted', function () {
            expect(res.status).to.equal(200)
        })
        it('reports no user', function () {
            expect(res.data.user).to.not.be.ok
        })
    })

    describe('when a user is logged in', function () {
        let res
        before(async function () {
            await util.login()
            res = await util.axios.post('api/session', undefined, noBody)
        })
        after(util.logout)
        it('is accepted', function () {
            expect(res.status).to.equal(200)
        })
        it('reports the user', function () {
            expect(res.data.user).to.equal(util.adminCredentials.username)
        })
    })
})
