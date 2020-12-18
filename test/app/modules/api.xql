xquery version "3.1";

declare namespace api="https://e-editiones.org/oas-router/xquery/test-api";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace router="http://exist-db.org/xquery/router";
import module namespace std-router="http://exist-db.org/xquery/router/std";
import module namespace errors = "http://exist-db.org/xquery/router/errors";

import module namespace auth="http://exist-db.org/xquery/router/auth";
import module namespace auth = "https://e-editiones.org/oas-router/xquery/jwt-auth" at "auth.xqm";

(:~
 : list of definition files to use
 :)
declare variable $api:definitions := (
    "api-jwt.json",
    "api.json"
);

(:~
 : Define authentication/authorization handlers
 : 
 : All securitySchemes in any api definition that is
 : included MUST have an entry in this map.
 : Otherwise the router will throw an error. 
 :)
declare variable $api:AUTH_STRATEGIES := map {
    $auth:METHOD : bearer:auth#1,
    "cookieAuth": auth:cookie-auth#1,
    "basicAuth": auth:use-basic-auth#1
};

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

(: end of route handlers :)

(:~
 : This function "knows" all modules and their functions
 : that are imported here 
 : You can leave it as it is, but it has to be here
 :)
declare function api:lookup ($name as xs:string) {
    let $fn := xs:QName($name) => fn:function-lookup(1)
    return
        if ($fn instance of function(*))
        then $fn
        else error()
};

(: std-router:route($api:definitions, api:lookup#1) :)
router:route($api:definitions, api:lookup#1,
    auth:use-authorization($api:AUTH_STRATEGIES))
