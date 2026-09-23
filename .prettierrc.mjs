import prettierPluginXQuery from 'prettier-plugin-xquery'

/**
 * @type {import('prettier').Config}
 */
const config = {
    semi: false,
    singleQuote: true,
    trailingComma: 'none',
    useTabs: false,
    tabWidth: 4,
    printWidth: 120,
    plugins: [prettierPluginXQuery],
    overrides: [
        {
            files: ['*.xq', '*.xql', '*.xqm', '*.xqy', '*.xquery'],
            options: {
                singleQuote: false
            }
        },
        {
            files: 'package.json',
            options: {
                tabWidth: 2
            }
        },
        {
            files: ['*.yml', '*.yaml'],
            options: {
                tabWidth: 2,
                singleQuote: false
            }
        }
    ]
}

export default config
