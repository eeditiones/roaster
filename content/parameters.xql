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
module namespace parameters="http://exist-db.org/xquery/router/parameters";

import module namespace errors = "http://exist-db.org/xquery/router/errors";

declare function parameters:in-path ($match as map(*), $config) as map(*)* {
    let $substitutions := analyze-string($match?pattern, "\{([^\}]+)\}")
    let $match-path := analyze-string($match?path, $match?regex)

    for $substitution at $pos in $substitutions//fn:group
    let $value := $match-path//fn:group[@nr=$pos]/string()
    let $param-config :=
        if ($config?parameters instance of array(*))
        then
            filter($config?parameters?*, function($parameter as array(*)) {
                $parameter?in = "path" and
                $parameter?name = $substitution
            })
        else ()

    return
        if (exists($param-config)) then
            map { $substitution/string() : parameters:cast($value, head($param-config)) }
        else
            error($errors:REQUIRED_PARAM, "No definition for required path parameter " || $substitution)
};

declare function parameters:in-request ($route as map(*)) as map(*)* {
    let $params := $route?parameters
    return
        if (exists($params)) then
            for $param in $params?*
            where $param?in != "path"
            let $default := if (exists($param?schema)) then $param?schema?default else ()
            let $values := 
                switch ($param?in)
                    (: todo case "body" :)
                    case "header" return
                        head((request:get-header($param?name), $default))
                    case "cookie" return
                        head((request:get-cookie-value($param?name), $default))
                    default return
                        request:get-parameter($param?name, $default)
            return
                if ($param?required and empty($values)) then
                    error($errors:REQUIRED_PARAM, "Parameter " || $param?name || " is required")
                else
                    map { $param?name : parameters:cast($values, $param) }
        else
            ()
};

declare %private function parameters:cast ($values as xs:string*, $config as map(*)) as item()* {
    for $value in $values
    return
        switch($config?schema?type)
            case "integer" return
                if ($config?schema?format) then
                    switch ($config?schema?format)
                        case "int32" case "int64" return
                            xs:int($value)
                        default return
                            xs:integer($value)
                else
                    xs:integer($value)
            case "number" return
                if ($config?schema?format) then
                    switch ($config?schema?format)
                        case "float" return
                            xs:float($value)
                        case "double" return
                            xs:double($value)
                        default return
                            number($value)
                else
                    number($value)
            case "boolean" return
                xs:boolean($value)
            case "string" return
                if ($config?schema?format) then
                    switch ($config?schema?format)
                        case "date" return
                            xs:date($value)
                        case "date-time" return
                            xs:dateTime($value)
                        case "binary" return
                            xs:base64Binary($value)
                        case "byte" return
                            util:binary-to-string(xs:base64Binary($value))
                        default return
                            string($value)
                else
                    string($value)
            default return
                string($value)
};

(:~
 : Try to retrieve and convert the request body if specified
 :)
declare function parameters:body ($request-body-config as map(*)?) as item()* {
    if (not(exists($request-body-config) and exists($request-body-config?content)))
    then () (: this route expects no body in request :)
    else (
        let $content := $request-body-config?content
        let $content-type-header := 
            request:get-header("Content-Type")
            => replace("^([^;]+);?.*$", "$1") (: strip charset info from mime-type if present :)

        return
            if (map:contains($content, $content-type-header))
            then (
                let $content-type := $content($content-type-header)
                let $body := request:get-data()
                return
                    switch ($content-type-header)
                        case "application/json" return
                            $body => util:binary-to-string() => parse-json()
                        case "text/xml" (: fall-through :)
                        case "application/xml" return
                            $body
                        case "multipart/form-data" return
                            () (: TODO: implement form-data handling? :)
                        default return
                            error($errors:BODY_CONTENT_TYPE, "Unable to handle request body content type " || $content-type)
            )
            else 
                error($errors:BODY_CONTENT_TYPE, "Passed in Content-Type " || $content-type-header || 
                    " not allowed")
    )
};
