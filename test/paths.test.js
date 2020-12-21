const util = require('./util.js');
const path = require('path');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator');

const spec = path.resolve("./test/app/api.json");
chai.use(chaiResponseValidator(spec));

describe('Path parameters', function () {
    it('passes parameter in last component of path', async function () {
        const res = await util.axios.get('api/paths/my-path');
        expect(res.status).to.equal(200);
        expect(res.data.parameters.path).to.equal('my-path');

        // expect(res).to.satisfyApiSpec;
    });
    it('handles get of path including $', async function () {
        const res = await util.axios.get('api/$op-er+ation*!');
        expect(res.status).to.equal(200);
        // expect(res).to.satisfyApiSpec;
    });
    it('handles post of binary data', async function () {
        const res = await util.axios.post('api/paths/my-path', 'TEST ME', {
            headers: {
                'Content-Type': 'application/octet-stream'
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data).to.equal('TEST ME');
    });
});

describe('Request body', function() {
    it('uploads string in body', async function() {
        const res = await util.axios.post('api/$op-er+ation*!');
        expect(res.status).to.equal(200);
    })
});

describe('Query parameters', function () {
    it('passes query parameters in GET', async function () {
        const res = await util.axios.get('api/parameters', {
            params: {
                num: 165.75,
                int: 776,
                bool: true,
                string: '&a=22'
            },
            headers: {
                "X-start": 22
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data.parameters.num).to.be.a('number');
        expect(res.data.parameters.num).to.equal(165.75);
        expect(res.data.parameters.bool).to.be.a('boolean');
        expect(res.data.parameters.bool).to.be.true;
        expect(res.data.parameters.int).to.be.a('number');
        expect(res.data.parameters.int).to.equal(776);
        expect(res.data.parameters.string).to.equal('&a=22');
        expect(res.data.parameters.defaultParam).to.equal('abcdefg');
        expect(res.data.parameters['X-start']).to.equal(22);
    });

    it('passes query parameters in POST', async function () {
        const res = await util.axios.request({
            url: 'api/parameters',
            method: 'post',
            params: {
                'num': 165.75,
                'int': 776,
                'bool': true,
                'string': '&a=22'
            },
            headers: {
                "X-start": 22
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data.method).to.equal('post');
        expect(res.data.parameters.num).to.be.a('number');
        expect(res.data.parameters.num).to.equal(165.75);
        expect(res.data.parameters.bool).to.be.a('boolean');
        expect(res.data.parameters.bool).to.be.true;
        expect(res.data.parameters.int).to.be.a('number');
        expect(res.data.parameters.int).to.equal(776);
        expect(res.data.parameters.string).to.equal('&a=22');
        expect(res.data.parameters.defaultParam).to.equal('abcdefg');
        expect(res.data.parameters['X-start']).to.equal(22);
    });

    it('handles date parameters', async function () {
        const res = await util.axios.get('api/dates', {
            params: {
                date: "2020-11-24Z",
                dateTime: "2020-11-24T20:22:41.975Z"
            }
        });
        expect(res.status).to.equal(200);
        expect(res.data).to.be.true;
    });
});

describe('Error reporting', function() {
    it('receives error report', function() {
        return util.axios.get('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(404);
                expect(error.response.data.description).to.equal('document not found');
                expect(error.response.data.value).to.equal('error details');
            });
    });

    it('receives dynamic XQuery error', function() {
        return util.axios.post('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(500);
                expect(error.response.data.description).to.match(/\[at line \d+ of.*\]/);
                expect(error.response.data.description).to.contain('$undefined');
            });
    });

    it('receives explicit error', function() {
        return util.axios.delete('api/errors')
            .catch(function(error) {
                expect(error.response.status).to.equal(403);
                expect(error.response.headers['content-type']).to.equal('application/xml');
                expect(error.response.data).to.equal('<forbidden/>');
            });
    });

    it('calls error handler', function() {
        return util.axios.get('api/errors/handle')
            .catch(function(error) {
                expect(error.response.status).to.equal(500);
                expect(error.response.headers['content-type']).to.equal('text/html');
                expect(error.response.data).to.contain('$undefined');
            });
    });
});
