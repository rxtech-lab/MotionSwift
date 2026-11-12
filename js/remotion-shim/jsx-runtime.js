const runtime = require('react/jsx-runtime');
const React = require('react');
const {useCurrentFrame} = require('./index');

// A component boundary keeps hooks unconditional and adds no layout node.
function TimelineElement({type, original}) {
  const frame = useCurrentFrame();
  const {'data-ms-timeline': timeline, ...props} = original;
  if (frame < timeline.from || (timeline.duration !== null && frame >= timeline.from + timeline.duration)) return null;
  const style = {...props.style};
  for (const [key, points] of Object.entries(timeline.keyframes)) {
    const local = frame - timeline.from;
    const next = points.findIndex(p => p.frame > local);
    if (next === 0) style[key] = points[0].value;
    else if (next < 0) style[key] = points.at(-1).value;
    else {
      const a = points[next - 1], b = points[next];
      style[key] = a.easing === 'hold' ? a.value : a.value + (b.value - a.value) * (local - a.frame) / (b.frame - a.frame);
    }
  }
  return React.createElement(type, {...props, style});
}
function jsx(type, props, key) {
  if (props?.['data-ms-timeline']) return runtime.jsx(TimelineElement, {type, original: props}, key);
  return runtime.jsx(type, props, key);
}
module.exports = {...runtime, jsx, jsxs: jsx};
