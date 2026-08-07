(:
 :  Copyright (C) 2026 TEI Publisher Project Team
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
 :  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :)
xquery version "3.1";

(:~
 : CSRF protection middleware for cookie-authenticated routes.
 :
 : Activated declaratively via an `x-csrf` extension in the OpenAPI
 : spec, either per-route or at the top level. Only enforced when the
 : matched security scheme is `cookieAuth` and the request method is
 : state-changing (POST, PUT, PATCH, DELETE). Basic-auth requests from
 : CLI clients bypass.
 :
 : Configuration shape:
 :   x-csrf:
 :     same-origin: true                          # require Origin/Referer to match request host
 :     allowed-origins: ["https://example.org"]   # optional explicit allow-list
 :
 : Behaviour on a cookie-auth state-changing request:
 :   - Origin (preferred) or Referer must be present.
 :   - If `same-origin: true`, the parsed origin must equal the request's own
 :     scheme/host/port.
 :   - If `allowed-origins` is set, the parsed origin must be a member.
 :   - On mismatch or missing header: 403.
 :)
module namespace csrf="http://e-editiones.org/roaster/csrf";

import module namespace request="http://exist-db.org/xquery/request";
import module namespace errors="http://e-editiones.org/roaster/errors";

declare %private variable $csrf:STATE_CHANGING_METHODS := ("post", "put", "patch", "delete");

declare %private variable $csrf:COOKIE_SCHEMES := ("cookieAuth");

(:~
 : Middleware entry point. Conforms to the Roaster middleware contract:
 : takes (request, response) and returns (request, response).
 :)
declare function csrf:enforce ($request as map(*), $response as map(*)) as map(*)+ {
    if (csrf:applies($request))
    then (
        csrf:check($request, csrf:config($request)),
        $request, $response
    )
    else (
        $request, $response
    )
};

(:~
 : Resolve effective x-csrf config: per-route wins, falls back to spec-level.
 :)
declare %private function csrf:config ($request as map(*)) as map(*)? {
    head((
        $request?config?x-csrf,
        $request?spec?x-csrf
    ))
};

(:~
 : True when this request is in scope for CSRF enforcement.
 :)
declare %private function csrf:applies ($request as map(*)) as xs:boolean {
    exists(csrf:config($request)) and
    $request?method = $csrf:STATE_CHANGING_METHODS and
    $request?auth-scheme = $csrf:COOKIE_SCHEMES
};

(:~
 : Perform the origin check. Throws errors:FORBIDDEN on failure.
 :)
declare %private function csrf:check ($request as map(*), $config as map(*)) as empty-sequence() {
    let $origin := csrf:header-origin()
    return
        if (empty($origin)) then
            error($errors:FORBIDDEN,
                "CSRF check failed: missing Origin and Referer headers on cookie-authenticated " ||
                upper-case($request?method) || " request")
        else if ($config?same-origin and $origin ne csrf:request-origin())
        then
            error($errors:FORBIDDEN,
                "CSRF check failed: Origin '" || $origin ||
                "' does not match request host '" || csrf:request-origin() || "'")
        else if (
            exists($config?allowed-origins) and
            not($origin = csrf:allowed-origins($config))
        )
        then
            error($errors:FORBIDDEN,
                "CSRF check failed: Origin '" || $origin || "' is not in the allowed-origins list")
        else ()
};

(:~
 : Origin/Referer of the incoming request, normalised to "scheme://host[:port]".
 : Origin is preferred (RFC 6454); Referer is a fallback because some user
 : agents and proxies strip Origin from same-origin requests.
 :)
declare %private function csrf:header-origin () as xs:string? {
    let $raw := head((
        request:get-header("Origin"),
        request:get-header("Referer")
    ))
    return
        if (empty($raw) or $raw = ("", "null"))
        then ()
        else csrf:normalize-origin($raw)
};

(:~
 : Strip path/query/fragment from a URL, leaving "scheme://host[:port]".
 :)
declare %private function csrf:normalize-origin ($url as xs:string) as xs:string {
    let $match := analyze-string($url, "^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/\?#]+).*$")
    let $group := $match//*:group[@nr="1"]/string()
    return
        if (exists($group)) then $group else $url
};

(:~
 : Compute the request's own origin from eXist's request module.
 :)
declare %private function csrf:request-origin () as xs:string {
    let $scheme := request:get-scheme()
    let $host := request:get-server-name()
    let $port := request:get-server-port()
    let $default-port :=
        ($scheme = "http"  and $port = 80) or
        ($scheme = "https" and $port = 443)
    return
        if ($default-port)
        then $scheme || "://" || $host
        else $scheme || "://" || $host || ":" || string($port)
};

(:~
 : Allowed-origins may be a JSON array or a single string.
 :)
declare %private function csrf:allowed-origins ($config as map(*)) as xs:string* {
    let $value := $config?allowed-origins
    return
        typeswitch ($value)
            case array(*) return $value?*
            case xs:string return $value
            default return ()
};
