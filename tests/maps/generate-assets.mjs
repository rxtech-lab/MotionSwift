// Authored test pattern, not downloaded map data. Regenerate with node tests/maps/generate-assets.mjs.
import fs from 'node:fs';
import {PNG} from 'pngjs';
const directory = new URL('./public/', import.meta.url);
fs.mkdirSync(directory, {recursive: true});
function image(width, height, originX, originY) {
  const png = new PNG({width, height});
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const worldX = originX + x, worldY = originY + y;
    const color = worldX > 240 && worldX < 290 ? [112, 176, 208] :
      worldX % 64 < 8 || worldY % 64 < 8 ? [248, 240, 216] : [176, 208, 144];
    png.data.set([...color, 255], (y * width + x) * 4);
  }
  return PNG.sync.write(png);
}
for (let index = 0; index < 6; index++) {
  fs.writeFileSync(new URL(`tile-${index}.png`, directory), image(128, 128, (index % 3) * 128, Math.floor(index / 3) * 128));
}
fs.writeFileSync(new URL('snapshot.png', directory), image(320, 180, 0, 32));
