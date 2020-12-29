# roaster 

OpenAPI Router for eXist

Reads an OpenAPI 3.0 specification from JSON and routes requests to handler functions written in XQuery.

It is a generic router to be used in any exist-db application. 
Since it is also the routing library used by TEI Publisher 7 you will find some examples referring to it.

![TEI Publisher API](https://teipublisher.com/exist/apps/tei-publisher/doc/api-spec.png)

## How it works

eXist applications usually have a controller as main entry point. The 
[controller.xql](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/controller.xql) in TEI Publisher only handles requests to static resources, but forwards all other requests to an XQuery script [api.xql](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/lib/api.xql). This script imports the Open API Router module and calls `simple-router:route`, passing it one or more Open API specifications in JSON format.

TEI Publisher uses two specifications: [api.json](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/lib/api.json) and [custom-api.json](https://github.com/eeditiones/tei-publisher-app/blob/feature/open-api/modules/custom-api.json). This is done to make it easier for users to extend the default API. It is also possible to overwrite a route from `api.json` by placing it into `custom-api.json`.

Each route in the specification _must_ have an `operationId` property.
Is is the name of the XQuery function that will handle the request to the given route. The XQuery function must be resolved by the $lookup function in one of the modules which are visible at the point where `router:route` is called. Consequently, [api.xql](test/app/modules/api.xql) imports all modules containing handler functions.

The XQuery handler function _must_ expect exactly one argument: `$request as map(*)`. This is a map with a number of keys:

* _id_: a uuid identifying this request (useful to find this exact request in your logfile)
* _parameters_: a map containing all parameters (path and query) which were defined in the spec. The key is the name of the parameter, the value is the parameter value cast to the defined target type.
* _body_: the body of the request (if ~requestBody~ was used), cast to the specified media type (currently application/json or application/xml).
* _config_: the JSON object corresponding to the Open API path configuration for the current route and method
* _user_: contains the authenticated user, if any authentication was successful
* _method_: PUT, POST, GET, ...
* _path_: the requested path
* _spec_: the entire API definition this route is defined in

For example, here's a simple function which just echoes the passed in parameters:

```xquery
declare function custom:echo($request as map(*)) {
    $request?parameters
};
```

## Responses

If the function returns a value, it is sent to the client with a HTTP status code of 200 (OK). The returned value is converted into the specified target media type (if any, otherwise application/xml is assumed).

If a different HTTP status code should be sent, the function may call `router:response($code as xs:int, $mediaType as xs:string?, $data as item()*)` as its last operation. You may also skip `$mediaType`, in which case the content type of the response is determined automatically by checking the response definition for the given status code. If a content type cannot be determined, the default, `application/xml` is used.

## Error Handling

If an error is encountered when processing the request, a JSON record is returned.

Example:

```json
{
  "module": "/db/apps/oas-test/modules/api.xql",
  "code": "errors:NOT_FOUND_404",
  "value": "error details",
  "line": 34,
  "column": 5,
  "description": "document not found"
}
```

Request handlers can also throw explicit errors using the variables defined in [errors.xql](content/errors.xql)

Example:

```xquery
error($errors:NOT_FOUND, "HTML file " || $path || " not found", map { "info": "additional info"})
```

The server will respond with the HTTP status code 404 to the client.
The description and additional information will be added to the data that is sent.

However, for some operations you may want to handle an error instead of just returning it to the client. In this case use the extension property `x-error-handler` inside an API path item. It should contain the name of an error handler function, which is expected to take exactly one argument, a map(*).
The error map will have all the keys that would normally be sent as json.

## Authentication

`basic` and `cookie` authentication are supported by default when the `simple-router` is used.
The key based authentication type corresponds to eXist's persistent login mechanism and uses cookies for the key. To enable it, use the following securityScheme declaration:

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

The security scheme must be named "cookieAuth". The `name` property defines the login session name to be used.

Custom authentication strategies are possible. The test application has an example for JSON Web Tokens.

## Access Constraints

Certain operations may be restricted to defined users or groups. We use an implementation-specific property, 'x-constraints' for this on the operation level, e.g.:

```json
"/api/upload/{collection}": {
  "post": {
    "summary": "Upload a number of files",
    "x-constraints": {
        "groups": "tei"
    }
  }
}
```

requires that the *effective user* or *real user* running the operation belongs to the "tei" group.
The *effective user* will be used, if present.

This will work also for custom authorization, if they extend the request map with the user information.

## Middleware

If you need to perform certain actions on each request you can add a transformation function also known as middleware.

Most internal operations that construct the $request map passed to your handler are in fact such functions.
Authorization is a middleware as well. 

A middleware has one parameter of type map, the current request map, and returns a map that will be the request map for the next transformation.

Example middleware that adds a "beep" property to each request:

```xquery
declare function custom-router:use-beep-boop ($request as map(*)) as map(*) {
    map:put($request, "beep", "boop")
};
```

## Installation (from source)

Create .xar by calling `gulp build` and install into local eXist.
`gulp install` will attempt to upload and install the library to 
a database at `localhost:8080`.
Database connection can be modified in `.existdb.json`.

ant-task is still defined, but will use gulp (through `npm run build`).

## Development

Running `gulp watch` will build and install the library and watch
for file changes. Whenever one of the watched files is changed a 
fresh version of the xar will be installed in the database.
This included the test application in `test/app`.

## Testing

To run the local test suite you need an instance of eXist running on `localhost:8080` and `npm` to be available in your path. To test against a different port, edit `.existdb.json`.


Run the test suite with

```
npm install
npm test
```

More extensive tests for this package are contained in the [tei-publisher-app](https://github.com/eeditiones/tei-publisher-app/tree/feature/open-api/test) repository.

# Limitations

The library does not support `$ref` references in the Open API specification.