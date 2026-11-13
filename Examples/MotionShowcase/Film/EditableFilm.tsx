// Appended only to the editor's working copy; the reviewed benchmark source stays intact.
// Each generated JSX call owns its editable style, timing and keyframes. The animated position
// remains on an unstamped parent, so a canvas transform offsets the original motion.
function pathBounds(d: string) {
  const tokens = d.match(/[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/gi) || [];
  const counts: any = {M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7};
  let i = 0, command = 'M', x = 0, y = 0, sx = 0, sy = 0;
  const xs = [0], ys = [0];
  while (i < tokens.length) {
    if (/^[a-z]$/i.test(tokens[i])) command = tokens[i++];
    const upper = command.toUpperCase(), relative = command !== upper;
    if (upper === 'Z') { x = sx; y = sy; command = 'M'; continue; }
    const count = counts[upper];
    if (!count || i + count > tokens.length) break;
    const values = tokens.slice(i, i + count).map(Number);
    if (values.some(v => !Number.isFinite(v))) break;
    i += count;
    if (upper === 'H') { x = values[0] + (relative ? x : 0); xs.push(x); }
    else if (upper === 'V') { y = values[0] + (relative ? y : 0); ys.push(y); }
    else if (upper === 'A') {
      const nx = values[5] + (relative ? x : 0), ny = values[6] + (relative ? y : 0);
      // A conservative hull covers rotated elliptical arcs as well as their endpoints.
      const radius = Math.abs(values[0]) + Math.abs(values[1]);
      xs.push(x - radius, x + radius, nx - radius, nx + radius);
      ys.push(y - radius, y + radius, ny - radius, ny + radius);
      x = nx; y = ny;
    } else {
      for (let j = 0; j < count; j += 2) {
        xs.push(values[j] + (relative ? x : 0)); ys.push(values[j + 1] + (relative ? y : 0));
      }
      x = xs[xs.length - 1]; y = ys[ys.length - 1];
      if (upper === 'M') { sx = x; sy = y; command = relative ? 'l' : 'L'; }
    }
  }
  return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
}

function objectBounds(n: any) {
  let box: number[];
  if (n.t === 'rect') box = [-n.w / 2, -n.h / 2, n.w / 2 + (n.sh ? 20 : 0), n.h / 2 + (n.sh ? 24 : 0)];
  else if (n.t === 'text') {
    const width = Array.from(n.text).reduce((sum: number, c: any) =>
      sum + (c.charCodeAt(0) > 255 ? 1.1 : 0.85) * n.size + (n.ls || 0), 0);
    const left = n.anchor === 'start' ? 0 : n.anchor === 'end' ? -width : -width / 2;
    box = [left, -n.size, left + width, n.size * 0.6];
  } else if (n.t === 'path') box = pathBounds(n.d);
  else box = [-180, -190, 180, 150];
  const angle = (n.rot || 0) * Math.PI / 180, scale = n.s ?? 1;
  const points = [[box[0], box[1]], [box[2], box[1]], [box[0], box[3]], [box[2], box[3]]]
    .map(([x, y]) => [n.x + scale * (x * Math.cos(angle) - y * Math.sin(angle)),
      n.y + scale * (x * Math.sin(angle) + y * Math.cos(angle))]);
  const pad = 20 + (n.sw || 0);
  const x = Math.min(...points.map(p => p[0])) - pad, y = Math.min(...points.map(p => p[1])) - pad;
  return {x, y, width: Math.max(1, Math.max(...points.map(p => p[0])) - x + pad),
    height: Math.max(1, Math.max(...points.map(p => p[1])) - y + pad)};
}

const EditableLayer = (props: any) => {
  let n = {...props.node};
  const style = props.style || {};
  if (style.content) n.text = style.content;
  if (style.color && style.color !== '#00000000') n.fill = style.color;
  if (style.fontSize) n.size = style.fontSize;
  const bounds = objectBounds(n);
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" font-family="PingFang SC, Helvetica Neue, sans-serif" '
    + 'viewBox="' + [bounds.x, bounds.y, bounds.width, bounds.height].join(' ') + '">'
    + xml(drawSVG(n, props.layerKey)) + '</svg>';
  const {content, color, fontSize, ...visualStyle} = style;
  return <div data-ms-src={undefined} style={{position: 'absolute', left: bounds.x, top: bounds.y}}>
    <div data-ms-src={props['data-ms-src']} style={{position: 'relative', width: bounds.width, height: bounds.height, ...visualStyle}}>
      <img data-ms-src={undefined} src={'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)}
        style={{width: '100%', height: '100%', objectFit: 'contain'}} />
    </div>
  </div>;
};

export const MyComposition: React.FC = () => {
  const frame = useCurrentFrame(), s = frame / 30;
  let ci = 0;
  for (let i = 0; i < cues.length; i++) if (s >= cues[i].at) ci = i;
  const cur = cues[ci], t = s - cur.at, u = t / D, B = scene(cur.id, t);
  const A = u < 1 ? (ci > 0 ? scene(cues[ci - 1].id, s - cues[ci - 1].at) : []) : null;
  const root = frameSvg(frame), children = root.props.children;
  const background = (index: number) => xml({...root, props: {...root.props,
    children: [children[0], children[index]]}}).replace('<svg ',
    '<svg xmlns="http://www.w3.org/2000/svg" font-family="PingFang SC, Helvetica Neue, sans-serif" ');
  const image = (index: number) => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(background(index));
  return <AbsoluteFill style={{backgroundColor: '#F1DFC4'}}>
    <img data-ms-label="Background gradient" src={image(1)}
      style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, opacity: 1, objectFit: 'contain'}} />
    <img data-ms-label="Background grain" src={image(2)}
      style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, opacity: 1, objectFit: 'contain'}} />
    <img data-ms-label="Gold backdrop circle" src={image(3)}
      style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, opacity: 1, objectFit: 'contain'}} />
    <img data-ms-label="Rust backdrop circle" src={image(4)}
      style={{position: 'absolute', left: 0, top: 0, width: 1920, height: 1080, opacity: 1, objectFit: 'contain'}} />
    {compose(A, B, u).filter(Boolean).map(({n, key}: any) =>
      <React.Fragment key={key}>{editableObject(n, key)}</React.Fragment>)}
  </AbsoluteFill>;
};
