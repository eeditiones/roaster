xquery version "3.0";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

if ($exist:path eq '') then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{request:get-uri()}/"/>
    </dispatch>

else if ($exist:path eq "/") then
    (: forward root path to index.xql :)
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="api.html"/>
    </dispatch>

(: static HTML page for API documentation should be served directly to make sure it is always accessible :)
else if ($exist:path eq '/api.html' or ends-with($exist:resource, "json")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>

(: other images are resolved against the data collection and also returned directly :)
else if (matches($exist:resource, "\.(png|jpg|jpeg|gif|tif|tiff|txt|mei)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/data/{$exist:path}">
            <set-header name="Cache-Control" value="max-age=31536000"/>
        </forward>
    </dispatch>

(: all other requests are passed on the Open API router :)
else
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/modules/api.xql">
            <set-header name="Access-Control-Allow-Origin" value="*"/>
            <set-header name="Access-Control-Allow-Credentials" value="true"/>
            <set-header name="Access-Control-Allow-Methods" value="GET, POST, DELETE, PUT, PATCH, OPTIONS"/>
            <set-header name="Access-Control-Allow-Headers" value="Content-Type, api_key, Authorization"/>
            <set-header name="Access-Control-Expose-Headers" value="pb-start, pb-total"/>
            <set-header name="Cache-Control" value="no-cache"/>
        </forward>
    </dispatch>