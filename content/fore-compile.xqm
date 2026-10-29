xquery version "3.1";

(:~
 : Compiles the binds of a Fore page into an XQuery main module.
 :
 : The generated module expects a map from instance id to instance data in the external variable
 : `$instances`, with the submitted payload under `default`. It returns a sequence of error maps
 : `{ ref, bind, kind, alert }`. An empty sequence means the payload is valid.
 :
 : Only binds targeting the default instance are compiled. Expressions may read other instances
 : with `instance('id')` or `$id`. These reference instances come from the Fore page itself (see
 : fcompile:reference-instances) and never from the request.
 :)
module namespace fcompile = "http://e-editiones.org/roaster/fore-compile";

import module namespace xqgen = "http://www.tei-c.org/tei-simple/xquery/xqgen";
import module namespace errors = "http://e-editiones.org/roaster/errors";

(: types accepted in `type`; anything else fails compilation rather than being spliced into code :)
declare %private variable $fcompile:TYPES := (
    "string",
    "normalizedString",
    "token",
    "boolean",
    "decimal",
    "integer",
    "long",
    "int",
    "short",
    "byte",
    "nonNegativeInteger",
    "positiveInteger",
    "nonPositiveInteger",
    "negativeInteger",
    "unsignedLong",
    "unsignedInt",
    "unsignedShort",
    "unsignedByte",
    "double",
    "float",
    "date",
    "dateTime",
    "time",
    "duration",
    "dayTimeDuration",
    "yearMonthDuration",
    "gYear",
    "gYearMonth",
    "gMonth",
    "gMonthDay",
    "gDay",
    "anyURI",
    "NCName",
    "Name",
    "language",
    "ID",
    "IDREF"
);

(:
 : HTML input types that are checked like the browser does. Fore reads the validity of the widget, so
 : the type of the input of a control is the rule on the client. The server applies the same rule.
 : Other types (text, tel, checkbox, ...) have nothing to check.
 :)
declare %private variable $fcompile:HTML-TYPES := (
    "email", "url", "date", "time", "datetime-local", "month", "week", "number", "range", "color"
);

(: source of the function that checks an HTML input type, added to each compiled module :)
declare %private variable $fcompile:HTML-VALID :=
    '(: whether a value is valid for an HTML input type, empty values are left to required :)
declare function local:html-valid($type as xs:string, $value as xs:string) as xs:boolean {
    switch ($type)
        case "email" return matches($value, "^[a-zA-Z0-9.!#$%&amp;amp;''*+/=?^_`{|}~-]+@[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$")
        case "url" return matches($value, "^[a-zA-Z][a-zA-Z0-9+.\-]*:[^\s]+$")
        case "date" return matches($value, "^\d{4,}-\d{2}-\d{2}$") and $value castable as xs:date
        case "time" return matches($value, "^\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?$") and (if (string-length($value) = 5) then $value || ":00" else $value) castable as xs:time
        case "datetime-local" return matches($value, "^\d{4,}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?$") and (if (matches($value, "T\d{2}:\d{2}$")) then $value || ":00" else $value) castable as xs:dateTime
        case "month" return matches($value, "^\d{4,}-(0[1-9]|1[0-2])$")
        case "week" return matches($value, "^\d{4,}-W(0[1-9]|[1-4][0-9]|5[0-3])$")
        case "number" case "range" return matches($value, "^-?(\d+|\d*\.\d+)([eE][-+]?\d+)?$")
        case "color" return matches($value, "^#[0-9a-fA-F]{6}$")
        default return true()
};
';

(: the instance a ref starts with: `instance('id')` or `$id`, a ref without one addresses the default instance :)
declare %private variable $fcompile:REF-INSTANCE := "^(instance\(\s*(['""]([^'""]*)['""])?\s*\)|\$([\w.\-]+))";

(: string literals of an XPath expression :)
declare %private variable $fcompile:STRING-LITERAL := "'[^']*'|""[^""]*""";

(: function libraries that Fore (fontoxpath) and eXist have in common, by prefix :)
declare %private variable $fcompile:FUNCTION-NAMESPACES := map {
    "": "http://www.w3.org/2005/xpath-functions",
    "fn": "http://www.w3.org/2005/xpath-functions",
    "math": "http://www.w3.org/2005/xpath-functions/math",
    "map": "http://www.w3.org/2005/xpath-functions/map",
    "array": "http://www.w3.org/2005/xpath-functions/array",
    "xs": "http://www.w3.org/2001/XMLSchema"
};

(: names that are followed by a parenthesis in XPath without being a function call :)
declare %private variable $fcompile:NOT-FUNCTIONS := (
    "node",
    "text",
    "comment",
    "processing-instruction",
    "element",
    "attribute",
    "document-node",
    "item",
    "empty-sequence",
    "schema-element",
    "schema-attribute",
    "namespace-node",
    "map",
    "array",
    "function",
    "if",
    "and",
    "or",
    "in",
    "return",
    "then",
    "else",
    "satisfies",
    "div",
    "mod",
    "idiv",
    "to",
    "union",
    "intersect",
    "except",
    "eq",
    "ne",
    "lt",
    "le",
    "gt",
    "ge",
    "is",
    "of",
    "as",
    "cast",
    "castable",
    "treat",
    "some",
    "every",
    "for",
    "let",
    "switch",
    "typeswitch",
    "case",
    "default"
);

(:~
 : Compile a Fore page into the source of an XQuery main module.
 :
 : @param $page the Fore page as parsed XML
 : @error errors:SERVER_ERROR when the page has no default instance or a bind can not be compiled,
 : for example because it calls a function that is not available on the server
 :)
declare function fcompile:compile($page as node()) as xs:string {
    let $instance := fcompile:default-instance($page)
    let $unsupported := fcompile:root-binds($page)/descendant-or-self::*:fx-bind!fcompile:unsupported(.)
    return if (empty($instance)) then
        error($errors:SERVER_ERROR, "Fore page has no default instance")
    else if (exists($unsupported)) then
        error(
            $errors:SERVER_ERROR,
            "Fore page uses functions that are not available on the server: " || string-join($unsupported, "; ")
        )
    else
        xqgen:generate(
            <xquery>
                <code>xquery version "3.1";&#10;&#10;declare variable $instances external;&#10;&#10;</code>
                <code
                >(: readable path of a node relative to the root element, e.g. item[2]/@id :)
declare function local:ref($n as node(), $root as node()) as xs:string {{
    string-join(
        for $s in ($n/ancestor-or-self::node() except $root/ancestor-or-self::node())
        return
            typeswitch ($s)
                case attribute() return "@" || name($s)
                case element() return name($s) || "[" || (count($s/preceding-sibling::*[node-name(.) = node-name($s)]) + 1) || "]"
                default return (),
        "/"
    )
}};

</code>
                <code
                >(: root element of an instance, the default one if no id is given :)
declare function local:instance() as element()? {{
    local:instance("default")
}};

declare function local:instance($id as xs:string?) as element()? {{
    let $instance := $instances(if (empty($id) or $id = "") then "default" else $id)
    return if ($instance instance of document-node()) then $instance/* else $instance
}};

</code>
                <code>{ $fcompile:HTML-VALID || "&#10;" }</code>
                <function name="local:validate">
                    <param>$instances as map(*)</param>
                    <body>
                        {
                            <let var="root">
                                <expr><code>local:instance("default")</code></expr>
                                <return>{ fcompile:binds(fcompile:root-binds($page), "root", 0) }</return>
                            </let>
                        }
                    </body>
                </function>
                <code>local:validate($instances)</code>
            </xquery>,
            0
        )
};

declare function fcompile:default-instance($page as node()) as element()? {
    ($page//*:fx-instance[not(@id) or @id = "default"])[1]
};

(: top-level binds of the page's model that address the default instance :)
declare %private function fcompile:root-binds($page as node()) as element()* {
    $page//*:fx-model[1]/*:fx-bind[fcompile:targets-default-instance(.)]
};

declare %private function fcompile:targets-default-instance($bind as element()) as xs:boolean {
    let $id := fcompile:ref-instance($bind/@ref)
    return empty($id) or $id = ("", "default")
};

(: the id of the instance a ref starts with, empty if it does not start with one :)
declare %private function fcompile:ref-instance($ref as xs:string) as xs:string? {
    let $match := analyze-string($ref, $fcompile:REF-INSTANCE)/*:match[1]
    return if (empty($match)) then (
    ) (: the groups are nested :) else
        string(($match//*:group[@nr = 4], $match//*:group[@nr = 3])[1])
};

(:~
 : Generate the code for a list of sibling binds. Binds nest: child refs are evaluated with the
 : node selected by the parent bind as context.
 :)
declare %private function fcompile:binds(
    $binds as element()*,
    $context as xs:string,
    $depth as xs:integer
) as element()* {
    if (empty($binds)) then
        <code>()</code>
    else
        <sequence>
            {
                for $bind at $pos in $binds
                return <item>{ fcompile:bind($bind, $context, $depth, $pos) }</item>
            }
        </sequence>
};

declare %private function fcompile:bind(
    $bind as element(),
    $context as xs:string,
    $depth as xs:integer,
    $pos as xs:integer
) as element() {
    let $node := "n" || $depth || "_" || $pos
    let $ref := fcompile:ref($bind/@ref, $context)
    let $label := string(($bind/@id, $bind/@ref)[1])
    let $alert := fcompile:alert($bind)
    let $type := fcompile:type($bind/@type)
    let $html := fcompile:html-type($bind)
    let $children := fcompile:binds($bind/*:fx-bind, $node, $depth + 1)
    return <code>for ${ $node } in { $ref }
let $relevant := {
            fcompile:test($bind/@relevant, $node, "true()", "true()")
        }
let $required := {
            fcompile:test($bind/@required, $node, "false()", "true()")
        }
return
    if (not($relevant)) then () else (
        {
            if ($bind/@required) then
                "if ($required and string($" ||
                    $node ||
                    ") = '') then " ||
                    fcompile:error($node, $label, "required", $alert) ||
                    " else ()"
            else
                "()"
        },
        {
            let $constraint := if ($bind/@constraint) then
                "if (not(" ||
                    fcompile:test($bind/@constraint, $node, "true()", "false()") ||
                    ")) then " ||
                    fcompile:error($node, $label, "constraint", $alert) ||
                    " else ()"
            else
                "()"
            let $xs-check := if ($type) then
                "if (string($" ||
                    $node ||
                    ") != '' and not(string($" ||
                    $node ||
                    ") castable as xs:" ||
                    $type ||
                    ")) then " ||
                    fcompile:error($node, $label, "type", $alert) ||
                    " else "
            else
                ""
            let $html-check := if ($html) then
                "if (string($" ||
                    $node ||
                    ") != '' and not(local:html-valid('" ||
                    $html ||
                    "', string($" ||
                    $node ||
                    ")))) then " ||
                    fcompile:error($node, $label, "type", ($alert[. != ""], "Please enter a valid " || $html)[1]) ||
                    " else "
            else
                ""
            return $xs-check || $html-check || $constraint
        },
        { xqgen:generate($children, 2) }
    )</code>
};

(: a ref is evaluated with the parent node as context :)
declare %private function fcompile:ref($ref as attribute(), $context as xs:string) as xs:string {
    "$" || $context || "/(" || fcompile:rewrite($ref) || ")"
};

(:~
 : A boolean attribute of a bind is an XPath expression evaluated with the node as context.
 : An expression that raises an error (e.g. a comparison on a tampered value) evaluates to
 : `$on-error`, so that bad input is reported instead of failing the request.
 :)
declare %private function fcompile:test(
    $expression as attribute()?,
    $node as xs:string,
    $default as xs:string,
    $on-error as xs:string
) as xs:string {
    if (exists($expression) and normalize-space($expression) != "") then
        "try { boolean($" || $node || " ! (" || fcompile:rewrite($expression) || ")) } catch * { " || $on-error || " }"
    else
        $default
};

declare %private function fcompile:type($type as attribute()?) as xs:string? {
    if (empty($type)) then (
    ) else
        let $name := replace($type, "^[^:]+:", "")
        return if ($name = $fcompile:TYPES) then
            $name
        else
            error($errors:SERVER_ERROR, "Unsupported type '" || $type || "' in bind " || $type/../@ref)
};

declare %private function fcompile:alert($bind as element()) as xs:string {
    string(($bind/@alert, $bind/*:fx-alert)[1])
};

declare %private function fcompile:error(
    $node as xs:string,
    $label as xs:string,
    $kind as xs:string,
    $alert as xs:string
) as xs:string {
    "map { 'ref': local:ref($" ||
        $node ||
        ", $root), 'bind': " ||
        fcompile:literal($label) ||
        ", 'kind': '" ||
        $kind ||
        "', 'alert': " ||
        fcompile:literal($alert) ||
        " }"
};

declare %private function fcompile:literal($value as xs:string) as xs:string {
    '"' || replace(replace($value, "&amp;", "&amp;amp;"), '"', '""') || '"'
};

(:~
 : Fore expressions run on fontoxpath plus Fore's own function library, the server on eXist.
 : Report each function call of a bind that eXist does not know, so that a form is never
 : silently validated with different semantics.
 :)
declare %private function fcompile:unsupported($bind as element()) as xs:string* {
    for $attribute in $bind/(@ref, @required, @constraint, @relevant)
    let $where := "bind '" || string(($bind/@id, $bind/@ref)[1]) || "' (" || name($attribute) || "): "
    return (
        for $name in distinct-values(fcompile:called-functions($attribute))
        where not(fcompile:available($name))
        return $where || $name || "()",
        for $id in distinct-values(fcompile:referenced-instances($attribute))
        let $problem := fcompile:instance-problem(root($bind), $id)
        where exists($problem)
        return $where || $problem
    )
};

(: ids of the instances an expression reads with `instance('id')` or `$id` :)
declare %private function fcompile:referenced-instances($expression as attribute()) as xs:string* {
    (
        analyze-string($expression, "instance\(\s*['""]([^'""]*)['""]\s*\)")/*:match/*:group,
        for $id in fcompile:instance-ids(root($expression))
        where fcompile:uses-variable(string($expression), $id)
        return $id
    )!string(.)
};

(: why a referenced instance can not be provided by the server :)
declare %private function fcompile:instance-problem($page as node(), $id as xs:string) as xs:string? {
    if ($id = ("", "default")) then (
    ) else
        let $instance := ($page//*:fx-instance[@id = $id])[1]
        return if (empty($instance)) then
            "instance '" || $id || "' is not defined"
        else if ($instance/@type = "json" or ends-with($instance/@src, ".json")) then
            "instance '" || $id || "' holds JSON, which is not supported yet"
        else if (matches($instance/@src, "^([a-zA-Z][a-zA-Z0-9+.\-]*:|/|#)")) then
            "instance '" || $id || "' has src '" || $instance/@src || "', only paths relative to the page are supported"
        else (
        )
};

declare %private function fcompile:called-functions($expression as xs:string) as xs:string* {
    (: string literals may contain anything :)
    let $code := replace($expression, $fcompile:STRING-LITERAL, "''")
    for $match in analyze-string($code, "[\w.\-]+(:[\w.\-]+)?\s*\(")/*:match
    let $name := replace($match, "\s*\($", "")
    let $before := string($match/preceding-sibling::*[1])
    where not(matches($name, "^[0-9]")) and not(ends-with($before, "$")) and not($name = $fcompile:NOT-FUNCTIONS)
    return $name
};

declare %private function fcompile:available($name as xs:string) as xs:boolean {
    let $prefix := if (contains($name, ":")) then
        substring-before($name, ":")
    else
        ""
    let $local := if (contains($name, ":")) then
        substring-after($name, ":")
    else
        $name
    return $name = "instance" or
        map:contains($fcompile:FUNCTION-NAMESPACES, $prefix) and
            (
                some
                    $arity in
                    0 to 10 satisfies
                    exists(function-lookup(QName($fcompile:FUNCTION-NAMESPACES?($prefix), $local), $arity))
            )
};

(: all instance ids of a page, the default instance can be addressed as "default" :)
declare %private function fcompile:instance-ids($page as node()) as xs:string+ {
    distinct-values(("default", $page//*:fx-instance/@id[. != ""]!string(.)))
};

(: does the code read `$id`, and not a variable of the same name that it binds itself? :)
declare %private function fcompile:uses-variable($expression as xs:string, $id as xs:string) as xs:boolean {
    let $name := replace($id, "([.\-])", "\\$1")
    let $code := string-join(analyze-string($expression, $fcompile:STRING-LITERAL)/*:non-match)
    return matches($code, "\$" || $name || "([^\w.\-]|$)") and not(matches($code, "\$" || $name || "(\s+in\s|\s*:=)"))
};

(:~
 : Rewrite what Fore resolves at runtime to calls of the generated `local:instance`:
 : `instance('id')` and `$id`, for each instance id of the page. String literals are left alone.
 :)
declare %private function fcompile:rewrite($expression as attribute()) as xs:string {
    let $ids := fcompile:instance-ids(root($expression))
    return string-join(
        for $part in analyze-string($expression, $fcompile:STRING-LITERAL)/*
        return if ($part/self::*:match) then
            string($part)
        else
            fold-left(
                $ids,
                replace(string($part), "(^|[^\w.\-:$])instance\s*\(", "$1local:instance("),
                function ($code, $id) {
                    if (fcompile:uses-variable($code, $id)) then
                        replace(
                            $code,
                            "\$" || replace($id, "([.\-])", "\\$1") || "([^\w.\-]|$)",
                            "local:instance('" || $id || "')$1"
                        )
                    else
                        $code
                }
            )
    )
};

(:~
 : The instances a validator reads besides the payload: every other instance of the page, with
 : the data given inline or loaded from a `src` relative to the page. They come from the page, not from
 : the request, so a tampered request can not change the data rules are checked against.
 :
 : @param $base the collection of the page, a `src` is relative to it like it is in the browser
 :)
declare function fcompile:reference-instances($page as node(), $base as xs:string) as map(*) {
    map:merge(
        for $instance in $page//*:fx-instance[@id != "" and @id != "default"]
        let $root := if ($instance/@src != "") then
            doc($base || "/" || $instance/@src)/*
        else
            $instance/*[1]
        where exists($root)
        (: a copy, so the expressions can not navigate into the page :)
        return map {string($instance/@id): document { $root }/*}
    )
};

(:~
 : The HTML input type of the control that edits the node of a bind, if it is one the browser
 : validates. A control belongs to a bind if its ref is the ref of the bind or the path of nested
 : bind refs.
 :)
declare %private function fcompile:html-type($bind as element()) as xs:string? {
    let $paths := (string-join($bind/ancestor-or-self::*:fx-bind/@ref, "/"), string($bind/@ref))
    let $types :=
        for $control in root($bind)//*:fx-control[normalize-space(@ref) = $paths]
        let $widget := ($control/*[tokenize(@class, "\s+") = "widget"], $control//*:input)[1]
        return lower-case($widget/@type)
    return ($types[. = $fcompile:HTML-TYPES])[1]
};
