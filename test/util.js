const chai = require('chai');
const expect = chai.expect;
const axios = require('axios');
const https = require('https')

// read connction options from ENV
const params = { user: 'admin', password: '' }
if (process.env.EXISTDB_USER && 'EXISTDB_PASS' in process.env) {
    params.user = process.env.EXISTDB_USER
    params.password = process.env.EXISTDB_PASS
}

// for use in custom controller tests
const adminCredentials = {
    username: params.user,
    password: params.password
}

const server = 'EXISTDB_SERVER' in process.env
    ? process.env.EXISTDB_SERVER
    : 'https://localhost:8443'
  
const {origin, hostname} = new URL(server)

const axiosInstance = axios.create({
    baseURL: `${origin}/exist/apps/roasted`,
    headers: { Origin: origin },
    withCredentials: true,
    httpsAgent: new https.Agent({
        rejectUnauthorized: hostname !== 'localhost'
    })
});

async function login() {
    // console.log('Logging in ' + serverInfo.user + ' to ' + app)
    const res = await axiosInstance.request({
        url: 'login',
        method: 'post',
        params
    });

    expect(res.status).to.equal(200);
    expect(res.data.user).to.equal('tei');

    const cookie = res.headers['set-cookie'];
    axiosInstance.defaults.headers.Cookie = cookie[0];
    // console.log('Logged in as %s: %s', res.data.user, res.statusText);
}

function logout(done) {
    // console.log('Logging out ...');
    axiosInstance.request({
        url: 'login',
        method: 'post',
        params: {
            logout: 'true'
        }
    })

    const cookie = res.headers["set-cookie"]
    axiosInstance.defaults.headers.Cookie = cookie[0]
    // console.log('Logged in as %s: %s', res.data.user, res.statusText)
}

module.exports = {axios: axiosInstance, login, logout, adminCredentials };
