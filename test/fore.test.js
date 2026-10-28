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

describe('Function check of Fore pages', function () {
    const postTo = (path, body) =>
        util.axios.post(path, body, { headers: { 'Content-Type': 'application/xml' }, validateStatus: () => true })

    before(async function () {
        await util.login()
    })

    after(async function () {
        await util.logout()
    })

    it('accepts functions the server provides', async function () {
        const valid = await postTo('api/fore/functions', '<data><name>abc</name><amount>5</amount></data>')
        expect(valid.status).to.equal(200)

        const invalid = await postTo('api/fore/functions', '<data><name>abx</name><amount>5</amount></data>')
        expect(invalid.status).to.equal(422)
        expect(invalid.data.value.errors[0].alert).to.equal('Lower case letters only, at least 3, no x')
    })

    it('does not mistake string literals and operators for function calls', async function () {
        // 'a(b)' in a string and "div (" must not be reported
        const res = await postTo('api/fore/functions', '<data><name>a(b</name><amount>100</amount></data>')
        expect(res.status).to.equal(422)
        expect(res.data.value.errors.map((e) => e.ref)).to.deep.equal(['amount[1]'])
    })

    it('fails compilation naming the bind and every unsupported function', async function () {
        const res = await postTo('api/fore/unsupported', '<data><name>abc</name><amount>5</amount></data>')
        expect(res.status).to.equal(500)
        const message = res.data.description
        expect(message).to.contain('functions that are not available on the server')
        expect(message).to.contain("bind 'name' (required): now()")
        expect(message).to.contain("bind 'limit' (constraint): depends()")
        expect(message).to.contain("bind 'limit' (constraint): instance 'rates' is not defined")
        // not reported: names inside string literals
        expect(message).to.not.contain('(constraint): string-length()')
    })
})

describe('Rules that read other instances', function () {
    const order = ({ qty = '1', code = 'A', note = '' } = {}) =>
        `<order><qty>${qty}</qty><code>${code}</code><note>${note}</note></order>`
    const postOrder = (body) =>
        util.axios.post('api/fore/instances', body, {
            headers: { 'Content-Type': 'application/xml' },
            validateStatus: () => true
        })

    before(async function () {
        await util.login()
    })

    after(async function () {
        await util.logout()
    })

    it('accepts an order within the limits of the inline instance and a known rate', async function () {
        const res = await postOrder(order({ qty: '10', code: 'A' }))
        expect(res.status).to.equal(200)
    })

    it('reads an inline instance with instance(id)', async function () {
        const res = await postOrder(order({ qty: '11' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors).to.have.length(1)
        expect(res.data.value.errors[0]).to.include({ ref: 'qty[1]', alert: 'Quantity above the limit' })
    })

    it('reads an instance loaded from src with $id', async function () {
        const res = await postOrder(order({ code: 'Z' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors[0]).to.include({ ref: 'code[1]', alert: 'Unknown rate code' })
    })

    it('reads the payload with $default and instance()', async function () {
        const small = await postOrder(order({ qty: '5', code: 'B' }))
        expect(small.status).to.equal(200)

        const largeA = await postOrder(order({ qty: '8', code: 'A' }))
        expect(largeA.status).to.equal(200)

        const largeB = await postOrder(order({ qty: '8', code: 'B' }))
        expect(largeB.status).to.equal(422)
        expect(largeB.data.value.errors[0]).to.include({
            ref: 'note[1]',
            alert: 'Large orders with rate B need a note'
        })
    })

    it('can not be given its reference data by the request', async function () {
        // extra elements in the payload are not instances
        const res = await postOrder('<order><qty>50</qty><code>A</code><note/><limits><max>100</max></limits></order>')
        expect(res.status).to.equal(422)
        expect(res.data.value.errors[0].ref).to.equal('qty[1]')
    })
})

describe('Documentation and demo page', function () {
    const order = ({ name = 'Ann', amount = '5', code = 'A', note = '' } = {}) =>
        `<order><name>${name}</name><amount>${amount}</amount><code>${code}</code><note>${note}</note></order>`
    const postOrder = (body) =>
        util.axios.post('api/fore/demo', body, {
            headers: { 'Content-Type': 'application/xml' },
            validateStatus: () => true
        })

    it('serves the page and the files of its instances', async function () {
        const page = await util.axios.get('static/fore-validation.html')
        expect(page.headers['content-type']).to.contain('text/html')
        expect(page.data).to.contain('<fx-fore')
        expect(page.data).to.contain('Validating requests with Fore')

        for (const file of ['order', 'limits', 'rates']) {
            const res = await util.axios.get(`static/fore-validation-${file}.xml`)
            expect(res.status).to.equal(200)
        }
    })

    it('validates with the binds of the page that the browser runs', async function () {
        expect((await postOrder(order())).status).to.equal(200)

        const res = await postOrder(order({ name: '', amount: '5000', code: 'Z', note: 'big' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors.map((e) => e.alert)).to.deep.equal([
            'A name is required',
            'The amount must be a whole number from 1 to the limit',
            'Unknown rate code'
        ])
    })

    it('requires a note only for large orders', async function () {
        expect((await postOrder(order({ amount: '100' }))).status).to.equal(200)

        const res = await postOrder(order({ amount: '101' }))
        expect(res.status).to.equal(422)
        expect(res.data.value.errors[0]).to.include({ ref: 'note[1]', alert: 'Orders above 100 need a note' })

        expect((await postOrder(order({ amount: '101', note: 'approved' }))).status).to.equal(200)
    })
})
