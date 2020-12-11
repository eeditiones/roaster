xquery version "3.1";

(:~
 : example implementation to use exist-JWT in combination with OAS-router
 :)
module namespace auth="https://e-editiones.com/oas-router/xquery/jwt-auth";


declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";


import module namespace jwt="http://existsolutions.com/ns/jwt";
import module namespace router="http://exist-db.org/xquery/router";
import module namespace rutil="http://exist-db.org/xquery/router/util";
import module namespace errors="http://exist-db.org/xquery/router/errors";


(:~
 : configure and get JWT instance
 :)
declare %private variable $auth:secret := "your-256-bit-secret";
declare %private variable $auth:token-lifetime := 30*60; (: 30 minutes :)
declare %private variable $auth:jwt := jwt:instance($auth:secret, $auth:token-lifetime);

(:~
 : The name of the securityScheme in API definition
 :)
declare variable $auth:METHOD := "JWTAuth";

(:~
 : which header to check for the token 
 : TODO: Authorization header seems to be swallowed by jetty
 : TODO: implement function to cut off scheme (BEARER )
 :)
declare variable $auth:AUTH_HEADER := "X-Auth-Token";

declare function auth:issue-token($request as map(*)) {
    if (
        $request?body instance of map(*) and 
        map:contains($request?body, 'username') and
        map:contains($request?body, 'password')
    )
    then (
        let $username := $request?body?username
        let $password := $request?body?password
        let $loggedin := xmldb:login("/db/apps/", $username, $password, false())
        let $user := rutil:getDBUser()

        return
            if ($loggedin and $username = $user?name)
            then (
                router:response(201, map {
                    "user": $user,
                    "token": $auth:jwt?create($user)
                })
            )
            else
                error($errors:UNAUTHORIZED, 'Username or password incorrect')
    )
    else
        error($errors:BAD_REQUEST, "Missing parameters 'username' and/or 'password'")
};

declare function auth:bearer-auth ($spec as map(*), $parameters as map(*)) as map(*)? {
    try {
        (: need to access request header directly because it will not be part of parameters :)
        let $token := request:get-header($auth:AUTH_HEADER)
        return
            if (exists($token))
            then (
                let $payload := $auth:jwt?read($token)
                return map {
                    "name": $payload?name,
                    "groups": $payload?groups
                }
            )
            else ()
    }
    catch too-old {
        error($errors:UNAUTHORIZED, "Token lifetime exceeded, please request a new one")
    }
    catch invalid-token | invalid-header | invalid-signature | future-date {
        error($errors:BAD_REQUEST, "token invalid")
    }
    catch * {
        error($errors:SERVER_ERROR, "Server error")
    }
};
