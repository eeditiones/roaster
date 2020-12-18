/**
 * an example gulpfile to make ant-less existdb package builds a reality
 */
const { src, dest, watch, series, parallel } = require('gulp')
const { createClient } = require('@existdb/gulp-exist')
const rename = require('gulp-rename')
const zip = require("gulp-zip")
const gulpExistTmplReplace = require('./gulp-tmpl-replace.js')
const del = require('delete')
const pkg = require('./package.json')

// read metadata from .existdb.json
const existJSON = require('./.existdb.json')
// .tmpl replacements to include 
// first value wins
const { version, license } = pkg
const replacements = [existJSON.package, {version, license}]

const packageUri = existJSON.package.namespace
const serverInfo = existJSON.servers.localhost

const connectionOptions = {
    basic_auth: {
        user: serverInfo.user, 
        pass: serverInfo.password
    }
}
const existClient = createClient(connectionOptions);

/**
 * Use the `delete` module directly, instead of using gulp-rimraf
 */
function clean (cb) {
    del(['build'], cb);
}
exports.clean = clean

/**
 * replace placeholders 
 * in src/*.xml.tmpl and 
 * output to build/*.xml
 */
function templates() {
    return src('*.tmpl')
        .pipe(gulpExistTmplReplace({ replacements, unprefixed:true, debug:true }))
        .pipe(rename(path => { path.extname = "" }))
        .pipe(dest('build/'))
}

exports.templates = templates

function watchTemplates () {
    watch('*.tmpl', series(templates))
}
exports["watch:tmpl"] = watchTemplates

const static = [
    "content/*",
    // "src/icon.svg"
]

/**
 * copy html templates, XSL stylesheet, XMLs and XQueries to 'build'
 */
function copyStatic () {
    return src(static, {base: '.'}).pipe(dest('build'))
}
exports.copy = copyStatic

function watchStatic () {
    watch(static, series(copyStatic));
}
exports["watch:static"] = watchStatic

/**
 * since this is a pure library package uploading
 * the library itself will not update the compiled
 * version in the cache.
 * This is why the xar will be installed instead
 */
function watchBuild () {
    watch('build/**/*', series(xar, installXar))
}

// construct the current xar name from available data
const packageName = () => `${existJSON.package.target}-${version}.xar`

/**
 * create XAR package in repo root
 */
function xar () {
    return src('build/**/*', {base: 'build'})
        .pipe(zip(packageName()))
        .pipe(dest('.'))
}

/**
 * upload and install the latest built XAR
 */
function installXar () {
    return src(packageName())
        .pipe(existClient.install({ packageUri }))
}

// composed tasks
const build = series(
    clean,
    templates,
    copyStatic,
    xar
)
const watchAll = parallel(
    watchStatic,
    watchTemplates,
    watchBuild
)

exports.build = build
exports.watch = watchAll

exports.xar = build
exports.install = series(build, installXar)

// main task for day to day development
exports.default = series(build, installXar, watchAll)
