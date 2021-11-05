const chai = require('chai')
const axios = require('axios')

const path = require('path')
const chaiResponseValidator = require('chai-openapi-response-validator')
const spec = path.resolve("./test/app/api.json")
chai.use(chaiResponseValidator(spec))

// read metadata from .existdb.json
const existJSON = require('../.existdb.json')
const serverInfo = existJSON.servers.localhost
const { origin } = new URL(serverInfo.server)

const app = `${origin}/exist/apps/roasted`

const axiosInstance = axios.create({
    baseURL: app,
    headers: { "Origin": origin },
    withCredentials: true
})

async function login() {
    // console.log('Logging in ' + serverInfo.user + ' to ' + app)
    const res = await axiosInstance.request({
        url: 'login',
        method: 'post',
        params: {
            "user": serverInfo.user,
            "password": serverInfo.password
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
