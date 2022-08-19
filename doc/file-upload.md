# Uploading files from an HTML form

When uploading a file from an HTML form, the file content is not sent as the request body.
This is because an HTML form may contain more than one input, and in a POST request all input values will be sent in the request body.

A form which has an `<input type="file">` must use `enctype="multipart/form-data"`, according to the [specification](https://www.ietf.org/rfc/rfc1867.txt).

The file content can be sent as raw data, or base64 encoded, according to the [OpenAPI specification](https://swagger.io/docs/specification/describing-request-body/file-upload/):
"Files use a `type: string` schema with `format: binary` or `format: base64`, depending on how the file contents will be encoded."

How this all works when using Roaster is illustrated in the examples below.

## Uploading a single file

In this example, the filename is sent as a separate parameter.
This is not strictly necessary, but it shows how to send a filename which may be different from the original filename as part of the URL path.

First look at the HTML form.

```html
    <form id="singleFileUploadForm"
        action="#"
        method="POST" 
        enctype="multipart/form-data"
        onsubmit="uploadSingleFile"
    >
        <input type="file" name="file" id="singleFileUploadInput"/><br/>
        <input type="submit" value="Upload text file"/>
    </form>
```

The javascript function used for upload:
The form action is modified to dynamically set the filename as part of the URL.
The filename is also sent in the form-data, so this is not really necessary (see batch upload example below).

```javascript
      function uploadSingleFile(event) {
        const input = document.getElementById('singleFileUploadInput')
        const fileName = input.files[0].name;

        const form = event.target
        form.action = `../upload-text/${fileName}`;
        // Return true to submit immediately.
        return true;
      }
```

The form is at the URL `static/upload.html`, which is why the relative URL for uploading is `../upload/single/${fileName}`.

The OpenAPI specification for the upload is:

```json
{
    "/upload/single/{path}": {
        "post": {
            "summary": "Upload a single file.",
            "description": "In this example, the file path is part of the URL.",
            "operationId": "upload:single",
            "required": true,
            "content": {
                "multipart/form-data": {
                    "schema": {
                        "type": "object",
                        "properties": {
                            "file": {
                                "type": "string",
                                "format": "binary"                    
                            }
                        }
                    }
                }
            },
            "parameters": [
                {
                    "name": "path",
                    "in": "path",
                    "required": true,
                    "schema":{ "type": "string" }
                }
            ],
            "responses": {
                "201": {
                    "description": "Created uploaded file",
                    "content": {
                        "application/json": {
                            "schema": { "type": "string" }
                        }
                    }
                },
                "400": {
                    "description": "Content was invalid",
                    "content": {
                        "application/json": {
                            "schema": { "type": "string" }
                        }
                    }
                }
            }
        }
    }
}
```

The request is handled by the XQuery function `upload:single` and 
writes the file into a collection inside the database.

```xquery
declare function upload:single ($request as map(*)) {
    let $filename as xs:string := $request?parameters?path
    let $file as map(*) := $request?body?file[1]
    let $stored as xs:boolean :=
        xmldb:store('/db/apps/roasted/uploads', $filename, $file?data)

    return roaster:response(201, map { "uploaded": $stored })
};
```

This setup is able to handle XML, text as well as binary file uploads.

## Uploading multiple files

In order to allow batch uploads only very few modifications to the above example for single file uploads have to made.

1. Signal that more than one element is expected in api.json 
   `"multipart/form-data".schema.properties.file` is now of type array
    ```json
    {
        "type": "array",
        "items": {
            "type": "string",
            "format": "binary"                    
        }
    }
    ```
2. `<input type="file" multiple="true" />`
3. iterate over all files in the body `for $file in $request?body?file`
4. return array of uploaded resources in response

```html
    <form action="../upload/batch" method="POST" enctype="multipart/form-data">
        <input type="file" name="file" multiple="true"/><br/>
        <input type="submit" value="Upload files"/>
    </form>
```

```json
{
    "/upload/batch": {
        "post": {
            "summary": "Upload a batch of files.",
            "operationId": "upload:batch",
            "requestBody": {
                "required": true,
                "content": {
                    "multipart/form-data": {
                        "schema": {
                            "type": "object",
                            "properties": {
                                "file": {
                                    "type": "array",
                                    "items": {
                                        "type": "string",
                                        "format": "binary"                    
                                    }
                                }
                            }
                        }
                    }
                }
            },
            "responses": {}
        }
    }
}
```

```xquery
declare function upload:batch ($request as map(*)) {
    let $stored :=
        array{
            for $file in $request?body?file
            return xmldb:store(
                "/db/apps/roasted/uploads", $file?name, $file?data)
        }

    return roaster:response(201, map{ "uploaded": $stored })
};
```


## Base64 encoded file upload

The previous example shows how to upload binary data unencoded, but since the OpenAPI specification provides a way to upload binary data encoded as base64, why not do that as well?

The HTML form is similar to the one for binary upload, but includes a hidden `data` input for the encoded data.

```html
    <form action="../upload/base64" method="POST" enctype="multipart/form-data" id="base64FileUploadForm"
        onsubmit="submitBase64FileUpload"
    >
        <input type="file" name="file" id="base64FileUploadInput"/>
        <br/>
        <input type="submit" value="Upload binary file as base64"/>
        <!-- A hidden field is used for sending the base64 encoded data. -->
        <input type="hidden" name="data" id="base64FileUploadData"/>
      </fieldset>
    </form>
```

Base64 encoding is not provided by the HTML form, so we need some javascript.

```javascript
function submitBase64FileUpload() {
    event.preventDefault();
    const file = document.getElementById('base64FileUploadInput').files[0];
    const reader = new FileReader();
    reader.onloadend = function () {
        // The reader makes a data: URI; remove the prefix and only keep the base64 string.
        const base64 = reader.result.replace(/^data:.+;base64,/, '');
        document.getElementById('base64FileUploadData').value = base64;
        document.getElementById('base64FileUploadForm').submit();
    };
    reader.readAsDataURL(file);
    // do not submit, but wait for the reader to finish.
    return false;
}
```

This time, the OpenAPI specification uses `"data": { "type": "string", "format": "base64" }`.

```json
{
    "/upload/base64": {
        "post": {
            "summary": "Upload a base64-encoded file.",
            "operationId": "upload:base64",
            "requestBody": {
                "content": {
                    "multipart/form-data": {
                        "schema": {
                            "type": "object",
                            "properties": {
                                "file": {
                                    "type": "string",
                                    "format": "binary"
                                },
                                "data": {
                                    "type": "string",
                                    "format": "base64"
                                }
                            }
                        }
                    }
                }
            },
            "parameters": [],
            "responses": {
                "201": {
                    "description": "Created uploaded file",
                    "content": {
                        "application/json": {
                            "schema": { "type": "string" }
                        }
                    }
                },
                "400": {
                    "description": "Content was invalid",
                    "content": {
                        "application/json": {
                            "schema": { "type": "string" }
                        }
                    }
                }
            }
        }
    }
}
```

The `file` data is still present in the request, but we will not use its data but only its name.
We could have removed it in the javascript, to save some precious bytes in the request body.

```xquery
declare function upload:base64 ($request as map(*)) {
    let $file-name as xs:string := $request?body?file[1]?name
    let $file-content as xs:base64Binary := $request?body?data
    let $stored as xs:string :=
        xmldb:store('/db/apps/roasted/uploads', $file-name, $file-content)

    return
        roaster:response(201, map{ 'uploaded': $stored })
};
```
