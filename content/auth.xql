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

import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

import module namespace router="http://e-editiones.org/roaster/router";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";

(: API Request Authentication and Authorisation :)

(:~
 :)
declare variable $auth:DEFAULT_STRATEGIES := map {
    "cookieAuth": auth:use-cookie-auth#1,
    "basicAuth": auth:use-basic-auth#1
};

(:~
 : standard authorization middleware
 : extend request with user information
 : authenticate user via cookie or basic auth
 : authorize users against x-constraints
 :
 : @param $request the current request
 : @return the extended request map
 :)
declare function auth:standard-authorization($request as map(*), $response as map(*)) as map(*)+ {
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
declare function auth:use-authorization($strategies as map(*)) as function(*) {
    auth:authenticate(?, ?, $strategies)
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

    let $methods := $defined-auth-methods 
        => array:for-each(function ($method-config as map(*)) {
            let $method-name := map:keys($method-config)
            (: TODO handle method-parameters for OAuth and openID
             : let $method-parameters := $method-config?($method-name) :)
            
            return
                if (map:contains($strategies, $method-name))
                then (
                    let $auth-method := $strategies($method-name)
                    return function () {
                        $auth-method($request)
                    }
                )
                else error(
                    $errors:OPERATION,
                    "No strategy found for : '" || $method-name || "'", ($method-config, $strategies)
                )
        })

    let $user := array:fold-left($methods, (), auth:use-first-matching-method#2)
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

declare function auth:use-first-matching-method ($user as map(*)?, $method as function(*)) as map(*)? {
    if (exists($user))
    then $user
    else $method()
};

(:~
 : Either login a user (if parameter `user` is specified) or check if the current user is logged in.
 : Setting parameter `logout` to any value will log out the current user.
 :
 : @param $request the current request map
 : @throws errors:OPERATION if cookieAuth does not provide a login domain 
 :)
declare function auth:login($request as map(*)) {
    (: login-domain must be configured! :)
    let $login-domain := auth:login-domain($request?spec)

    let $login :=
        if ($request?parameters?user)
        then
            login:set-user($login-domain, (), false())
        else
            ()

    let $user := request:get-attribute($login-domain || ".user")
    (: Work-around for the actual login request  
     : It is possible that the session is not yet ready 
     : and sm:id() still reports "guest" as real user
     :)
    let $session-ready := (sm:id()//sm:real/sm:username/string() = $user)
    return
        if (exists($user) and $session-ready)
        then
            map {
                "user": $user,
                "groups": array { sm:get-user-groups($user) },
                "dba": sm:is-dba($user),
                "domain": $login-domain
            }
        else if (exists($user))
        then
            map {
                "user": $user,
                "domain": $login-domain
            }
        else
            error($errors:UNAUTHORIZED, "Wrong user or password", map {
                "user": $user,
                "domain": $login-domain
            })
};

(:~
 : Read the login domain from components.securitySchemes.cookieAuth.name
 : @param $spec API definition
 : @throws errors:OPERATION if cookieAuth does not provide a login domain 
 :)
declare function auth:login-domain ($spec as map(*)) as xs:string {
    router:resolve-pointer($spec, ("components", "securitySchemes", "cookieAuth", "name"))
};

(:~
 : 
 : @throws errors:OPERATION if cookieAuth does not provide a login domain 
 :)
declare function auth:use-cookie-auth ($request as map(*)) as map(*)? {
    (: login-domain must be configured! :)
    let $login-domain := auth:login-domain($request?spec)
    let $login := login:set-user($login-domain, (), false())
    let $user := request:get-attribute($login-domain || ".user")
    return (
        if ($user)
        then rutil:getDBUser()
        else ()
    )
};

(:~
 : Basic authentication is handled by Jetty
 : the user is already authenticated in the database and we just need to
 : retrieve the information here
 :)
declare function auth:use-basic-auth ($request as map(*)) as map(*) {
    rutil:getDBUser()
};
