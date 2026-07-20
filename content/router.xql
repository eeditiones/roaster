(:
 : Copyright (C) 2020 TEI Publisher Project Team
 :
 : This program is free software: you can redistribute it and/or modify
 : it under the terms of the GNU General Public License as published by
 : the Free Software Foundation, either version 3 of the License, or
 : (at your option) any later version.
 :
 : This program is distributed in the hope that it will be useful,
 : but WITHOUT ANY WARRANTY; without even the implied warranty of
 : MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 : GNU General Public License for more details.
 :
 : You should have received a copy of the GNU General Public License
 : along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

(:~
 : The core library functions of the OAS router.
 :)
module namespace router = "http://e-editiones.org/roaster/router";

import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace parameters = "http://e-editiones.org/roaster/parameters";
import module namespace body = "http://e-editiones.org/roaster/body";

declare variable $router:RESPONSE_CODE := xs:QName("router:RESPONSE_CODE");

declare variable $router:RESPONSE_TYPE := xs:QName("router:RESPONSE_TYPE");

declare variable $router:RESPONSE_HEADERS := xs:QName("router:RESPONSE_HEADERS");

declare variable $router:RESPONSE_BODY := xs:QName("router:RESPONSE_BODY");

(:~
 : May be called from user code to send a response with a particular
 : response code (other than 200) or media type.
 :
 : @param $code the response code to return
 : @param $mediaType the Content-Type for the response; assumes that the provided body can
 : be converted into the target media type
 : @param $body data to be sent in the body of the response
 :)
declare function router:response(
    $code as xs:integer,
    $media-type as xs:string?,
    $body as item()*,
    $headers as map(*)?
) {
    map {
        $router:RESPONSE_CODE: $code,
        $router:RESPONSE_TYPE: $media-type,
        $router:RESPONSE_HEADERS: $headers,
        $router:RESPONSE_BODY: $body
    }
};

(:~
 : resolve pointer to information in API definition
 :
 : @param $config the API definition
 : @param $ref either a single string from $ref or a sequence of strings
 :)
declare function router:resolve-pointer($config as map(*), $ref as xs:string*) {
    let $parts := if (starts-with($ref, "#/")) then
        tokenize($ref, "/") (: this is a $ref in the document :)
    else
        $ref (: internal spec lookup :)

    return router:resolve-ref($config, $parts)
};

(:~
 : Maps a request to the configured handler
 : Loads API definitions, matches routes
 : Calls route handler function returned by $lookup function
 : Accepts middlewares
 :
 : Route specificity rules:
 : 1. normalize patterns: replace placeholders with "?"
 : 2. use the matching route with the longest normalized pattern
 : 3. If two paths have the same (normalized) length, prioritize by appearance in API files, first one wins
 :)
declare function router:route(
    $api-files as xs:string+,
    $lookup as function (xs:string) as function(*)?,
    $middlewares as function(*)*
) {
    let $controller := request:get-attribute("$exist:controller")
    let $base-collection := ``[`{repo:get-root()}`/`{$controller}`/]``

    let $request-data := map {
        "id": util:uuid(),
        "method": request:get-method() => lower-case(),
        "path": request:get-attribute("$exist:path")
    }

    return (
        util:log("debug", ``[[`{$request-data?id}`] request `{$request-data?method}` `{$request-data?path}`]``),
        try {
            (: load router definitions :)
            let $specs :=
                for $api-file in $api-files
                let $file-path := concat($base-collection, $api-file)
                let $spec := json-doc($file-path)
                return if (exists($spec)) then (
                    $spec
                ) else
                    error($errors:OPERATION, "Failed to load JSON file from " || $file-path)

            (: find all matching routes :)
            let $matching-routes :=
                for $spec at $pos in $specs
                let $priority := $pos
                return router:match-route($request-data, $spec, $priority)

            let $first-match := if (empty($matching-routes)) then
                error($errors:NOT_FOUND, "No route matches pattern: " || $request-data?path)
            else if (count($matching-routes) eq 1) then
                $matching-routes
            else (
                (: if there are multiple matches, prefer the one matching the longest pattern and the highest priority :)
                let $matching-routes-with-specificity := for-each($matching-routes, router:add-specificity#1)
                return (
                    util:log(
                        "debug",
                        map {
                            "ambiguous route": $request-data?path,
                            "method": $request-data?method,
                            "matching definitions":
                                array
                                    {
                                        $matching-routes-with-specificity!map {
                                            "priority": .?priority,
                                            "specificity": .?specificity,
                                            "pattern": .?pattern
                                        }
                                    }
                        }
                    ),
                    head(sort($matching-routes-with-specificity, (), router:sort-by-specificity-and-priority#1))
                )
            )

            return router:process-request($first-match, $lookup, $middlewares)
        } catch * {
            let $error := if (router:is-rethrown-error($err:value)) then
                $err:value
            else
                (: add line and column for server errors, java exceptions and the like for debugging :)
                map {
                    "_error":
                        map {
                            "code": $err:code,
                            "description": $err:description,
                            "value": $err:value,
                            "line": $err:line-number,
                            "column": $err:column-number,
                            "module": $err:module
                        },
                    "_request": $request-data
                }

            let $status-code := if (contains($error?description, "permission")) then
                403
            else
                errors:get-status-code-from-error($err:code)

            return router:error($status-code, $error, $lookup)
        }
    )
};

(:~
 : find matching route by checking each path pattern
 :)
declare %private function router:match-route($request as map(*), $spec as map(*), $priority as xs:integer) as map(*)* {
    map:for-each(
        $spec?paths,
        function ($route-pattern as xs:string, $route-config as map(*)) {
            let $regex := router:create-regex($route-pattern)

            return if (matches($request?path, $regex)) then
                map:merge(
                    (
                        $request,
                        map {
                            "pattern": $route-pattern,
                            "config": $route-config,
                            "regex": $regex,
                            "spec": $spec,
                            "priority": $priority
                        }
                    )
                )
            else (
            )
        }
    )
};

declare %private variable $router:path-parameter-matcher := "\{[^\}]+\}";

declare %private function router:create-regex($path as xs:string) as xs:string {
    let $components := substring-after($path, "/") (: cut-off first slash :)
        => replace("(\.|\$|\^|\+|\*)", "\\$1") (: escape special characters :)
        => tokenize("/") (: split into components :)

    let $length := count($components)

    let $replaced :=
        for $component at $index in $components
        let $replacement := if ($index = $length) then
            "(.+)"
        else
            "([^/]+)"
        return replace($component, $router:path-parameter-matcher, $replacement)

    return "^/" || string-join($replaced, "/")
};

declare %private function router:add-specificity($route as map(*)) as map(*) {
    let $specificity := string-length( (: the longer the more specific :)
        replace( (: normalize route specificity by replacing path params :)
            $route?pattern,
            $router:path-parameter-matcher,
            "?"
        )
    )

    return map:put($route, "specificity", $specificity)
};

(:~
 : Sort routes by specificity
 :)
declare %private function router:sort-by-specificity-and-priority($route as map(*)) as xs:integer+ {
    -$route?specificity (: sort descending :) (: the longer the more specific :), $route?priority (: sort ascending :)
};

declare %private function router:process-request(
    $pattern-map as map(*),
    $lookup as function(*),
    $custom-middlewares as function(*)*
) {
    let $route := if (map:contains($pattern-map?config, $pattern-map?method)) then
        $pattern-map?config?($pattern-map?method)
    else
        error(
            $errors:METHOD_NOT_ALLOWED,
            "The method " || $pattern-map?method || " is not supported for " || $pattern-map?path
        )

    let $default-middleware := (parameters:in-path#2, parameters:in-request#2)
    (: enable arbitrary middleware configuration :)
    let $use := ($default-middleware, $custom-middlewares)

    (: overwrite config field with the specific method handler :)
    let $base-request := map:put($pattern-map, "config", $route)

    let $response := router:execute-handler($base-request, $use, $lookup)

    let $status := if (map:contains($response, $router:RESPONSE_CODE)) then
        $response?($router:RESPONSE_CODE)
    else
        200

    return (
        router:write-response($status, $response, $route),
        util:log("debug", ``[[`{$base-request?id}`] `{$base-request?method}` `{$base-request?path}`: `{$status}`]``)
    )
};

declare %private function router:middleware-reducer(
    $args as array(map(*)),
    $next-middleware as function (map(*), map(*)) as map(*)+
) as array(map(*)) {
    array { apply($next-middleware, $args) }
};

(:~
 : Look up the XQuery function whose name matches property "operationId".
 : If found, call it and pass the request map as single parameter.
 :)
declare %private function router:execute-handler(
    $base-request as map(*),
    $use,
    $lookup as function (xs:string) as function(*)?
) as map(*) {
    if (not(map:contains($base-request?config, "operationId"))) then
        error($errors:OPERATION, "Operation does not define an operationId", $base-request?config)
    else
        try {
            let $request-with-content-type := map:merge(($base-request, body:content-type($base-request)))
            let $request-with-body := map:put(
                $request-with-content-type,
                "body",
                body:parse($request-with-content-type)
            )

            let $request-response-array := fold-left($use, [$request-with-body, map {}], router:middleware-reducer#2)

            let $request := $request-response-array?1
            let $response := $request-response-array?2

            let $fn := $lookup($base-request?config?operationId)
            let $handler-response := if (empty($fn)) then (
                error(
                    $errors:OPERATION,
                    'Operation not found for operationId:"' || $base-request?config?operationId || '"',
                    $base-request?config
                )
            ) else (
                $fn($request)
            )

            return if (router:is-response-map($handler-response)) then
                (:
                 : handler values will overwrite code, content-type and body
                 : headers are merged with middleware response map
                 :)
                map {
                    $router:RESPONSE_CODE:
                        head(($handler-response?($router:RESPONSE_CODE), $response?($router:RESPONSE_CODE))),
                    $router:RESPONSE_TYPE:
                        head(($handler-response?($router:RESPONSE_TYPE), $response?($router:RESPONSE_TYPE))),
                    $router:RESPONSE_HEADERS:
                        map:merge(($response?($router:RESPONSE_HEADERS), $handler-response?($router:RESPONSE_HEADERS))),
                    $router:RESPONSE_BODY:
                        head(($handler-response?($router:RESPONSE_BODY), $response?($router:RESPONSE_BODY)))
                }
            else
                (: handler just returned the response body :)
                map:put($response, $router:RESPONSE_BODY, $handler-response)
        } catch * {
            (:
             : Catch all errors and add the current route configuration to $err:value,
             : so we can check it later to format the response
             :)
            error(
                $err:code,
                "",
                map {
                    "_error":
                        map {
                            "code": $err:code,
                            "description": $err:description,
                            "value": $err:value,
                            "module": $err:module,
                            "line": $err:line-number,
                            "column": $err:column-number
                        },
                    "_request": $base-request
                }
            )
        }
};

(: content types :)

(:~
 : Content types tried, in order, when a status code has no declared (or
 : `default`) response and the operation declares no other response we can
 : borrow a content type from: negotiated against the client's Accept
 : header, application/xml preferred when nothing matches, application/json
 : as the next choice, and text/plain as a last resort (see #127).
 : A sequence, not a map, because the order of map keys is undefined.
 :)
declare %private variable $router:DEFAULT_CONTENT_TYPE_CANDIDATES := (
    "application/xml", "application/json", "text/plain"
);

(:~
 : Resolve the content type for a response status that has no explicit
 : media type, without regard to the actual body. Tries, in order:
 :
 : 1. the response declared for $code
 : 2. the operation's `default` response
 : 3. the operation's declared 2xx ("success") response, if any -- an
 : undeclared status (e.g. an ad-hoc 500) most likely wants to speak
 : whatever format the route normally responds with
 : 4. any other declared response on the operation (its declared error
 : conditions), in case there is no success response to borrow from
 : 5. content negotiated against $router:DEFAULT_CONTENT_TYPE_CANDIDATES
 :
 : Each step that finds a `content` map negotiates within it via
 : router:get-matching-content-type, so the client's Accept header is
 : honored at every step, not just the last.
 :)
declare %private function router:get-content-type-for-code($config as map(*), $code as xs:integer) as xs:string {
    let $responses := $config?responses
    (:
     : OpenAPI response keys are strings ("200", "default"); look up the integer status code by its
     : string form. Indexing the string-keyed responses map with the integer $code only ever matched
     : because of eXist's pre-conformance map-key coercion, removed in eXist-db/exist#6491.
     :)
    let $response-definition := (
        $responses?(string($code)),
        $responses?default,
        router:first-declared-response($responses, router:is-success-status#1),
        router:first-declared-response(
            $responses,
            function ($key as xs:string) as xs:boolean {
                $key != "default" and $key != string($code) and not(router:is-success-status($key))
            }
        )
    )[. instance of map(*)][exists(?content)][1]

    return if (exists($response-definition)) then
        router:get-matching-content-type($response-definition?content)
    else
        let $accepted := router:accepted-content-types()[. = $router:DEFAULT_CONTENT_TYPE_CANDIDATES]
        return head(($accepted, $router:DEFAULT_CONTENT_TYPE_CANDIDATES))
};

declare %private function router:is-success-status($key as xs:string) as xs:boolean {
    $key castable as xs:integer and
        (
            let $n := xs:integer($key)
            return $n ge 200 and $n lt 300
        )
};

(:~
 : First response definition (with a `content` map) among $responses whose
 : key matches $predicate, in declaration order.
 :)
declare %private function router:first-declared-response(
    $responses as map(*)?,
    $predicate as function (xs:string) as xs:boolean
) as map(*)? {
    if (empty($responses)) then (
    ) else
        let $matching-keys := filter(
            map:keys($responses),
            function ($key as xs:string) as xs:boolean {
                $predicate($key) and $responses?($key) instance of map(*) and exists($responses?($key)?content)
            }
        )
        (: lookup with zero keys ($m?(())) is well-defined and returns () :) return $responses?(head($matching-keys))
};

(:~
 : Guard against unserializable bodies, returning a (possibly adjusted)
 : `content-type` and `body` as a map with those two keys:
 :
 : - a map(*)/array(*) body cannot be serialized by the xml/xhtml/html5/text
 : output methods (raises an uncaught err:SENR0001 after the response
 : status/headers are already committed): the content type is overridden
 : to application/json, under which the body is already natively
 : representable as-is.
 : - conversely a node() body serialized with the json output method
 : silently loses its markup (atomized to its string value) rather than
 : failing loudly. There is no lossless way to turn arbitrary XML into
 : JSON (fn:xml-to-json only accepts XML already in the fn:json-to-xml
 : element vocabulary -- ordinary application XML raises err:FOJS0006).
 : Since every caller of write-response reaches this branch only for a
 : status this reconciliation had to override in the first place, the
 : body is assumed to describe that anomaly and is wrapped as a single
 : "error" key instead: `{"error": "<the serialized xml, escaped>"}`.
 : This keeps the response valid, parseable JSON -- matching the
 : content type that was actually resolved/negotiated -- without
 : discarding the original markup the way silent atomization would.
 :
 : Bodies that are neither (plain atomic values) serialize fine either way
 : and are left untouched. See #127.
 :)
declare %private function router:reconcile-content-type-with-body(
    $content-type as xs:string,
    $body as item()*
) as map(*) {
    let $method := router:method-for-content-type($content-type)
    return if (($body instance of map(*) or $body instance of array(*)) and $method != "json") then (
        util:log(
            "warn",
            "roaster: response body is a map/array but the resolved content type '" ||
                $content-type ||
                "' cannot serialize it; falling back to 'application/json'. Consider declaring a matching content type for this status code in the API spec."
        ),
        map {"content-type": "application/json", "body": $body}
    ) else if ($body instance of node() and $method = "json") then (
        util:log(
            "warn",
            "roaster: response body is an XML node but the resolved content type '" ||
                $content-type ||
                "' would otherwise silently discard its markup; wrapping it as an 'error' key instead. Consider declaring a matching content type for this status code in the API spec."
        ),
        map {"content-type": $content-type, "body": map {"error": $body}}
    ) else
        map {"content-type": $content-type, "body": $body}
};

(:~
 : Check the list of content types defined for the response
 : and compare with the Accept header sent by the client. Use the
 : first content type if none matches.
 :)
declare %private function router:get-matching-content-type($content-types as map(*)) {
    let $accept := router:accepted-content-types()
    let $matches := filter($accept, map:contains($content-types, ?))

    return if (exists($matches)) then
        head($matches)
    else
        head(map:keys($content-types))
};

(:~
 : Tokenize the accept header and return a sequence of content types.
 :)
declare function router:accepted-content-types() as xs:string* {
    let $accept-header := head((request:get-header("accept"), request:get-header("Accept")))
    for $type in tokenize($accept-header, "\s*,\s*")
    return replace($type, "^([^;]+).*$", "$1")
};

(:
 : resolve pointers in API definition
 : @throws errors:OPERATION if the pointer cannot be resolved
 :)
declare %private function router:resolve-ref($config as map(*), $parts as xs:string*) as item()* {
    fold-left(
        $parts,
        $config,
        function ($config as item()?, $next as xs:string) as item()? {
            if (empty($next) or $next = ("", "#")) then
                $config
            else if ($config instance of map(*) and map:contains($config, $next)) then
                $config?($next)
            else
                error($errors:OPERATION, "could not resolve ref: " || string-join($parts, "/"), $parts)
        }
    )
};

(:~
 : Add line and source info to error description. To avoid outputting multiple locations
 : for rethrown errors, check if $value is set.
 :)
declare %private function router:error-description(
    $description as xs:string?,
    $line as xs:integer?,
    $column as xs:integer?,
    $module as xs:string?,
    $value as item()*
) as xs:string {
    if ($line and $line > 0 and empty($value)) then
        ``[`{$description}` [at line `{$line}` column `{$column}` in module `{head(($module, "unknown"))}`]]``
    else
        ($description, $value, "No description provided.")[1]
};

(:~
 : Called when an error is caught. Note that users can also throw an error from within a function
 : to indicate that a different response code should be sent to the client. Errors thrown from user
 : code will have a map with keys "_request" and "_response" as $value, where "_request?config" is the current
 : OAS configuration for the route and "_response" is the response data provided by the user function
 : in the third argument of error().
 :)
declare %private function router:error(
    $code as xs:integer,
    $error as map(*),
    $lookup as function (xs:string) as function(*)?
) {
    router:log-error($code, $error),
    (: unwrap error data :)
    let $route := $error?_request?config
    let $error := $error?_error
    return (: if an error handler is defined, call it instead of returning the error directly :) if (
        exists($route) and map:contains($route, "x-error-handler")
    ) then (
        try {
            let $fn := $lookup($route?x-error-handler)
            let $handled-error := $fn($error)
            let $error-response := if (router:is-response-map($handled-error)) then
                $handled-error
            else
                map {$router:RESPONSE_BODY: $handled-error}

            return router:write-response($code, $error-response, $route)
        } catch * {
            let $_error := map {
                "code": $err:code,
                "description":
                    "Failed to execute error handler " ||
                        $route?x-error-handler ||
                        ": " ||
                        $err:description ||
                        ". Error which triggered this: " ||
                        router:error-description(
                            $error?description,
                            $error?line,
                            $error?column,
                            $error?module,
                            $error?value
                        ),
                "value": $err:value,
                "module": $err:module,
                "line": $err:line-number,
                "column": $err:column-number
            }
            return (router:log-error(500, $_error), router:default-error-handler(500, $_error))
        }
    ) (: default error handler :) else
        router:default-error-handler($code, $error)
};

declare function router:default-error-handler($code as xs:integer, $error as map(*)) as item()* {
    response:set-status-code($code),
    response:set-header("Content-Type", "application/json"),
    util:declare-option("output:method", "json"),
    map:put(
        $error,
        "description",
        router:error-description($error?description, $error?line, $error?column, $error?module, $error?value)
    )
};

declare %private function router:write-response($default-code as xs:integer, $response as item()*, $config as map(*)) {
    let $code := head(($response?($router:RESPONSE_CODE), $default-code))

    let $response-body := $response?($router:RESPONSE_BODY)

    (: an explicit media type always wins and is never reconciled against the
       body -- deliberately serializing a map as XML, say, stays a hard error.
       $router:get-content-type-for-code/reconcile-content-type-with-body are
       only called (and only then may log or rewrite the body) when there is
       no explicit type. :)
    let $resolved := if (exists($response?($router:RESPONSE_TYPE))) then
        map {"content-type": $response?($router:RESPONSE_TYPE), "body": $response-body}
    else
        router:reconcile-content-type-with-body(router:get-content-type-for-code($config, $code), $response-body)

    let $content-type := $resolved?content-type
    let $body := $resolved?body

    let $method := router:method-for-content-type($content-type)

    return (
        response:set-status-code($code),
        router:set-additional-headers($response?($router:RESPONSE_HEADERS)),
        if ($code = 204) then (
        ) else (
            response:set-header("Content-Type", router:content-type-header($content-type, $method)),
            util:declare-option("output:method", $method),
            $body
        )
    )
};

declare %private function router:set-additional-headers($headers as map(*)?) as empty-sequence() {
    if (not(exists($headers))) then (
    ) else
        map:remove($headers, "Content-Type") => map:for-each(router:safe-set-header#2)
};

declare %private function router:safe-set-header($header as xs:string, $value as item()?) as empty-sequence() {
    if (not(exists($value))) (: Q: rather throw here error ? :) then
        util:log("warn", "Empty header '" || $header || "'")
    else if (not($value castable as xs:string)) (: Q: rather throw here error ? :) then
        util:log("warn", "Headervalue for '" || $header || "' is not castable to xs:string")
    else
        response:set-header($header, $value)
};

(:~
 : Build the actual Content-Type header value for a response.
 :
 : eXist-db's serializer always writes text-based output as UTF-8 unless a
 : route explicitly overrides it - there is no per-route encoding to track,
 : so a response's charset isn't something routes.json should have to
 : declare. Derive it from the already-computed serialization $method
 : instead, for every text-ish type, so it's never missing or hand-wired
 : (a missing charset leaves the client to guess the encoding, which is how
 : non-Latin scripts end up mangled into mojibake).
 : A type that already carries parameters (the operation explicitly asked
 : for something specific) is left untouched. application/json is left
 : alone too - RFC 8259 says senders shouldn't add a charset parameter to
 : it, since JSON text is always UTF-8 by definition.
 :
 : $method "text" is ambiguous: router:method-for-content-type also returns it
 : as a passthrough for binary types (e.g. application/octet-stream, image/png)
 : that aren't otherwise recognized, so it can't be trusted alone - a charset
 : is only added for it when $type itself is actually a text/* media type.
 :)
declare %private function router:content-type-header($type as xs:string, $method as xs:string) as xs:string {
    if (contains($type, ";")) then
        $type
    else if ($method = ("html5", "xhtml", "xml") or ($method = "text" and starts-with($type, "text/"))) then
        $type || "; charset=UTF-8"
    else
        $type
};

(:~
 : Q: binary types?
 : XSLT default values: "xml", "xhtml", "html", "text", "json", "adaptive"
 : "html5" is an eXist-DB provided extension
 :)
declare %private function router:method-for-content-type($type as xs:string) as xs:string {
    switch (substring-before($type, "/"))
        case "application" return
            if (ends-with($type, "json")) then
                "json" (: matches application/json and any type ending in +json :)
            else if (ends-with($type, "/xhtml+xml")) then
                "xhtml"
            else if (ends-with($type, "xml")) then
                "xml" (: matches application/xml and any type ending in +xml :)
            else
                "text"
        case "text" return
            if (ends-with($type, "/xml")) then
                "xml"
            else if (ends-with($type, "/html")) then
                "html5"
            else
                "text"
        case "image" return
            if (ends-with($type, "/svg+xml")) then
                "xml"
            else
                "text"
        case "multipart"
        case "audio"
        case "font"
        case "example"
        case "message"
        case "model"
        case "video" return
            "text" (: assume binary content :)
        default return
            error($errors:OPERATION, "Unknown media type '" || $type || '"')
};

(: helpers :)

declare %private function router:is-response-map($value as item()*) as xs:boolean {
    count($value) eq 1 and
        $value instance of map(*) and
        (map:contains($value, $router:RESPONSE_CODE) or map:contains($value, $router:RESPONSE_BODY))
};

declare %private function router:is-rethrown-error($value as item()*) as xs:boolean {
    count($value) eq 1 and $value instance of map(*) and map:contains($value, "_error")
};

declare %private function router:log-error($code as xs:integer, $data as map(*)) as empty-sequence() {
    let $error := $data?_error => serialize(map {"method": "json"})
    return util:log(
        "error",
        ``[[`{$data?_request?id}`] `{$data?_request?method}` `{$data?_request?path}`: `{$code}`
            `{$error}`]``
    )
};
