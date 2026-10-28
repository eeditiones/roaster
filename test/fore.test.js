const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

const post = (body) =>
    util.axios.post('api/fore/invoice', body, {
        headers: { 'Content-Type': 'application/xml' },
        validateStatus: () => true
    })

const invoice = ({ name = 'ACME', amount = '5', note = '' } = {}) =>
    `<data><name>${name}</name><amount>${amount}</amount><note>${note}</note></data>`

describe('Validation against a Fore page', function () {
    before(async function () {
        await util.login()
    })

    after(async function () {
        await util.logout()
    })

    it('calls the handler for a valid body', async function () {
        const res = await post(invoice())
        expect(res.status).to.equal(200)
        expect(res.data.valid).to.equal(true)
        expect(res.data.name).to.equal('ACME')
    })

    it('rejects a missing required value with the alert of the bind', async function () {
        const res = await post(invoice({ name: '' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors).to.have.length(1)
        expect(res.data.value.errors[0]).to.include({
            kind: 'required',
            ref: 'name[1]',
            alert: 'Name is required'
        })
    })

    it('rejects a failing constraint', async function () {
        const res = await post(invoice({ amount: '-3' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors).to.have.length(1)
        expect(res.data.value.errors[0].kind).to.equal('constraint')
    })

    it('rejects a value of the wrong type once', async function () {
        const res = await post(invoice({ amount: 'abc' }))
        expect(res.status).to.equal(422)
        const kinds = res.data.value.errors.filter((e) => e.ref === 'amount[1]').map((e) => e.kind)
        expect(kinds).to.deep.equal(['type'])
    })

    it('only requires a value where the bind is relevant', async function () {
        const small = await post(invoice({ amount: '50' }))
        expect(small.status).to.equal(200)

        const large = await post(invoice({ amount: '500' }))
        expect(large.status).to.equal(422)
        expect(large.data.value.errors[0]).to.include({ kind: 'required', alert: 'Orders above 100 need a note' })

        const noted = await post(invoice({ amount: '500', note: 'approved' }))
        expect(noted.status).to.equal(200)
    })

    it('ignores binds on other instances', async function () {
        // the bind on instance('rates') is required but the payload has no such node
        const res = await post(invoice())
        expect(res.status).to.equal(200)
    })

    it('reports all violations at once', async function () {
        const res = await post(invoice({ name: '', amount: '-1' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors.map((e) => e.kind).sort()).to.deep.equal(['constraint', 'required'])
    })

    it('rejects a body that is not XML', async function () {
        const res = await util.axios.post('api/fore/invoice', '{"name":"x"}', {
            headers: { 'Content-Type': 'application/json' },
            validateStatus: () => true
        })
        expect(res.status).to.be.oneOf([400, 415])
    })

    it('leaves operations without x-fore alone', async function () {
        const res = await util.axios.get('api/arrays', { validateStatus: () => true })
        expect(res.status).to.not.equal(422)
    })
})

describe('Validator cache', function () {
    const axios = require('axios')
    const https = require('https')
    const page = new URL('/exist/rest/db/apps/roasted/forms/invoice.html', util.axios.defaults.baseURL).href
    const admin = {
        auth: { username: util.adminCredentials.username, password: util.adminCredentials.password },
        httpsAgent: util.axios.defaults.httpsAgent
    }
    // no session, requests run as guest, who can not write to the cache collection
    const guest = axios.create({
        baseURL: util.axios.defaults.baseURL,
        httpsAgent: new https.Agent({ rejectUnauthorized: false }),
        validateStatus: () => true
    })
    let original

    const postAsGuest = (body) =>
        guest.post('api/fore/invoice', body, { headers: { 'Content-Type': 'application/xml' } })

    const storePage = (xml) => axios.put(page, xml, { ...admin, headers: { 'Content-Type': 'application/xml' } })

    before(async function () {
        original = (await axios.get(page, { ...admin, responseType: 'text', transformResponse: (r) => r })).data
        // an admin request builds the cache entry that guest requests then have to run
        await storePage(original)
        await util.login()
        await post(invoice())
        await util.logout()
    })

    afterEach(async function () {
        await storePage(original)
    })

    it('uses the changed page on the next request', async function () {
        const before = await postAsGuest(invoice({ amount: '5' }))
        expect(before.status).to.equal(200)

        await storePage(original.replace('. &gt; 0', '. &gt; 1000'))

        const after = await postAsGuest(invoice({ amount: '5' }))
        expect(after.status).to.equal(422)
        expect(after.data.value.errors[0].kind).to.equal('constraint')
    })

    it('validates as guest although the cache can not be written', async function () {
        // the page is newer than the cached validator, which guest can not replace
        await storePage(original.replace('Name is required', 'Please enter a name'))

        const res = await postAsGuest(invoice({ name: '' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors[0].alert).to.equal('Please enter a name')
    })
})
