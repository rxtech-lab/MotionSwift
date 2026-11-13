import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import test from 'node:test';
import {filmFrames, layerRegistry} from './generate-editable-film.mjs';
import {loadPortable, repo} from './portable.mjs';
const require = createRequire(import.meta.url);
const {transform} = require('sucrase');

test('film timeline represents exact appearances, including dissolves and recurring objects', () => {
  const frames = filmFrames();
  const registry = layerRegistry(frames);
  assert.equal(fs.readFileSync(`${repo}/Examples/MotionShowcase/Film/LayerRegistry.tsx`, 'utf8'), registry,
    'Regenerate the layer registry after changing the fixture or generator');
  const tracks = JSON.parse(loadPortable().timeline(registry, 'src/Composition.tsx'));
  assert.ok(tracks.every(t => t.reason === null && t.duration > 0 && t.from + t.duration <= 2700));
  assert.ok(tracks.every(t => t.from > 0 || t.duration < 2700));
  const audience = tracks.find(t => t.label === 'aub0');
  assert.equal(audience.from, 319);
  assert.equal(audience.from + audience.duration, 660);
  const outgoing = tracks.find(t => t.label === 'a_aub0');
  assert.equal(outgoing.from, 660);
  assert.equal(outgoing.from + outgoing.duration, 681);
  const titles = tracks.filter(t => t.label === 'title');
  assert.ok(titles.length > 1, 'Separated appearances must have separate editable clips');
  const code = transform(registry + '\nexport {editableObject};', {transforms: ['typescript', 'jsx', 'imports']}).code;
  const exports = {};
  const React = {createElement: (type, props) => ({type, props})};
  new Function('React', 'EditableLayer', 'exports', code)(React, 'EditableLayer', exports);
  frames.forEach((objects, frame) => {
    const active = tracks.filter(t => t.from <= frame && frame < t.from + t.duration).map(t => t.label).sort();
    assert.deepEqual(active, objects.map(o => o.key).sort(), `Frame ${frame} must have exactly the visible clips`);
    for (const {n, key} of objects) {
      const element = exports.editableObject(n, key, frame);
      const timing = element.props['data-ms-timeline'];
      assert.ok(timing.from <= frame && frame < timing.from + timing.duration, `Frame ${frame}: ${key} must render`);
      assert.equal(element.props.node, n);
    }
  });
});
