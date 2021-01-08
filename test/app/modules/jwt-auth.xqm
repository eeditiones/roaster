xquery version "3.1";

(:~
 : example implementation to use exist-JWT in combination with roaster, the OpenAPI router
 :)
module namespace jwt-auth="http://e-editiones.org/roasted/jwt-auth";


import module namespace jwt="http://existsolutions.com/ns/jwt";
import module namespace router="http://e-editiones.org/roaster/router";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";


(:~
 : configure and get JWT instance
 :)
declare %private variable $jwt-auth:secret := "your-256-bit-secret";
declare %private variable $jwt-auth:token-lifetime := 30*60; (: 30 minutes :)
declare %private variable $jwt-auth:jwt := jwt:instance($jwt-auth:secret, $jwt-auth:token-lifetime);

(:~
 : The name of the securityScheme in API definition
 :)
declare variable $jwt-auth:METHOD := "JWTAuth";

(:~
 : The name of the securityScheme in API definition
 :)
declare variable $jwt-auth:handler := map { $jwt-auth:METHOD : jwt-auth:bearer-auth#1 };

(:~
 : which header to check for the token 
 : TODO: Authorization header seems to be swallowed by jetty
 : TODO: implement function to cut off scheme (BEARER )
 :)
declare variable $jwt-auth:AUTH_HEADER := "X-Auth-Token";

declare function jwt-auth:issue-token ($request as map(*)) {
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
                router:response(201, (), map {
                    "user": $user,
                    "token": $jwt-auth:jwt?create($user)
                }, ())
            )
            else
                error($errors:UNAUTHORIZED, 'Username or password incorrect')
    )
    else
        error($errors:BAD_REQUEST, "Missing parameters 'username' and/or 'password'")
};

declare function jwt-auth:bearer-auth ($request as map(*)) as map(*)? {
    try {
        (: need to access request header directly because it will not be part of parameters :)
        let $token := request:get-header($jwt-auth:AUTH_HEADER)
        return
            if (exists($token))
            then (
                let $payload := $jwt-auth:jwt?read($token)
                return map {
                    "name": $payload?name,
                    "groups": $payload?groups,
                    "dba": $payload?dba
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
