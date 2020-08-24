xquery version "3.1";

module namespace login="http://exist-db.org/xquery/router/login";

import module namespace plogin="http://exist-db.org/xquery/persistentlogin" at "java:org.exist.xquery.modules.persistentlogin.PersistentLoginModule";

declare function login:login($request as map(*)) {
    login:create-login-session($request?loginDomain, (), $request?parameters?user, $request?parameters?password, (), false())
};

declare function login:refresh($request as map(*)) {
    let $cookie := request:get-cookie-value($request?loginDomain)
    return
        if (exists($cookie) and $cookie != "deleted") then
            login:get-credentials($request?loginDomain, (), $cookie, false())
        else
            login:get-credentials-from-session($request?loginDomain)
};

declare function login:logout($request as map(*)) {
    let $cookie := request:get-cookie-value($request?loginDomain)
    return
        login:clear-credentials($cookie, $request?loginDomain, ())
};

declare %private function login:callback($newToken as xs:string?, $user as xs:string, $password as xs:string,
    $expiration as xs:duration, $domain as xs:string, $path as xs:string?, $asDba as xs:boolean) {
    if (not($asDba) or sm:is-dba($user)) then (
        request:set-attribute($domain || ".user", $user),
        request:set-attribute("xquery.user", $user),
        request:set-attribute("xquery.password", $password),
        request:set-attribute($domain || ".token", $newToken),
        if ($newToken) then
            response:set-cookie($domain, $newToken, $expiration, false(), (),
                if (exists($path)) then $path else request:get-context-path())
        else
            ()
    ) else
        ()
};

declare %private function login:get-credentials($domain as xs:string, $path as xs:string?, $token as xs:string, $asDba as xs:boolean) as empty-sequence() {
    plogin:login($token, login:callback(?, ?, ?, ?, $domain, $path, $asDba))
};

declare %private function login:create-login-session($domain as xs:string, $path as xs:string?, $user as xs:string, $password as xs:string?,
    $maxAge as xs:dayTimeDuration?, $asDba as xs:boolean) as empty-sequence() {
    if (exists($maxAge)) then (
        plogin:register($user, $password, $maxAge, login:callback(?, ?, ?, ?, $domain, $path, $asDba)),
        session:invalidate()
    ) else
        login:fallback-to-session($domain, $user, $password, $asDba)
};

declare %private function login:clear-credentials($token as xs:string?, $domain as xs:string, $path as xs:string?) as empty-sequence() {
    response:set-cookie($domain, "deleted", xs:dayTimeDuration("-P1D"), false(), (),
        if (exists($path)) then $path else request:get-context-path()),
    if ($token and $token != "deleted") then
        plogin:invalidate($token)
    else
        (),
    session:invalidate()
};

(:~
 : If "remember me" is not enabled (no duration passed), fall back to the usual
 : session-based login mechanism.
 :)
declare %private function login:fallback-to-session($domain as xs:string, $user as xs:string, $password as xs:string?, $asDba as xs:boolean) {
    let $isLoggedIn := xmldb:login("/db", $user, $password, true())
    return
        if ($isLoggedIn and (not($asDba) or sm:is-dba($user))) then (
            session:set-attribute($domain || ".user", $user),
            request:set-attribute($domain || ".user", $user),
            request:set-attribute("xquery.user", $user),
            request:set-attribute("xquery.password", $password)
        ) else
            ()
};

declare %private function login:get-credentials-from-session($domain as xs:string) {
    let $userFromSession := session:get-attribute($domain || ".user")
    return (
        request:set-attribute($domain || ".user", $userFromSession)
    )
};

