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

import module namespace errors="http://exist-db.org/xquery/router/errors";

(:~
 : path parameter middleware
 :)
declare function parameters:in-path ($request as map(*)) as map(*)* {
    let $path-param-map := parameters:get-path-parameter-map-from-config($request?config?parameters)
    let $has-path-parameters-in-pattern := contains($request?pattern, "{")

    return
        if (not($has-path-parameters-in-pattern) and exists($path-param-map))
        then error($errors:OPERATION, "Path pattern has no substitutions, but path parameters are defined " || $request?pattern, $request)
        else if (not($has-path-parameters-in-pattern))
        then $request (: the matching route does not define path parameters :)
        else
            let $substitutions := analyze-string($request?pattern, "\{([^\}]+)\}")
            let $match-path := analyze-string($request?path, $request?regex)

            let $maps :=
                for $substitution at $pos in $substitutions//fn:group
                let $key := $substitution/string()
                return
                    if (map:contains($path-param-map, $key))
                    then (
                        let $value :=
                            $match-path//fn:group[@nr=$pos]/string()
                            => parameters:cast($path-param-map?($key))

                        return map { $key : $value }
                    )
                    else
                        error($errors:REQUIRED_PARAM, "No definition for required path parameter " || $substitution)

            (: extend previous parameters map with new values :)
            let $merged := map:merge(($request?parameters, $maps))

            return map:put($request, "parameters", $merged)
};

declare %private function parameters:is-path-parameter($parameter as map(*)) as xs:boolean {
    $parameter?in = "path"
};

declare %private function parameters:get-path-parameter-map-from-config ($parameters as array(*)?) as map(*)? {
    if (not(exists($parameters)))
    then () (: no parameters defined :)
    else
        let $path-parameters :=
            for-each($parameters?*, function ($parameter as map(*)) as map(*)? {
                if (parameters:is-path-parameter($parameter))
                then map { $parameter?name : $parameter }
                else ()
            })
        
        return
            if (count($path-parameters))
            then map:merge($path-parameters)
            else ()
};

(:~
 : request parameter middleware
 :)
declare function parameters:in-request ($request as map(*)) as map(*)* {
    if (not(map:contains($request?config, "parameters")))
    then ($request) (: route expects no parameters, return request unchanged :)
    else if (not($request?config?parameters instance of array(*)))
    then error($errors:OPERATION, "Parameter definition must be an array: " || $request?pattern, $request)
    else
        let $maps := for-each($request?config?parameters?*, parameters:retrieve#1)

        (: extend previous parameters map with new values :)
        let $merged := map:merge(($request?parameters, $maps))

        return
            map:put($request, "parameters", $merged)
};

declare %private function parameters:retrieve ($parameter as map(*)) as map(*)? {
    if (parameters:is-path-parameter($parameter))
    then ()
    else
        let $name := $parameter?name
        let $default := parameters:get-parameter-default-value($parameter?schema)
        let $values := 
            switch ($parameter?in)
                (: TODO case "body" :)
                case "header" return
                    head((request:get-header($name), $default))
                case "cookie" return
                    head((request:get-cookie-value($name), $default))
                default return
                    request:get-parameter($name, $default)

        return
            if ($parameter?required and empty($values)) then
                error($errors:REQUIRED_PARAM, "Parameter " || $name || " is required")
            else
                map { $name : parameters:cast($values, $parameter) }
};

declare %private function parameters:get-parameter-default-value ($schema as map(*)?) as item()? {
    if (exists($schema)) 
    then ($schema?default)
    else ()
};

declare %private function parameters:cast ($values as xs:string*, $config as map(*)) as item()* {
    (: TODO handle $ref :)
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
declare function parameters:body ($request as map(*)) as item()* {
    if (
        not(map:contains($request?config, "requestBody")) or
        not(map:contains($request?config?requestBody, "content"))
    )
    then ($request) (: this route expects no body in request, return untouched :)
    else (
        let $content-spec := $request?config?requestBody?content
        let $content-type-header := 
            request:get-header("Content-Type")
            => replace("^([^;]+);?.*$", "$1") (: strip charset info from mime-type if present :)

        let $content :=
            if (map:contains($content-spec, $content-type-header))
            then (
                let $content-type := $content-spec($content-type-header)
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

        return map:put($request, "body", $content)
    )
};
