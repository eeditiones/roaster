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
 : Utility handler functions for getting the current user and debugging
 :)
module namespace rutil="http://e-editiones.org/roaster/util";

import module namespace router="http://e-editiones.org/roaster/router";

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
    router:response(200, "application/json", $request)
};