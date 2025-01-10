(:
 :  Copyright (C) 2024 TEI Publisher Project Team
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
module namespace cookie="http://e-editiones.org/roaster/cookie";

import module namespace response="http://exist-db.org/xquery/response";
import module namespace errors="http://e-editiones.org/roaster/errors";

declare %private variable $cookie:enforce-rfc2109 := "[/()<>@,;:\\""\[\]\?=\{\} \t]";
declare variable $cookie:properties := map{
    "Domain": "xs:string",
    "Path": "xs:string",
    "SameSite": ("None", "Lax", "Strict"),
    "Secure": "xs:boolean",
    "HttpOnly": "xs:boolean"
};

(:~
 : Custom implementation of response:set-cookie in XQuery
 : Uses response:set-header instead
 : The cookie is built from the passed in map
 : This allows to set more cookie attributes
 : Specifically, SameSite and HttpOnly
 :
 : name and value are mandatory, 
 : if they are missing an error is raised with code $errors:OPERATION.
 : The same error will be raised, if maxAge is not an
 : instance of xs:dayTimeDuration
 :
 : Example Input
   map {
    "name": "awesome.cookie",
    "value": "._.*^*._.*^*._.*^*._.*^*._.*",
    "maxAge": xs:dayTimeDuration("P1D"),
    "Path": "/",
    "SameSite": "Strict",
    "Secure": false(),
    "HttpOnly": true()
    }
 :)
declare function cookie:set($options as map(*)) as empty-sequence() {
    response:set-header('Set-Cookie', string-join(
        (
            cookie:name-and-value($options?name, $options?value),
            cookie:lifetime($options?maxAge),
            cookie:samesite($options?SameSite),
            cookie:add-property($options, "Domain"),
            cookie:add-property($options, "Path"),
            cookie:add-flag($options, "Secure"),
            cookie:add-flag($options, "HttpOnly")
        ),
        "; "
    ))
};

declare %private function cookie:name-and-value($name as xs:string?, $value as xs:string?) as xs:string {
    if (empty($name) or empty($value)) then (
        error($errors:OPERATION, "cookie:set: Cookie name and value must be set", ($name, $value))
    ) else
    if (matches($name, $cookie:enforce-rfc2109)) then (
        error($errors:OPERATION, "cookie:set: Cookie name contains illegal charecters", $name)
    ) else if ($name = map:keys($cookie:properties)) then (
        error($errors:OPERATION, "cookie:set: Cookie name cannot be equal to property name", $name)
    ) else (
        $name || "=" || $value
    )
};

declare %private function cookie:lifetime($maxAge as item()?) as xs:string* {
    if (empty($maxAge)) then (
        (: the cookie will not expire :) 
    ) else if (
        not($maxAge instance of xs:dayTimeDuration)
        and not($maxAge castable as xs:integer)
    ) then (
        error($errors:OPERATION, "cookie:set: maxAge must be an instance of xs:dayTimeDuration or xs:integer", $maxAge)
    ) else if ($maxAge instance of xs:integer) then (
        "Max-Age=" || $maxAge,
        "Expires=" || string(current-dateTime() + xs:dayTimeDuration('PT' || $maxAge || 'S'))
    ) else (
        "Max-Age=" || ($maxAge div xs:dayTimeDuration('PT1S')),
        "Expires=" || string(current-dateTime() + $maxAge)
    )
};

declare %private function cookie:samesite($samesite as xs:string?) as xs:string? {
    if (empty($samesite)) then (
        (: unset :)
    ) else if (not($samesite = $cookie:properties?SameSite)) then (
        error($errors:OPERATION, "cookie:set: SameSite must be one of " || string-join($cookie:properties?SameSite, ", "), $samesite)
    ) else (
        "SameSite=" || $samesite
    )
};

declare %private function cookie:add-property($options as map(*), $property as xs:string) as xs:string? {
    if (empty($options?($property))) then () else (
        $property || "=" || $options?($property)
    )
};

declare %private function cookie:add-flag($options as map(*), $property as xs:string) as xs:string? {
    if (boolean($options?($property))) then ($property) else ()
};

