const chai = require('chai');
const expect = chai.expect;
const axios = require('axios');

// read connction options from ENV
const params = { user: 'admin', password: '' }
if (process.env.EXISTDB_USER && 'EXISTDB_PASS' in process.env) {
    params.user = process.env.EXISTDB_USER
    params.password = process.env.EXISTDB_PASS
}

const origin = 'EXISTDB_SERVER' in process.env 
    ? (new URL(process.env.EXISTDB_SERVER)).origin
    : 'https://localhost:8443'


const axiosInstance = axios.create({
    baseURL: `${origin}/exist/apps/roasted`,
    headers: { Origin: origin },
    withCredentials: true
})

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

function logout() {
    // console.log('Logging out ...')
    return axiosInstance
        .request({ url: 'logout', method: 'get'})
        .catch(_ => Promise.resolve())
}

module.exports = {
    axios: axiosInstance,
    login, logout,
    spec
}
