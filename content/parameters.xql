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
module namespace parameters="http://e-editiones.org/roaster/parameters";

import module namespace errors="http://e-editiones.org/roaster/errors";

(:~
 : path parameter middleware
 :)
declare function parameters:in-path ($request as map(*), $response as map(*)) as map(*)+ {
    let $path-param-map := parameters:get-path-parameter-map-from-config($request?config?parameters)
    let $has-path-parameters-in-pattern := contains($request?pattern, "{")

    return
        if (not($has-path-parameters-in-pattern) and exists($path-param-map))
        then error($errors:OPERATION, "Path pattern has no substitutions, but path parameters are defined " || $request?pattern, $request)
        else if (not($has-path-parameters-in-pattern))
        then ($request, $response) (: the matching route does not define path parameters :)
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
                            => xmldb:decode()
                            => parameters:cast($path-param-map?($key))

                        return map { $key : $value }
                    )
                    else
                        error($errors:REQUIRED_PARAM, "No definition for required path parameter " || $substitution)

            (: extend previous parameters map with new values :)
            let $merged := map:merge(($request?parameters, $maps))

            return (
                map:put($request, "parameters", $merged),
                $response

            )
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
declare function parameters:in-request ($request as map(*), $response as map(*)) as map(*)+ {
    if (not(map:contains($request?config, "parameters")))
    then ($request, $response) (: route expects no parameters, return request unchanged :)
    else if (not($request?config?parameters instance of array(*)))
    then error($errors:OPERATION, "Parameter definition must be an array: " || $request?pattern, $request)
    else
        let $maps := for-each($request?config?parameters?*, parameters:retrieve#1)

        (: extend previous parameters map with new values :)
        let $merged := map:merge(($request?parameters, $maps))

        return (
            map:put($request, "parameters", $merged),
            $response
        )
};

declare %private function parameters:retrieve ($parameter as map(*)) as map(*)? {
    if (parameters:is-path-parameter($parameter))
    then ()
    else
        let $name := $parameter?name
        let $values := 
            switch ($parameter?in)
                case "header" return
                    try { request:get-header($name) } catch * { () }
                case "cookie" return
                    request:get-cookie-value($name)
                default return
                    request:get-parameter($name, ())

        return (
            if (exists($parameter?style) and $parameter?style = ("simple", "label", "matrix")) then (
                error($errors:NOT_IMPLEMENTED, "Unsupported parameter style " || $parameter?style || " for parameter " || $name || ".")
            ) else if ($parameter?required and empty($values)) then (
                error($errors:REQUIRED_PARAM, "Parameter " || $name || " is required")
            ) else (
                map { $name : parameters:cast($values, $parameter) }
            )
        )
};

declare %private function parameters:get-parameter-default-value ($schema as map(*)?) as item()? {
    if (exists($schema)) 
    then ($schema?default)
    else ()
};

declare %private function parameters:cast ($values as xs:string*, $config as map(*)) as item()* {
    switch($config?schema?type)
        case "object" return 
            error($errors:NOT_IMPLEMENTED, "Parameter '" || $config?name || "' is of type 'object', which is not supported yet.")
        case "array" return
            parameters:cast-array($values, $config)
        default return (
            head((
                $values,
                parameters:get-parameter-default-value($config?schema)
            )) ! parameters:cast-value(., $config?schema)
        )
};

declare %private function parameters:cast-array($values as xs:string*, $config as map(*)) as array(*)? {
    let $default := parameters:get-parameter-default-value($config?schema)
    let $cast := parameters:cast-value(?, $config?schema?items)
    (: for style "form", explode is true by default, false otherwise :)
    let $explode := boolean($config?explode) or ($config?style = "form" and empty($config?explode))

    return if (empty($values) and empty($default)) then (
        (: null :)
    ) else if (empty($values)) then (
        array:for-each($default, $cast)
    ) else if ($explode and $config?style = ("spaceDelimited", "pipeDelimited")) then (
        error($errors:OPERATION, "Unsupported combination of parameter style " || $config?style || " with explode set to true.")
    ) else if ($explode) then (
        array {
            for-each($values, $cast)
        }
    ) else (
        let $separator := 
            switch ($config?style)
            case "spaceDelimited" return " "
            case "pipeDelimited" return "\|" (: pipe needs to be escaped for use in tokenize :)
            case "form" return ","
            default return ()

        return array {
            for-each(tokenize($values, $separator), $cast)
        }
    )
};

declare %private function parameters:cast-value ($value as item()?, $schema as map(*)) as item()? {
    switch($schema?type)
        case "integer" return
            switch ($schema?format)
                case "int32"
                case "int64" return
                    xs:int($value)

                default return
                    xs:integer($value)

        case "number" return
            switch ($schema?format)
                case "float" return
                    xs:float($value)
                case "double" return
                    xs:double($value)

                default return
                    number($value)

        case "boolean" return
            xs:boolean($value)

        case "string" return
            switch ($schema?format)
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

        default return
            string($value)
};