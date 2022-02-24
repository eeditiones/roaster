/**
 * build, watch, deploy tasks
 * for the library and example application package
 */
const { src, dest, watch, series, parallel } = require('gulp')
const rename = require('gulp-rename')
const zip = require("gulp-zip")
const del = require('delete')

const { createClient, readOptionsFromEnv } = require('@existdb/gulp-exist')
const replace = require('@existdb/gulp-replace-tmpl')

// read metadata from package.json and .existdb.json
const { version, license, app } = require('./package.json')

// .tmpl replacements to include 
// first value wins
const replacements = [app, {version, license}]

const defaultOptions = { basic_auth: { user: "admin", pass: "" } }
const connectionOptions = Object.assign(defaultOptions, readOptionsFromEnv())
const existClient = createClient(connectionOptions);

const distFolder = 'dist'

const library = {
    static: [
        "content/*",
        "icon.svg"
    ],
    allBuildFiles: 'build/**/*',
    build: 'build',
    templates: '*.tmpl'
}


// test application metadata
const testApp = {
    files: [
        'test/app/*.*',
        'test/app/modules/*',
        "test/app/resources/*",
        "test/app/uploads/*"
    ],
    packageFilename: "roasted.xar",
    build: 'test/app/build',
    base: 'test/app'
}
// construct the current xar name from available data
const packageFilename = `${app.target}-${version}.xar`

/**
 * helper function that uploads and installs a built XAR
 */
function installXar (packageFilename) {
    return src(packageFilename, {cwd: distFolder})
        .pipe(existClient.install())
}

function cleanDist (cb) {
    del([distFolder], cb);
}
exports['clean:dist'] = cleanDist

function cleanLibrary (cb) {
    del([library.build], cb);
}
exports['clean:library'] = cleanLibrary

function cleanTest (cb) {
    del([testApp.build], cb);
}
exports['clean:test'] = cleanTest

function cleanAll (cb) {
    del([distFolder, library.build, testApp.build], cb);
}
exports['clean:all'] = cleanAll

exports.clean = cleanAll

/**
 * replace placeholders 
 * in src/*.xml.tmpl and 
 * output to build/*.xml
 */
function templates() {
    return src(library.templates)
        .pipe(replace(replacements, { unprefixed: true }))
        .pipe(rename(path => { path.extname = "" }))
        .pipe(dest(library.build))
}

exports.templates = templates

function watchTemplates () {
    watch(library.templates, series(templates))
}
exports["watch:tmpl"] = watchTemplates

/**
 * copy html templates, XSL stylesheet, XMLs and XQueries to 'build'
 */
function copyStatic () {
    return src(library.static, {base: '.'}).pipe(dest(library.build))
}
exports.copy = copyStatic

function watchStatic () {
    watch(library.static, series(copyStatic));
}
exports["watch:static"] = watchStatic

/**
 * since this is a pure library package uploading
 * the library itself will not update the compiled
 * version in the cache.
 * This is why the xar will be installed instead
 */
function watchBuild () {
    watch(library.allBuildFiles, series(xar, installLibraryXar))
}

/**
 * create XAR package in repo root
 */
function xar () {
    return src(library.allBuildFiles, {base: library.build})
        .pipe(zip(packageFilename))
        .pipe(dest(distFolder))
}

/**
 * create XAR package in repo root
 */
function packageTestApp () {
    return src(testApp.files, {base: testApp.base, dot:true})
        .pipe(zip(testApp.packageFilename))
        .pipe(dest(distFolder))
}
exports["build:test"] = series(cleanTest, packageTestApp)

/**
 * upload and install a built XAR
 */
function installTestAppXar () {
    return installXar(testApp.packageFilename)
}
exports["install:test"] = series(cleanTest, packageTestApp, installTestAppXar)

function watchTestApp () {
    watch(testApp.files, series(packageTestApp, installTestAppXar));
}
exports["watch:test"] = watchTestApp

/**
 * upload and install the latest built XAR
 */
function installLibraryXar () {
    return installXar(packageFilename)
}

// composed tasks
const packageLibrary = series(
    templates,
    copyStatic,
    xar
)

exports.build = series(cleanLibrary, packageLibrary)
exports["build:all"] = series(
    cleanAll,
    packageLibrary, 
    packageTestApp
)

exports.install = series(cleanLibrary, packageLibrary, installLibraryXar)
exports["install:all"] = series(
    cleanAll,
    packageLibrary, installLibraryXar, 
    packageTestApp, installTestAppXar
)

const watchAll = parallel(
    watchStatic,
    watchTemplates,
    watchBuild,
    watchTestApp
)
exports.watch = watchAll

// main task for day to day development
// package and install library
// package test application but do not install it
// still watch all and install on change 
exports.default = series(
    cleanAll, 
    packageLibrary, installLibraryXar,
    packageTestApp,
    watchAll
)
