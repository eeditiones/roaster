xquery version "3.1";

module namespace router="http://exist-db.org/xquery/router";

declare function router:route($jsonPath as xs:string, $lookup as function(*)) {
    let $controller := request:get-attribute("$exist:controller")
    let $json := replace(``[`{repo:get-root()}`/`{$controller}`/`{$jsonPath}`]``, "/+", "/")
    let $config := json-doc($json)
    return
        if (exists($config)) then
            router:match-path($config, $lookup)
        else (
            response:set-status-code(404),
            "JSON doc not found"
        )
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
            let $parameters := map:merge((
                router:map-request-parameters($route?config),
                router:map-path-parameters($route, $path)
            ))
            return
                router:exec($route?config, $parameters, $lookup) => router:write-response($route?config)
};

declare function router:exec($route as map(*), $parameters as map(*), $lookup as function(*)) {
    let $fn := $lookup($route?operationId)
    return
        if (exists($fn)) then
            $fn($parameters)
        else (
            response:set-status-code(404),
            "Function not found: " || $route?operationId
        )
};

declare function router:write-response($response, $config as map(*)) {
    let $content := $config?responses?200?content
    return
        if (exists($content)) then
            (: currently we're only accepting one content type :)
            let $contentType := head(map:keys($content))
            return (
                response:set-header("Content-Type", $contentType),
                util:declare-option("output:method", router:method-for-content-type($contentType)),
                $response
            )
        else (
            response:set-header("Content-Type", "text/xml"),
            util:declare-option("output:method", "xml"),
            $response
        )

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
    for $subst in $match//fn:group
    let $value := $matchPath//fn:group[@nr=$subst/@nr]/string()
    let $paramConfig := array:filter($route?config?parameters, function($param) {
        $param?name = $subst and $param?in = "path"
    })
    return
        map:entry($subst/string(), router:cast-parameter($value, $paramConfig?1))
};

declare function router:map-request-parameters($route as map(*)) {
    let $params := $route?parameters
    return
        if (exists($params)) then
            for $param in $params?*
            let $values := request:get-parameter($param?name, ())
            return
                map:entry($param?name, router:cast-parameter($values, $param))
        else
            ()
};

declare function router:cast-parameter($values as xs:string*, $config as map(*)) {
    for $value in $values
    return
        switch($config?schema?type)
            case "xs:integer" return
                xs:integer($value)
            default return
                string($value)
};

declare function router:create-regex($path as xs:string) {
    let $components := substring-after($path, "/") => replace("\.", "\\.") => tokenize("/")
    let $regex :=
        for $component at $p in $components
        return
            (: replace($component, "\{[^\}]+\}", if ($p = 1) then "(.+?)" else "([^/]+)") :)
            replace($component, "\{[^\}]+\}", "([^/]+)")
    return
        "/" || string-join($regex, "/")
};