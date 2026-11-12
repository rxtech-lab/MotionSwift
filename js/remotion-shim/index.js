const React = require('react');
const Frame = React.createContext(0);
const Config = React.createContext(null);
const useCurrentFrame = () => React.useContext(Frame);
const useVideoConfig = () => React.useContext(Config);
const AbsoluteFill = ({style, children, ...props}) => React.createElement('div', {
  ...props, style: {position: 'absolute', left: 0, top: 0, right: 0, bottom: 0,
    width: '100%', height: '100%', display: 'flex', flexDirection: 'column', ...style}
}, children);
function Composition(props) { return React.createElement('ms-composition', props); }
function registerRoot(root) { globalThis.__ms_root = root; }
function interpolate(value, input, output, options = {}) {
  if (input.length !== output.length || input.length < 2 || input.some((x,i) => i && x <= input[i-1])) {
    throw Error('interpolate requires equal, strictly increasing input/output ranges');
  }
  const extrapolate = value < input[0] ? options.extrapolateLeft : options.extrapolateRight;
  if ((value < input[0] || value > input.at(-1)) && extrapolate === 'wrap') {
    const span = input.at(-1) - input[0];
    value = input[0] + ((value - input[0]) % span + span) % span;
  }
  let index = Math.max(0, input.findIndex((x,i) => i < input.length-1 && value <= input[i+1]));
  if (value > input[input.length-1]) index = input.length - 2;
  let t = (value-input[index])/(input[index+1]-input[index]);
  const mode = t < 0 ? options.extrapolateLeft : options.extrapolateRight;
  if ((t < 0 || t > 1) && mode === 'identity') return value;
  if (mode === 'clamp') t = Math.min(1, Math.max(0,t));
  return output[index]+(output[index+1]-output[index])*(options.easing || (x=>x))(t);
}
function spring({frame, fps, config = {}, from = 0, to = 1}) {
  const {mass = 1, stiffness = 100, damping = 10, overshootClamping = false} = config;
  if (!(mass > 0 && stiffness > 0 && damping > 0 && fps > 0)) throw Error('Invalid spring config');
  const positive = Math.max(0,frame);
  const time = Math.floor(positive)*Math.min(1/fps,0.064)+Math.min((positive%1)/fps,0.064);
  const omega = Math.sqrt(stiffness/mass), zeta = damping/(2*Math.sqrt(stiffness*mass));
  let displacement;
  if (zeta < 1) {
    const damped = omega*Math.sqrt(1-zeta*zeta);
    displacement = Math.exp(-zeta*omega*time)*(Math.cos(damped*time)+zeta*omega/damped*Math.sin(damped*time));
  } else {
    // Remotion uses its critical-damping branch for damping ratios at or above one.
    displacement = Math.exp(-omega*time)*(1+omega*time);
  }
  const value = 1-displacement;
  return from+(to-from)*(overshootClamping ? Math.min(1,value) : value);
}
function Sequence({from = 0, durationInFrames = Infinity, children, layout = 'absolute-fill', style}) {
  const frame = useCurrentFrame();
  if (frame < from || frame >= from + durationInFrames) return null;
  const content = React.createElement(Frame.Provider, {value: frame-from}, children);
  return layout === 'none' ? content : React.createElement(AbsoluteFill, {style}, content);
}
function Freeze({frame, children}) { return React.createElement(Frame.Provider, {value: frame}, children); }
function Loop({durationInFrames, children, times = Infinity}) {
  const frame = useCurrentFrame();
  if (!(durationInFrames > 0)) throw Error('Loop duration must be positive');
  return frame >= durationInFrames*times ? null : React.createElement(Freeze, {frame: frame%durationInFrames}, children);
}
const Easing = {
  linear: x => x, quad: x => x*x, cubic: x => x*x*x,
  sin: x => 1-Math.cos(x*Math.PI/2), exp: x => Math.pow(2,10*(x-1)),
  circle: x => 1-Math.sqrt(1-x*x),
  in: easing => easing, out: easing => x => 1-easing(1-x),
  inOut: easing => x => x < 0.5 ? easing(x*2)/2 : 1-easing((1-x)*2)/2,
};
module.exports = {AbsoluteFill, Composition, Still: props => Composition({...props, durationInFrames: 1, fps: 1}),
  Folder: ({children}) => children, registerRoot, useCurrentFrame, useVideoConfig, interpolate, spring,
  Sequence, Freeze, Loop, Easing, __Frame: Frame, __Config: Config};
