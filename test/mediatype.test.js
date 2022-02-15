const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

const fs = require('fs')
const dbUploadCollection = '/db/apps/roasted/uploads/'

describe("Binary up and download", function () {
    const contents = fs.readFileSync("./dist/roasted.xar")

    describe("using basic authentication", function () {
        const filename = 'roasted.xar'
        it('handles post of binary data', async function () {
            const res = await util.axios.post('api/paths/' + filename, contents, {
                headers: {
                    'Content-Type': 'application/octet-stream',
                    'Authorization': 'Basic YWRtaW46'
                }
            })
            expect(res.status).to.equal(201)
            expect(res.data).to.equal(dbUploadCollection + filename)
        })
        it('retrieves the data', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })

    describe("using cookie authentication", function () {
        const filename = "roasted2.xar"
        before(async function () {
            await util.login()
        })
        after(async function () {
            await util.logout()
        })

        it('handles post of binary data', async function () {
            const res = await util.axios.post('api/paths/' + filename, contents, {
                headers: { 'Content-Type': 'application/octet-stream' }
            })
            expect(res.status).to.equal(201)
            expect(res.data).to.equal(dbUploadCollection + filename)
        })
        it('retrieves the data', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })
})

describe("body with content-type application/xml", function () {
    before(async function () {
        await util.login()
    })
    after(async function () {
        await util.logout()
    })

    describe("with valid content", function () {
        let uploadResponse
        const filename = 'valid.xml'
        const contents = Buffer.from('<root/>')
        before(function () {
            return util.axios.post('api/paths/' + filename, contents, {
                headers: { 'Content-Type': 'application/xml' }
            })
            .then(r => uploadResponse = r)
            .catch(e => {
                console.error(e.response.data)
                uploadResponse = e.response
            })
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data).to.equal(dbUploadCollection + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })

    // this "feature" is quite buggy and is only here to test for other encodings
    // bottom line - don't use it
    describe("with valid content encoded in latin1", function () {
        let uploadResponse
        const filename = 'latin1.xml'
        const contents = Buffer.from(`<?xml version="1.0" encoding="ISO-8859-1"?>
<örtchen name="München" />`, 'latin1')
        const dbNormalizedValue = '<örtchen name="München"/>'

        before(function () {
            return util.axios.post('api/paths/' + filename, contents, {
                headers: { 'Content-Type': 'application/xml; charset=iso-8859-1' }
            })
            .then(r => uploadResponse = r)
            .catch(e => {
                console.error(e.response.data)
                uploadResponse = e.response
            })
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data).to.equal(dbUploadCollection + filename)
        })
        it('can is stored encoded in UTF-8 and normalized', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data.toString('utf-8')).to.equal(dbNormalizedValue)
        })
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(async function () {
            return util.axios.post('api/paths/invalid.xml', Buffer.from('<invalid>asdf'), {
                headers: { 'Content-Type': 'application/xml' }
            })
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is rejected as Bad Request", function () {
            expect(uploadResponse.status).to.equal(400)
        })
        it("with the correct error code", function () {
            expect(uploadResponse.data.code).to.equal('errors:BODY_CONTENT_TYPE')
        })
        it("with a human readable description", function () {
            expect(uploadResponse.data.description).to.equal('Body with media type \'application/xml\' could not be parsed (invalid XML).')
        })
    })
})

describe("body with content-type application/tei+xml", function () {
    before(async function () {
        await util.login()
    })
    after(async function () {
        await util.logout()
    })

    describe("with valid content", function () {
        let uploadResponse
        const filename = 'valid.tei.xml'
        const contents = Buffer.from('<TEI/>')
        before(function () {
            return util.axios.post('api/paths/' + filename, contents, {
                headers: { 'Content-Type': 'application/tei+xml' }
            })
            .then(r => uploadResponse = r)
            .catch(e => {
                console.error(e)
                uploadResponse = e.response
            })
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data).to.equal(dbUploadCollection + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(async function () {
            return util.axios.post('api/paths/invalid.tei.xml', Buffer.from('<TEI>asdf'), {
                headers: { 'Content-Type': 'application/tei+xml' }
            })
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is rejected as Bad Request", function () {
            expect(uploadResponse.status).to.equal(400)
        })
        it("with the correct error code", function () {
            expect(uploadResponse.data.code).to.equal('errors:BODY_CONTENT_TYPE')
        })
        it("with a human readable description", function () {
            expect(uploadResponse.data.description).to.equal('Body with media type \'application/tei+xml\' could not be parsed (invalid XML).')
        })
    })
})

describe("body with content-type application/json", function () {
    before(async function () {
        await util.login()
    })
    after(async function () {
        await util.logout()
    })
    describe("with valid content", function () {
        let uploadResponse
        const filename = 'valid.json'
        const contents = Buffer.from('{"valid":[]}')
        before(function () {
            return util.axios.post(
                'api/paths/' + filename, 
                contents, 
                { headers: { 'Content-Type': 'application/json'} }
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data).to.equal(dbUploadCollection + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get('api/paths/' + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(function () {
            return util.axios.post(
                'api/paths/invalid.json',
                '{"invalid: ()',
                { headers: { 'Content-Type': 'application/json' } }
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is rejected as Bad Request", function () {
            expect(uploadResponse.status).to.equal(400)
        })
        it("with the correct error code", function () {
            expect(uploadResponse.data.code).to.equal('errors:BODY_CONTENT_TYPE')
        })
        it("with a human readable description", function () {
            expect(uploadResponse.data.description).to.equal('Body with media type \'application/json\' could not be parsed (invalid JSON).')
        })
    })
})

describe("with invalid content-type header", function () {
    let uploadResponse
    before(function () {
        return util.axios.post(
            'api/paths/invalid.stuff',
            'asd;lfkjdas;flkja',
            {
                headers: { 
                    'Content-Type': 'my/thing',
                    'Authorization': 'Basic YWRtaW46'
                }
            }
        )
        .then(r => uploadResponse = r)
        .catch(e => uploadResponse = e.response)
    })
    it("is rejected as Bad Request", function () {
        expect(uploadResponse.status).to.equal(400)
    })
    it("with the correct error code", function () {
        expect(uploadResponse.data.code).to.equal('errors:BODY_CONTENT_TYPE')
    })
    it("with a human readable description", function () {
        expect(uploadResponse.data.description).to.equal('Body with media-type \'my/thing\' is not allowed')
    })
})

describe("Retrieving an SVG image", function () {
    let response
    const avatarImage = 
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">\n' +
        '    <g fill="darkgreen" stroke="lime" stroke-width=".25" transform="skewX(4) skewY(8) translate(0,.5)">\n' +
        '        <rect x="2" y="2" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="5" y="2" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="8" y="2" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="11" y="2" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="2" y="5" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="5" y="5" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="8" y="5" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="11" y="5" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="2" y="8" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '        <rect x="5" y="8" width="2" height="2" rx=".5" ry=".5"/>\n' +
        '    </g>\n' +
        '</svg>'
    
    before(async function () {
        response = await util.axios.get('api/avatar')
    })
    it("should succeed", function () {
        expect(response.status).to.equal(200)
    })
    it("was sent with the correct Content-Type header", function () {
        expect(response.headers['content-type']).to.equal('image/svg+xml')
    })
    it("is pretty printed", function () {
        expect(response.data).to.equal(avatarImage)
    })
})
