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
import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

declare variable $router:RESPONSE_CODE := xs:QName("router:RESPONSE_CODE");
declare variable $router:RESPONSE_TYPE := xs:QName("router:RESPONSE_TYPE");
declare variable $router:RESPONSE_BODY := xs:QName("router:RESPONSE_BODY");

declare function router:route($jsonPaths as xs:string+, $lookup as function(xs:string, xs:integer) as function(*)?) {
    try {
        let $controller := request:get-attribute("$exist:controller")
        let $routes :=
            for $jsonPath at $pos in $jsonPaths
            let $json := replace(``[`{repo:get-root()}`/`{$controller}`/`{$jsonPath}`]``, "/+", "/")
            let $config := json-doc($json)
            return
                if (exists($config)) then
                    router:match-path($config, count($jsonPaths) - $pos)
                else
                    error($errors:NOT_FOUND, "Failed to load JSON file from " || $json)
        return
            if (empty($routes)) then
                error($errors:NOT_FOUND, "No route matches pattern: " || request:get-attribute("$exist:path"))
            else
                router:process($routes, $lookup)
    } catch router:CREATED_201 {
        router:send(201, $err:description, $err:value, $lookup)
    } catch router:NO_CONTENT_204 {
        router:send(204, $err:description, $err:value, $lookup)
    } catch errors:NOT_FOUND_404 {
        router:send(404, $err:description, $err:value, $lookup)
    } catch errors:BAD_REQUEST_400 {
        router:send(400, $err:description, $err:value, $lookup)
    } catch errors:UNAUTHORIZED_401 {
        router:send(401, $err:description, $err:value, $lookup)
    } catch errors:FORBIDDEN_403 {
        router:send(403, $err:description, $err:value, $lookup)
    } catch errors:REQUIRED_PARAM | errors:OPERATION | errors:BODY_CONTENT_TYPE {
        router:send(400, $err:description, $err:value, $lookup)
    } catch * {
        if (contains($err:description, "permission")) then
            router:send(403, $err:description, $err:value, $lookup)
        else
            router:send(500, $err:description, $err:value, $lookup)
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
declare function router:response($code as xs:int, $body as item()*) {
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
declare function router:response($code as xs:int, $mediaType as xs:string?, $body as item()*) {
    map {
        $router:RESPONSE_CODE : $code,
        $router:RESPONSE_TYPE : $mediaType,
        $router:RESPONSE_BODY : $body
    }
};

declare function router:match-path($config as map(*), $priority as xs:int) {
    let $method := request:get-method() => lower-case()
    let $path := request:get-attribute("$exist:path")
    (: find matching route by checking each path pattern :)
    let $routes := map:for-each($config?paths, function($pattern, $route) {
        if (exists($route($method))) then
            let $regex := router:create-regex($pattern)
            return
                if (matches($path, $regex)) then
                    map {
                        "path": $path,
                        "pattern": $pattern,
                        "config": $route($method),
                        "regex": $regex,
                        "spec": $config,
                        "priority": $priority
                    }
                else
                    ()
        else
            ()
    })
    return
        if (empty($routes)) then
            ()
        else
            $routes
};

declare function router:process($routes as map(*)*, $lookup as function(*)) {
    (: if there are multiple matches, prefer the one matching the longest pattern :)
    let $route := sort($routes, (), function($route) {
            string-length(replace($route?pattern, "\{[^\}]+\}", "?")) + $route?priority
        }) => reverse() => head()
    let $loginDomain := router:login-domain($route?spec)
    let $parameters := map:merge((
        router:map-request-parameters($route?config),
        router:map-path-parameters($route, $route?path)
    ))
    let $info := $route?spec?info
    let $request := map {
        "parameters": $parameters,
        "body": router:request-body($route?config),
        "loginDomain": $loginDomain,
        "info": $info,
        "config": $route
    }
    return (
        if ($loginDomain) then (
            login:set-user($loginDomain, (), false())
        ) else
            (),
        if (router:check-login($route?config)) then
            ()
        else
            error($errors:UNAUTHORIZED, "Access denied"),
        router:exec($route?config, $request, $lookup) => router:write-response(200, $route?config)
    )
};

(:~
 : Look up the XQuery function whose name matches property "operationId". If found,
 : call it and pass the request map as single parameter.
 :)
declare function router:exec($route as map(*), $request as map(*), $lookup as function(xs:string, xs:integer) as function(*)?) {
    let $operationId := $route?operationId
    return
        if (exists($operationId)) then
            let $fn :=
                try {
                    $lookup($operationId, 1)
                } catch * {
                    error($errors:OPERATION, "Function " || $operationId || " could not be resolved")
                }
            return
                if (exists($fn)) then
                    try {
                        $fn($request)
                    } catch * {
                        (: Catch all errors and add the current route configuration to $err:value,
                           so we can check it later to format the response :)
                        if (exists($route('x-error-handler'))) then
                            error($err:code, '', map {
                                "_config": $route,
                                "_response": if (exists($err:value)) then $err:value else $err:description
                            })
                        else
                            error($err:code, if ($err:description) then $err:description else '', map {
                                "_config": $route,
                                "_response": $err:value
                            })
                    }
                else
                    error($errors:OPERATION, "Function " || $operationId || " could not be resolved")
        else
            error($errors:OPERATION, "Operation does not define an operationId")
};

declare function router:write-response($data, $defaultCode as xs:int, $config as map(*)) {
    if ($data instance of map(*) and map:contains($data, $router:RESPONSE_CODE)) then
        let $code := $data($router:RESPONSE_CODE)
        let $contentType := $data($router:RESPONSE_TYPE)
        let $contentType := 
            if (exists($contentType)) then 
                $contentType
            else
                router:get-content-type-for-code($config, $defaultCode, "text/xml")
        return
        (
            response:set-status-code($code),
            if ($code != 204) then (
                response:set-header("Content-Type", $contentType),
                util:declare-option("output:method", router:method-for-content-type($contentType)),
                $data($router:RESPONSE_BODY)
            ) else
                ()
        )
    else
        let $contentType := router:get-content-type-for-code($config, $defaultCode, "text/xml")
        return (
            response:set-status-code($defaultCode),
            response:set-header("Content-Type", $contentType),
            util:declare-option("output:method", router:method-for-content-type($contentType)),
            $data
        )
};

declare %private function router:get-content-type-for-code($config as map(*), $code as xs:int, $fallback as xs:string) {
    let $respDef := head(($config?responses?($code), $config?responses?default))
    let $content := if (exists($respDef)) then $respDef?content else ()
    return
        if (exists($content)) then
            router:get-matching-content-type($content)
        else
            $fallback
};

(:~
 : Check the list of content types defined for the response
 : and compare with the Accept header sent by the client. Use the
 : first content type if none matches.
 :)
declare %private function router:get-matching-content-type($contentTypes as map(*)) {
    let $accept := router:accepted-content-types()
    let $matches := filter($accept, function($type) {
        map:contains($contentTypes, $type)
    })
    return
        if (exists($matches)) then
            $matches[1]
        else
            head(map:keys($contentTypes))
};

(:~
 : Tokenize the accept header and return a sequence of content types.
 :)
declare function router:accepted-content-types() {
    let $header := head((request:get-header("accept"), request:get-header("Accept")))
    for $type in tokenize($header, "\s*,\s*")
    return
        replace($type, "^([^;]+).*$", "$1")
};

declare function router:method-for-content-type($type) {
    switch($type)
        case "application/json" return "json"
        case "text/html" return "html5"
        case "text/text" return "text"
        default return "xml"
};

declare function router:map-path-parameters($route as map(*), $path as xs:string) {
    let $match := analyze-string($route?pattern, "\{([^\}]+)\}")
    let $matchPath := analyze-string($path, $route?regex)
    for $subst at $pos in $match//fn:group
    let $value := $matchPath//fn:group[@nr=$pos]/string()
    let $paramConfig := 
        if (exists($route?config?parameters)) then
            array:filter($route?config?parameters, function($param) {
                $param?name = $subst and $param?in = "path"
            })
        else
            ()
    return
        if (exists($paramConfig) and array:size($paramConfig) > 0) then
            map:entry($subst/string(), router:cast-parameter($value, $paramConfig?1))
        else
            error($errors:REQUIRED_PARAM, "No definition for required path parameter " || $subst)
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
declare function router:request-body($route as map(*)) {
    if (exists($route?requestBody) and exists($route?requestBody?content)) then
        let $content := $route?requestBody?content
        let $contentTypeHeader := replace(request:get-header("Content-Type"), "^([^;]+);?.*$", "$1")
        return
            if (map:contains($content, $contentTypeHeader)) then
                let $contentType := map:get($content, $contentTypeHeader)
                let $body := request:get-data()
                return
                    switch ($contentTypeHeader)
                        case "application/json" return
                            parse-json(util:binary-to-string($body))
                        case "text/xml" case "application/xml" return
                            $body
                        case "multipart/form-data" return
                            ()
                        default return
                            error($errors:BODY_CONTENT_TYPE, "Unable to handle request body content type " || $contentType)
            else
                error($errors:BODY_CONTENT_TYPE, "Passed in Content-Type " || $contentTypeHeader || 
                    " not allowed")
    else
        ()
};

declare function router:create-regex($path as xs:string) {
    let $components := substring-after($path, "/") => replace("\.", "\\.") => tokenize("/")
    let $regex := (
        for $component in subsequence($components, 1, count($components) - 1)
        return
            (: replace($component, "\{[^\}]+\}", if ($p = 1) then "(.+?)" else "([^/]+)") :)
            replace($component, "\{[^\}]+\}", "([^/]+)"),
            replace($components[last()], "\{[^\}]+\}", "(.+)")
    )
    return
        "/" || string-join($regex, "/")
};

declare function router:login-domain($config as map(*)) {
    router:do-resolve-pointer($config, ("components", "securitySchemes", "cookieAuth", "name"))
};

declare function router:resolve-pointer($config as map(*), $ref as xs:string) {
    router:do-resolve-pointer($config, tokenize($ref, "/"))
};

declare function router:login-constraints($config as map(*)) {
    if (exists($config?security)) then
        for $entry in $config?security?*
        for $method in map:keys($entry)
        return
            router:do-resolve-pointer($config, ("components", "securitySchemes", $method, "x-constraints"))
    else
        ()
};

declare function router:check-login($config as map(*)) {
    let $realUser := sm:id()//sm:real
    let $constraints := $config('x-constraints')
    return
        if (exists($constraints?group)) then
            $realUser/sm:groups/sm:group = $constraints?group
        else if (exists($constraints?user)) then
            $realUser/sm:groups/sm:username = $constraints?user
        else
            true()
};

declare %private function router:do-resolve-pointer($config as map(*), $refs as xs:string*) {
    if (empty($refs) or (count($refs) = 1 and $refs[1] = "")) then
        $config
    else if (head($refs) = "#") then
        router:do-resolve-pointer($config, tail($refs))
    else 
        let $object := $config(head($refs))
        return
            if (exists($object) and $object instance of map(*)) then
                router:do-resolve-pointer($object, tail($refs))
            else
                $object
};

(:~
 : Called when an error is caught. Note that users can also throw an error from within a function 
 : to indicate that a different response code should be sent to the client. Errors thrown from user
 : code will have a map with keys "_config" and "_response" as $value, where "_config" is the current
 : oas configuration for the route and "_response" is the response data provided by the user function
 : in the third argument of error().
 :)
declare function router:send($code as xs:integer, $description as xs:string, $value as item()*, $lookup as function(xs:string, xs:integer) as function(*)?) {
    if ($description = "" and count($value) = 1 and $value instance of map(*) and map:contains($value, "_config")) then
        let $route := map:get($value, "_config")
        let $errorHandler := $route('x-error-handler')
        return
            (: if an error handler is defined, call it instead of returning the error directly :)
            if (exists($errorHandler)) then
                let $fn :=
                    try {
                        $lookup($errorHandler, 1)
                    } catch * {
                        error($errors:OPERATION, "Error handler function " || $errorHandler || " could not be resolved")
                    }
                return
                    if (exists($fn)) then
                        try {
                            let $response := $fn(map:get($value, "_response"))
                            return
                                router:write-response($response, $code, $route)
                        } catch * {
                            (: Catch all errors and add the current route configuration to $err:value,
                            so we can check it later to format the response :)
                            error($errors:OPERATION, "Failed to execute error handler " || $errorHandler)
                        }
                    else
                        error($errors:OPERATION, "Error handler function " || $errorHandler || " could not be resolved")
            else
                router:write-response(map:get($value, "_response"), $code, $route)
    else (
        response:set-status-code($code),
        response:set-header("Content-Type", "application/json"),
        util:declare-option("output:method", "json"),
        if ($description = "") then
            $value
        else
            map {
                "description": $description,
                "details": if (exists($value) and map:contains($value, "_response")) then map:get($value, "_response") else $value
            }
    )
};