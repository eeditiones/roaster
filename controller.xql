xquery version "3.1";

declare variable $exist:path external := "/test.xml";
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

response:set-header("Access-Control-Allow-Origin", request:get-header("Origin") => replace("^(\w+://[^/]+).*$", "$1")),
response:set-header("Access-Control-Allow-Methods", "GET, POST, DELETE"),
response:set-header("Access-Control-Allow-Headers", "Content-Type"),
if ($exist:resource = ("docs.html", "routes.json")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>
else
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/routes.xql"/>
    </dispatch>