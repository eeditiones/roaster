const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

const fs = require('fs')
const FormData = require('form-data')
const dbUploadCollection = '/db/apps/roasted/uploads/'
const downloadApiEndpoint = 'api/paths/'

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
            const res = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'arraybuffer' })
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
            const res = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'arraybuffer' })
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
        const contents = Buffer.from('<root>\n\t<nested>text</nested>\n</root>')
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
            const {status, data} = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'arraybuffer' })
            expect(status).to.equal(200)
            expect(data).to.eql(contents)
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
            const res = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'arraybuffer' })
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
        const contents = Buffer.from('<TEI xmlns="http://www.tei-c.org/ns/1.0">\n\t<teiHeader/>\n\t<text>some text</text>\n</TEI>')
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
            const res = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'arraybuffer' })
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
        const contents = Buffer.from('{"valid":["json","data"]}')
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
            const res = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(function () {
            return util.axios.post(
                'api/paths/invalid.json',
                '{"invalid: ()}',
                {
                    headers: { 'Content-Type': 'application/json' },
                    // override default request transformation to send raw data
                    transformRequest: [data => data]
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
            expect(uploadResponse.data.description).to.equal('Body with media type \'application/json\' could not be parsed (invalid JSON).')
        })
    })
})

describe("body with content-type application/json-patch+json", function () {
    before(async function () {
        await util.login()
    })
    after(async function () {
        await util.logout()
    })
    describe("with valid content", function () {
        let uploadResponse
        const filename = 'valid-patch.json'
        const contents = Buffer.from('[{"op":"test","value":"foo","path":"/a/b/c"},{"op":"remove","path":"/a/b/c"}]')

        before(function () {
            return util.axios.post(
                'api/paths/' + filename, 
                contents,
                { headers: { 'Content-Type': 'application/json-patch+json'} }
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data).to.equal(dbUploadCollection + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(downloadApiEndpoint + filename, { responseType: 'json' })
            expect(res.status).to.equal(200)
            expect(res.data.length).to.equal(2)
            expect(res.data).to.deep.equal([
                {"op":"test","value":"foo","path":"/a/b/c"},
                {"op":"remove","path":"/a/b/c"}
            ])
        })
    })

    describe("with invalid content", function () {
        let uploadResponse
        before(function () {
            return util.axios.post(
                'api/paths/invalid-path.json',
                '[{"op":"test","value":"foo","',
                {
                    headers: { 'Content-Type': 'application/json-patch+json' },
                    // override default request transformation to send raw data
                    transformRequest: [data => data]
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
            expect(uploadResponse.data.description).to.equal('Body with media type \'application/json-patch+json\' could not be parsed (invalid JSON).')
        })
    })
})

describe("body with content-type multipart/form-data", function () {
    before(async function () {
        await util.login()
    })
    after(async function () {
        await util.logout()
    })

    describe("with valid content textual content", function () {
        let uploadResponse
        const filename = 'valid.txt'
        const contents = Buffer.from(`
 This
is 
 just
    a 
test.
`)
        const data = new FormData()
        data.append('file', contents, {
            knownLength: contents.length,
            filename,
            contentType: 'text/plain'
        })
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/single/' + filename,
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.equal(downloadApiEndpoint + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(contents)
        })
    })

    describe("with valid content XML content", function () {
        let uploadResponse
        const filename = 'some.xml'
        // this example is carefully constructed to equal the default XML serialization
        // of exist in order to be strictly equal when read from the db
        const contents = `<root>
    <nested att="val"/>
    <nested>
        asd;flksj;
    </nested>
</root>`
        const data = new FormData()
        data.append('file', contents, {
            knownLength: contents.length,
            filename,
            // filepath?: string;
            contentType: 'application/xml'
        })
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/single/' + filename,
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.equal(downloadApiEndpoint + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data.toString()).to.eql(contents.toString())
        })
    })

    describe("with binary data read from disk", function () {
        let uploadResponse
        const filename = 'roaster-router-logo.png'
        const localPath = 'test/app/resources/'
        const contents = fs.readFileSync(localPath + filename)
        const data = new FormData()
        data.append('file', contents, {
            knownLength: contents.length,
            filename,
            // filepath?: string;
            contentType: 'image/png'
        })
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/single/' + filename,
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("is uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.equal(downloadApiEndpoint + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data.length).to.eql(contents.length)
        })
    })

    describe("with no data", function () {
        let uploadResponse
        const data = new FormData()
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/single/nothing',
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("is rejected", function () {
            expect(uploadResponse.status).to.equal(400)
            expect(uploadResponse.data.code).to.equal('errors:BODY_CONTENT_TYPE')
            expect(uploadResponse.data.value).to.equal('Property "file" is required!')
        })
    })

    describe("with two files when only one is allowed", function () {
        let uploadResponse
        const data = new FormData()

        // first file
        const firstFileName = 'first-file.txt'
        const firstFileContent = 'first text'
        data.append('file', firstFileContent, {
            knownLength: firstFileContent.length,
            filename: firstFileName,
            contentType: 'text/plain'
        })
        // second file
        const secondFileName = 'second-file.txt'
        const secondFileContent = 'some additional text'
        data.append('file', secondFileContent, {
            knownLength: secondFileContent.length,
            filename: secondFileName,
            contentType: 'text/plain'
        })
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/single/abcd',
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response)
        })
        it("request is rejected", function () {
            expect(uploadResponse.status).to.equal(400)
            expect(uploadResponse.data.code).to.equal('errors:BODY_CONTENT_TYPE')
            expect(uploadResponse.data.value).to.equal('Property "file" only allows one item. Got 2')
        })
    })


    describe("with two files", function () {
        let uploadResponse
        const data = new FormData()

        // first file
        const firstFileName = 'first-file.txt'
        const firstFileContent = 'first text'
        data.append('file', firstFileContent, {
            knownLength: firstFileContent.length,
            filename: firstFileName,
            contentType: 'text/plain'
        })
        // second file
        const secondFileName = 'second-file.txt'
        const secondFileContent = 'some additional text'
        data.append('file', secondFileContent, {
            knownLength: secondFileContent.length,
            filename: secondFileName,
            contentType: 'text/plain'
        })
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/batch',
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("both were uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.deep.equal([
                downloadApiEndpoint + firstFileName,
                downloadApiEndpoint + secondFileName
            ])
        })
        it('both can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded[0], { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data.toString()).to.eql(firstFileContent, 'Contents of first file differs')

            const secondRes = await util.axios.get(uploadResponse.data.uploaded[1], { responseType: 'arraybuffer' })
            expect(secondRes.status).to.equal(200)
            expect(secondRes.data.toString()).to.eql(secondFileContent, 'Second of first file differs')
        })
    })

    describe("text sent base64 encoded", function () {
        let uploadResponse
        const data = new FormData()

        const fileName = 'sent-base64-encoded.txt'
        const fileContent = Buffer.from('first text')
        data.append('file', fileContent, {
            knownLength: fileContent.length,
            filename: fileName,
            contentType: 'application/octet-stream'
        })
        data.append('data', fileContent.toString('base64'))
        const headers = data.getHeaders();

        before(function () {
            return util.axios.post(
                'upload/base64',
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("was uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.equal(downloadApiEndpoint + fileName)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data).to.eql(fileContent, 'Content of file does not match')
        })
    })

    // there is an issue with uploading binary data encoded as base64
    describe("png sent base64 encoded", function () {
        let uploadResponse
        const data = new FormData()

        const dbResourceName = 'roaster-router-logo-base64.png'
        const fileContent = fs.readFileSync('test/app/resources/roaster-router-logo.png')
        data.append('file', fileContent, {
            knownLength: fileContent.length,
            filename: dbResourceName,
            contentType: 'image/png'
        })
        data.append('data', fileContent.toString('base64'))
        const headers = data.getHeaders()

        before(function () {
            return util.axios.post(
                'upload/base64',
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("was uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.equal(downloadApiEndpoint + dbResourceName)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded, { responseType: 'arraybuffer' })
            // console.log(res)
            expect(res.status).to.equal(200)
            expect(res.data.toString()).to.equal(fileContent.toString())
        })
    })

    describe("xml sent base64 encoded", function () {
        let uploadResponse
        const data = new FormData()

        const filename = 'sent-base64-encoded.xml'
        const fileContent = Buffer.from(`<root>
    <nested/>
</root>`)
        data.append('file', fileContent, {
            knownLength: fileContent.length,
            filename,
            contentType: 'application/octet-stream'
        })
        data.append('data', fileContent.toString('base64'))
        const headers = data.getHeaders()

        before(function () {
            return util.axios.post(
                'upload/base64',
                data,
                { headers }                
            )
            .then(r => uploadResponse = r)
            .catch(e => uploadResponse = e.response )
        })
        it("was uploaded", function () {
            expect(uploadResponse.status).to.equal(201)
            expect(uploadResponse.data.uploaded).to.exist
            expect(uploadResponse.data.uploaded).to.equal(downloadApiEndpoint + filename)
        })
        it('can be retrieved', async function () {
            const res = await util.axios.get(uploadResponse.data.uploaded, { responseType: 'arraybuffer' })
            expect(res.status).to.equal(200)
            expect(res.data.toString()).to.eql(fileContent.toString(), 'Content of file does not match')
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
