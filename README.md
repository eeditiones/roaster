# Open API Router for eXist

Reads an Open API 3.0 specification from JSON and routes requests to XQuery functions.

Currently works as follows: [controller.xql](controller.xql) forwards all requests to [routes.xql](routes.xql), which knows all the functions to be called as endpoints for a request. It calls [router.xql](content/router.xql), which reads the Open API specification JSON file and forwards requests to the corresponding functions.

Due to limitations in eXist's controller, `routes.xql` needs to be in a separate XQuery. In future versions this code may be directly included in the controller.

## Installation

Create .xar by calling `ant` and install into local eXist.

## Testing

Extensive tests for this package are contained in the [tei-publisher-app](https://github.com/eeditiones/tei-publisher-app/tree/feature/open-api/test) repository.

## Writing Request Handlers

This implementation forwards requests to XQuery functions. The name of the function is taken from the Open API property `operationId` associated with each request method. Each function should accept a single parameter: `$request`. This is a map with a number of keys:

* _parameters_: a map containing all parameters (path and query) which were defined in the spec. The key is the name of the parameter, the value is the parameter value cast to the defined target type.
* _body_: the body of the request (if ~requestBody~ was used), cast to the specified media type (currently application/json or application/xml).

If the function returns a value, it is sent to the client with a HTTP status code of 200 (OK). The returned value is converted into the specified target media type (if any, otherwise 
application/xml is assumed).

If a different HTTP status code should be sent, the function may call `router:response($code as xs:int, $mediaType as xs:string?, $data as item()*)` as last operation. You may also skip `$mediaType`, in which case the content type of the response is determined automatically by checking the response definition for the given status code. If a content type cannot be determined, the default, `application/xml` is used.

## Authentication

Currently basic and key based authentication types are supported. The key based authentication type corresponds to eXist's persistent login mechanism and uses cookies for the key. To enable it, use the following securityScheme declaration:

```json
"components": {
    "securitySchemes": {
        "cookieAuth": {
            "type": "apiKey",
            "name": "org.exist.login",
            "in": "cookie"
        }
    }
}
```

The security scheme should be named "cookieAuth". The ~name~ property defines the login session name to be used.

## Access Constraints

Certain operations may be restricted to defined users or groups. We use an implementation-specific property, 'x-constraints' for this on the operation level, e.g.:

```json
"/api/upload/{collection}": {
  "post": {
    "summary": "Upload a number of files",
    "x-constraints": {
        "group": "tei"
    }
  }
}
```

requires that the *real user* running the operation belongs to the "tei" group. Note that the *real user* is the user who logged in and may be different from the *effective user* under which the query runs.

## Todo

- [ ] Parameter type conversion
  - [X] string, integer, number, boolean
  - [ ] array (check item type)
  - [X] *format*: float, double, byte, binary, date, date-time
  - [X] *default* value
  - [X] checking *required*
  - [ ] check *enums*
- [X] parameters from headers and cookies
- [X] requestBody in POST
  - [X] allow multiple content types
- [X] error handling
- [ ] reusable components
- [X] login (securityScheme)
- [X] allow other responses than 200, e.g. 201
- [X] respect media-types for errors (if context is known, otherwise use JSON)
- [ ] support binary response formats
- [X] if multiple response formats are specified, check Accept request header to determine expected format