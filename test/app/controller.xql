xquery version "3.1";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

declare variable $local:isget := request:get-method() = ("GET","get");

util:log("debug", map {
    "$exist:path": $exist:path,
    "$exist:resource": $exist:resource,
    "$exist:controller": $exist:controller,
    "$exist:prefix": $exist:prefix,
    "$exist:root": $exist:root,
    "$local:isget": $local:isget
}),
if ($local:isget and $exist:path eq "") then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{request:get-uri()}/"/>
    </dispatch>

(: forward root path to index.xql :)
else if ($local:isget and $exist:path eq "/") then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="api.html"/>
    </dispatch>

(: static HTML page for API documentation should be served directly to make sure it is always accessible :)
else if (
    ($local:isget and $exist:path eq "/api.html") or 
    ($local:isget and matches($exist:path, "^/[^/]+\.json$", "s"))
) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist" />

(: other static resources are resolved against the resources collection and also returned directly :)
else if ($local:isget and matches($exist:path, "^/static/.+$", "s")) then

    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/{replace($exist:path, "static", "resources")}">
            <set-header name="Cache-Control" value="max-age=31536000"/>
        </forward>
    </dispatch>

(: use a different Open API router, needs exist-jwt installed! :)
else if (starts-with($exist:path, '/jwt')) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/modules/custom-router.xq">
            <set-header name="Access-Control-Allow-Origin" value="*"/>
            <set-header name="Access-Control-Allow-Credentials" value="true"/>
            <set-header name="Access-Control-Allow-Methods" value="GET, POST, DELETE, PUT, PATCH, OPTIONS"/>
            <set-header name="Access-Control-Allow-Headers" value="Accept, Content-Type, Authorization, X-Auth-Token"/>
            <set-header name="Cache-Control" value="no-cache"/>
        </forward>
    </dispatch>

(: all other requests are passed on the Open API router :)
else
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/modules/api.xql">
            <set-header name="Access-Control-Allow-Origin" value="*"/>
            <set-header name="Access-Control-Allow-Credentials" value="true"/>
            <set-header name="Access-Control-Allow-Methods" value="GET, POST, DELETE, PUT, PATCH, OPTIONS"/>
            <set-header name="Access-Control-Allow-Headers" value="Accept, Content-Type, Authorization, X-Start"/>
            <set-header name="Cache-Control" value="no-cache"/>
        </forward>
    </dispatch>