# Fore-driven server-side validation middleware for Roaster

## Context

Fore forms already declare their rules once, in `fx-bind` (`required`, `constraint`, `type`, `alert`). Today the server side of an eXist app has to re-implement those rules by hand, so the two layers drift apart. Idea: an operation in a Roaster `api.json` points at a local Fore page. A Roaster middleware reads that page's binds, validates the request body against them, and calls the handler only if validation passes. Otherwise it returns the errors.

Server-side validation should almost never fail, because the client already validated. It exists to reject tampered or compromised data. So v1 is only an allow/deny gate with an error report. There is no relevance pruning and no `calculate`.

## Workspace

All implementation happens in `/Users/joern/dev/roaster`, on a feature branch for a later PR. The first action is `git switch -c feature/fore-validation` from `master`, before any file is created. `master` currently has an unrelated `package-lock.json` change and an untracked `roasted/`, which stay out of my commits (I stage only the files I add). No commits to `master`. Commit messages carry no Claude attribution, per your global instruction. The marketing repo (this session's directory) is not touched. The session should be started from, or have `/add-dir` for, the roaster directory so edits and tests run there.

## Findings that shape the design

- **Roaster** (`/Users/joern/dev/roaster/content/`):
    - Middleware has the signature `function($request, $response) as map(*)+`.
    - Defaults are `parameters:in-path`, `parameters:in-request` (`router.xql:210-213`), then custom middleware, then the handler (`router.xql:362`).
    - The only way to short-circuit is to throw an error. `error($errors:BAD_REQUEST, …)` gives a 400, and `x-error-handler` can format it.
    - Per-operation vendor extensions already exist (`x-constraints` in `auth.xql:115`, `x-error-handler` in `router.xql:485`). The new extension follows the `x-constraints` pattern.
    - `request?body` is already parsed (XML or JSON) before middleware runs.
    - Roaster has no body validation today.
- **Fore** (`/Users/joern/dev/Fore`) can't run headless: its bind engine is tied to custom elements, `DOMParser` and `window`. Its XPath layer (`fontoxpath`) is plain XPath 3.1, so bind expressions are portable. Server-side validation therefore has to be a re-implementation of the bind semantics, not a reuse of the engine.
- **Engine choice (from you):** compile the Fore page's rules to XQueryX once per form and store the result in a collection, because `util:eval` per request is too expensive.

## Design

1. **Declaration.** New operation property in `api.json`, for example `"x-fore": "forms/invoice.html"`. The value is a path relative to the app, resolved to a database resource.
    - **What is validated:** always the Fore page's **default instance** (the `fx-instance` without an `id` or with `id="default"`) which is the submitted payload. Only binds that target the default instance are compiled. Binds on other instances are ignored, and no `instance('…')` lookup is needed. No configuration for this is added.
2. **Compile once, run many.** The middleware reads the Fore page and finds the `fx-instance` and `fx-bind` elements. A compiler turns the bind rules into **XQueryX** (the XML form of XQuery) that encodes a `typeswitch`-style evaluation, specialised for that one form. It yields a `validate($body as node()) as map(*)*` function that returns a list of `{ref, bind, kind, alert}` errors. The compiled result is stored in a cache collection and reused on later requests, which avoids parsing the page and evaluating expressions through `util:eval` every time. The cache key is the source page's last-modified timestamp, so editing the page invalidates it.
    - **Update after reading `tei-publisher-lib/content/xqgen.xql`:** that is the "XQueryX" you meant. `xqgen:generate` is a `typeswitch` over a small XML descriptor (`module`, `function`, `let`, `return`, `typeswitch`/`case`, `if`/`then`/`else`, `map`, `sequence`, `function-call`, `code`, …) that serialises to XQuery text. So the compiler builds that descriptor from the Fore binds, `xqgen:generate` turns it into XQuery source, `util:compile-query` checks it (as in `pmu:process-odd`, `util.xql:160-185`), `xmldb:store` keeps it in the cache collection, and the middleware runs it with `util:eval(xs:anyURI($uri), false(), (xs:QName("body"), $request?body))`. Both projects are GPL-3.0, so `xqgen.xql` is vendored into roaster (`content/xqgen.xql`, with its copyright header kept), not added as a package dependency.
    - **Earlier note (superseded):** you pointed out that eXist has a function that compiles XQueryX, so the compiler emits XQueryX and hands it to that function. A grep of the local eXist checkout (`/Users/joern/dev/exist`) for "xqueryx" found nothing, so I don't know its name or module yet. The first step is to confirm it (please tell me if you remember it) and prototype the round trip: XQueryX in, callable function out. If it turns out not to cover this, the fallback is to serialise the same compiler output to XQuery text and load it with `util:import-module`.
3. **Bind semantics for v1**, applied to every node that a bind's `ref` selects. Binds nest, so child `ref`s are evaluated in the parent bind's context.
    - `required`: this is an XPath expression too, not a flag. It is evaluated per node, and **only when it evaluates to `true()` is the node required**, so it must then be non-empty. A `required` that evaluates to false means the node may be empty. Fore's `fx-model.js` `revalidate()` is the reference for the emptiness check.
    - `constraint`: the XPath must evaluate to true.
    - `type`: check with `castable as xs:<type>`. Fore itself does not enforce this server-side today, so it's a deliberate addition.
    - `alert` (attribute or child `fx-alert`) becomes the error message.
    - The `required`/`constraint` expressions are taken verbatim from the bind and compiled into the XQueryX tree, so they are parsed once at compile time and not on each request.
    - `relevant`: for non-relevant nodes the compiled rules skip `required` and `constraint`, as Fore does. It does not prune them.
4. **Middleware.** `fore:validate#2` in a new module (for example `content/fore-validation.xqm`). It runs after `parameters:in-request`, looks up `x-fore` on `$request?config`, and does nothing if the property is absent. If the module returns errors, it throws `error($errors:UNPROCESSABLE_ENTITY, "Validation failed", $errors-as-map)`. This is a 422 (a 400 would also work), and the default error handler emits the error list as JSON.
    - It is opt-in custom middleware passed to `roaster:route/3`, so existing apps are not affected. Placed after auth in that list, it keeps unauthenticated callers from triggering compilation.
5. **XML first, JSON later.** The compiler and the instance-binding code sit behind one interface, `fore:instance($request) as node()`. JSON support later means mapping the `?` lookup paths onto an eXist JSON map, with no change to the middleware or the `api.json` contract.
6. **Function mismatch is watched at compile time.** Fore expressions run on `fontoxpath` plus Fore's own function library (`instance()`, `now()`, `depends()`, and so on), while the server runs eXist's XQuery. The compiler walks every `required`/`constraint`/`relevant` expression and checks each function call against what eXist provides (standard `fn:`/`math:`/`map:`/`array:` functions, plus a small shim module for any Fore function worth supporting). An unknown or divergent function fails compilation with a message naming the bind and the function, so a form is never silently validated with different semantics. The result is reported once when the form is first compiled, not on each request. Behavioural differences for functions that exist on both sides are listed in the README.

## Other instances and comparisons

The request carries a single payload, the default instance. If an app needs several documents they are arranged inside that payload; there is no envelope or multipart packaging of instances.

Rules may still read other instances with `instance('id')` and `$id`. Those are **reference instances**: the server takes them from the Fore page itself (inline content or an app-relative `src`) and never from the request, because client-supplied reference data would let a tampered client make a tampered payload pass. The compiled module takes them in `$instances` (instance id to root node) next to the payload under `default`. Undefined, JSON or remote instances fail compilation.

eXist has no typed nodes, so comparing two nodes compares text (`"5" <= "10"` is false), as in Fore. Rules cast explicitly (`number(.) <= number(...)`); there is no automatic typing from the bind's `type`.

## Critical files

- New: `roaster/content/fore-validation.xqm` (middleware, cache, module loading) and a compiler module (for example `roaster/content/fore-compile.xqm`, which also holds the function check).
- Touch: `roaster/README.md` (a "Fore validation" section next to "Middleware"), and `roaster/expath-pkg.xml` or the build config to ship the new modules.
- Reuse: `errors.xql` (`UNPROCESSABLE_ENTITY`/`BAD_REQUEST`), `router:default-error-handler` and `x-error-handler` for output formatting, and the middleware contract from `router.xql:235`.
- Reference (read-only): `Fore/src/fx-bind.js` and `Fore/src/fx-model.js:1160-1230` for the exact `required`/`constraint` rules.

## Sample app (two-layer validation demo)

A small eXist app in the roaster workspace, `roaster/test/app-fore/` (next to the existing `test/app/`), so it ships with the tests. It has:

- `forms/invoice.html`, a Fore page with an inline XML instance and binds for `required`, `constraint` and `type`.
- `api.json` with a POST operation using `"x-fore": "forms/invoice.html"`.
- A trivial handler that stores the submitted data.
- The same page is served to the browser, so the demo shows that the client catches errors first and the server catches tampered requests (a `curl` with bad data returns the same alerts).

## Verification

- Mocha tests in `roaster/test/` (the same style as `error.test.js`):
    - valid body returns 200 and the handler runs;
    - missing required field returns 422 with the alert text;
    - failing `constraint` returns 422;
    - wrong `type` returns 422;
    - an operation without `x-fore` is unchanged;
    - a form using an unsupported Fore function fails compilation with a clear message that names the bind and the function;
    - binds on a non-default instance are ignored.
- Cache test: editing the Fore page changes validation behaviour on the next request.
- Run: `npm run test:build`, then `npm test` against a running eXist.
- Manual: open the sample form in a browser, break a field, and confirm that the browser and `curl` report the same error.

## Open questions before implementation

- The name of eXist's XQueryX compile function (step 2), and whether the cache collection should live in the database or on the filesystem. A short prototype answers both before the full build.
