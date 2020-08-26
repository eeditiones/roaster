# Open API Router for eXist

Reads an Open API 3.0 specification from JSON and routes requests to XQuery functions.

Currently works as follows: [controller.xql](controller.xql) forwards all requests to [routes.xql](routes.xql), which knows all the functions to be called as endpoints for a request. It calls [router.xql](content/router.xql), which reads the Open API specification JSON file and forwards requests to the corresponding functions.

Due to limitations in eXist's controller, `routes.xql` needs to be in a separate XQuery. In future versions this code may be directly included in the controller.

## Demo

A demo using the examples contained in this repository is available: [demo](https://teipublisher.com/exist/apps/oas-router/docs.html)

## Installation

* Create .xar by calling `ant` and install into local eXist
* Open http://localhost:8080/exist/apps/oas-router/docs.html

## Writing Request Handlers

This implementation forwards requests to XQuery functions (see [routes.xql](routes.xql)). The name of the function is taken from the Open API property `operationId` associated with each request method. Each function should accept a single parameter: `$request`. This is a map with a number of keys:

* _parameters_: a map containing all parameters (path and query) which were defined in the spec. The key is the name of the parameter, the value is the parameter value cast to the defined target type.
* _body_: the body of the request (if ~requestBody~ was used), cast to the specified media type (currently application/json or application/xml).

If the function returns a value, it is sent to the client with a HTTP status code of 200 (OK). The returned value is converted into the specified target media type (if any, otherwise 
application/xml is assumed).

If a different HTTP status code should be sent, the function may call `router:response($code as xs:int, $mediaType as xs:string?, $data as item()*)` as last operation. You may also skip `$mediaType`, in which case the content type of the response is determined automatically by checking the response definition for the given status code. If a content type cannot be determined, the default, `application/xml` is used.

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