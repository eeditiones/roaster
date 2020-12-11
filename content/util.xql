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
xquery version "3.1";

(:~
 : Utility handler functions for user login/logout and debugging.
 :)
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

declare function rutil:cookie-auth($config as map(*), $parameters as map(*)) {
    let $login-domain := router:login-domain($config?spec)
    return (
        if ($login-domain)
        then (
            let $login := login:set-user($login-domain, (), false())
            return rutil:getDBUser()
        )
        else ()
    )
};

(:~
 : Basic authentication is handled by Jetty
 : the user is already authenticated in the database and we just need to
 : retrieve the information here
 :)
declare function rutil:basic-auth($spec as map(*), $parameters as map(*)) {
    rutil:getDBUser()
};

declare function rutil:getDBUser() as map(*) {
    let $smid := sm:id()/sm:id
    (: 
     : TODO unsure if sm:effective should ever be exposed by this
     : but this is the only way to reliable get token issue request work
     : xmldb:login seems to set sm:effective instead of sm:real
     :)
    let $user := ($smid/sm:effective, $smid/sm:real)[1]
    let $name := $user/sm:username/text()
    return map {
        "name": $name,
        "groups": array { $user//sm:group/text() },
        "dba" : sm:is-dba($name)
    }
};

(:~
 : Return a JSON representation of the current request, showing the
 : parameters, configuration and request body which would be available
 : to handler functions.
 :)
declare function rutil:debug($request as map(*)) {
    router:response(200, "application/json",
        map {
            "parameters": $request?parameters,
            "body": $request?body,
            "method": request:get-method(),
            "pattern": $request?config?pattern,
            "path": $request?config?path,
            "regex": $request?config?regex,
            "priority": $request?config?priority,
            "user": $request?user
        }
    )
};