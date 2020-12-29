xquery version "3.1";

declare namespace custom-router="https://e-editiones.org/roasted/custom-router";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

import module namespace roaster="http://e-editiones.org/roaster";
import module namespace rutil="http://e-editiones.org/roaster/util";
import module namespace errors="http://e-editiones.org/roaster/errors";
import module namespace auth="http://e-editiones.org/roaster/auth";

(:~
 : For the bearer token authentication example to work install following packages 
 : - exist-jwt 1.0.1
 : - crypto-lib 1.0.0
 :)
import module namespace jwt-auth="http://e-editiones.org/roasted/jwt-auth" at "jwt-auth.xqm";

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
 : Example of a app-specific middleware that
 : will add the "beep" field to each request
 :)
declare function custom-router:use-beep-boop ($request as map(*)) as map(*) {
    map:put($request, "beep", "boop")
};

declare variable $custom-router:use := (
    (:
     : Define authentication/authorization middleware 
     : with a custom authentication strategy
     : 
     : All securitySchemes in any api definition that is
     : included MUST have an entry in the map passed to
     : auth:use-authorization().
     : Otherwise the router will throw an error. 
     :)
    auth:use-authorization($jwt-auth:handler),
    custom-router:use-beep-boop#1
);

roaster:route($custom-router:definitions, custom-router:lookup#1, $custom-router:use)
