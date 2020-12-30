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
 : The core library functions of the OAS router.
 :)
module namespace roaster="http://e-editiones.org/roaster";

import module namespace router="http://e-editiones.org/roaster/router";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace parameters="http://e-editiones.org/roaster/parameters";
import module namespace auth="http://e-editiones.org/roaster/auth";

(:~
 : May be called from user code to send a response with a particular
 : response code (other than 200). The media type will be determined by
 : looking at the response specification for the given status code.
 :
 : @param code the response code to return
 : @param body data to be sent in the body of the response
 :)
declare function roaster:response ($code as xs:integer, $body as item()*) {
    router:response($code, (), $body, ())
};

(:~
 : May be called from user code to send a response with a particular
 : response code (other than 200) or media type.
 :
 : @param $code the response code to return
 : @param $mediaType the Content-Type for the response; assumes that the provided body can
 : be converted into the target media type
 : @param $body data to be sent in the body of the response
 :)
declare function roaster:response ($code as xs:integer, $media-type as xs:string?, $body as item()*) {
    router:response($code, $media-type, $body, ())
};

declare function roaster:response ($code as xs:integer, $media-type as xs:string?, $body as item()*, $headers as map(*)?) {
    router:response($code, $media-type, $body, $headers)
};

(:~
 : resolve pointer to information in API definition
 :
 : @param $config the API definition
 : @param $ref either a single string from $ref or a sequence of strings 
 :)
declare function roaster:resolve-pointer ($config as map(*), $ref as xs:string*) {
    router:resolve-pointer($config, $ref)
};

(:~
 : Maps a request to the configured handler 
 : Loads API definitions, matches routes
 : Calls route handler function returned by $lookup function
 : Uses standard authorization strategies
 :
 : Route specificity rules:
 : 1. normalize patterns: replace placeholders with "?"
 : 2. use the matching route with the longest normalized pattern
 : 3. If two paths have the same (normalized) length, prioritize by appearance in API files, first one wins
 :)
declare function roaster:route($api-files as xs:string+, $lookup as function(xs:string) as function(*)?) {
    router:route($api-files, $lookup, auth:standard-authorization#2)
};

declare function roaster:route($api-files as xs:string+, $lookup as function(xs:string) as function(*)?, $middleware) {
    router:route($api-files, $lookup, $middleware)
};

declare function roaster:accepted-content-types () as xs:string* {
    router:accepted-content-types()
};
