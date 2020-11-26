xquery version "3.1";

declare namespace api="https://tei-publisher.com/xquery/api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei="http://www.tei-c.org/ns/1.0";

import module namespace router="http://exist-db.org/xquery/router";
import module namespace rutil="http://exist-db.org/xquery/router/util";
import module namespace errors = "http://exist-db.org/xquery/router/errors";

declare function api:date($request as map(*)) {
    $request?parameters?date instance of xs:date and
    $request?parameters?dateTime instance of xs:dateTime
};

declare function api:error-triggered($request as map(*)) {
    error($errors:NOT_FOUND, "document not found", "error details")
};

declare function api:error-dynamic($request as map(*)) {
    $undefined
};

declare function api:error-explicit($request as map(*)) {
    router:response(403, "application/xml", <forbidden/>)
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