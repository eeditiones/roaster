xquery version "3.1";

declare namespace custom-router="https://e-editiones.org/oas-router/xquery/test/custom-router";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace router="http://exist-db.org/xquery/router";

import module namespace rutil="http://exist-db.org/xquery/router/util";
import module namespace errors = "http://exist-db.org/xquery/router/errors";
import module namespace auth="http://exist-db.org/xquery/router/auth";

(: 
 : For the bearer token authentication example to work install following packages 
 : - exist-jwt 1.0.1
 : - crypto-lib 1.0.0
 :)
import module namespace jwt-auth="https://e-editiones.org/oas-router/xquery/jwt-auth" at "jwt-auth.xqm";

(:~
 : list of definition files to use
 :)
declare variable $custom-router:definitions := ("api-jwt.json");

(:~
 : You can add application specific route handlers here.
 : Having them in imported modules is preferred.
 :)

(:~
 : This function "knows" all modules and their functions
 : that are imported here 
 : You can leave it as it is, but it has to be here
 :)
declare function custom-router:lookup ($name as xs:string) {
    function-lookup(xs:QName($name), 1)
};

(:~
 : Define authentication/authorization middleware 
 : with a custom authentication strategy
 : 
 : All securitySchemes in any api definition that is
 : included MUST have an entry in this map.
 : Otherwise the router will throw an error. 
 :)
declare variable $custom-router:use-custom-authentication := auth:use-authorization($jwt-auth:handler);

(:~
 : Example of a app-specific middleware that
 : will add the "beep" field to each request
 :)
declare function custom-router:use-beep-boop ($request as map(*)) as map(*) {
    map:put($request, "beep", "boop")
};

declare variable $custom-router:use := (
    $custom-router:use-custom-authentication,
    custom-router:use-beep-boop#1
);

router:route($custom-router:definitions, custom-router:lookup#1, $custom-router:use)
