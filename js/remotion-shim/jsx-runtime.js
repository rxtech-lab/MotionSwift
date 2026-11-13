const runtime = require('react/jsx-runtime');
const React = require('react');
const {useCurrentFrame} = require('./index');
const threeEdit = require('./three-edit');

// A component boundary keeps hooks unconditional and adds no layout node.
function TimelineElement({type, original}) {
  const frame = useCurrentFrame();
  const {'data-ms-timeline': timeline, ...props} = original;
  if (frame < timeline.from || (timeline.duration !== null && frame >= timeline.from + timeline.duration)) return null;
  const style = {...props.style};
  const three = threeEdit.isThree(type?.__msThreeCanvas === true ? 'ThreeCanvas' : type);
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
    if (three) threeEdit.animate(typeof type === 'string' ? type : 'ThreeCanvas', props, key, value);
    else style[key] = value;
  }
  return React.createElement(type, three ? props : {...props, style});
}
function jsx(type, props, key) {
  if (props?.['data-ms-timeline']) return runtime.jsx(TimelineElement, {type, original: props}, key);
  return runtime.jsx(type, props, key);
}
module.exports = {...runtime, jsx, jsxs: jsx};
