import crypto from 'node:crypto';
import fs from 'node:fs';
import {PNG} from 'pngjs';

export const testFilmChromiumOptions = {gl:'swangle'};
export const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
export function pixelHash(file, width, height) {
  const png = PNG.sync.read(fs.readFileSync(file));
  if (png.width !== width || png.height !== height) throw Error(`Unexpected image dimensions: ${file}`);
  return sha256(png.data);
}
export function maxChannelDelta(expected, actual) {
  if (expected.length !== actual.length) throw Error('Pixel buffers differ in size');
  let maximum=0;
  for(let i=0;i<expected.length;i++) maximum=Math.max(maximum,Math.abs(expected[i]-actual[i]));
  return maximum;
}
export function validateBaseline(baseline, pins) {
  if (baseline.schema !== 1 || baseline.backend !== 'cpu' || !Array.isArray(baseline.frames) || !baseline.frames.length)
    throw Error('Invalid Test Film baseline');
  for (const key of ['remotionVersion', 'platform', 'arch', 'osRelease']) {
    if (baseline[key] !== pins[key]) throw Error(`Test Film ${key} changed; review and regenerate the baseline explicitly`);
  }
  if (JSON.stringify(baseline.browser) !== JSON.stringify(pins.browser)) throw Error('Test Film browser pin changed');
  if (JSON.stringify(baseline.chromiumOptions) !== JSON.stringify(pins.chromiumOptions)) throw Error('Test Film Chromium renderer changed');
  const hash = /^[a-f0-9]{64}$/;
  if (!Array.isArray(baseline.files) || !baseline.files.length || baseline.files.some(file=>
    !/^[\w.-]+\.(tsx?|json)$/.test(file.name) || !hash.test(file.sha256))) throw Error('Invalid source manifest');
  if (new Set(baseline.files.map(file=>file.name)).size !== baseline.files.length) throw Error('Duplicate source files');
  const seen = new Set();
  for (const row of baseline.frames) {
    if (!Number.isInteger(row.frame) || row.frame < 0 || row.frame >= baseline.composition.durationInFrames || seen.has(row.frame)
      || typeof row.nativeRGBA !== 'string' || !hash.test(row.nativeRGBA)
      || typeof row.remotionRGBA !== 'string' || !hash.test(row.remotionRGBA)
      || (row.remotionWebP !== undefined && !hash.test(row.remotionWebP))) throw Error('Invalid/duplicate baseline frame');
    seen.add(row.frame);
  }
}
// Native is exact and repeatable. Chrome gets only the existing 0.3% pixel
// allowance AND a one-unit maximum channel delta to accommodate raster rounding.
export function assessFrame(expected, nativeRGBA, remotionRGBA, repeatRGBA, referenceComparison) {
  const nativeMatch = expected.nativeRGBA === nativeRGBA;
  const referenceMatch = referenceComparison
    ? referenceComparison.diffRatio <= 0.003 && referenceComparison.maxChannelDelta <= 1
    : expected.remotionRGBA === remotionRGBA;
  const deterministic = nativeRGBA === repeatRGBA;
  return {nativeMatch, referenceMatch, deterministic, pass:nativeMatch && referenceMatch && deterministic};
}
