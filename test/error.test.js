const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Error reporting', function () {
    it('receives error report', function () {
        return util.axios.get('api/errors').catch(function (error) {
            expect(error.response.status).to.equal(404)
            expect(error.response.data.description).to.equal('document not found')
            expect(error.response.data.value).to.equal('error details')
        })
    })

    it('receives dynamic XQuery error', function () {
        return util.axios.post('api/errors').catch(function (error) {
            expect(error.response.status).to.equal(500)
            expect(error.response.data.line).to.match(/\d+/)
            expect(error.response.data.description).to.contain('$undefined')
        })
    })

    it('receives explicit error', function () {
        return util.axios.delete('api/errors').catch(function (error) {
            expect(error.response.status).to.equal(403)
            // xml responses carry an explicit UTF-8 charset (see charset.test.js)
            expect(error.response.headers['content-type']).to.equal('application/xml; charset=UTF-8')
            expect(error.response.data).to.equal('<forbidden/>')
        })
    })

    it('calls error handler', function () {
        return util.axios.get('api/errors/handle').catch(function (error) {
            expect(error.response.status).to.equal(500)
            // html responses carry an explicit UTF-8 charset too, though
            // eXist-db's servlet re-normalizes the header it is given
            // (no space, lowercase) when it sets the character encoding
            expect(error.response.headers['content-type']).to.equal('text/html;charset=utf-8')
            expect(error.response.data).to.contain('$undefined')
        })
    })

    it('reports a misconfigured path parameter as JSON', async function () {
        const res = await util.axios.get('api/errors/misconfigured').catch((error) => error.response)
        expect(res.status).to.equal(500)
        expect(res.headers['content-type']).to.match(/^application\/json/)
        expect(res.data.description).to.contain('Path pattern has no substitutions')
    })

    it('reports an error with the request map as its value as JSON', async function () {
        const res = await util.axios.get('api/errors/with-request').catch((error) => error.response)
        expect(res.status).to.equal(400)
        expect(res.headers['content-type']).to.match(/^application\/json/)
        expect(res.data.description).to.equal('invalid request')
        expect(res.data.value.path).to.equal('/api/errors/with-request')
        expect(res.data.value.logger).to.equal('function(*)')
    })
})
