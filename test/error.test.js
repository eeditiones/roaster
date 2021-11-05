const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('Error reporting', function() {
    it('receives error report', function() {
        return util.axios.get('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(404)
                expect(error.response.data.description).to.equal('document not found')
                expect(error.response.data.value).to.equal('error details')
            })
    })

    it('receives dynamic XQuery error', function() {
        return util.axios.post('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(500)
                expect(error.response.data.line).to.match(/\d+/)
                expect(error.response.data.description).to.contain('$undefined')
            })
    })

    it('receives explicit error', function() {
        return util.axios.delete('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(403)
                expect(error.response.headers['content-type']).to.equal('application/xml')
                expect(error.response.data).to.equal('<forbidden/>')
            })
    })

    it('calls error handler', function() {
        return util.axios.get('api/errors/handle')
            .catch(function(error) {
                expect(error.response.status).to.equal(500)
                expect(error.response.headers['content-type']).to.equal('text/html')
                expect(error.response.data).to.contain('$undefined')
            })
    })
})
