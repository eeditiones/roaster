const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

const adminAuth = {
    username: util.adminCredentials.username,
    password: util.adminCredentials.password
}

describe('CSRF protection', function () {

    describe('on a route with x-csrf same-origin', function () {

        before(util.login)
        after(util.logout)

        it('allows cookie-auth POST with matching Origin', async function () {
            const res = await util.axios.post('api/csrf/same-origin', {})
            expect(res.status).to.equal(200)
        })

        it('rejects cookie-auth POST with mismatched Origin', async function () {
            try {
                await util.axios.post('api/csrf/same-origin', {}, {
                    headers: { Origin: 'https://evil.example' }
                })
                expect.fail('expected request to be rejected with 403')
            } catch (e) {
                expect(e.response.status).to.equal(403)
            }
        })

        it('rejects cookie-auth POST with no Origin or Referer', async function () {
            try {
                await util.axios.post('api/csrf/same-origin', {}, {
                    headers: { Origin: null, Referer: null }
                })
                expect.fail('expected request to be rejected with 403')
            } catch (e) {
                expect(e.response.status).to.equal(403)
            }
        })

        it('falls back to Referer when Origin is absent', async function () {
            const res = await util.axios.post('api/csrf/same-origin', {}, {
                headers: { Origin: null, Referer: util.axios.defaults.baseURL + '/anything' }
            })
            expect(res.status).to.equal(200)
        })
    })

    describe('with basic auth', function () {

        it('bypasses CSRF check even with mismatched Origin', async function () {
            const res = await util.axios.post('api/csrf/same-origin', {}, {
                auth: adminAuth,
                headers: { Origin: 'https://evil.example', Cookie: null }
            })
            expect(res.status).to.equal(200)
        })
    })

    describe('on a route with x-csrf allowed-origins', function () {

        before(util.login)
        after(util.logout)

        it('allows cookie-auth POST when Origin is in the list', async function () {
            const res = await util.axios.post('api/csrf/allowed-origins', {}, {
                headers: { Origin: 'https://allowed.example' }
            })
            expect(res.status).to.equal(200)
        })

        it('rejects cookie-auth POST when Origin is not in the list', async function () {
            try {
                await util.axios.post('api/csrf/allowed-origins', {}, {
                    headers: { Origin: 'https://not-allowed.example' }
                })
                expect.fail('expected request to be rejected with 403')
            } catch (e) {
                expect(e.response.status).to.equal(403)
            }
        })
    })

    describe('on a route with no x-csrf config', function () {

        before(util.login)
        after(util.logout)

        it('does not enforce CSRF even with mismatched Origin', async function () {
            // POST /api/paths/{path} is authed (x-constraints user=admin)
            // but has no x-csrf, so the middleware must bypass.
            const res = await util.axios.post('api/paths/whatever', 'hello', {
                headers: {
                    Origin: 'https://evil.example',
                    'Content-Type': 'text/plain'
                }
            })
            expect(res.status).to.equal(201)
        })
    })
})
