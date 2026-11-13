import {basemap} from './basemap';
import {path, route, stations} from './route';

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const offsets = [[-6, 35], [-36, 48], [-40, -38], [-38, 45], [-62, 48], [-76, 40], [-105, -24]];

// Prepare static cartography once. Playback computes the train's geographic path.
export function artwork() {
  const labels = stations.map((station, index) => {
    const [x, y] = station.point;
    const [dx, dy] = offsets[index];
    const width = Math.max(100, station.name.length * 7 + 18);
    const labelY = y + dy;
    return `<path d="M${x},${y} L${x + dx + 12},${labelY}" stroke="#667a81" stroke-width="1"/>` +
      `<circle cx="${x}" cy="${y}" r="6" fill="#ffffff" stroke="#007dc5" stroke-width="2"/>` +
      `<rect x="${x + dx}" y="${labelY - 18}" width="${width}" height="36" rx="5" fill="#ffffff" fill-opacity="0.94"/>` +
      `<text x="${x + dx + 9}" y="${labelY - 3}" font-size="12" fill="#163747">${escape(station.name)}</text>` +
      `<text x="${x + dx + 9}" y="${labelY + 11}" font-size="10" fill="#58727a">${escape(station.localName)}</text>`;
  }).join('');
  const content = `<image href="${basemap}" width="960" height="540"/>` +
    `<path d="${path(route)}" fill="none" stroke="#ffffff" stroke-width="11" stroke-linecap="round"/>` +
    `<path d="${path(route)}" fill="none" stroke="#007dc5" stroke-width="5" stroke-linecap="round"/>` + labels +
    '<rect width="960" height="94" fill="#112f38"/>' +
    '<text x="36" y="29" font-size="12" letter-spacing="3" fill="#90c9d4">HONG KONG / ISLAND LINE</text>' +
    '<text x="34" y="65" font-size="30" fill="#f6f4e9">Across the island.</text>' +
    '<text x="660" y="38" font-size="12" fill="#b3d3d9">7 STATIONS · EASTBOUND</text>' +
    '<text x="660" y="62" font-size="12" fill="#b3d3d9">Real OpenStreetMap streets &amp; track</text>' +
    '<text x="360" y="148" font-size="14" letter-spacing="4" fill="#527e8c">VICTORIA HARBOUR</text>' +
    '<rect x="0" y="470" width="960" height="70" fill="#112f38"/>' +
    '<text x="36" y="496" font-size="11" fill="#90c9d4">FOLLOW THE TRAIN / ISLAND LINE</text>' +
    '<text x="36" y="523" font-size="19" fill="#f6f4e9">Sheung Wan → Fortress Hill</text>' +
    '<text x="620" y="498" font-size="11" fill="#b3d3d9">© OpenStreetMap contributors · ODbL</text>' +
    '<text x="620" y="519" font-size="10" fill="#b3d3d9">openstreetmap.org/copyright · geographic data extract</text>';
  return 'data:image/svg+xml,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="960" height="540" font-family="Helvetica Neue, sans-serif">${content}</svg>`);
}
