xquery version "3.1";

(:~
 : Compiles the binds of a Fore page into an XQuery main module.
 :
 : The generated module expects a map from instance id to instance data in the external variable
 : `$instances`, with the submitted payload under `default`. Today only the default instance is
 : compiled; the map is the seam for further instances (see docs/fore-validation-plan.md). It
 : returns a sequence of error maps `{ ref, bind, kind, alert }`. An empty sequence means the
 : payload is valid.
 :
 : Only binds targeting the default instance are compiled.
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

(: `instance()` or `instance('default')` at the start of a ref addresses the payload itself :)
declare %private variable $fcompile:DEFAULT-INSTANCE := "^instance\(\s*(''|'default'|""default"")?\s*\)";

declare %private variable $fcompile:ANY-INSTANCE := "^instance\(";

(:~
 : Compile a Fore page into the source of an XQuery main module.
 :
 : @param $page the Fore page as parsed XML
 : @error errors:BAD_REQUEST when the page has no default instance or a bind can not be compiled
 :)
declare function fcompile:compile($page as node()) as xs:string {
    let $instance := fcompile:default-instance($page)
    return if (empty($instance)) then
        error($errors:BAD_REQUEST, "Fore page has no default instance")
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
                <function name="local:validate">
                    <param>$instances as map(*)</param>
                    <body>
                        {
                            <let var="root">
                                <expr>
                                    <code
                                    >let $default := $instances?default return if ($default instance of document-node()) then $default/* else $default</code>
                                </expr>
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
    not(matches($bind/@ref, $fcompile:ANY-INSTANCE)) or matches($bind/@ref, $fcompile:DEFAULT-INSTANCE)
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
            return if ($type) then
                "if (string($" ||
                    $node ||
                    ") != '' and not(string($" ||
                    $node ||
                    ") castable as xs:" ||
                    $type ||
                    ")) then " ||
                    fcompile:error($node, $label, "type", $alert) ||
                    " else " ||
                    $constraint
            else
                $constraint
        },
        { xqgen:generate($children, 2) }
    )</code>
};

(: a ref is evaluated with the parent node as context, `instance()` stands for the payload :)
declare %private function fcompile:ref($ref as xs:string, $context as xs:string) as xs:string {
    if (matches($ref, $fcompile:DEFAULT-INSTANCE)) then
        "$root/(" || replace($ref, $fcompile:DEFAULT-INSTANCE, ".") || ")"
    else
        "$" || $context || "/(" || $ref || ")"
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
        "try { boolean($" || $node || " ! (" || $expression || ")) } catch * { " || $on-error || " }"
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
            error($errors:BAD_REQUEST, "Unsupported type '" || $type || "' in bind " || $type/../@ref)
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
