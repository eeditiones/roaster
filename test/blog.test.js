const path = require('path');
const chai = require('chai');
const expect = chai.expect;
const chaiResponseValidator = require('chai-openapi-response-validator');
const axios = require('axios');

const spec = path.resolve("routes.json");
chai.use(chaiResponseValidator(spec));

describe('/posts', function () {
    it('gets posts', async function () {

        const res = await axios.get('http://localhost:8080/exist/apps/oas-router/posts?start=10&date=2020-08-24');

        expect(res.status).to.equal(200);
        expect(res.data.posts.length).to.equal(2);
        expect(res.data.start).to.equal(10);
        expect(res.data.date).to.equal('Montag, 24. August, 2020');
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
    it('gets post', async function () {
        const res = await axios.get('http://localhost:8080/exist/apps/oas-router/posts/a12345');

        expect(res.status).to.equal(200);
        expect(res).to.satisfyApiSpec;
    });
});

describe('/login', () => {
    it('logs in user', async function () {
        const res = await axios.request({
            url: 'http://localhost:8080/exist/apps/oas-router/login',
            method: 'post',
            params: {
                "user": "oas",
                "password": "oas"
            },
            withCredentials: true
        });
        expect(res.status).to.equal(200);
        expect(res.data.user).to.equal('oas');
        expect(res).to.satisfyApiSpec;
    });
});

describe('/logout', () => {
    it('logs out user', function (done) {
        axios.get('http://localhost:8080/exist/apps/oas-router/logout')
        .catch((error) => {
            expect(error.response.status).to.equal(401);
            expect(error.response).to.satisfyApiSpec;
            done();
        });
    });
});