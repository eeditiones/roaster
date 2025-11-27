const axios = require('axios');
const https = require('https')

// for use in custom controller tests
const adminCredentials = {
    username: 'admin',
    password: ''
}

// read connction options from ENV
if (process.env.EXISTDB_USER && 'EXISTDB_PASS' in process.env) {
    adminCredentials.username = process.env.EXISTDB_USER
    adminCredentials.password = process.env.EXISTDB_PASS
}

const server = 'EXISTDB_SERVER' in process.env
    ? process.env.EXISTDB_SERVER
    : 'https://localhost:8443'

const {origin, hostname} = new URL(server)

// authentication data for normal login
const authForm = new FormData()
authForm.append('user', adminCredentials.username)
authForm.append('password', adminCredentials.password)

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
    let res = await axiosInstance.post('login', authForm, {
        headers: { 'Content-Type': 'multipart/form-data' }
    })

    const cookie = res.headers['set-cookie'];
    axiosInstance.defaults.headers.Cookie = cookie;
    // console.log('Logged in as %s: %s', res.data.user, res.statusText, res.headers['set-cookie']);
}

async function logout() {
    const res = await axiosInstance.get('logout')
    const cookie = res.headers["set-cookie"]
    // on logout we only get an update for the domain cookie
    // the first cookie, the JSESSIONID, stays intact
    axiosInstance.defaults.headers.Cookie = cookie
}

module.exports = {
    axios: axiosInstance,
    login, logout,
    adminCredentials, authForm
};
