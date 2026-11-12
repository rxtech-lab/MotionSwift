// Download/generate gitignored SwiftPM resources before building. Built apps need no Node/npm.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = process.env.MOTIONSWIFT_COMPILER_RESOURCES
  ? path.resolve(process.env.MOTIONSWIFT_COMPILER_RESOURCES)
  : path.join(repo, 'Sources/MotionCompiler/Resources');
const deps = path.join(repo, 'tests/node_modules');
const require = createRequire(path.join(repo, 'tests/package.json'));
const versions = {typescript: '7.0.2', esbuild: '0.28.1'};
fs.mkdirSync(path.join(output, 'Toolchains'), {recursive: true});
for (const arch of ['arm64', 'x64']) {
  for (const [name, version] of Object.entries(versions)) {
    const pkg = name === 'typescript' ? `@typescript/typescript-darwin-${arch}` : `@esbuild/darwin-${arch}`;
    const archive = `${pkg.replace('@', '').replace('/', '-')}-${version}.tgz`;
    // A local archive cache is useful when updating the resources offline.
    const cached = process.env.MOTIONSWIFT_ARCHIVE_CACHE;
    if (fs.existsSync(path.join(output, 'Toolchains', archive))) {
      continue;
    } else if (cached && fs.existsSync(path.join(cached, archive))) {
      fs.copyFileSync(path.join(cached, archive), path.join(output, 'Toolchains', archive));
    } else {
      execFileSync('npm', ['pack', `${pkg}@${version}`, '--ignore-scripts', '--pack-destination', path.join(output, 'Toolchains'), '--loglevel=error'], {stdio: 'inherit'});
    }
  }
}
for (const name of ['react', 'react-reconciler', 'scheduler', '@types/react', '@types/prop-types', 'csstype']) {
  fs.cpSync(path.join(deps, name), path.join(output, 'Vendor/node_modules', name), {recursive: true});
}
fs.cpSync(path.join(repo, 'js/remotion-shim'), path.join(output, 'Vendor/shim'), {recursive: true});
const entry = path.join(repo, 'js/compiler/inspect.mjs');
execFileSync(require.resolve(`@esbuild/darwin-${process.arch}/bin/esbuild`), [entry, '--bundle', `--alias:@babel/parser=${require.resolve('@babel/parser')}`, '--format=iife', '--global-name=MotionInspector', '--minify', `--outfile=${path.join(output, 'inspect.js')}`]);
fs.copyFileSync(path.join(deps, '@babel/parser/LICENSE'), path.join(output, 'PARSER-LICENSE.txt'));
fs.copyFileSync(path.join(deps, 'esbuild/LICENSE.md'), path.join(output, 'ESBUILD-LICENSE.txt'));
fs.writeFileSync(path.join(output, 'versions.json'), JSON.stringify(versions, null, 2) + '\n');
