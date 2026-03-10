(:
 :  Copyright (C) 2020 TEI Publisher Project Team
 :
 :  This program is free software: you can redistribute it and/or modify
 :  it under the terms of the GNU General Public License as published by
 :  the Free Software Foundation, either version 3 of the License, or
 :  (at your option) any later version.
 :
 :  This program is distributed in the hope that it will be useful,
 :  but WITHOUT ANY WARRANTY; without even the implied warranty of
 :  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 :  GNU General Public License for more details.
 :
 :  You should have received a copy of the GNU General Public License
 :  along with this program. If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

(:~
 : request body parser
 :)
module namespace body="http://e-editiones.org/roaster/body";

import module namespace errors="http://e-editiones.org/roaster/errors";

(:~
 : Try to retrieve and convert the request body if specified
 :)
declare function body:parse ($request as map(*)) {
    if (not(exists($request?media-type)))
    then () (: this route expects no body, return an empty sequence :)
    else (
        try {
            switch ($request?format)
            case "form-data" return
                body:parse-form-data($request?schema)
            (:
                Parse body contents to XQuery data structure for media types
                that were identified as being in JSON format.
                NOTE: The data needs to be serialized again before it can be stored.
                NOTE: For application/json-patch+json request:get-data returns an xs:string.
            :)
            case "json" return
                let $data := request:get-data()
                return
                    typeswitch($data)
                    case xs:string return parse-json($data)
                    default return
                        util:binary-to-string($data)
                        => parse-json()
            (: 
                Workaround for eXist-DB specific behaviour, 
                this way we will get parse errors as early as possible
                while still having access to the data afterwards.
            :)
            case "xml" return 
                let $data := request:get-data()
                return
                    typeswitch ($data)
                    case node() return $data
                    default return parse-xml($data)
            (: Treat everything else as binary data :)
            default return request:get-data()
        }
        catch * {
            error( 
                $errors:BODY_CONTENT_TYPE, 
                "Body with media type '" || $request?media-type || "' could not be parsed (invalid " || upper-case($request?format) || ").",
                $err:description
            )
        }
    )
};

declare function body:content-type ($request as map(*)) as map(*) {
    if (not(exists($request?config?requestBody?content)))
    then (map{}) (: this route expects no body, return an empty map :)
    else if (not($request?config?requestBody?content instance of map(*)))
    then error($errors:OPERATION, "requestBody.content is not defined correctly", $request?config)
    else (
        let $content := $request?config?requestBody?content
        let $defined-content-types := map:keys($content)

        let $raw-content-type-header-value := request:get-header("Content-Type")
        let $media-type :=
            if (contains($raw-content-type-header-value, ";"))
            then substring-before($raw-content-type-header-value, ";")
            else $raw-content-type-header-value
        
        let $charset :=
            if (contains($raw-content-type-header-value, "charset="))
            then (
                substring-after($raw-content-type-header-value, "charset=")
                => lower-case()
                => replace("^([a-z0-9\-]+).*$", "$1")
            )
            else ()

        let $registry := substring-before($media-type, "/")

        return
            if (
                $media-type = $defined-content-types or (
                    $defined-content-types = "*/*" and
                    $registry = (
                        "application", "audio", "example", "font", "image",
                        "message", "model", "multipart", "text", "video"
                    )
                )
            )
            then map {
                "media-type": $media-type,
                "charset": $charset,
                "registry": $registry,
                "schema": $content?($media-type)?schema,
                "format": 
                    if ($media-type = ("application/json", "text/json")) 
                    then "json" 
                    else if ($media-type = ("application/xml", "text/xml", "image/svg+xml"))
                    then "xml"
                    else if ($media-type = ("multipart/form-data", "application/x-www-form-urlencoded"))
                    then "form-data"
                    else if (
                        starts-with($media-type, "application/") and 
                        (ends-with($media-type, "+json") or ends-with($media-type, "+xml"))
                    ) 
                    then substring-after($media-type, "+")
                    else "binary"
            }
            else error(
                $errors:BODY_CONTENT_TYPE,
                "Body with media-type '" || $media-type || "' is not allowed", 
                $request
            )
    )
};

declare %private
function body:get-form-data-value ($name as xs:string, $format as xs:string?) as item()* {
    switch ($format)
    case 'binary' return
        if (request:is-multipart-content())
        then
            let $names := request:get-uploaded-file-name($name)
            let $data := request:get-uploaded-file-data($name) ! util:base64-decode(.)
            let $sizes := request:get-uploaded-file-size($name)

            return
                for $_name at $index in $names
                return map {
                    "name": $_name,
                    "data": $data[$index],
                    "size": $sizes[$index]
                }
        else if ( starts-with(request:get-header('Content-Type'), 'multipart/form-data')  and $name = 'file') then
            map {
                "name": request:get-attribute("fileName"),
                "data": request:get-attribute("file"),
                "size": string-length(request:get-attribute("file"))
            }
        else
            request:get-parameter($name, ())

    case 'base64' return 
        xs:base64Binary(request:get-parameter($name, ()))

    default return
        if ( not(request:is-multipart-content()) and starts-with(request:get-header('Content-Type'), 'multipart/form-data') ) then
            request:get-attribute($name)
        else
            request:get-parameter($name, ())
};

declare %private
function body:additional-property ($name as xs:string) as map(*) {
    map { $name : request:get-parameter($name, ()) }
};

declare %private
function body:validate-value ($schema as map(*)) as function(*) {
    let $required-props := $schema?required?*
    let $property-definitions := $schema?properties
    return function ($name as xs:string) as map(*) {
        if (not(map:contains($property-definitions, $name)))
        (: additional property, no validation :)
        then body:additional-property($name)
        else
            let $property := $property-definitions?($name)
            let $is-array := $property?type = "array"
            (: only needed to check here as required props must be defined in schema :)
            let $is-required := $name = $required-props
            let $format :=
                if ($property?type = "array")
                then $property?items?format
                else $property?format
            let $value := body:get-form-data-value($name, $format)
            return
                if (not(exists($value)) and $is-required)
                then error($errors:BAD_REQUEST, 'Property "' || $name || '" is required!')
                else if (count($value) > 1 and not($is-array))
                then error($errors:BAD_REQUEST, 'Property "' || $name || '" only allows one item. Got ' || count($value), $value)
                else map:entry($name, $value)
    }
};

(:~
 : extra check needed to ensure required properties are set
 :)
declare %private
function body:ensure-required-properties ($received-property-names as xs:string*, $required-properties as xs:string*) as xs:string* {
    for-each($required-properties, function ($required-prop-name as xs:string) as empty-sequence() {
        if ($required-properties = $received-property-names)
        then ()
        else error($errors:BAD_REQUEST, 'Property "' || $required-prop-name || '" is required!')
    }),
    $received-property-names
};

(:~
 : parse form-data in body
 : some basic schema validation is done when $schema is set
 :)
declare %private
function body:parse-form-data ($schema as map(*)?) as map(*) {
    if (exists($schema) and request:is-multipart-content())
    then
        map:merge(
            for-each(
                body:ensure-required-properties(
                    request:get-parameter-names(), $schema?required?*),
                body:validate-value($schema)))
    else if ( starts-with(request:get-header('Content-Type'), 'multipart/form-data') ) then
        let $parsed := body:parse-multipart(request:get-data(), request:get-header('Content-Type'))
          , $set := ( 
              request:set-attribute("fileName", $parsed?file?header?Content-Disposition?filename),
              for $property in map:keys($parsed)
                return request:set-attribute($property, $parsed($property)?body)
            )
        return map:merge(
            for-each(
                body:ensure-required-properties(
                    map:keys($parsed), $schema?required?*),
                body:validate-value($schema)
            )
        )
    else
        map:merge(
            for-each(
                request:get-parameter-names(), body:additional-property#1))
};

declare function body:parse-multipart ( $data as xs:string, $header as xs:string ) as map(*) {
  let $boundary := $header => substring-after('boundary=') => translate('"', '')
  
  return map:merge(
    (: split multipart data at the boundary :)
    for $m in tokenize($data, "\s*--" || $boundary || '\s*')
      (: ignore the last part after the final boundary, which is just '--' :)
      where string-length($m) gt 6
      
      (: the header is separated by an empty line :)
      let $result := analyze-string($m, "(\r?\n)\s*(\r?\n)")
        , $match := $result/fn:match[1]
        , $content := substring($m, string-length(string-join($match/preceding-sibling::node(), "")) + string-length(string($match)) + 1)
      
      let $header := map:merge( 
        for $line in tokenize($result/fn:non-match[1]/text(), "\n")
          where normalize-space($line) != ""

          let $val := $line => substring-after(': ') => normalize-space()
          let $value := if ( contains($val, '; ') )
            (: combined header fields; e.g., Content-Disposition :)
            then map:merge( 
              for $entry in tokenize($val, '; ') return
                if ( contains($entry, '=') )
                  then map:entry ( substring-before($entry, '='), translate(substring-after($entry, '='), '"', '') )
                  else map:entry ( "text", $entry )
            )
            else $val
          return map:entry(substring-before($line, ': '), $value)
      )
      (: eXist’s parse-xml does not like XML declarations :)
        , $body := if ( matches($content, '^\s+<\?xml version="1.0" encoding="UTF-8"\?>') )
                then substring-after($content, '?>')
                else $content
      
      return map:entry(
          ($header?Content-Disposition?name, 'name')[1],
          map { "header" : $header, "body" : $body }
      )
  )
};
