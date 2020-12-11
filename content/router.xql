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
module namespace router="http://exist-db.org/xquery/router";

import module namespace errors = "http://exist-db.org/xquery/router/errors";

declare variable $router:RESPONSE_CODE := xs:QName("router:RESPONSE_CODE");
declare variable $router:RESPONSE_TYPE := xs:QName("router:RESPONSE_TYPE");
declare variable $router:RESPONSE_BODY := xs:QName("router:RESPONSE_BODY");

declare variable $router:path-parameter-matcher := "\{[^\}]+\}";

declare function router:route($api-files as xs:string+, $lookup as function(xs:string) as function(*)?, $strategies as map(xs:string, function(*))) {
    let $request-id := util:uuid()
    let $controller := request:get-attribute("$exist:controller")
    let $path := request:get-attribute("$exist:path")
    let $method := request:get-method() => lower-case()
    let $base-collection := ``[`{repo:get-root()}`/`{$controller}`/]``
    let $number-of-api-files := count($api-files)
    let $log-data := map { "id": $request-id, "method": $method, "path": $path }

    return (
        util:log("info", ``[[`{$request-id}`] `{$method}` `{$path}`]``),
        try {
            (: load router definitions :)
            let $route-definitions := 
                for $api-file in $api-files
                let $file-path := concat($base-collection, $api-file)
                let $config := json-doc($file-path)
                return 
                    if (exists($config))
                    then ($config)
                    else error($errors:OPERATION, "Failed to load JSON file from " || $file-path)

            (: find all matching routes :)
            let $matching-routes :=
                for $config at $pos in $route-definitions
                let $priority := $number-of-api-files - $pos
                return
                    router:match-route(map { 
                        "method": $method,
                        "path": $path,
                        "spec": $config,
                        "priority": $priority
                    })

            let $first-match :=
                if (empty($matching-routes)) then
                    error($errors:NOT_FOUND, "No route matches pattern: " || $path)
                else if (count($matching-routes) eq 1) then
                    $matching-routes
                else (
                    (: if there are multiple matches, prefer the one matching the longest pattern and the highest priority :)
                    util:log("warn", "ambigous route: " || $path),
                    head(sort($matching-routes, (), router:route-specificity#1))
                )

            return (
                router:process($first-match, $lookup, $strategies),
                util:log("info", ``[[`{$request-id}`] `{$method}` `{$path}`: OK]``)
            )

        } catch errors:BAD_REQUEST_400 | errors:REQUIRED_PARAM | errors:BODY_CONTENT_TYPE {
            router:log-error($log-data,
                map { "code": $err:code, "description": $err:description, "value": $err:value}),
            router:send(400, $err:description, $err:value, $lookup)
        } catch errors:UNAUTHORIZED_401 {
            router:log-error($log-data,
                map { "code": $err:code, "description": $err:description, "value": $err:value}),
            router:send(401, $err:description, $err:value, $lookup)
        } catch errors:FORBIDDEN_403 {
            router:log-error($log-data,
                map { "code": $err:code, "description": $err:description, "value": $err:value}),
            router:send(403, $err:description, $err:value, $lookup)
        } catch errors:NOT_FOUND_404 {
            router:log-error($log-data,
                map { "code": $err:code, "description": $err:description, "value": $err:value}),
            router:send(404, $err:description, $err:value, $lookup)
        } catch errors:METHOD_NOT_ALLOWED_405 {
            router:log-error($log-data,
                map { "code": $err:code, "description": $err:description, "value": $err:value}),
            router:send(405, $err:description, $err:value, $lookup)
        } catch * {
            router:log-error($log-data, map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number
            })
            ,
            if (contains($err:description, "permission")) then
                router:send(403, $err:description, $err:value, $lookup)
            else (
                router:send(500, $err:description, $err:value, $lookup)
            )
        }
    )
};

declare function router:log-error($request as map(*), $data as map(*)) {
    util:log("error", 
        ``[[`{$request?id}`] `{$request?method}` `{$request?path}`: `{serialize($data, map{"method": "adaptive"})}`]``)
};


(: find matching route by checking each path pattern :)
declare function router:match-route($info as map(*)) {
    map:for-each($info?spec?paths, function ($route-pattern as xs:string, $route-config as map(*)) {
        let $regex := router:create-regex($route-pattern)
        let $match := matches($info?path, $regex)

        return
            if (not($match)) then ()
            else if (map:contains($route-config, $info?method)) then (
                map:merge(($info, map {
                    "pattern": $route-pattern,
                    "config": $route-config($info?method),
                    "regex": $regex
                }))
            )
            else (
                error($errors:METHOD_NOT_ALLOWED, 
                    "The method "|| $info?method || " is not supported for " || $info?path))
    })
};

declare function router:use-first-matching-auth-method ($user as map(*)?, $method as function(*)) as map(*)? {
    if (exists($user))
    then $user
    else $method()
};

declare function router:auth ($route as map(*), $strategies as map(*), $parameters as map(*)) as map(*)? {
    let $allowed-auth-methods := 
        if (exists($route?config?security))
        then ($route?config?security)
        else if (exists($route?spec?security))
        then ($route?spec?security)
        else ()

    let $allowed-method-names := $allowed-auth-methods 
        => array:for-each(function ($method-config as map(*)) {
            let $method-name := map:keys($method-config)
            (: let $method-parameters := $method-config?($method-name) :)
            
            return
                if (map:contains($strategies, $method-name))
                then (
                    let $auth-method := $strategies($method-name)
                    return function () { $auth-method($route, $parameters) }
                )
                else error(
                    $errors:OPERATION,
                    "No strategy found for : '" || $method-name || "'", ($method-config, $strategies)
                )
        })

    return array:fold-left(
        $allowed-method-names, (),
        router:use-first-matching-auth-method#2)
};

declare function router:process($route as map(*), $lookup as function(*), $strategies as map(xs:string, function(*))) {
    let $parameters := map:merge((
        router:map-request-parameters($route?config),
        router:map-path-parameters($route, $route?path)
    ))

    let $request := map {
        "parameters": $parameters,
        "body": router:request-body($route?config?requestBody),
        (: "loginDomain": $loginDomain, :)
        "info": $route?spec?info,
        "config": $route,
        "user": router:auth($route, $strategies, $parameters)
    }
    let $constraints := $route?config?("x-constraints")

    return 
        if (
            router:is-public-route($constraints) or 
            router:is-authorized($constraints, $request?user)
        )
        then (
            let $response := router:exec($route?config, $request, $lookup)
            return router:write-response(200, $response, $route?config)
        )
        else error($errors:UNAUTHORIZED, "Access denied")
};

declare %private function router:route-specificity ($route as map(*)) as xs:integer+ {
    replace($route?pattern, $router:path-parameter-matcher, "?") (: normalize route specificity by replacing path params :)
    => string-length() (: the longer the more specific :)
    => (function ($a) { -$a })() (: sort descending :)
    ,
    -$route?priority (: sort descending :)
};

declare function router:is-public-route ($constraints as map(*)?) as xs:boolean {
    not(exists($constraints))
};

declare function router:is-authorized($constraints as map(*), $user as map(*)?) {
    (exists($constraints?groups) and $user?groups = $constraints?groups?*) or
    (exists($constraints?user) and $user?name = $constraints?user)
};

(:~
 : Look up the XQuery function whose name matches property "operationId". If found,
 : call it and pass the request map as single parameter.
 :)
declare function router:exec($route as map(*), $request as map(*), $lookup as function(xs:string) as function(*)?) {
    let $operation-id := $route?operationId
    let $error-handler := $route?('x-error-handler')

    return
        if (not($operation-id)) then
            error($errors:OPERATION, "Operation does not define an operationId")
        else
            try {
                let $fn := $lookup($operation-id)
                return $fn($request)
            } catch * {
                (: Catch all errors and add the current route configuration to $err:value,
                    so we can check it later to format the response :)
                if (not($error-handler)) 
                then
                    error($err:code, if ($err:description) then $err:description else '', map {
                        "_config": $route,
                        "_response": $err:value
                    })
                else
                    error($err:code, '', map {
                        "_config": $route,
                        "_response": if (exists($err:value)) then $err:value else $err:description
                    })
            }
};

(:~
 : May be called from user code to send a response with a particular
 : response code (other than 200). The media type will be determined by
 : looking at the response specification for the given status code.
 :
 : @param code the response code to return
 : @param body data to be sent in the body of the response
 :)
declare function router:response($code as xs:integer, $body as item()*) {
    router:response($code, (), $body)
};

(:~
 : May be called from user code to send a response with a particular
 : response code (other than 200) or media type.
 :
 : @param code the response code to return
 : @param mediaType the Content-Type for the response; assumes that the provided body can
 : be converted into the target media type
 : @param body data to be sent in the body of the response
 :)
declare function router:response($code as xs:integer, $media-type as xs:string?, $body as item()*) {
    map {
        $router:RESPONSE_CODE : $code,
        $router:RESPONSE_TYPE : $media-type,
        $router:RESPONSE_BODY : $body
    }
};

declare function router:write-response($default-code as xs:integer, $data as item()?, $config as map(*)) {
    if ($data instance of map(*) and map:contains($data, $router:RESPONSE_CODE))
    then (
        let $code := head(($data?($router:RESPONSE_CODE), $default-code))
        let $content-type := 
            if (exists($data?($router:RESPONSE_TYPE)))
            then $data($router:RESPONSE_TYPE)
            else router:get-content-type-for-code($config, $code, "application/xml")

        return (
            response:set-status-code($code),
            if ($code = 204)
            then ()
            else (
                response:set-header("Content-Type", $content-type),
                util:declare-option("output:method", router:method-for-content-type($content-type)),
                $data?($router:RESPONSE_BODY)
            )
        )
    )
    else (
        let $content-type := router:get-content-type-for-code($config, $default-code, "application/xml")
        return (
            response:set-status-code($default-code),
            response:set-header("Content-Type", $content-type),
            util:declare-option("output:method", router:method-for-content-type($content-type)),
            $data
        )
    )
};

declare %private function router:get-content-type-for-code($config as map(*), $code as xs:integer, $fallback as xs:string) {
    let $response-definition := head(($config?responses?($code), $config?responses?default))
    let $content := 
        if (exists($response-definition) and $response-definition instance of map(*))
        then $response-definition?content
        else ()

    return
        if (exists($content))
        then router:get-matching-content-type($content)
        else $fallback
};

(:~
 : Check the list of content types defined for the response
 : and compare with the Accept header sent by the client. Use the
 : first content type if none matches.
 :)
declare %private function router:get-matching-content-type($content-types as map(*)) {
    let $accept := router:accepted-content-types()
    let $matches := filter($accept, map:contains($content-types, ?))

    return
        if (exists($matches))
        then head($matches)
        else head(map:keys($content-types))
};

(:~
 : Tokenize the accept header and return a sequence of content types.
 :)
declare function router:accepted-content-types() as xs:string* {
    let $accept-header := head((request:get-header("accept"), request:get-header("Accept")))
    for $type in tokenize($accept-header, "\s*,\s*")
    return
        replace($type, "^([^;]+).*$", "$1")
};

(:~
 : Q: binary types?
 :)
declare function router:method-for-content-type($type) {
    switch($type)
        case "application/json" return "json"
        case "text/html" return "html5"
        case "text/text" return "text"
        default return "xml"
};

declare function router:map-path-parameters($route as map(*), $path as xs:string) {
    let $substitutions := analyze-string($route?pattern, "\{([^\}]+)\}")
    let $match-path := analyze-string($path, $route?regex)

    for $substitution at $pos in $substitutions//fn:group
    let $value := $match-path//fn:group[@nr=$pos]/string()
    let $param-config :=
        if ($route?config?parameters instance of array(*))
        then
            filter($route?config?parameters?*, function($parameter as array(*)) {
                $parameter?in = "path" and
                $parameter?name = $substitution
            })
        else ()

    return
        if (exists($param-config)) then
            map { $substitution/string() : router:cast-parameter($value, head($param-config)) }
        else
            error($errors:REQUIRED_PARAM, "No definition for required path parameter " || $substitution)
};

declare function router:map-request-parameters($route as map(*)) {
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
                    map:entry($param?name, router:cast-parameter($values, $param))
        else
            ()
};

declare function router:cast-parameter($values as xs:string*, $config as map(*)) {
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
declare function router:request-body($request-body-config as map(*)?) {
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
                        case "multipart/form-data" return
                            () (: TODO: implement form-data handling? :)
                        default return
                            $body
            )
            else
                error($errors:BODY_CONTENT_TYPE, "Passed in Content-Type " || $content-type-header || 
                    " not allowed")
    )
};

declare %private function router:create-regex($path as xs:string) {
    let $components := 
        substring-after($path, "/") (: cut-off first slash :)
        => replace("(\.|\$|\^|\+|\*)", "\\$1") (: escape special characters :)
        => tokenize("/") (: split into components :)

    let $length := count($components)

    let $replaced :=
        for $component at $index in $components
        let $replacement := 
            if ($index = $length)
            then "(.+)"
            else "([^/]+)"
        return replace($component, $router:path-parameter-matcher, $replacement)
    
    return
        "/" || string-join($replaced, "/")
};

declare function router:login-domain($config as map(*)) {
    router:resolve-ref($config, ("components", "securitySchemes", "cookieAuth", "name"))
};

declare function router:resolve-pointer($config as map(*), $ref as xs:string) {
    router:resolve-ref($config, tokenize($ref, "/"))
};

(:
 :  QUESTION: what is returned for pointers that cannot be resolved?
 :)
declare %private function router:resolve-ref($config as map(*), $parts as xs:string*) {
    fold-left($parts, $config, function ($config as item()?, $next as xs:string) as item()? {
        if (empty($next) or $next = ("", "#"))
        then
            $config
        else if ($config instance of map(*) and map:contains($config, $next))
        then 
            $config($next)
        else 
            error($errors:OPERATION, "could not resolve ref: " || string-join($parts, '/'), $parts)
    })
};

(:~
 : Add line and source info to error description. To avoid outputting multiple locations
 : for rethrown errors, check if $value is set.
 :)
declare function router:error-description($description as xs:string, $line as xs:integer?, $module as xs:string?, $value) {
    if ($line and $line > 0 and empty($value)) then
        ``[`{$description}` [at line `{$line}` of `{($module, 'unknown')[1]}`]]``
    else
        $description
};

(:~
 : Called when an error is caught. Note that users can also throw an error from within a function 
 : to indicate that a different response code should be sent to the client. Errors thrown from user
 : code will have a map with keys "_config" and "_response" as $value, where "_config" is the current
 : oas configuration for the route and "_response" is the response data provided by the user function
 : in the third argument of error().
 :)
declare function router:send($code as xs:integer, $description as xs:string, $value as item()*, $lookup as function(xs:string) as function(*)?) {
    if (
        $description = "" and 
        count($value) = 1 and
        $value instance of map(*) and
        map:contains($value, "_config") and
        map:contains($value, "_response")
    )
    then (
        let $route := $value?("_config")
        let $response := $value?("_response")
        return
            (: if an error handler is defined, call it instead of returning the error directly :)
            if (map:contains($route, "x-error-handler")) then (
                try {
                    let $fn := $lookup($route?("x-error-handler"))
                    return
                        router:write-response($code, $fn($response), $route)
                } catch * {
                    (: Catch all errors and add the current route configuration to $err:value,
                    so we can check it later to format the response :)
                    error($errors:OPERATION, "Failed to execute error handler " || $route?("x-error-handler"))
                }
            )
            else
                router:write-response($code, $response, $route)
    )
    else (
        response:set-status-code($code),
        response:set-header("Content-Type", "application/json"),
        util:declare-option("output:method", "json"),
        if ($description = "") then
            $value
        else
            map {
                "description": $description,
                "details": 
                    if ($value instance of map(*) and map:contains($value, "_response"))
                    then $value?("_response") 
                    else $value
            }
    )
};
