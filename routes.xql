xquery version "3.1";

import module namespace router="http://exist-db.org/xquery/router" at "content/router.xql";
import module namespace errors = "http://exist-db.org/xquery/router/errors" at "content/errors.xql";

declare namespace route="http://exist-db.org/apps/router/route";
declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";

declare function route:list-posts($request as map(*)) {
    map {
        "start": $request?parameters?start,
        "date": format-date($request?parameters?date, '[FNn], [D1o] [MNn], [Y]'),
        "posts":
            [
                map {
                    "title": "Authoring Open API specifications"
                },
                map {
                    "title": "Testing REST APIs"
                }
            ]
    }
};

declare function route:new-post($request as map(*)) {
    let $user := request:get-attribute($request?loginDomain || ".user")
    return
        if ($user) then
            map {
                "id": util:uuid(),
                "title": 
                    if ($request?body instance of map(*)) then 
                        $request?body?title 
                    else 
                        $request?body//title/text()
            }
        else
            error($errors:UNAUTHORIZED, "Permission denied to create new post")
};

declare function route:get-post($request as map(*)) {
    <article xml:id="{$request?parameters?id}">
        <title>Lorem ipsum</title>
        <para>Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy 
        eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. 
        At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, 
        no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, 
        consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et 
        dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo 
        dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem 
        ipsum dolor sit amet.</para>
    </article>
};

declare function route:delete-post($request as map(*)) {
    error($errors:UNAUTHORIZED, "You don't have permission to delete the post", map {
        "id": $request?parameters?id
    })
};

let $lookup := function($name as xs:string) {
    function-lookup(xs:QName($name), 1)
}
let $resp := router:route("routes.json", $lookup)
return
    $resp