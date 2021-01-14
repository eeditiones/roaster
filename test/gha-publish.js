const execa = require('execa');

async function publish ({pkgRoot}, {cwd, env, stdout, stderr, nextRelease: {version}, logger}) {
    const basePath = pkgRoot ? path.resolve(cwd, pkgRoot) : cwd;

    logger.log('Create XAR in version %s in %s', version, basePath);

    const packageResult = execa('npm', ['run', 'build'], {cwd:basePath, env});

    packageResult.stdout.pipe(stdout, {end: false});
    packageResult.stderr.pipe(stderr, {end: false});
  
    await packageResult;
}

module.exports = { publish };
