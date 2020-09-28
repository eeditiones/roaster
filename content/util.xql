xquery version "3.1";

module namespace rutil="http://exist-db.org/xquery/router/util";

import module namespace errors="http://exist-db.org/xquery/router/errors";
import module namespace router="http://exist-db.org/xquery/router";
import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

(:~
 : Either login a user (if parameter `user` is specified) or check if the current user is logged in.
 : Setting parameter `logout` to any value will log out the current user.
 :)
declare function rutil:login($request as map(*)) {
    if ($request?parameters?user) then
        login:set-user($request?loginDomain, (), false())
    else
        (),
    let $user := request:get-attribute($request?loginDomain || ".user")
    return
        if (exists($user)) then
            map {
                "user": $user,
                "groups": array { sm:get-user-groups($user) },
                "dba": sm:is-dba($user)
            }
        else
            error($errors:UNAUTHORIZED, "Wrong user or password", map {
                "user": $user,
                "domain": $request?loginDomain
            })
};

(:~
 : Return a JSON representation of the current request, showing the
 : parameters, configuration and request body which would be available
 : to handler functions.
 :)
declare function rutil:debug($request as map(*)) {
    router:response(200, "application/json",
        map {
            "parameters":
                map:merge(
                    map:for-each($request?parameters, function($key, $value) {
                        map {
                            $key: $value
                        }
                    })
                ),
            "body": $request?body,
            "config": $request?config
        }
    )
};