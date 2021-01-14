const execa = require('execa');

async function publish (pluginConfig, {cwd, env}) {
    const packageResult = execa('npm', ['run', 'build'], {cwd, env});
    packageResult.stdout.pipe(stdout, {end: false});
    packageResult.stderr.pipe(stderr, {end: false});
    await packageResult;
}

module.exports = { publish };
