const chai = require('chai');
const expect = chai.expect;
const axios = require('axios');
// read metadata from .existdb.json
const existJSON = require('../.existdb.json')
const serverInfo = existJSON.servers.localhost

const { origin } = new URL(serverInfo.server)

const app = `${origin}/exist/apps/roasted`;

const axiosInstance = axios.create({
    baseURL: app,
    headers: {
        "Origin": origin
    },
    withCredentials: true
});

async function login() {
    // console.log('Logging in ' + serverInfo.user + ' to ' + app);
    const res = await axiosInstance.request({
        url: 'login',
        method: 'post',
        params: {
            "user": serverInfo.user,
            "password": serverInfo.password
        }
    });

    // expect(res.status).to.equal(200);
    // expect(res.data.user).to.equal(serverInfo.user);

    const cookie = res.headers["set-cookie"];
    axiosInstance.defaults.headers.Cookie = cookie[0];
    // console.log('Logged in as %s: %s', res.data.user, res.statusText);
}

function logout() {
    // console.log('Logging out ...');
    return axiosInstance.request({
        url: 'login',
        method: 'get',
        params: { logout: "true" }
    })
    .catch(_ => Promise.resolve())
}

module.exports = {axios: axiosInstance, login, logout};
