/**
 * build, watch, deploy tasks
 * for the library and example application package
 */
import { src, dest, watch, series, parallel } from 'gulp'
import rename from 'gulp-rename'
import zip from 'gulp-zip'
import del from 'delete'

import { createClient, readOptionsFromEnv } from '@existdb/gulp-exist'
import replace from '@existdb/gulp-replace-tmpl'

// read metadata from package.json and .existdb.json
import packageJSON from './package.json' with { type: 'json' }

const { version, license, app } = packageJSON

// .tmpl replacements to include
// first value wins
const replacements = [app, { version, license }]

const defaultOptions = { basic_auth: { user: 'admin', pass: '' } }
const connectionOptions = Object.assign(defaultOptions, readOptionsFromEnv())
const existClient = createClient(connectionOptions)

const distFolder = 'dist'

// XARs the test application depends on, installed from local files when present
const dependenciesFolder = 'test/dependencies'

const library = {
    static: ['content/*', 'icon.svg'],
    allBuildFiles: 'build/**/*',
    build: 'build',
    templates: '*.tmpl'
}

// test application metadata
const testApp = {
    files: ['test/app/*.*', 'test/app/modules/*', 'test/app/resources/*', 'test/app/uploads/*'],
    packageFilename: 'roasted.xar',
    build: 'test/app/build',
    base: 'test/app'
}
// construct the current xar name from available data
const packageFilename = `${app.target}-${version}.xar`

/**
 * helper function that uploads and installs a built XAR
 */
function installXar(packageFilename) {
    return src(packageFilename, { cwd: distFolder, encoding: false }).pipe(existClient.install())
}

/**
 * Install any XAR placed in test/dependencies.
 *
 * The test application declares dependencies on jwt and, through it,
 * expath-crypto. When they are not already present, eXist-db resolves them
 * from the public repository at exist-db.org while installing roasted.xar,
 * which makes the whole test suite depend on that host being reachable: when
 * it is down, every leg of CI fails at installTestAppXar with
 * "experr:EXPATH007 ... Connection refused" before a single test runs.
 *
 * Dropping the XARs here instead installs them from a local file. The folder
 * is normally empty - the task is then a no-op and resolution falls back to
 * the public repository, so an existing local setup keeps working unchanged.
 */
function installDependencies() {
    return src('*.xar', { cwd: dependenciesFolder, encoding: false, allowEmpty: true }).pipe(existClient.install())
}

export function cleanDist(cb) {
    del([distFolder], cb)
}

export function cleanLibrary(cb) {
    del([library.build], cb)
}

export function cleanTest(cb) {
    del([testApp.build], cb)
}

export function cleanAll(cb) {
    del([distFolder, library.build, testApp.build], cb)
}
export const clean = cleanAll

/**
 * replace placeholders
 * in src/*.xml.tmpl and
 * output to build/*.xml
 */
export function templates() {
    return src(library.templates)
        .pipe(replace(replacements, { unprefixed: true }))
        .pipe(
            rename((path) => {
                path.extname = ''
            })
        )
        .pipe(dest(library.build))
}

function watchTemplates() {
    watch(library.templates, series(templates))
}
export const watch_tmpl = watchTemplates

/**
 * copy html templates, XSL stylesheet, XMLs and XQueries to 'build'
 */
function copyStatic() {
    return src(library.static, { base: '.', encoding: false }).pipe(dest(library.build))
}
export const copy = copyStatic

function watchStatic() {
    watch(library.static, series(copyStatic))
}
export const watch_static = watchStatic

/**
 * since this is a pure library package uploading
 * the library itself will not update the compiled
 * version in the cache.
 * This is why the xar will be installed instead
 */
function watchBuild() {
    watch(library.allBuildFiles, series(xar, installLibraryXar))
}

/**
 * create XAR package in repo root
 */
function xar() {
    return src(library.allBuildFiles, { base: library.build, encoding: false })
        .pipe(zip(packageFilename))
        .pipe(dest(distFolder))
}

/**
 * create XAR package in repo root
 */
function packageTestApp() {
    return src(testApp.files, { base: testApp.base, dot: true, encoding: false })
        .pipe(zip(testApp.packageFilename))
        .pipe(dest(distFolder))
}
export const build_test = series(cleanTest, packageTestApp)

/**
 * upload and install a built XAR
 */
function installTestAppXar() {
    return installXar(testApp.packageFilename)
}
export const install_test = series(cleanTest, packageTestApp, installTestAppXar)

export function watchTestApp() {
    watch(testApp.files, series(packageTestApp, installTestAppXar))
}

/**
 * upload and install the latest built XAR
 */
function installLibraryXar() {
    return installXar(packageFilename)
}

// composed tasks
const packageLibrary = series(templates, copyStatic, xar)

export const build = series(cleanLibrary, packageLibrary)
export const build_all = series(cleanAll, packageLibrary, packageTestApp)

export const install = series(cleanLibrary, packageLibrary, installLibraryXar)
export const install_all = series(
    cleanAll,
    installDependencies,
    packageLibrary,
    installLibraryXar,
    packageTestApp,
    installTestAppXar
)

const watchAll = parallel(watchStatic, watchTemplates, watchBuild, watchTestApp)
export { watchAll as watch, build_all as 'build:all', install_all as 'install:all' }

// main task for day to day development
// package and install library
// package test application but do not install it
// still watch all and install on change
export default series(cleanAll, packageLibrary, installLibraryXar, packageTestApp, watchAll)
