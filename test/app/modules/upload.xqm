xquery version "3.1";

module namespace upload="http://e-editiones.org/roasted/upload";

import module namespace roaster="http://e-editiones.org/roaster";

declare variable $upload:collection := '/db/apps/roasted/uploads';
declare variable $upload:download-path := 'api/paths/';

declare function upload:single ($request as map(*)) {
    try {
        let $file-name as xs:string := $request?parameters?path
        let $file as map(*) := $request?body?file[1]
        let $stored as xs:string :=
            xmldb:store($upload:collection, $file-name, $file?data)

        return
            roaster:response(201, map { 
                "uploaded": $upload:download-path || $file-name })
    }
    catch * {
        roaster:response(400, map { "error": $err:description })        
    }
};

declare function upload:batch ($request as map(*)) {
    try {
        let $download-links as xs:string+ :=
            for $file in $request?body?file
            let $stored := xmldb:store($upload:collection, $file?name, $file?data)
            return $upload:download-path || $file?name

        return
            roaster:response(201, map{ "uploaded": array{ $download-links }})
    }
    catch * {
        roaster:response(400, map { "error": $err:description })        
    }
};

declare function upload:base64 ($request as map(*)) {
    let $file-name as xs:string := $request?body?file[1]?name
    let $file-content as xs:base64Binary := $request?body?data
    let $stored as xs:string :=
        xmldb:store('/db/apps/roasted/uploads', $file-name, $file-content)

    return
        roaster:response(201, map { 
            "uploaded": $upload:download-path || $file-name })
};
