xquery version "3.1";

(:~
 : Validate a request body against the binds of a Fore page.
 :
 : An operation opts in with the vendor extension `x-fore`, a path (relative to the app) to a Fore
 : page. Pass `fore:validate#2` to `roaster:route` as middleware:
 :
 : roaster:route($definitions, $lookup, fore:validate#2)
 :
 : The page is compiled once (see fore-compile.xqm) and the result is kept in a cache collection
 : next to the app. The cache entry is rebuilt when the page is newer than the entry.
 :
 : If the body is invalid the handler is not called. Instead the request fails with
 : errors:UNPROCESSABLE_ENTITY (422) and the list of violations as error value.
 :)
module namespace fore = "http://e-editiones.org/roaster/fore-validation";

import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace fcompile = "http://e-editiones.org/roaster/fore-compile";

(: name of the collection, relative to the app, which holds the compiled validators :)
declare variable $fore:CACHE-COLLECTION := "fore-cache";

declare function fore:validate($request as map(*), $response as map(*)) as map(*)+ {
    let $page-path := $request?config?x-fore
    return (
        if (empty($page-path)) then (
        ) else
            let $violations := fore:violations(fore:app-collection(), $page-path, $request?body)
            return if (empty($violations)) then (
            ) else
                error($errors:UNPROCESSABLE_ENTITY, "Validation failed", map {"errors": array { $violations }}),
        $request,
        $response
    )
};

(:~
 : Run the validator of a Fore page on an XML body.
 :
 : @return a map for each violation: `ref`, `bind`, `kind` (required, constraint, type) and `alert`
 :)
declare function fore:violations($app as xs:string, $page-path as xs:string, $body as item()?) as map(*)* {
    if (not($body instance of node())) then
        error($errors:UNSUPPORTED_MEDIA_TYPE, "Validation against a Fore page requires an XML body")
    else
        let $validator := fore:validator($app, $page-path)
        return util:eval($validator, false(), (xs:QName("instances"), map {"default": $body}))
};

(:~
 : URI of the up to date compiled validator for a page. Compiles and stores it if the cache has no
 : entry or an older one. If the cache can not be written the validator is returned as a string.
 :)
declare %private function fore:validator($app as xs:string, $page-path as xs:string) as item() {
    let $page-uri := $app || "/" || $page-path
    return if (not(doc-available($page-uri))) then
        error($errors:SERVER_ERROR, "Fore page " || $page-path || " not found in " || $app)
    else
        let $cache := $app || "/" || $fore:CACHE-COLLECTION
        let $name := replace($page-path, "[/\.]", "_") || ".xq"
        let $cached := $cache || "/" || $name
        return if (fore:is-current($cached, $page-uri)) then
            xs:anyURI($cached)
        else
            let $code := fcompile:compile(doc($page-uri))
            return try {
                if (not(xmldb:collection-available($cache))) then
                    xmldb:create-collection($app, $fore:CACHE-COLLECTION)!()
                else (
                ),
                let $stored := xmldb:store($cache, $name, $code, "application/xquery")
                return (
                    (: stored queries are not executable by default, which other users need :)
                    sm:chmod(xs:anyURI($stored), "rwxr-xr-x"), xs:anyURI($stored)
                )
            } catch * {
                util:log("warn", "Fore validation: can not write " || $cached || ": " || $err:description), $code
            }
};

declare %private function fore:is-current($cached as xs:string, $page-uri as xs:string) as xs:boolean {
    util:binary-doc-available($cached) and
        xmldb:last-modified(util:collection-name($cached), util:document-name($cached)) >=
            xmldb:last-modified(util:collection-name($page-uri), util:document-name($page-uri))
};

(: the collection of the app, the same the router resolves api files against :)
declare %private function fore:app-collection() as xs:string {
    replace(repo:get-root() || "/" || request:get-attribute("$exist:controller"), "/+", "/") => replace("/$", "")
};
