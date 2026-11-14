import {basemap} from './basemap';
import {path, route, stations} from './route';

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;');

// All names sit outside the geographic track, with leaders instead of overlapping labels.
export function artwork() {
  const left = stations.filter((_, index) => index >= 8 && index <= 21).sort((a, b) => a.point[1] - b.point[1]);
  const right = stations.filter((_, index) => index < 8 || index > 21).sort((a, b) => a.point[1] - b.point[1]);
  const labels = stations.map(station => {
    const onLeft = left.includes(station), column = onLeft ? left : right;
    const row = column.indexOf(station);
    const y = 185 + row * (onLeft ? 55 : 49);
    const [sx, sy] = station.point;
    const edge = onLeft ? 414 : 1008, x = onLeft ? 400 : 1022;
    const anchor = onLeft ? 'end' : 'start';
    return `<path d="M${sx},${sy} L${edge},${y}" fill="none" stroke="#9cac9a" stroke-width="1"/>` +
      `<circle cx="${sx}" cy="${sy}" r="5.5" fill="#ffffff" stroke="#5a9229" stroke-width="2.5"/>` +
      `<text x="${x}" y="${y - 4}" text-anchor="${anchor}" font-size="18" font-weight="600" fill="#233c2d">${escape(station.localName)}</text>` +
      `<text x="${x}" y="${y + 17}" text-anchor="${anchor}" font-size="16" fill="#526953">${escape(station.code)} · ${escape(station.name)}</text>`;
  }).join('');
  const content = `<image href="${basemap}" width="1440" height="1080"/>` +
    `<path d="${path(route)}" fill="none" stroke="#ffffff" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>` +
    `<path d="${path(route)}" fill="none" stroke="#85b348" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>` + labels +
    '<rect width="1440" height="106" fill="#173d2b"/>' +
    '<text x="44" y="36" font-size="15" letter-spacing="4" fill="#b5d68d">TOKYO, JAPAN / JR YAMANOTE LINE</text>' +
    '<text x="42" y="80" font-size="34" font-weight="600" fill="#f6f6eb">A whole journey around Tokyo.</text>' +
    '<text x="1396" y="40" text-anchor="end" font-size="16" fill="#c9dfb4">30 STATIONS · CLOCKWISE / 外回り</text>' +
    '<text x="1396" y="74" text-anchor="end" font-size="16" fill="#c9dfb4">Tokyo → Tokyo · Complete loop</text>' +
    '<text x="724" y="448" text-anchor="middle" font-size="46" font-weight="600" fill="#36553b">山手線</text>' +
    '<text x="724" y="480" text-anchor="middle" font-size="15" letter-spacing="3" fill="#62775e">YAMANOTE LINE</text>' +
    '<rect x="0" y="1008" width="1440" height="72" fill="#173d2b"/>' +
    '<text x="44" y="1037" font-size="15" fill="#d6e9c2">Real railway geometry · All 30 stations · Illustrative timing</text>' +
    '<text x="44" y="1062" font-size="13" fill="#a9c69b">© OpenStreetMap contributors · ODbL · openstreetmap.org/copyright</text>' +
    '<text x="1396" y="1050" text-anchor="end" font-size="15" fill="#d6e9c2">BUNDLED MAP / OFFLINE PLAYBACK</text>';
  return 'data:image/svg+xml,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1080" font-family="Helvetica Neue, Hiragino Sans, sans-serif">${content}</svg>`);
}
