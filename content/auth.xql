(:
 :  Copyright (C) 2020 TEI Publisher Project Team
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
module namespace auth="http://e-editiones.org/roaster/auth";

import module namespace plogin="http://exist-db.org/xquery/persistentlogin"
    at "java:org.exist.xquery.modules.persistentlogin.PersistentLoginModule";
import module namespace request = "http://exist-db.org/xquery/request";
import module namespace response = "http://exist-db.org/xquery/response";
import module namespace session = "http://exist-db.org/xquery/session";

import module namespace router="http://e-editiones.org/roaster/router";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace cookie="http://e-editiones.org/roaster/cookie";

(: API Request Authentication and Authorisation :)

(:~
 :)
declare variable $auth:DEFAULT_STRATEGIES := map {
    "cookieAuth": auth:use-cookie-auth#1,
    "basicAuth": auth:use-basic-auth#1
};

declare variable $auth:DEFAULT_LOGIN_OPTIONS := map {
    "asDba": true(), 
    "maxAge": xs:dayTimeDuration("P7D"),
    "Path": request:get-context-path(),
    "createSession": true() (: this will _also_ set the JSESSIONID cookie :)
};

declare variable $auth:log-level := "debug";

(:~
 : standard authorization middleware
 : extend request with user information
 : authenticate user via cookie or basic auth
 : authorize users against x-constraints
 :
 : @param $request the current request
 : @return the extended request map
 :)
declare function auth:standard-authorization ($request as map(*), $response as map(*)) as map(*)+ {
    auth:authenticate($request, $response, $auth:DEFAULT_STRATEGIES)
};

(:~
 : general authorization middleware
 : extend request with user information
 : authenticate user via cookie or basic auth
 : authorize users against x-constraints
 :
 : @param $strategies the authorization strategies to use
 : @return the authorization middleware that extends the request map
 :)
declare function auth:use-authorization ($strategies as map(*)) as function(*) {
    auth:authenticate(?, ?, $strategies)
};

(:~ 
 : helper function that sets the cookie name according to the API definition
 :)
declare function auth:add-cookie-name ($request as map(*), $auth-options as map(*)) as map(*) {
    let $cookie-name := auth:read-cookie-name($request?spec)
    return
        if (empty($cookie-name)) then (
            error($errors:OPERATION, 'Cookie-name not specified in API-definition!')
        ) else (
            map:put($auth-options, 'name', $cookie-name)
        )
};

(:~
 : @deprecated Default login handler
 :
 : @param $request the current request map
 : @throws errors:OPERATION if cookieAuth does not provide a login domain 
 :)
declare function auth:login ($request as map(*)) as map(*) {
    let $cookie-name := auth:read-cookie-name($request?spec)
    let $user := auth:login-user(
        $request?body?user, $request?body?password,
        map{ "name": $cookie-name }
    )

    return
        if (exists($user))
        then
            map {
                "user": $user,
                "groups": array { sm:get-user-groups($user) },
                "dba": sm:is-dba($user),
                "domain": $cookie-name
            }
        else
            error($errors:UNAUTHORIZED, "Wrong user or password", map {
                "user": $user,
                "domain": $cookie-name
            })
};

(:~
 : Preferred app-specific login function, that will set a cookie for cookieAuth
 :)
declare function auth:login-user ($user as xs:string, $password as xs:string, $options as map(*)) as xs:string? {
    let $merged-options :=
        if (empty($options?name)) then (
            error($errors:OPERATION, 'Cookie-name not set in call to auth:login-user!')
        ) else (
            map:merge(($auth:DEFAULT_LOGIN_OPTIONS, $options), map{ "duplicates": "use-last" })
        )

    let $ttl :=
        if ($merged-options?maxAge instance of xs:dayTimeDuration) then (
            $merged-options?maxAge
        ) else if ($merged-options?maxAge instance of xs:integer) then (
            xs:dayTimeDuration('PT' || $merged-options?maxAge || 'S')
        ) else (
            error($errors:OPERATION, "the maxAge option value cannot be used", $merged-options?maxAge)
        )

    return (
        util:log($auth:log-level, ("auth:login-user: ", $user)),
        plogin:register($user, $password, $ttl,
            auth:get-register-callback($merged-options))
    )
};

(:~
 : @deprecated Default logout handler
 :
 : @param $request the current request map
 : @throws errors:OPERATION if cookieAuth does not provide a login domain 
 :)
declare function auth:logout ($request as map(*)) as map(*) {
    auth:logout-user(map{ "name": auth:read-cookie-name($request?spec) }),
    map {
        "success": true(),
        "message": "logged out"
    }
};

(:~
 : Preferred logout function for use in app-specific handlers
 : user session will immediately stop working
 :)
declare function auth:logout-user ($options as map(*)) as empty-sequence() {
    let $token :=
        if (empty($options?name)) then (
            error($errors:OPERATION, 'Cookie-name not set in call to auth:logout-user!')
        ) else (
            request:get-cookie-value($options?name)
        )

    return (
        session:invalidate(),
        if ($token and $token != "deleted") then (plogin:invalidate($token)) else (),
        cookie:set(map:merge(
            ($auth:DEFAULT_LOGIN_OPTIONS, $options, $auth:INVALIDATE_COOKIE),
            map{ "duplicates": "use-last" }))
    )
};

declare %private variable $auth:INVALIDATE_COOKIE := map{ "value": "deleted", "maxAge": xs:dayTimeDuration("-P1D") };

(:~
 : Read the login domain from components.securitySchemes.cookieAuth.name
 : @param $spec API definition
 : @deprecated use auth:read-cookie-name instead
 :)
declare function auth:login-domain ($spec as map(*)) as xs:string? {
    auth:read-cookie-name($spec)
};

(:~
 : Read the cookie name from the API definition
 : @param $spec API definition
 :)
declare function auth:read-cookie-name ($spec as map(*)) as xs:string? {
    router:resolve-pointer($spec, ("components", "securitySchemes", "cookieAuth", "name"))
};

declare function auth:use-cookie-auth ($request as map(*)) as map(*)? {
    auth:use-cookie-auth($request, ())
};

(:~
 : 
 : @throws errors:OPERATION if cookieAuth does not provide a login domain 
 :)
declare function auth:use-cookie-auth ($request as map(*), $custom-options as map(*)?) as map(*)? {
    let $cookie-name := auth:read-cookie-name($request?spec)
    let $token := request:get-cookie-value($cookie-name)

    let $user :=
        if (empty($token)) then () else (
            let $merged-options := map:merge(($auth:DEFAULT_LOGIN_OPTIONS, $custom-options, map{ "name": $cookie-name }), map{ "duplicates": "use-last" })
            let $callback := auth:get-credentials-callback($merged-options)
            return plogin:login($token, $callback)
        )

    return (
        (: util:log($auth:log-level, ("auth:use-cookie-auth: token ", substring-before($token, ":") , ":******** evaluated to ", $user)), :)
        if (empty($user)) then () else rutil:getDBUser()
    )
};

(:~
 : Basic authentication is handled by Jetty
 : the user is already authenticated in the database and we just need to
 : retrieve the information here
 :)
declare function auth:use-basic-auth ($request as map(*)) as map(*) {
    util:log($auth:log-level, sm:id()),
    rutil:getDBUser()
};


declare %private function auth:is-public-route ($constraints as map(*)?) as xs:boolean {
    not(exists($constraints))
};

declare %private function auth:is-authorized-user ($constraints as map(*), $user as map(*)?) as xs:boolean {
    exists($user) and 
    (
        not(exists($constraints?groups)) or 
        (: is member of at least one required group :)
        auth:at-least-one-matches($user?groups?*, $constraints?groups)
    ) and
    (
        not(exists($constraints?user)) or 
        (: is the allowed user or one of them :)
        auth:at-least-one-matches($user?name, $constraints?user)
    )
};

declare %private function auth:at-least-one-matches ($data as xs:string*, $constraint as item()) {
    typeswitch($constraint)
        case xs:string return $data = $constraint
        case array(xs:string) return $data = $constraint?*
        default return error($errors:OPERATION,
            "Unable to handle constraint : '" || $constraint || "'")
};

declare %private function auth:authenticate ($request as map(*), $response as map(*), $strategies as map(*)) as map(*)+ {
    let $defined-auth-methods := 
        if (exists($request?config?security)) (: route specific :)
        then ($request?config?security)
        else if (exists($request?spec?security)) (: API global :)
        then ($request?spec?security)
        else ()

    let $methods := array:for-each($defined-auth-methods, auth:map-auth-methods(?, $strategies))

    let $user := array:fold-left($methods, (), auth:use-first-matching-method($request))
    let $constraints := $request?config?x-constraints
    return
        if (
            auth:is-public-route($constraints) or 
            auth:is-authorized-user($constraints, $user)
        )
        then (
            map:put($request, "user", $user), (: add "user" to request :)
            $response
        )
        else error($errors:UNAUTHORIZED, "Access denied")
};

declare %private function auth:map-auth-methods ($method-config as map(*), $strategies as map(*)) as function(*) {
    let $method-name := map:keys($method-config)
    (: TODO handle method-parameters for OAuth and openID
        : let $method-parameters := $method-config?($method-name) :)
    
    return
        if (map:contains($strategies, $method-name))
        then ($strategies($method-name))
        else error(
            $errors:OPERATION,
            "No strategy found for : '" || $method-name || "'", ($method-config, $strategies)
        )
};

declare %private function auth:use-first-matching-method ($request as map(*)) as function(*) {
    function ($user as map(*)?, $method as function(*)) as map(*)? {
        if (exists($user))
        then $user
        else $method($request)
    }
};

declare %private function auth:get-register-callback ($options as map(*)) {
    function (
        $new-token as xs:string?,
        $user as xs:string,
        $password as xs:string,
        $expiration as xs:duration
    ) {
        if ($options?asDba and not(sm:is-dba($user))) then (
            (: raise error here? :)
            util:log($auth:log-level, 'asDba is set to true() but user is non-DBA // not creating a session')
        ) else (
            if ($new-token) then (
                (: session:invalidate(), :)
                cookie:set(
                    map:merge(
                        ($options, map{ "value": $new-token, "maxAge": $expiration }),
                        map{ "duplicates": "use-last" }))
            ) else (),
            let $_ := xmldb:login("/db", $user, $password, $options?createSession)
            return $user
        )
    }
};

declare %private function auth:get-credentials-callback ($options as map(*)) as function(*) {
    function (
        $new-token as xs:string?,
        $user as xs:string,
        $password as xs:string,
        $expiration as xs:duration
    ) as xs:string? {
        (: util:log($auth:log-level, "auth:credentials-callback: --" || $user || "--"), :)
        if (empty($new-token)) then (
            util:log($auth:log-level, "session still valid")
        ) else (
            util:log($auth:log-level, "new token"),
            cookie:set(
                map:merge(($options, map{ "value": $new-token, "maxAge": $expiration}),
                    map{ "duplicates": "use-last" }))
        ),
        (: util:log($auth:log-level, "USER: --" || $user || "--"), :)
        $user
    }
};

