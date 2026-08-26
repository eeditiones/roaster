const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

// Regression test for missing response charsets.
describe('Content-Type header charset handling', function () {
    const phrase = 'café 💩'

    function fetchAs (type) {
        return util.axios.get('api/encoding-test', {
            params: { type },
            responseType: 'arraybuffer'
        })
    }

    describe('text-ish types get an explicit UTF-8 charset', function () {
        const cases = [
            ['application/xml', 'application/xml; charset=UTF-8'],
            ['application/xhtml+xml', 'application/xhtml+xml; charset=UTF-8'],
            ['image/svg+xml', 'image/svg+xml; charset=UTF-8'],
            // eXist-db's servlet recognizes text/* as textual and re-normalizes
            // the header when it sets the response's character encoding -
            // still charset=utf-8, just reformatted (no space, lowercase).
            ['text/html', 'text/html;charset=utf-8'],
            ['text/plain', 'text/plain;charset=utf-8']
        ]

        cases.forEach(([type, expectedHeader]) => {
            it(`${type} -> ${expectedHeader}`, async function () {
                const res = await fetchAs(type)
                expect(res.headers['content-type']).to.equal(expectedHeader)
                expect(Buffer.from(res.data).toString('utf-8')).to.include(phrase)
            })
        })
    })

    describe('types that must not get a charset appended', function () {
        // application/json is handled separately: it correctly serializes the
        // string as a quoted JSON value, so its bytes aren't the raw phrase.
        it('application/json is returned without a charset parameter', async function () {
            const res = await fetchAs('application/json')
            expect(res.headers['content-type']).to.equal('application/json')
            expect(Buffer.from(res.data).toString('utf-8')).to.include(phrase)
        })

        const cases = [
            'application/octet-stream', // binary passthrough via the "text" method
            'image/png', // binary passthrough via the "text" method
            'audio/mpeg' // binary passthrough via the "text" method
        ]

        cases.forEach((type) => {
            it(`${type} is returned without a charset parameter`, async function () {
                const res = await fetchAs(type)
                expect(res.headers['content-type']).to.equal(type)
                expect(Buffer.from(res.data).toString('utf-8')).to.include(phrase)
            })
        })
    })

    it('leaves a type that already declares its own parameters untouched', async function () {
        const res = await fetchAs('application/xml; charset=us-ascii')
        expect(res.headers['content-type']).to.equal('application/xml; charset=us-ascii')
        expect(Buffer.from(res.data).toString('utf-8')).to.include('café 💩')
    })
})
