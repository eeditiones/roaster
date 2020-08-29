const path = require('path');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator');
const axios = require('axios');

const spec = path.resolve("routes.json");
chai.use(chaiResponseValidator(spec));

axios.defaults.withCredentials = true;

describe('/posts', function () {
    it('gets posts', async function () {
        const now = new Date().toISOString();
        const res = await axios.get('http://localhost:8080/exist/apps/oas-router/posts?start=10&date=2020-08-24', {
            headers: {
                'X-Token': now,
                'Cookie': `track-me=keep track`
            }
        });

        expect(res.status).to.equal(200);
        expect(res.data.posts).to.have.lengthOf(2);
        expect(res.data.start).to.equal(10);
        expect(res.data.date).to.equal('Montag, 24. August, 2020');
        expect(res.data['X-Token']).to.equal(now);
        expect(res.data['track-me']).to.equal('keep track');
        expect(res).to.satisfyApiSpec;
    });

    it('takes JSON as POST body', async function () {
        const res = await axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/posts',
            method: 'post',
            headers: {
                'Content-Type': 'application/json'
            },
            data: {
                "title": "My shiny new post",
                "author": "Rudi Rüssel"
            },
            auth: {
                username: "oas",
                password: "oas"
            }
        });
        expect(res.status).to.equal(201);

        // Assert that the HTTP response satisfies the OpenAPI spec
        expect(res).to.satisfyApiSpec;
    });

    it('takes XML as POST body', async function () {
        const res = await axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/posts',
            method: 'post',
            headers: {
                'Content-Type': 'application/xml'
            },
            data: "<article><title>My new post</title></article>",
            auth: {
                username: "oas",
                password: "oas"
            }
        });
        expect(res.status).to.equal(201);

        // Assert that the HTTP response satisfies the OpenAPI spec
        expect(res).to.satisfyApiSpec;
    });

    it('denies unauthenticated ', (done) => {
        axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/posts',
            method: 'post',
            headers: {
                'Content-Type': 'application/xml'
            },
            data: "<article><title>My new post</title></article>"
        })
        .catch((error) => {
            expect(error.response.status).to.equal(401);
            expect(error.response.data).to.equal('<error>Permission denied to create new post</error>');
            expect(error.response).to.satisfyApiSpec;
            done();
        });
    });
});

describe('/posts/{id}', () => {
    it('gets post as XML', async function () {
        const res = await axios.get('http://localhost:8080/exist/apps/oas-router/posts/a12345?format=xml');

        expect(res.status).to.equal(200);
        expect(res.headers['content-type']).to.equal("application/xml");
        expect(res.data).to.match(/title/);
        expect(res).to.satisfyApiSpec;
    });

    it('gets post as HTML', async function () {
        const res = await axios.get('http://localhost:8080/exist/apps/oas-router/posts/a12345?format=html');

        expect(res.status).to.equal(200);
        expect(res.headers['content-type']).to.equal("text/html");
        expect(res.data).to.match(/h1/);
        expect(res).to.satisfyApiSpec;
    });

    it('gets post as HTML because of accept header', async function () {
        const res = await axios.get('http://localhost:8080/exist/apps/oas-router/posts/a12345', {
            "headers": {
                "Accept": "text/html"
            }
        });

        expect(res.status).to.equal(200);
        expect(res.headers['content-type']).to.equal("text/html");
        expect(res.data).to.match(/h1/);
        expect(res).to.satisfyApiSpec;
    });

    it('deletes post', async function() {
        const res = await axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/posts/a12345',
            method: 'delete',
            auth: {
                username: "oas",
                password: "oas"
            }
        });
        expect(res.status).to.equal(204);

        // Assert that the HTTP response satisfies the OpenAPI spec
        expect(res).to.satisfyApiSpec;
    });

    it('refuses to delete', function (done) {
        const res = axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/posts/a12345',
            method: 'delete'
        })
        .catch((error) => {
            expect(error.response.status).to.equal(401);
            expect(error.response.data.description).to.equal('You don\'t have permission to delete the post');
            expect(error.response.data.details.id).to.equal('a12345');
            expect(error.response).to.satisfyApiSpec;
            done();
        });
    });
});

describe('/login', () => {
    it('fails with wrong password', function (done) {
        axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/login',
            method: 'post',
            params: {
                "user": "oas",
                "password": "foobar"
            },
            withCredentials: true
        })
            .catch((error) => {
                expect(error.response.status).to.equal(401);
                expect(error.response).to.satisfyApiSpec;
                done();
            });
    });

    it('logs in user', async function () {
        const res = await axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/login',
            method: 'post',
            params: {
                "user": "oas",
                "password": "oas"
            },
            mode: 'no-cors',
            withCredentials: true,
            credentials: 'same-origin'
        });
        expect(res.status).to.equal(200);
        expect(res.data.user).to.equal('oas');
        expect(res).to.satisfyApiSpec;
    });

    it('logs out user', function (done) {
        axios.request('http://localhost:8080/exist/apps/oas-router/login', {
            method: 'post',
            params: {
                "logout": "true"
            }
        })
            .catch((error) => {
                expect(error.response.status).to.equal(401);
                expect(error.response).to.satisfyApiSpec;
                done();
            });
    });
});