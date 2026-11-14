const runtime = require('react/jsx-runtime');
const React = require('react');
const {useCurrentFrame} = require('./index');
const threeEdit = require('./three-edit');
const mapEdit = require('./map-edit');

// A component boundary keeps hooks unconditional and adds no layout node.
function TimelineElement({type, original}) {
  const frame = useCurrentFrame();
  const {'data-ms-timeline': timeline, ...props} = original;
  if (frame < timeline.from || (timeline.duration !== null && frame >= timeline.from + timeline.duration)) return null;
  const style = {...props.style};
  // Prop domains (3D, maps) keyframe component props; everything else keyframes CSS styles.
  const name = type?.__msThreeCanvas === true ? 'ThreeCanvas' : typeof type === 'string' ? type : type?.__msEditType;
  const three = threeEdit.isThree(name);
  const map = !three && mapEdit.isMap(name);
  if (type?.__msThreeCanvas === true && Object.keys(timeline.keyframes).some(key => key.startsWith('camera')))
    props.__msEditorCamera = true;
  for (const [key, points] of Object.entries(timeline.keyframes)) {
    const local = frame - timeline.from;
    const next = points.findIndex(p => p.frame > local);
    let value;
    if (next === 0) value = points[0].value;
    else if (next < 0) value = points.at(-1).value;
    else {
      const a = points[next - 1], b = points[next];
      value = a.easing === 'hold' ? a.value : a.value + (b.value - a.value) * (local - a.frame) / (b.frame - a.frame);
    }
    if (three) threeEdit.animate(name, props, key, value);
    else if (map) mapEdit.animate(name, props, key, value);
    else style[key] = value;
  }
  if (map) applyPreview(name, props);
  return React.createElement(type, three || map ? props : {...props, style});
}

// Editor previews of map props: the host sets `__ms_propOverridesJSON` for one evaluation.
let previewText = null, previewValues = null;
function applyPreview(name, props) {
  const text = globalThis.__ms_propOverridesJSON, source = props['data-ms-src'];
  if (typeof text !== 'string' || !source) return false;
  if (text !== previewText) { previewText = text; previewValues = JSON.parse(text); }
  const patch = previewValues[source];
  if (!patch) return false;
  const known = new Set(mapEdit.fields(name).map(field => field.key));
  for (const [key, value] of Object.entries(patch)) if (known.has(key)) mapEdit.animate(name, props, key, value);
  return true;
}
function jsx(type, props, key) {
  if (props?.['data-ms-timeline']) return runtime.jsx(TimelineElement, {type, original: props}, key);
  const name = typeof type === 'function' ? type.__msEditType : null;
  if (name && globalThis.__ms_propOverridesJSON && mapEdit.isMap(name)) {
    const copy = {...props};
    if (applyPreview(name, copy)) return runtime.jsx(type, copy, key);
  }
  return runtime.jsx(type, props, key);
}
module.exports = {...runtime, jsx, jsxs: jsx};
