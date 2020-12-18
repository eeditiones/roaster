xquery version "3.1";


module namespace simple-router="http://exist-db.org/xquery/router/simple";


import module namespace router="http://exist-db.org/xquery/router";
import module namespace auth="http://exist-db.org/xquery/router/auth";


declare function simple-router:route($api-files as xs:string+, $lookup as function(xs:string) as function(*)?) {
    router:route($api-files, $lookup, auth:standard-authorization#1)
};
