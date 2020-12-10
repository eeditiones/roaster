xquery version "3.1";

declare namespace api="https://e-editiones.com/oas-router/xquery/test-api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace router="http://exist-db.org/xquery/router";
import module namespace rutil="http://exist-db.org/xquery/router/util";
import module namespace errors = "http://exist-db.org/xquery/router/errors";

(:~
 : You can add application specific route handlers here.
 : Having them in imported modules is preferred.
 :)

declare function api:date($request as map(*)) {
    $request?parameters?date instance of xs:date and
    $request?parameters?dateTime instance of xs:dateTime
};

(:~
 : An example how to throw a dynamic custom error (error:NOT_FOUND_404)
 : This error is handled in the router
 :)
declare function api:error-triggered($request as map(*)) {
    error($errors:NOT_FOUND, "document not found", "error details")
};

(:~
 : calling this function will throw dynamic XQuery error (err:XPST0003)
 :)
declare function api:error-dynamic($request as map(*)) {
    util:eval('1 + $undefined')
};

(:~
 : Handlers can also respond with an error directly 
 :)
declare function api:error-explicit($request as map(*)) {
    router:response(403, "application/xml", <forbidden/>)
};

(:~
 : This is used as an error-handler in the API definition 
 :)
declare function api:handle-error($response) {
    <p>{$response}</p>
};

declare function api:binary-upload($request as map(*)) {
    util:binary-to-string($request?body)
};

let $lookup := function($name as xs:string, $arity as xs:integer) {
    try {
        function-lookup(xs:QName($name), $arity)
    } catch * {
        ()
    }
}
let $resp := router:route("api.json", $lookup)
return
    $resp