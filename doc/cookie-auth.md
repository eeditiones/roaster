# Cookie Authentication

Roaster now uses the PersistentLogin module functions directly and bypasses its convenience functions.
Next to fixing several issues related to login and logout and cookie authentication this allows

- application specific login and logout route handlers
- reading login information from anywhere in the request
- using XML payloads to login
- set additional login cookie attributes `HttpOnly` and `SameSite`

These changes are completely backwards compatible and you do not need to do anything to reap some of the benefits.

However, having the login and logout route handlers in your app allows you to set the additional cookie attributes
`HttpOnly` and `SameSite` and also to read them from custom field names and formats like **XML**.

## Options

| name         | default                      | description                                                                                         |
| ------------ | ---------------------------- | --------------------------------------------------------------------------------------------------- |
| `name`       | -                            | **REQUIRED** the name of the _cookie_ (AKA "Login Domain") usually set by `auth:add-cookie-name#2`  |
| `path`       | `request:get-context-path()` | requests must include this path for the cookie to be included                                       |
| `lifetime`   | `xs:dayTimeDuration("P7D")`  | set the lifetime of the cookie either as a `xs:dayTimeDuration` or in seconds with a literal number  |
| `domain`     | -                            | "The Domain attribute specifies which server can receive a cookie."                                 |
| `samesite`   | -                            | one of `"None"`, `"Lax"`, or `"Strict"`                                                             |
| `secure`     | -                            | mark the cookie as secure                                                                           |
| `httponly`   | -                            | sets the HttpOnly property                                                                          |
| `jsession`   | `true()`                     | this will _also_ set the JSESSIONID cookie and is needed for some write operations                  |

In order to override default authentication options or add other ones create a map in your API module

```xquery
declare variable $api:auth-options := map {
    "lifetime": 10, (: set the cookie lifetime to 10 seconds :)
    "path": "/exist/apps/roasted", (: requests must include this path for the cookie to be included :)
    "samesite": "Lax", (: set the SameSite attribute to "Lax" :)
    "secure": true(), (: mark the cookie as secure :)
    "httponly": true() (: sets the HttpOnly property :)
    "jsession": false(), (: do not set the JSESSIONID cookie :)
};
```

## Login handler

Instead of using the login handler that comes with Roaster you can use your own one.
The payload will use read username and password information from custom fields 
It needs to call `auth:login-user` which needs three parameters:

- `$username` : In the example below it is sent in the `usr` property in the body
- `$password` : In the example below it is sent in the `pwd` property in the body
- `$options` : A map of options. Make sure to add at least the name - mostly done using `auth:add-cookie-name#2`.

This function will return a user map if the login was succesful or an empty sequence if it was not.

Example login route handler using non-standard properties
within the request body to authenticate users against exist-db.

> The data can also be supplied as JSON and you can redirect the request here to go to the page that was originally requested!

```xquery
declare function api:login ($request as map(*)) {
    let $user := auth:login-user(
            $request?body?usr,
            $request?body?pwd, 
            auth:add-cookie-name($request, $api:auth-options)
        )

    return
        if (empty($user)) then (
            roaster:response(401, "application/json",
                map{ "message": "Wrong user or password" })
        ) else (
            map{ "message": concat("Logged in as ", $user) }
        )
};
```

The corresponding API JSON (shortened for brevity):

```json
{
    "/api/login": {
        "post": {
            "operationId": "api:login",
            "requestBody": {
                "required": true,
                "content": {
                    "application/json": {
                        "schema": {
                            "type": "object",
                            "required": [ "usr" ],
                            "properties": {
                                "usr": {
                                    "description": "Username",
                                    "type": "string"
                                },
                                "pwd": {
                                    "description": "Password",
                                    "type": "string",
                                    "format": "password"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Login with XML

Example login route handler using XML


```xquery
declare function api:login-xml ($request as map(*)) {
    let $user := auth:login-user(
            $request?body//user/string(),
            $request?body//password/string(), 
            auth:add-cookie-name($request, $api:auth-options)
        )

    return
        if (empty($user)) then (
            roaster:response(401, "application/xml",
                <message>Wrong user or password</message>)
        ) else (
            roaster:response(200, "application/xml",
                <message>Logged in as {$user}</message>)
        )
};
```

and the corresponding definition

```json
{
    "/api/login-xml": {
        "post": {
            "operationId": "api:login-xml",
            "requestBody": {
                "required": true,
                "content": {
                    "application/xml": {
                        "schema": {
                            "type": "object",
                            "required": [ "username" ],
                            "properties": {
                                "username": {
                                    "description": "Username",
                                    "type": "string"
                                },
                                "password": {
                                    "description": "Password",
                                    "type": "string",
                                    "format": "password"
                                }
                            },
                            "xml": {
                                "wrapped": true,
                                "name": "login"
                            }
                        }
                    }
                }
            }
        }
    }
}
```

## Logout handler

Instead of using the route handler to logout users provided by Roaster you should
consider creating your own in order to be more flexible when a user logs out of your application:

- redirect users afterwards
- perform additional tasks
- show custom messages

Here is an example logout handler that just returns a custom message encoded as JSON.

```xquery
declare function api:logout ($request as map(*)) {
    auth:logout-user(auth:add-cookie-name($request, $api:auth-options)),
    map{ "message": "Logged out" }
};
```

In API JSON

```json
{
    "/api/logout": {
        "get": {
            "operationId": "api:logout"
        }
    }
}
```

## Cookies

Roaster now comes with a new module `content/cookie.xqm`.
It was introduced to overcome the limitations of eXist-db's `response:set-cookie` function
and allows to set additional cookie attributes `HttpOnly` and `SameSite`.
It is as secure as jetty's Cookie class that is used under the hood for the built-in function. 
It can be used to set arbitrary cookies although it was created specifically for the use in Roaster.
This functionality is therefore now available in all versions of eXist-db that Roaster 
is compatible with.

```xquery
import module namespace cookie="http://e-editiones.org/roaster/cookie";

cookie:set(map {
    (: options :)
    "name": "my-cookie",
    "value": "my-value",
    "lifetime": xs:dayTimeDuration("P1D"),
    (: properties :)
    "domain": "localhost",
    "path": "/",
    "samesite": true(),
    "secure": true(),
    "httponly": "lax"
})
```

### cookie:set Options

| name       | required | description                                                                                |
|------------|----------|--------------------------------------------------------------------------------------------|
| `name`     | X        | used to retrieve the value, can be any string compliant with RFC2109                       |
| `value`    | X        | a string payload that can be read on subsequent requests                                   |
| `lifetime` |          | set the life time of the cookie either as a xs:dayTimeDuration or an xs:integer in seconds |
| `path`     |          | Requests must include this path for the cookie to be included                              |
| `domain`   |          | The Domain attribute specifies which server can receive a cookie.                          |
| `samesite` |          | one of `"None"`, `"Lax"`, or `"Strict"`                                                    |
| `secure`   |          | mark the cookie as secure                                                                  |
| `httponly` |          | sets the HttpOnly property                                                                 |
