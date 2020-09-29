# Open API Router for eXist

Reads an Open API 3.0 specification from JSON and routes requests to handler functions written in XQuery.

This repository contains the routing library used by TEI Publisher 7. It is generic though and can be integrated into any application. In the following TEI Publisher is only used as an example.

## How it works

eXist applications usually have a controller as main entry point. The 
[controller.xql](controller.xql) in TEI Publisher only handles requests to static resources, but forwards all other requests to an XQuery script [api.xql](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/lib/api.xql). This script imports the Open API Router module and calls `router:route`, passing it one or more Open API specifications in JSON format.

TEI Publisher uses two specifications: [api.json](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/lib/api.json) and [custom-api.json](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/custom-api.json). This is done to make it easier for users to extend the default API. It is also possible to overwrite a route from `api.json` by placing it into `custom-api.json`.

Each route in the specification should have an `operationId` property, referencing the name of an XQuery function to be called to handle a request to the given route. The XQuery function must exist in one of the modules which are visible at the point where `router:route` is called. Consequently, [api.xql](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/lib/api.xql) imports all modules containing handler functions.

The XQuery handler function should take exactly one argument: `$request as map(*)`. This is a map with a number of keys:

* _parameters_: a map containing all parameters (path and query) which were defined in the spec. The key is the name of the parameter, the value is the parameter value cast to the defined target type.
* _body_: the body of the request (if ~requestBody~ was used), cast to the specified media type (currently application/json or application/xml).
* _config_: the JSON object corresponding to the Open API path configuration for the current route

For example, here's a simple function which just echoes the passed in parameters:

```xquery
declare function custom:echo($request as map(*)) {
    $request?parameters
};
```

## Responses
If the function returns a value, it is sent to the client with a HTTP status code of 200 (OK). The returned value is converted into the specified target media type (if any, otherwise application/xml is assumed).

If a different HTTP status code should be sent, the function may call `router:response($code as xs:int, $mediaType as xs:string?, $data as item()*)` as last operation. You may also skip `$mediaType`, in which case the content type of the response is determined automatically by checking the response definition for the given status code. If a content type cannot be determined, the default, `application/xml` is used.

## Error Handling
If an error is encountered when processing the request, a JSON record is returned. This has two properties: `description` containing a short description of the error, and `details` which may contain arbitrary additional information (as passed into the 3rd parameter of the standard XQuery error function).

Request handlers can also throw explicit errors using the variables defined in [errors.xql](content/errors.xql), e.g. by calling

```xquery
error($errors:NOT_FOUND, "HTML file " || $path || " not found")
```

This will result in a 404 response being sent to the client.

However, for some operations you may want to handle an error instead of just returning it to the client. In this case use the extension property `x-error-handler` inside an API path item. It should contain the name of an error handler function, which is expected to take exactly one argument (of any type). The argument will either contain a simple string describing the error, or - if available - the additional information passed in the 3rd argument of a call to the `error` function.

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

# Installation

Create .xar by calling `ant` and install into local eXist.

## Testing

Extensive tests for this package are contained in the [tei-publisher-app](https://github.com/eeditiones/tei-publisher-app/tree/feature/open-api/test) repository.

# Limitations

The library does not support `$ref` references in the Open API specification.