# Open API Router for eXist

Reads an Open API 3.0 specification from JSON and routes requests to XQuery functions.

Currently works as follows: `controller.xql` forwards all requests to `routes.xql`, which knows all the functions to be called as endpoints for a request. It calls `content/router.xql`, which reads the Open API specification JSON file and forwards requests to the corresponding functions.

Due to limitations in eXist's controller, `routes.xql` needs to be in a separate XQuery. In future versions this code may be directly included in the controller.

## Installation

* Create .xar by calling `ant`
* Install into local eXist
* Open http://localhost:8080/exist/apps/oas-router/docs.html

## Todo

- [ ] Parameter type conversion
  - [X] string, integer, number, boolean
  - [ ] array (check item type)
  - [X] *format*: float, double, byte, binary, date, date-time
  - [X] *default* value
  - [ ] checking *required*
- [X] requestBody in POST
  - [X] allow multiple content types
- [X] error handling
- [ ] reusable components
- [X] login (securityScheme)
- [ ] allow other responses than 200, e.g. 201
- [ ] respect media-types for errors