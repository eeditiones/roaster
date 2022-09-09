
# Roaster
<img alt="roaster router logo" src="icon.svg" width="128" />

> **Define** your API, **then** implement it.

![Test and Release](https://github.com/eeditiones/roaster/workflows/Test%20and%20Release/badge.svg) [![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)

## OpenAPI Router for eXist


Roaster is a generic router to be used in any exist-db application. It reads an [OpenAPI 3.0](https://oai.github.io/Documentation/) specification from a JSON file and routes requests to handler functions written in XQuery.

![Roasted API](doc/roasted-api.png)

From any valid API specification you can generate an interactive documentation as the one above.
This is also very helpful for exploratory testing of your implementation (see [demo app](#demo-app)).

Roaster is the routing library powering [TEI Publisher](https://teipublisher.com). So, make sure to also check there for additional [documentation](https://teipublisher.com/exist/apps/tei-publisher/doc/documentation.xml?odd=docbook.odd&id=api) and examples.

## Installation

This library XAR can be either downloaded from the [releases](https://github.com/eeditiones/roaster/releases) and is also available
on [eXist-db's public package repository](https://exist-db.org/exist/apps/public-repo/packages/roaster).

## How it works

eXist applications usually have a controller as main entry point. The 
[controller.xql](test/app/controller.xql) in the example application only handles requests to static resources, but forwards all other requests to an XQuery script [api.xql](test/app/modules/api.xql). This script imports the OpenAPI router module and calls `roaster:route`, passing it one or more Open API specifications in JSON format.

The [demo app](#demo-app), included in this repository, uses two specifications:

- [api.json](test/app/api.json)
  demonstrates basic usage like parameters in path, query and body
  as well as file up- and downloads
- [api-jwt.json](test/app/api-jwt.json)
  introduces more advanced use-cases like custom authentication and middlewares

Splitting up your api specifications can help keeping each focussed on specific tasks and also split up really long ones.

TEI Publisher has [api.json](https://github.com/eeditiones/tei-publisher-app/tree/master/modules/lib/api.json) and [custom-api.json](https://github.com/eeditiones/tei-publisher-app/tree/master/modules/custom-api.json). There, it is done to make it easier for users to extend the default API.
It is also possible to overwrite a route from `api.json` by placing it into `custom-api.json`.

Each route in the specification _must_ have an `operationId` property.
This is the name of the XQuery function that will handle the request to the given route. Several routes _can_ use the same handler function, where applicable.
The XQuery function will be resolved by the lookup-function passed to  `roaster:route`. In order for that to work all route handler functions need to be available in the context of that function. This is why [api.xql](test/app/modules/api.xql) imports all modules containing handler functions.

## Route Handling

The XQuery handler function _must_ expect exactly one argument: `$request as map(*)`. This is a map with a number of keys:

* _id_: a uuid identifying this request (useful to find this exact request in your logfile)
* _parameters_: a map containing all parameters (path and query) which were defined in the spec. The key is the name of the parameter, the value is the parameter value cast to the defined target type.
* _body_: the body of the request (if ~requestBody~ was used), cast to the specified media type (currently application/json or application/xml).
* _config_: the JSON object corresponding to the Open API path configuration for the current route and method
* _user_: contains the authenticated user, if any authentication was successful
* _method_: GET, POST, PUT, DELETE, HEAD...
* _path_: the requested path
* _spec_: the entire API definition this route is defined in

For example, here's a simple function which just echoes the passed in parameters:

```xquery
declare function custom:echo($request as map(*)) {
    $request?parameters
};
```

## Responses

If the function returns a value, it is sent to the client with a HTTP status code of 200 (OK). The returned value is converted into the specified target media type (if any, otherwise `application/xml` is assumed).

To modify responses like HTTP status code, body and headers the handler function may call `roaster:response` as its last operation.

- `roaster:response($code as xs:int, $data as item()*)`
- `roaster:response($code as xs:int, $mediaType as xs:string?, $data as item()*)`
- `roaster:response($code as xs:int, $mediaType as xs:string?, $data as item()*, $headers as map(*)?)`

**Example:**

```xquery
declare function custom:response($request as map(*)) {
    roaster:response(427, "application/octet-stream", "101010", 
      map { "x-special": "23", "Content-Length" : "1" })
};
```

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

## Authentication

`basic` and `cookie` authentication are supported by default when the two-parameter signature of `roaster:router` is used.
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

The security scheme must be named **cookieAuth**. The `name` property defines the login session name to be used.

Custom authentication strategies are possible. The test application has an example for JSON Web Tokens.

## Access Constraints

Certain operations may be restricted to defined users or groups. We use an implementation-specific property, 'x-constraints' for this on the operation level, e.g.:

```json
"/api/upload/{collection}": {
  "post": {
    "summary": "Upload a number of files",
    "x-constraints": {
        "groups": "dba"
    }
  }
}
```

requires that the *effective user* or *real user* running the operation belongs to the "tei" group.
The *effective user* will be used, if present.

**groups** can be an array, too. In that case the user must be in at least one of them.

```json
{ "groups": ["tei", "dba"] }
```

This will work also for custom authorization strategies. The handler function needs to [extend the request map with the user information](test/app/modules/jwt-auth.xqm#L66).

## Middleware

If you need to perform certain actions on each request you can add a transformation function also known as middleware.

Most internal operations that construct the $request map passed to your operations are such functions. Authorization is a middleware as well.

A middleware has two parameters of type map, the current request map and the current response, and returns two map that will become the request and response maps for the next transformation.

Example middleware that adds a "beep" property to each request and a custom x-beep header to each response:

```xquery
declare function custom-router:use-beep-boop ($request as map(*), $response as map(*)) as map(*) {
    (: extend request :)
    map:put($request, "beep", "boop"),
    (: add custom header to all responses :)
    map:put($response, $router:RESPONSE_HEADERS, map:merge((
      $response?($router:RESPONSE_HEADERS),
      map { "x-beep": "boop" }
    ))
};
```

## File Uploads

Roaster transparently handles data from multipart/form-data requests to keep route handlers short and readable.
Please see the [file upload documentation](doc/file-upload.md) for more details on this.

## Limitations

The library does not support yet support following OpenAPI feature(s): 

- `$ref` references in the Open API specification ([issue](https://github.com/eeditiones/roaster/issues/39))

## Development

Clone this repository and switch to your local working directory.

### Requirements

-  [node](https://nodejs.org/en/): `v14+`
-  [exist-db](https://www.exist-db.org): `v5.0.0+`
-  [Ant](https://ant.apache.org): `v1.10.9+` (optional)

### Building and Installation

Roaster uses Gulp as its build tool which itself builds on NPM. 
To initialize the project and load dependencies run

```bash
npm i
```

> Note: the `install` commands below assume that you have a local eXist-db running on port 8080. However the database connection can be modified in .existdb.json.

| Run | Description |
|---------|-------------|
|```gulp build```|to just build the roaster routing lib. |
|```gulp build:all```|to build the routing lib and the demo app.|
|```gulp install```|To build and install the lib in one go|
|```gulp install:all```|To build and install lib and demo app run|

The resulting xar(s) are found in the root of the project.

An ant-task is still defined, but will use gulp in the end (through `npm run build`).

### Demo App

The repository contains a demo and test application, 'Roasted', which is using the Roaster router. It serves a good starting-point for playing, learning and as a 'template' for your own apps.

Run `gulp install:all` to install both the library and the testapp.
Now navigate to http://localhost:8080/exist/apps/roasted/
This will open a form dynamically created from the definition files [api.json](test/app/api.json) _and_ [api-jwt.json](test/app/api-jwt.json).

### Development

Running `gulp watch` will build and install the library and watch
for file changes. Whenever one of the watched files is changed a 
fresh version of the xar will be installed in the database.
This included the test application in `test/app`.

### Testing

To run the local test suite you need an instance of eXist running on `localhost:8080` and `npm` to be available in your path. To test against a different different server, or use a different user or password you can copy `.env.example` to `.env` and edit it to your needs.

Run the test suite with

```shell
npm test
```

Additional tests that cover this package are contained in the [tei-publisher-app](https://github.com/eeditiones/tei-publisher-app) repository.

## Contributing

Roaster uses [Angular Commit Message Conventions](https://github.com/angular/angular.js/blob/master/DEVELOPERS.md#-git-commit-guidelines) to determine semantic versioning of releases, see these examples:

| Commit message  | Release type |
|-----------------|--------------|
| `fix(pencil): stop graphite breaking when too much pressure applied` | Patch Release |
| `feat(pencil): add 'graphiteWidth' option` | ~~Minor~~ Feature Release |
| `perf(pencil): remove graphiteWidth option`<br/><br/>`BREAKING CHANGE: The graphiteWidth option has been removed.`<br/>`The default graphite width of 10mm is always used for performance reasons.` | ~~Major~~ Breaking Release |
