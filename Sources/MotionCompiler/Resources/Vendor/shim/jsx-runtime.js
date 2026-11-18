const runtime = require('react/jsx-runtime');
const React = require('react');
const {useCurrentFrame} = require('./index');
const threeEdit = require('./three-edit');
const mapEdit = require('./map-edit');

const HTML_TAGS = new Set([
  'div', 'span', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'section', 'article', 'header', 'footer',
  'main', 'aside', 'nav', 'ul', 'ol', 'li', 'a', 'button', 'label', 'strong', 'em', 'b', 'i', 'small',
  'code', 'pre', 'blockquote', 'figure', 'figcaption', 'img', 'svg', 'video', 'canvas',
]);

const isCustomComponent = type =>
  typeof type === 'function' && !(type.prototype && type.prototype.isReactComponent) &&
  !type.__msBuiltin && !type.__msEditType && !type.__msThreeCanvas;

const wrappedComponents = new WeakMap();
function wrapComponent(type) {
  let wrapped = wrappedComponents.get(type);
  if (!wrapped) {
    wrapped = function MotionComponentInstance(props) {
      const src = props?.['data-ms-src'];
      const out = type(props);
      if (!src || !out || typeof out !== 'object' || typeof out.type !== 'string' || !HTML_TAGS.has(out.type)) return out;
      if (Object.hasOwn(out.props ?? {}, 'data-ms-src') && out.props['data-ms-src'] === undefined) return out;
      const hasUserProps = Object.keys(props).some(k => !k.startsWith('data-ms-'));
      if (!hasUserProps) return out;
      const nextProps = {'data-ms-src': src};
      if (props.style && typeof props.style === 'object') {
        nextProps.style = {...(out.props?.style ?? {}), ...props.style};
      }
      return React.cloneElement(out, nextProps);
    };
    wrappedComponents.set(type, wrapped);
  }
  return wrapped;
}

// A component boundary keeps hooks unconditional and adds no layout node.
function TimelineElement({type, original}) {
  const frame = useCurrentFrame();
  const {'data-ms-timeline': timeline, ...props} = original;
  if (frame < timeline.from || (timeline.duration !== null && frame >= timeline.from + timeline.duration)) return null;
  const style = {...props.style};
  // Prop domains (3D, maps) keyframe component props; custom components keyframe matching props or CSS styles.
  const name = type?.__msThreeCanvas === true ? 'ThreeCanvas' : typeof type === 'string' ? type : type?.__msEditType;
  const three = threeEdit.isThree(name);
  const map = !three && mapEdit.isMap(name);
  const custom = !three && !map && isCustomComponent(type) && props['data-ms-editable'] === undefined;
  if (type?.__msThreeCanvas === true && Object.keys(timeline.keyframes).some(key => key.startsWith('camera')))
    props.__msEditorCamera = true;
  let wroteStyle = false;
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
    else if (custom && Object.hasOwn(props, key) && key !== 'style') props[key] = value;
    else { style[key] = value; wroteStyle = true; }
  }
  if (map) applyPreview(name, props);
  const target = custom && props['data-ms-src'] ? wrapComponent(type) : type;
  const nextProps = three || map ? props : (props.style !== undefined || wroteStyle || !custom ? {...props, style} : props);
  return React.createElement(target, nextProps);
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
  if (props?.['data-ms-src'] && props['data-ms-editable'] === undefined && isCustomComponent(type)) {
    return runtime.jsx(wrapComponent(type), props, key);
  }
  return runtime.jsx(type, props, key);
}
module.exports = {...runtime, jsx, jsxs: jsx};
