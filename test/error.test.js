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

    describe('handler lookup', function () {
        // resolves with the error response, fails the test if the request succeeds
        async function expectError(path) {
            const response = await util.axios.get(path, { validateStatus: () => true })
            expect(response.status).to.equal(500)
            return response.data
        }

        it('reports an operationId without handler function', async function () {
            const data = await expectError('api/errors/handler/missing')
            expect(data.code).to.contain('OPERATION')
            expect(data.description).to.equal('Operation not found for operationId:"api:handler-does-not-exist"')
        })

        it('reports a lookup that returns something other than a function', async function () {
            const data = await expectError('api/errors/handler/not-a-function')
            expect(data.code).to.contain('OPERATION')
            expect(data.description).to.equal(
                'Lookup for operationId:"api:handler-not-a-function" did not return a function, got the string "not a function"'
            )
        })

        it('reports a handler function with the wrong arity', async function () {
            const data = await expectError('api/errors/handler/wrong-arity')
            expect(data.code).to.contain('OPERATION')
            expect(data.description).to.equal(
                'Handler for operationId:"api:handler-wrong-arity" must take exactly one argument (the request map), but takes 0'
            )
        })
    })
})
