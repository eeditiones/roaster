const util = require('./util.js');
const path = require('path');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator');

const spec = path.resolve("./test/app/api.json");
chai.use(chaiResponseValidator(spec));

before(util.install);

after(util.uninstall);

describe('Path parameters', function () {
    it('passes parameter in last component of path', async function () {
        const res = await util.axios.get('api/paths/my-path');
        expect(res.status).to.equal(200);
        expect(res.data.parameters.path).to.equal('my-path');

        // expect(res).to.satisfyApiSpec;
    });
    // it('handles path including $', async function () {
    //     const res = await util.axios.get('api/$operation');
    //     expect(res.status).to.equal(200);
    //     // expect(res).to.satisfyApiSpec;
    // });
});