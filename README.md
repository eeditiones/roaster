# Open API Router for eXist

Reads an Open API 3.0 specification from JSON and routes requests to XQuery functions.

Currently works as follows: `controller.xql` forwards all requests to `routes.xql`, which knows all the functions to be called as endpoints for a request. It calls `content/router.xql`, which reads the Open API specification JSON file and forwards requests to the corresponding functions.

Due to limitations in eXist's controller, `routes.xql` needs to be in a separate XQuery. In future versions this code may be directly included in the controller.