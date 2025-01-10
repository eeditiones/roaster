const util = require('./util.js')
const chai = require('chai')
const expect = chai.expect

function parseCookies(cookies) {
    return cookies.map(parseCookieString)
}

function parseCookieString (cookieString) {
    return cookieString.split(';')
            .map(kv => kv.split('='))
            .reduce((acc, next) => {
                const key = decodeURIComponent(next[0].trim())
                const value = next[1] ? decodeURIComponent(next[1].trim()) : true
                acc[key] = value;
                return acc;
            }, {})
}

function oneCookieHas(key) {
    return cookies => cookies.filter(cookie => (key in cookie)).length === 1
}

function getCookieWith(cookies, key) {
    return cookies.filter(cookie => (key in cookie))[0]
}

const testAppLoginDomain = 'roasted.com.login'
const jettySessionId = 'JSESSIONID'

describe('On Login', function () {
    describe('using multipart/form-data', function(){
    let cookie, parsedCookies

    before(async function () {
        let res = await util.axios.post('login', util.authForm, {
            headers: { 'Content-Type': 'multipart/form-data' }
        })
        cookie = res.headers['set-cookie'];
        parsedCookies = parseCookies(cookie)
    })

    it('sets two cookies', function () {
        expect(cookie).to.have.lengthOf(2)
    })

    it('sets the ' + jettySessionId + ' cookie', function () {
        expect(parsedCookies).to.satisfy(oneCookieHas(jettySessionId))
    })

    it('sets the login domain cookie', function () {
        expect(parsedCookies).to.satisfy(oneCookieHas(testAppLoginDomain))
    })

    it('domain cookie has defaults', function () {
        const domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
        expect(domainCookie).to.exist
        expect(domainCookie).to.have.property('Path')
        expect(domainCookie['Path']).to.equal('/exist')
        expect(domainCookie).to.have.property('Max-Age')
        expect(domainCookie['Max-Age']).to.equal('604800')
        expect(domainCookie).to.have.property('Expires')
        expect(new Date(domainCookie.Expires).getTime()).to.be.greaterThan(Date.now())
    })

    describe('using cookie auth', function () {
        let publicRouteResponse

        before(async function () {
            publicRouteResponse = await util.axios.get('api/parameters', { headers: { cookie } })
        })

        it('public route can be called', async function () {
            expect(publicRouteResponse.status).to.equal(200);
        })

        it('sets the correct user', function () {
            expect(publicRouteResponse.data.user).to.be.a('object')
            expect(publicRouteResponse.data.user.name).to.equal("admin")
            expect(publicRouteResponse.data.user.dba).to.equal(true)
        })
    })

    describe('On logout', function () {
        let logoutResponse, guestResponse, updatedCookie, parsedCookies

        before(async function () {
            logoutResponse = await util.axios.get('logout', { headers: { cookie }})
            updatedCookie = logoutResponse.headers['set-cookie'];
            parsedCookies = parseCookies(updatedCookie)
            guestResponse = await util.axios.get('api/parameters', { headers: { cookie: updatedCookie }})
        })

        it('request returns true', function () {
            expect(logoutResponse.status).to.equal(200)
            expect(logoutResponse.data.success).to.equal(true)
        })

        it('invalidates session and domain cookie', function () {
            expect(updatedCookie.length).to.equal(1)
            // expect(parsedCookies).to.satisfy(oneCookieHas(jettySessionId))
            expect(parsedCookies).to.satisfy(oneCookieHas(testAppLoginDomain))
            const domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
            expect(domainCookie[testAppLoginDomain]).to.equal('deleted')
        })

        it('public route sets guest as user', async function () {
            expect(guestResponse.status).to.equal(200)
            expect(guestResponse.data.user.name).to.equal("guest")
            expect(guestResponse.data.user.dba).to.equal(false)
        })

        it('invalidated cookie reverts to guest access', async function () {
            const responseWithOldCookies = await util.axios.get('api/parameters', { headers: { cookie }})
            expect(responseWithOldCookies.status).to.equal(200)
            expect(responseWithOldCookies.data.user.name).to.equal("guest")
            expect(responseWithOldCookies.data.user.dba).to.equal(false)
        })
    })
    })

    describe('using application/x-www-form-urlencoded', function(){
        let cookie, parsedCookies

        before(async function () {
            const urlEncodedAuthForm = new URLSearchParams(util.authForm).toString()
            const res = await util.axios.post('login', urlEncodedAuthForm, {
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
            })
            cookie = res.headers['set-cookie'];
            parsedCookies = parseCookies(cookie)
        })

        it('sets two cookies', function () {
            expect(cookie).to.have.lengthOf(2)
        })

        it('sets the ' + jettySessionId + ' cookie', function () {
            expect(parsedCookies).to.satisfy(oneCookieHas(jettySessionId))
        })

        it('sets the login domain cookie', function () {
            expect(parsedCookies).to.satisfy(oneCookieHas(testAppLoginDomain))
        })

        it('sets a cookie with defaults', function () {
            const domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
            expect(domainCookie).to.exist
            expect(domainCookie).to.have.property('Path')
            expect(domainCookie['Path']).to.equal('/exist')
            expect(domainCookie).to.have.property('Max-Age')
            expect(domainCookie['Max-Age']).to.equal('604800')
            expect(domainCookie).to.have.property('Expires')
            expect(new Date(domainCookie.Expires).getTime()).to.be.greaterThan(Date.now())
        })

        describe('sets the correct user using cookie auth', function () {
            let publicRouteResponse

            before(async function () {
                publicRouteResponse = await util.axios.get('api/parameters', { headers: { cookie } })
            })

            it('public route can be called', async function () {
                expect(publicRouteResponse.status).to.equal(200);
            })

            it('user property is set on request map', function () {
                expect(publicRouteResponse.data.user).to.be.a('object')
                expect(publicRouteResponse.data.user.name).to.equal("admin")
                expect(publicRouteResponse.data.user.dba).to.equal(true)
            })
        })

        describe('On logout', function () {
            let logoutResponse, guestResponse

            before(async function () {
                logoutResponse = await util.axios.get('logout', { headers: { cookie }})
                updatedCookie = logoutResponse.headers['set-cookie'];
                guestResponse = await util.axios.get('api/parameters', { headers: { updatedCookie }})
            })
            it('request returns true', function () {
                expect(logoutResponse.status).to.equal(200)
                expect(logoutResponse.data.success).to.equal(true)
            })
            it('public route sets guest as user', async function () {
                expect(guestResponse.status).to.equal(200)
                expect(guestResponse.data.user.name).to.equal("guest")
                expect(guestResponse.data.user.dba).to.equal(false)
            })
        })
    })
    describe('using application/json', function(){
        let cookie, parsedCookies
    
        before(async function () {
            const data = {
                user: util.adminCredentials.username,
                password: util.adminCredentials.password
            }
            
            const res = await util.axios.post('login', data, {
                headers: { 'Content-Type': 'application/json' }
            })
            cookie = res.headers['set-cookie'];
            parsedCookies = parseCookies(cookie)
        })
    
        it('sets two cookies', function () {
            expect(cookie).to.have.lengthOf(2)
        })
    
        it('sets the ' + jettySessionId + ' cookie', function () {
            expect(parsedCookies).to.satisfy(oneCookieHas(jettySessionId))
        })
    
        it('sets the login domain cookie', function () {
            expect(parsedCookies).to.satisfy(oneCookieHas(testAppLoginDomain))
        })
    
        it('domain cookie has defaults', function () {
            const domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
            expect(domainCookie).to.exist
            expect(domainCookie).to.have.property('Path')
            expect(domainCookie['Path']).to.equal('/exist')
            expect(domainCookie).to.have.property('Max-Age')
            expect(domainCookie['Max-Age']).to.equal('604800')
            expect(domainCookie).to.have.property('Expires')
            expect(new Date(domainCookie.Expires).getTime()).to.be.greaterThan(Date.now())
        })
    
        describe('sets the correct user using cookie auth', function () {
            let publicRouteResponse
    
            before(async function () {
                publicRouteResponse = await util.axios.get('api/parameters', { headers: { cookie } })
            })
    
            it('public route can be called', async function () {
                expect(publicRouteResponse.status).to.equal(200);
            })
    
            it('user property is set on request map', function () {
                expect(publicRouteResponse.data.user).to.be.a('object')
                expect(publicRouteResponse.data.user.name).to.equal("admin")
                expect(publicRouteResponse.data.user.dba).to.equal(true)
            })
        })
    
        describe('On logout', function () {
            let logoutResponse, guestResponse, updatedCookie, parsedCookies
    
            before(async function () {
                logoutResponse = await util.axios.get('logout', { headers: { cookie }})
                updatedCookie = logoutResponse.headers['set-cookie'];
                parsedCookies = parseCookies(updatedCookie)
                guestResponse = await util.axios.get('api/parameters', { headers: { cookie: updatedCookie }})
            })
    
            it('request returns true', function () {
                expect(logoutResponse.status).to.equal(200)
                expect(logoutResponse.data.success).to.equal(true)
            })
    
            it('invalidates session and domain cookie', function () {
                expect(updatedCookie.length).to.equal(1)
                // expect(parsedCookies).to.satisfy(oneCookieHas(jettySessionId))
                expect(parsedCookies).to.satisfy(oneCookieHas(testAppLoginDomain))
                const domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
                expect(domainCookie[testAppLoginDomain]).to.equal('deleted')
            })
    
            it('public route sets guest as user', async function () {
                expect(guestResponse.status).to.equal(200)
                expect(guestResponse.data.user.name).to.equal("guest")
                expect(guestResponse.data.user.dba).to.equal(false)
            })
    
            it('invalidated cookie reverts to guest access', async function () {
                const responseWithOldCookies = await util.axios.get('api/parameters', { headers: { cookie }})
                expect(responseWithOldCookies.status).to.equal(200)
                expect(responseWithOldCookies.data.user.name).to.equal("guest")
                expect(responseWithOldCookies.data.user.dba).to.equal(false)
            })
        })
    })

    describe('custom login using application/json', function(){
        let cookie, parsedCookies, domainCookie
    
        before(async function () {
            const data = {
                usr: util.adminCredentials.username,
                pwd: util.adminCredentials.password
            }
            
            const res = await util.axios.post('api/login', data, {
                headers: { 'Content-Type': 'application/json' }
            })
            cookie = res.headers['set-cookie'];
            parsedCookies = parseCookies(cookie)
            domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
        })
    
        it('sets two cookies', function () {
            expect(cookie).to.have.lengthOf(1)
        })
    
        it('does not set the ' + jettySessionId + ' cookie', function () {
            expect(parsedCookies).to.not.satisfy(oneCookieHas(jettySessionId))
        })
    
        it('sets the login domain cookie', function () {
            expect(domainCookie).to.exist
        })
    
        it('domain cookie has defaults', function () {
            expect(domainCookie).to.have.property('Path')
            expect(domainCookie['Path']).to.equal('/exist/apps/roasted')
            expect(domainCookie).to.have.property('Expires')
            expect(new Date(domainCookie.Expires).getTime()).to.be.greaterThan(Date.now())
        })

        it('domain cookie has short lifetime', function () {
            expect(domainCookie).to.have.property('Max-Age')
            expect(domainCookie['Max-Age']).to.equal('10')
        })

        it('domain cookie has SameSite=strict', function () {
            expect(domainCookie).to.have.property('SameSite')
            expect(domainCookie['SameSite']).to.equal('Lax')
        })

        it('domain cookie has Secure', function () {
            expect(domainCookie).to.have.property('Secure')
        })

        it('domain cookie has HttpOnly', function () {
            expect(domainCookie).to.have.property('HttpOnly')
        })

        describe('sets the correct user using cookie auth', function () {
            let publicRouteResponse
    
            before(async function () {
                publicRouteResponse = await util.axios.get('api/parameters', { headers: { cookie } })
            })
    
            it('public route can be called', async function () {
                expect(publicRouteResponse.status).to.equal(200);
            })
    
            it('user property is set on request map', function () {
                expect(publicRouteResponse.data.user).to.be.a('object')
                expect(publicRouteResponse.data.user.name).to.equal("admin")
                expect(publicRouteResponse.data.user.dba).to.equal(true)
            })
        })
    
        describe('On logout', function () {
            let logoutResponse, guestResponse, updatedCookie, parsedCookies
    
            before(async function () {
                logoutResponse = await util.axios.get('api/logout', { headers: { cookie }})
                updatedCookie = logoutResponse.headers['set-cookie'];
                parsedCookies = parseCookies(updatedCookie)
                guestResponse = await util.axios.get('api/parameters', { headers: { cookie: updatedCookie }})
            })
    
            it('request returns a message', function () {
                expect(logoutResponse.status).to.equal(200)
                expect(logoutResponse.data.message).to.exist
            })
    
            it('invalidates domain cookie', function () {
                expect(updatedCookie.length).to.equal(1)
                domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
                expect(domainCookie).to.exist
                expect(domainCookie[testAppLoginDomain]).to.equal('deleted')
            })
    
            it('public route sets guest as user', async function () {
                expect(guestResponse.status).to.equal(200)
                expect(guestResponse.data.user.name).to.equal("guest")
                expect(guestResponse.data.user.dba).to.equal(false)
            })
    
            it('invalidated cookie reverts to guest access', async function () {
                const responseWithOldCookies = await util.axios.get('api/parameters', { headers: { cookie }})
                expect(responseWithOldCookies.status).to.equal(200)
                expect(responseWithOldCookies.data.user.name).to.equal("guest")
                expect(responseWithOldCookies.data.user.dba).to.equal(false)
            })
        })
    })

    describe('custom XML login using application/xml', function(){
        let cookie, parsedCookies, domainCookie
    
        before(async function () {
            const data = `
<login>
  <user>${util.adminCredentials.username}</user>
  <password>${util.adminCredentials.password}</password>
</login>
`
            const res = await util.axios.post('api/login-xml', data, {
                headers: { 'Content-Type': 'application/xml' }
            })
            cookie = res.headers['set-cookie'];
            parsedCookies = parseCookies(cookie)
            domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
        })
    
        it('sets one cookie', function () {
            expect(cookie).to.have.lengthOf(1)
        })
    
        it('does not set the ' + jettySessionId + ' cookie', function () {
            expect(parsedCookies).to.not.satisfy(oneCookieHas(jettySessionId))
        })
    
        it('sets the login domain cookie', function () {
            expect(domainCookie).to.exist
        })
    
        it('domain cookie has defaults', function () {
            expect(domainCookie).to.have.property('Path')
            expect(domainCookie['Path']).to.equal('/exist/apps/roasted')
            expect(domainCookie).to.have.property('Expires')
            expect(new Date(domainCookie.Expires).getTime()).to.be.greaterThan(Date.now())
        })

        it('domain cookie has short lifetime', function () {
            expect(domainCookie).to.have.property('Max-Age')
            expect(domainCookie['Max-Age']).to.equal('10')
        })

        it('domain cookie has SameSite=strict', function () {
            expect(domainCookie).to.have.property('SameSite')
            expect(domainCookie['SameSite']).to.equal('Lax')
        })

        it('domain cookie has Secure', function () {
            expect(domainCookie).to.have.property('Secure')
        })

        it('domain cookie has HttpOnly', function () {
            expect(domainCookie).to.have.property('HttpOnly')
        })

        describe('sets the correct user using cookie auth', function () {
            let publicRouteResponse

            before(async function () {
                publicRouteResponse = await util.axios.get('api/parameters', { headers: { cookie } })
            })

            it('public route can be called', async function () {
                expect(publicRouteResponse.status).to.equal(200);
            })

            it('user property is set on request map', function () {
                expect(publicRouteResponse.data.user).to.be.a('object')
                expect(publicRouteResponse.data.user.name).to.equal("admin")
                expect(publicRouteResponse.data.user.dba).to.equal(true)
            })
        })

        describe('On logout', function () {
            let logoutResponse, guestResponse, updatedCookie, parsedCookies

            before(async function () {
                logoutResponse = await util.axios.get('api/logout', { headers: { cookie }})
                updatedCookie = logoutResponse.headers['set-cookie'];
                parsedCookies = parseCookies(updatedCookie)
                guestResponse = await util.axios.get('api/parameters', { headers: { cookie: updatedCookie }})
            })

            it('request returns a message', function () {
                expect(logoutResponse.status).to.equal(200)
                expect(logoutResponse.data.message).to.exist
            })

            it('invalidates session and domain cookie', function () {
                expect(updatedCookie.length).to.equal(1)
                expect(parsedCookies).to.satisfy(oneCookieHas(testAppLoginDomain))
                const domainCookie = getCookieWith(parsedCookies, testAppLoginDomain)
                expect(domainCookie[testAppLoginDomain]).to.equal('deleted')
            })

            it('public route sets guest as user', async function () {
                expect(guestResponse.status).to.equal(200)
                expect(guestResponse.data.user.name).to.equal("guest")
                expect(guestResponse.data.user.dba).to.equal(false)
            })

            it('invalidated cookie reverts to guest access', async function () {
                const responseWithOldCookies = await util.axios.get('api/parameters', { headers: { cookie }})
                expect(responseWithOldCookies.status).to.equal(200)
                expect(responseWithOldCookies.data.user.name).to.equal("guest")
                expect(responseWithOldCookies.data.user.dba).to.equal(false)
            })
        })
    })
})
