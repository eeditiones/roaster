/**
 * an example gulpfile to make ant-less existdb package builds a reality
 */
const { src, dest, watch, series, parallel } = require('gulp')
const { createClient } = require('@existdb/gulp-exist')
const rename = require('gulp-rename')
const zip = require("gulp-zip")
const replace = require('@existdb/gulp-replace-tmpl')
const del = require('delete')

// read metadata from package.json and .existdb.json
const { version, license } = require('./package.json')
const { package, servers } = require('./.existdb.json')

// .tmpl replacements to include 
// first value wins
const replacements = [package, {version, license}]

const serverInfo = servers.localhost
const { port, hostname } = new URL(serverInfo.server)
const connectionOptions = {
    basic_auth: {
        user: serverInfo.user, 
        pass: serverInfo.password
    },
    host: hostname,
    port
}
const existClient = createClient(connectionOptions);

const static = [
    "content/*",
    "icon.png"
]

// test application metadata
const testAppNs = "http://exist-db.org/apps/oas-test"
const testAppFiles = ['test/app/*.*', "test/app/modules/*"]
const testAppPackageName = "oas-test.xar"

// construct the current xar name from available data
const packageName = () => `${package.target}-${version}.xar`

/**
 * helper function that uploads and installs a built XAR
 */
function installXar (packageName, packageUri) {
    return src(packageName)
        .pipe(existClient.install({ packageUri }))
}

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
        .pipe(replace(replacements, { unprefixed: true }))
        .pipe(rename(path => { path.extname = "" }))
        .pipe(dest('build/'))
}

exports.templates = templates

function watchTemplates () {
    watch('*.tmpl', series(templates))
}
exports["watch:tmpl"] = watchTemplates

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

/**
 * create XAR package in repo root
 */
function xar () {
    return src('build/**/*', {base: 'build'})
        .pipe(zip(packageName()))
        .pipe(dest('.'))
}

/**
 * create XAR package in repo root
 */
function packageTestApp () {
    return src(testAppFiles, {base: 'test/app'})
        .pipe(zip(testAppPackageName))
        .pipe(dest('.'))
}
exports["build:test"] = packageTestApp

/**
 * upload and install a built XAR
 */
function installTestAppXar () {
    return installXar(testAppPackageName, testAppNs)
}
exports["install:test"] = series(packageTestApp, installTestAppXar)

function watchTestApp () {
    watch(testAppFiles, series(packageTestApp, installTestAppXar));
}
exports["watch:test"] = watchTestApp

/**
 * upload and install the latest built XAR
 */
function installLibraryXar () {
    return installXar(packageName(), package.namespace)
}

// composed tasks
const packageLibrary = series(
    clean,
    templates,
    copyStatic,
    xar
)
const watchAll = parallel(
    watchStatic,
    watchTemplates,
    watchBuild,
    watchTestApp
)

exports.build = packageLibrary
// alias of build
exports.xar = packageLibrary

exports.watch = watchAll
exports.install = series(packageLibrary, installLibraryXar)
exports["install:all"] = series(
    packageLibrary, installLibraryXar, 
    packageTestApp, installTestAppXar
)

// main task for day to day development
exports.default = series(packageLibrary, installLibraryXar, watchAll)
