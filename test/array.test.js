const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

describe('endpoint with pipe delimited parameter in query', function () {
    const params = {
        piped: 'one|two',
        spaced: 'three four',
        formStrExpNo: 'blue,black',
        formStrExpYes: ['green', 'red'],
        formIntExpNo: '1,2',
        formIntExpYes: ['10', '20']
    }

    let res, parameters

    before(async function () {
        res = await util.axios.get('api/arrays', {
            params,
            paramsSerializer: {
                indexes: null // render array parameter names without square brackets
            }
        })
        parameters = res?.data?.parameters
    })

    it('the query succeeds', async function () {
        expect(res.status).to.equal(200)
    })

    it('parses pipe delimited values into an array', function () {
        const p = parameters.piped
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['one','two'])
    })

    it('parses space delimited values into an array', function () {
        const p = parameters.spaced
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['three','four'])
    })

    it('parses comma separated values in parameter formStrExpNo into an array of strings', function () {
        const p = parameters.formStrExpNo
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['blue','black'])
    })

    it('parses occurrences of parameter formStrExpYes into an array of strings', function () {
        const p = parameters.formStrExpYes
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['green','red'])
    })

    it('parses comma separated values in parameter formIntExpNo into an array of integers', function () {
        const p = parameters.formIntExpNo
        expect(p).to.be.an('array')
        expect(p).to.deep.equal([1,2])
    })

    it('parses occurrences of parameter formIntExpYes into an array of integers', function () {
        const p = parameters.formIntExpYes
        expect(p).to.be.an('array')
        expect(p).to.deep.equal([10,20])
    })
});

describe('empty array parameters in GET request', function () {
    const params = {
        spaced: '',
        piped: '',
        formStrExpNo: '',
        formStrExpYes: [],
        formIntExpNo: '',
        formIntExpYes: []
    }

    let res, parameters

    before(async function () {
        try {
            res = await util.axios.get('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
            parameters = res?.data?.parameters
        } catch (e) {
            console.log(e)
        }
    })

    it('the query succeeds', async function () {
        expect(res.status).to.equal(200)
    })

    it('parses parameter piped to null', function () {
        const p = parameters.spaced
        expect(p).to.equal(null)
    })

    it('parses parameter spaced to null', function () {
        const p = parameters.spaced
        expect(p).to.equal(null)
    })

    it('parses parameter formStrExpNo is parsed to null', function () {
        const p = parameters.formStrExpNo
        expect(p).to.equal(null)
    })

    it('parses parameter formStrExpYes to null', function () {
        const p = parameters.formStrExpYes
        expect(p).to.equal(null)
    })

    it('parses parameter formIntExpNo to null', function () {
        const p = parameters.formIntExpNo
        expect(p).to.equal(null)
    })

    it('parameter formIntExpYes defaults to an array with one item', function () {
        const p = parameters.formIntExpYes
        expect(p).to.be.an('array')
        expect(p).to.deep.equal([123])
    })
});

describe('A parameter with style:pipeDelimited and explode:true will raise a server error when set', function () {
    const params = {
        pipedExplode: 'one',
    }

    let res, errorResponse

    before(async function () {
        try {
            res = await util.axios.get('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
        } catch (e) {
            errorResponse = e.response
        }
    })

    it('the query does not succeed', async function () {
        expect(res).to.be.undefined
        expect(errorResponse).to.not.be.undefined
        expect(errorResponse.status).to.equal(500)
    })

    it('the error message is actionable', function () {
        expect(errorResponse.data.description).to.include('Explode cannot be true for query-parameter pipedExplode with style set to pipeDelimited.')
    })
});

describe('A parameter with style:pipeDelimited and explode:true will raise a server error when set', function () {
    const params = {
        spacedExplode: 'one',
    }

    let res, errorResponse

    before(async function () {
        try {
            res = await util.axios.get('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
        } catch (e) {
            errorResponse = e.response
        }
    })

    it('the query does not succeed', async function () {
        expect(res).to.be.undefined
        expect(errorResponse).to.not.be.undefined
        expect(errorResponse.status).to.equal(500)
    })

    it('the error message is actionable', function () {
        expect(errorResponse.data.description).to.include('Explode cannot be true for query-parameter spacedExplode with style set to spaceDelimited.')
    })
});

describe('Array parameters a default value when unset in the request', function () {
    const params = {}

    let res, parameters

    before(async function () {
        try {
            res = await util.axios.get('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
            parameters = res?.data?.parameters
        } catch (e) {
            console.log(e)
        }
    })

    it('the query succeeds', async function () {
        expect(res.status).to.equal(200)
    })

    it('parameter pipedDefault is set to its default value', function () {
        const p = parameters.pipedDefault
        expect(p).to.be.an('array')
        expect(p).to.deep.equal(['one', 'two', 'three'])
    })

    it('parameter spacedDefault is set to its default value', function () {
        const p = parameters.spacedDefault
        expect(p).to.be.an('array')
        expect(p).to.deep.equal([1, 2, 3])
    })
});

describe('Wrong item types provided for array parameter', function () {
    const params = {
        spacedDefault: '1 2 three',
    }

    let res, errorResponse

    before(async function () {
        try {
            res = await util.axios.get('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
        } catch (e) {
            errorResponse = e.response
        }
    })

    it('no response', async function () {
        expect(res).to.be.undefined
        expect(errorResponse.status).to.equal(400)
    })

    it('error message', function () {
        console.log(errorResponse.data.description)
        expect(errorResponse.data.description).to.include('One or more values for spacedDefault could not be cast to integer.')
    })
});

describe('unset required array parameter in POST request', function () {
    const params = {
        'requiredArray' : []
    }

    let status

    before(async function () {
        try {
            res = await util.axios.post('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
            status = res.status
        } catch (e) {
            status = e.response.status
            message = e.response.data.description
        }
    })

    it('the query fails with bad request', async function () {
        expect(status).to.equal(400)
    })

    it('the response contains an actionable error message', async function () {
        expect(message.startsWith('Parameter requiredArray is required [')).to.be.true
    })

});

describe('unset required array parameter in POST request', function () {
    const params = {}

    let status

    before(async function () {
        try {
            res = await util.axios.post('api/arrays', {
                params,
                paramsSerializer: {
                    indexes: null // render array parameter names without square brackets
                }
            })
            status = res.status
        } catch (e) {
            status = e.response.status
            message = e.response.data.description
        }
    })

    it('the query fails with bad request', async function () {
        expect(status).to.equal(400)
    })

    it('the response contains an actionable error message', async function () {
        expect(message.startsWith('Parameter requiredArray is required [')).to.be.true
    })

});
