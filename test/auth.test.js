const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

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
