xquery version "3.1";

module namespace router="http://exist-db.org/xquery/router";

import module namespace errors = "http://exist-db.org/xquery/router/errors";
import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

declare variable $router:RESPONSE_CODE := xs:QName("router:RESPONSE_CODE");
declare variable $router:RESPONSE_TYPE := xs:QName("router:RESPONSE_TYPE");
declare variable $router:RESPONSE_BODY := xs:QName("router:RESPONSE_BODY");

declare function router:route($jsonPaths as xs:string+, $lookup as function(*)) {
    try {
        let $controller := request:get-attribute("$exist:controller")
        for $jsonPath in $jsonPaths
        let $json := replace(``[`{repo:get-root()}`/`{$controller}`/`{$jsonPath}`]``, "/+", "/")
        let $config := json-doc($json)
        return
            if (exists($config)) then
                router:match-path($config, $lookup)
            else
                error($errors:NOT_FOUND, "Failed to load JSON file from " || $json)
    } catch router:CREATED_201 {
        router:send(201, $err:description, $err:value)
    } catch router:NO_CONTENT_204 {
        router:send(204, $err:description, $err:value)
    } catch errors:NOT_FOUND_404 {
        router:send(404, $err:description, $err:value)
    } catch errors:BAD_REQUEST_400 {
        router:send(400, $err:description, $err:value)
    } catch errors:UNAUTHORIZED_401 {
        router:send(401, $err:description, $err:value)
    } catch errors:FORBIDDEN_403 {
        router:send(403, $err:description, $err:value)
    } catch errors:REQUIRED_PARAM | errors:OPERATION | errors:BODY_CONTENT_TYPE {
        router:send(400, $err:description, $err:value)
    } catch * {
        if (contains($err:description, "permission")) then
            router:send(403, $err:description, $err:value)
        else
            router:send(500, $err:description, $err:value)
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

declare function router:match-path($config as map(*), $lookup as function(*)) {
    let $method := request:get-method() => lower-case()
    let $path := request:get-attribute("$exist:path")
    (: find matching route by checking each path pattern :)
    let $routes := map:for-each($config?paths, function($pattern, $route) {
        if (exists($route($method))) then
            let $regex := router:create-regex($pattern)
            return
                if (matches($path, $regex)) then
                    map {
                        "pattern": $pattern,
                        "config": $route($method),
                        "regex": $regex
                    }
                else
                    ()
        else
            ()
    })
    return
        if (empty($routes)) then
            response:set-status-code(404)
        else
            (: if there are multiple matches, prefer the one matching the longest pattern :)
            let $route := sort($routes, (), function($route) {
                string-length($route?pattern)
            }) => reverse() => head()
            let $loginDomain := router:login-domain($config)
            let $parameters := map:merge((
                router:map-request-parameters($route?config),
                router:map-path-parameters($route, $path)
            ))
            let $info := $config?info
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
declare function router:exec($route as map(*), $request as map(*), $lookup as function(*)) {
    let $operationId := $route?operationId
    return
        if (exists($operationId)) then
            let $fn :=
                try {
                    $lookup($operationId)
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
declare function router:send($code as xs:integer, $description as xs:string, $value as item()*) {
    if ($description = "" and count($value) = 1 and $value instance of map(*) and map:contains($value, "_config")) then
        router:write-response(map:get($value, "_response"), $code, map:get($value, "_config"))
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

declare function router:login($request as map(*)) {
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

declare function router:logout($request as map(*)) {
    login:set-user($request?loginDomain, (), false()),
    error($errors:UNAUTHORIZED, "Logged out successfully", map {
        "user": request:get-attribute($request?loginDomain || ".user")
    })
};

declare function router:debug($request as map(*)) {
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