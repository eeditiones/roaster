                    "content": {
# Uploading files from an HTML form

When uploading a file from an HTML form, the file content is not sent as the request body.
This is because an HTML form may contain more than one input, and in a POST request all input values will be sent in the request body.
A form which has an `<input type="file">` must use `enctype="multipart/form-data"`, according to the [specification](https://www.ietf.org/rfc/rfc1867.txt).
The file content can be sent as raw data, or base64 encoded, according to the [OpenAPI specification](https://swagger.io/docs/specification/describing-request-body/file-upload/):
"Files use a `type: string` schema with `format: binary` or `format: base64`, depending on how the file contents will be encoded."

How this all works when using Roaster is illustrated in the examples below.

## Text file upload

In this example, the filename is sent as a separate parameter.
This is not strictly necessary, but it shows how to send a filename which may be different from the original filename as part of the URL path.

First look at the HTML form.

```html
    <form action="#" method="POST" enctype="multipart/form-data" id="textFileUploadForm"
      onsubmit="return submitTextFileUpload()"
    >
      <fieldset>
        <legend>Upload a text file.</legend>
        <p><input type="file" name="file" id="textFileUploadInput"/></p>
        <p><input type="submit" value="Upload text file"/></p>
      </fieldset>
    </form>
```

The javascript function used for upload:

```javascript
      /**
       * Upload a text file.
       * In this example, the filename is part of the URL, so the form action is modified.
       * The filename is also sent in the form-data, so this is not really necessary.
       */
      function submitTextFileUpload()
      {
        const fileName = document.getElementById('textFileUploadInput').files[0].name;
        document.getElementById('textFileUploadForm').action = `../upload-text/${fileName}`;
        // Return true to submit immediately.
        return true;
      }
```
The form is at the URL `static/upload.html`, which is why the relative URL for uploading is `../upload-text/${fileName}`.

The OpenAPI specification for the upload is:

```json:
        "/upload-text/{path}": {
            "post": {
                "summary": "Upload a text file.",
                "description": "In this example, the file path is part of the URL.",
                "operationId": "file-upload:upload-text",
                "requestBody": {
                    "content": {
                        "multipart/form-data": {
                            "schema": {
                                "type": "object",
                                "properties": {
                                    "file": { "type": "string", "format": "binary" }
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
```

The request is handled by the XQuery function `file-upload:upload-text`, which uses a function `local:file-path` to determine a location on the file system. Of course you could do something else with the uploaded file.

```xquery
declare function file-upload:upload-text($request as map(*)) {
  (: Get the file name from the URL path. :)
  let $file-path as xs:string? := local:file-path($request?parameters?path)
  (: Make a text node for serialization. :)
  let $file-content as node() := text { $request?body?file }
  let $stored as xs:boolean? :=
    if (exists($file-path)) then
      file:serialize-text($file-content, $file-path, ('method=text'))
    else
      util:log("error", ``[Cannot store uploaded text file of size `{string-length($file-content)}` without a correct file path]``)
  return
    if ($stored) then
      let $log := util:log("info", ``[Stored uploaded text file of size `{string-length($file-content)}` into `{$file-path}`]``)
      return
        roaster:response(201, $stored)
    else
      roaster:response(400, $stored)
};
```

## Binary file upload

Next is a binary file upload, which can be used for images and other data that does not fit in an `xs:string`.
The HTML form:

```html
    <form action="../upload-binary" method="POST" enctype="multipart/form-data" id="binaryFileUploadForm">
      <fieldset>
        <legend>Upload a binary file.</legend>
        <p><input type="file" name="file" id="binaryFileUploadInput"/></p>
        <p><input type="submit" value="Upload binary file"/></p>
      </fieldset>
    </form>
```

No javascript is needed, so let's move on to the OpenAPI specification.

```json
        "/upload-binary": {
            "post": {
                "summary": "Upload a binary file.",
                "description": "In this example, the file path is sent as binary form data.",
                "operationId": "file-upload:upload-binary",
                "requestBody": {
                    "content": {
                        "multipart/form-data": {
                            "schema": {
                                "type": "object",
                                "properties": {
                                    "file": { "type": "string", "format": "binary" }
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
```
The corresponding XQuery function is `file-upload:upload-binary`.

```xquery
declare function file-upload:upload-binary($request as map(*)) {
  let $file-path as xs:string? := local:file-path(request:get-uploaded-file-name('file'))
  let $file-content as xs:base64Binary := request:get-uploaded-file-data('file')
  let $file-content-length as xs:double := request:get-uploaded-file-size('file')
  let $stored as xs:boolean? :=
    if (exists($file-path)) then
      file:serialize-binary($file-content, $file-path)
    else
      util:log("error", ``[Cannot store uploaded binary file of size `{$file-content-length}` without a correct file path]``)
  return
    if ($stored) then
      let $log := util:log("info", ``[Stored uploaded binary file of size `{$file-content-length}` into `{$file-path}`]``)
      return
        roaster:response(201, $stored)
    else
      roaster:response(400, $stored)
};
```

## Base64 encoded file upload

The previous example shows how to upload binary data unencoded, but since the OpenAPI specification provides a way to upload binary data encoded as base64, why not do that as well?

The HTML form is similar to the one for binary upload, but includes a hidden `data` input for the encoded data.

```html
    <form action="../upload-base64" method="POST" enctype="multipart/form-data" id="base64FileUploadForm"
        onsubmit="return submitBase64FileUpload()"
    >
      <fieldset>
        <legend>Upload a binary file encoded as base64.</legend>
        <p><input type="file" name="file" id="base64FileUploadInput"/>
          <!-- A hidden field is used for sending the base64 encoded data. -->
          <input type="hidden" name="data" id="base64FileUploadData"/>
        </p>
        <p><input type="submit" value="Upload binary file as base64"/></p>
      </fieldset>
    </form>
```

Base64 encoding is not provided by the HTML form, so we need some javascript.

```javascript
      function submitBase64FileUpload()
      {
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
        // Return true to not submit, but wait for the reader to finish.
        return false;
      }
```

This time, the OpenAPI specification uses `"data": { "type": "string", "format": "base64" }`.

```json
        "/upload-base64": {
            "post": {
                "summary": "Upload a binary file, which is encoded as base64.",
                "operationId": "file-upload:upload-base64",
                "requestBody": {
                    "content": {
                        "multipart/form-data": {
                            "schema": {
                                "type": "object",
                                "properties": {
                                    "data": { "type": "string", "format": "base64" }
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
```

The `file` data is still present in the request, but we will not use it in the XQuery function.
We could have removed it in the javascript, to save some precious bytes in the request body.

```xquery
declare function file-upload:upload-base64($request as map(*)) {
  let $file-path as xs:string? := local:file-path(request:get-uploaded-file-name('file'))
  let $file-content as xs:base64Binary := xs:base64Binary($request?body?data)
  let $file-content-length as xs:integer := string-length($request?body?data) * 3 idiv 4 (: approximately :)
  let $stored as xs:boolean? :=
    if (exists($file-path)) then
      file:serialize-binary($file-content, $file-path)
    else
      util:log("error", ``[Cannot store uploaded binary file of size `{$file-content-length}` without a correct file path]``)
  return
    if ($stored) then
      let $log := util:log("info", ``[Stored uploaded binary file of size `{$file-content-length}` into `{$file-path}`]``)
      return
        roaster:response(201, $stored)
    else
      roaster:response(400, $stored)
};
```
