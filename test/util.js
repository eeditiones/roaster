const chai = require('chai');
const expect = chai.expect;
const axios = require('axios');
const fs = require('fs');
const path = require('path');

const server = 'http://localhost:8080';

const app = `${server}/exist/apps/oas-test`;

const axiosInstance = axios.create({
    baseURL: app,
    headers: {
        "Origin": server
    },
    withCredentials: true
});

async function login() {
    console.log('Logging in user ...');
    const res = await axiosInstance.request({
        url: 'login',
        method: 'post',
        params: {
            "user": "tei",
            "password": "simple"
        }
    });
    expect(res.status).to.equal(200);
    expect(res.data.user).to.equal('tei');

    const cookie = res.headers["set-cookie"];
    axiosInstance.defaults.headers.Cookie = cookie[0];
    console.log('Logged in as %s: %s', res.data.user, res.statusText);
}

function logout(done) {
    console.log('Logging out ...');
    axiosInstance.request({
        url: 'login',
        method: 'post',
        params: {
            "logout": "true"
        }
    })
    .catch((error) => {
        expect(error.response.status).to.equal(401);
        done();
    });
}

async function install() {
    // install the oas-test xar into the database
    const stream = fs.createReadStream(path.join(__dirname, './app/build/oas-test-1.0.0.xar'));
    // const buffer = fs.readFileSync(path.join(__dirname, './app/build/oas-test-1.0.0.xar'));
    let res = await axios.put(`${server}/exist/rest/db/system/repo/oas-test-1.0.0.xar`, stream, {
        auth: {
            username: "admin"
        },
        headers: {
            "Content-Type": "application/octet-stream"
        }
    });
    expect(res.status).to.equal(201);

    const query = `
        repo:install-and-deploy-from-db("/db/system/repo/oas-test-1.0.0.xar")
    `;
    res = await axios.get(`${server}/exist/rest/db?_query=${encodeURIComponent(query)}&_wrap=no`, {
        auth: {
            "username": "admin",
            "password": ""
        }
    });
    expect(res.status).to.equal(200);
    expect(res.data).to.match(/result="ok"/);
}

async function uninstall() {
    const query = `
        repo:undeploy('http://exist-db.org/apps/oas-test'),
        repo:remove('http://exist-db.org/apps/oas-test')
    `;
    const res = await axios.get(`${server}/exist/rest/db?_query=${encodeURIComponent(query)}&_wrap=no`, {
        auth: {
            "username": "admin"
        }
    });
    expect(res.status).to.equal(200);
    expect(res.data).to.match(/result="ok"/);
}

module.exports = {axios: axiosInstance, login, logout, install, uninstall};