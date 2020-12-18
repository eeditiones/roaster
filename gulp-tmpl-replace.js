const replace = require('gulp-replace')

const defaultPrefix = "package"
const defaultPattern = /@(package\.)?([^@]+)@/g
const contextCharacters = 20

/**
 * show that the file contents were shortened
 * 
 * @param {Boolean} display 
 * @returns {String} '...' if display is true, '' otherwise
 */
function ellipsis (display) {
    if (display) { return '...' }
    return ''
}

function getLine (string, offset) {
    return string.substring(0, offset).match(/\n/g).length + 1
}

/**
 * report problems in replacements in .tmpl files
 * replaces the problematic values with an empty string
 * 
 * @param {String} match
 * @param {Number} offset
 * @param {String} string
 * @param {String} path
 * @param {String} message
 * @returns {String} empty string
 */
function logReplacementIssue (match, offset, string, path, message) {
    const startIndex = Math.max(0, offset - contextCharacters)
    const startEllipsis = Boolean(startIndex)
    const start = string.substring(startIndex, offset)

    const matchEnd = offset + match.length
    const endIndex = Math.min(string.length, matchEnd + contextCharacters)
    const endEllipsis = endIndex === string.length
    const end = string.substring(matchEnd, endIndex)

    console.warn(`\n\x1b[31m${match}\x1b[39m ${message}`)
    console.warn(`Found at line ${getLine(string, offset)} in ${path}`)
    console.warn(`${ellipsis(startEllipsis)}${start}\x1b[31m${match}\x1b[39m${end}${ellipsis(endEllipsis)}`)
}

/**
 * replace placeholders in the form `@{prefix}.something@`
 * similar to your normal .tmpl replacements
 * 
 * @param {String} match 
 * @param {String} p1 
 * @param {String} p2
 * @param {Number} offset 
 * @param {String} string 
 * @returns {String} replacement or empty string
 */
function getMatchHandlerWithPrefix(prefix, replacements) {
    return function handleMatchesWithPrefix (match, p1, p2, offset, string) {
        const path = this.file.relative

        // handle missing "package." prefix
        if (!p1) {
            logReplacementIssue(match, offset, string, path, `replacement must start with '${prefix}.'`)
            return ""
        }

        // handle missing substitution
        if (!replacements.has(p2)) {
            logReplacementIssue(match, offset, string, path, "has no replacement!")
            return ""
        }

        return replacements.get(p2)
    }
}

/**
 * replace placeholders in the form `@something@`
 * similar to your normal .tmpl replacements
 * 
 * @param {String} match 
 * @param {String} p1 
 * @param {Number} offset 
 * @param {String} string 
 * @returns {String} replacement or empty string
 */
function getMatchHandler(replacements) {
    return function handleMatches (match, p1, offset, string) {
        const path = this.file.relative

        // handle missing substitution
        if (!replacements.has(p1)) {
            logReplacementIssue(match, offset, string, path, "has no replacement!")
            return ""
        }

        return replacements.get(p1)
    }
}

function mergeReplacements (replacements) {
    // convert an array of objects into a single merged map
    if (Array.isArray(replacements)) {
        return replacements
            .reverse() // last repeated key wins
            .map(obj => Object.entries(obj)) // convert into an array of [k, v]
            .reduce((map, nextEntries) => new Map([...map, ...nextEntries]), new Map())
    }

    return new Map(Object.entries(replacements))
}

function GulpExistTmplReplace(options) {
    // required option missing
    if (!options || !options.replacements) {
        throw new Error("Substitutions missing")
    }
    if (options.prefix && options.prefix.match(/[^a-zA-Z0-9]/)) {
        throw new Error("Invalid prefix, only [a-zA-Z0-9] allowed")
    }

    const mergedReplacements = mergeReplacements(options.replacements)
    
    let pattern, handler, prefix 

    if (!options.prefix && !options.unprefixed) {
        prefix = defaultPrefix
        pattern = defaultPattern
        handler = getMatchHandlerWithPrefix(defaultPrefix, mergedReplacements)
    }
    if (options.prefix) {
        prefix = options.prefix
        pattern = new RegExp(`@(${options.prefix}\.)?([^@]+)@`, "g")
        handler = getMatchHandlerWithPrefix(options.prefix, mergedReplacements)
    }
    if (options.unprefixed) {
        prefix = undefined
        pattern = /@([^@]+)@/g
        handler = getMatchHandler(mergedReplacements, options)        
    }

    if (options.debug) {
        console.log("Prefix:", prefix ? prefix : "unprefixed" )
        console.log("Replacements:", mergedReplacements)
    }

    return replace(pattern, handler)
}

module.exports = GulpExistTmplReplace