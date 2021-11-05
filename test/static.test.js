const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Requesting a static file from the server', function () {
    it('will download the resource', async function () {
        const res = await util.axios.get('static/roaster-router-logo.png')
        expect(res.status).to.equal(200)
    })
})
