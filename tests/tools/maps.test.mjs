import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {loadPortable, vendorInfo} from './portable.mjs';
import {testRoot} from './common.mjs';

const portable = loadPortable();
const vendor = vendorInfo().specifiers;
for (const specifier of ['leaflet', 'react-leaflet', 'mapkit.js', '@apple/mapkitjs-react']) {
  test(`native map boundary: ${specifier} needs a browser integration`, () => {
    assert.throws(() => portable.compile(JSON.stringify({files: {
      'src/index.ts': `import * as maps from '${specifier}'; console.log(maps);`,
    }, entry: 'src/index.ts', vendor})), /ms\/unsupported-package/);
  });
}
test('map tile and snapshot compositions compile and type check against the native subset', () => {
  const entry = 'src/index.tsx';
  const project = path.join(testRoot, 'maps');
  const source = fs.readFileSync(path.join(project, entry), 'utf8');
  const graph = JSON.parse(portable.compile(JSON.stringify({files: {[entry]: source}, entry, vendor})));
  assert.equal(graph.modules[entry].dependencies.remotion, 'vendor:remotion');
  const {check} = createRequire(import.meta.url)('../../js/compiler/check.cjs');
  assert.deepEqual(check(project, entry), []);
});
