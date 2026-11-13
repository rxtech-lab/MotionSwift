const React = require('react');
const Frame = React.createContext(0);
const Config = React.createContext(null);
const MediaEnabled = React.createContext(true);
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
function springValue({frame, fps, config = {}, from = 0, to = 1}) {
  const {mass = 1, stiffness = 100, damping = 10, overshootClamping = false} = config;
  if (![mass, stiffness, damping, fps].every(Number.isFinite) || !(mass > 0 && stiffness > 0 && damping > 0 && fps > 0)) throw Error('Invalid spring config');
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
// Measure the final threshold crossing, allowing a full second for later oscillations.
const springDurations = new Map();
function measureSpring({fps, config = {}, threshold = 0.005}) {
  if (!(Number.isFinite(fps) && fps > 0 && threshold > 0 && threshold < 1)) throw Error('Invalid spring fps/threshold');
  const key = JSON.stringify([fps, config.mass ?? 1, config.stiffness ?? 100, config.damping ?? 10, threshold]);
  if (springDurations.has(key)) return springDurations.get(key);
  let lastOutside = 0;
  for (let frame = 0; frame < 1000000; frame++) {
    if (Math.abs(1-springValue({frame, fps, config: {...config, overshootClamping: false}})) > threshold) lastOutside = frame;
    if (frame-lastOutside >= fps) {
      springDurations.set(key, lastOutside+1);
      return lastOutside+1;
    }
  }
  throw Error('Spring does not settle within the supported measurement limit');
}
function spring({frame, fps, config = {}, from = 0, to = 1, durationInFrames, durationRestThreshold, delay = 0, reverse = false}) {
  if (![frame, fps, from, to, delay].every(Number.isFinite) || fps <= 0 ||
      (durationInFrames !== undefined && !(Number.isFinite(durationInFrames) && durationInFrames > 0))) throw Error('Invalid spring timing');
  const natural = reverse || durationInFrames !== undefined ? measureSpring({fps, config, threshold: durationRestThreshold}) : 0;
  const local = reverse ? (durationInFrames ?? natural)-frame+delay : frame-delay;
  if (durationInFrames !== undefined && local > durationInFrames) return to;
  return springValue({frame: durationInFrames === undefined ? local : local*natural/durationInFrames, fps, config, from, to});
}
function SeriesSequence() { throw Error('Series.Sequence must be a direct child of Series'); }
function Series({children, layout = 'none', ...props}) {
  let cursor = 0;
  const items = React.Children.toArray(children).map((child, index, all) => {
    if (!React.isValidElement(child) || child.type !== SeriesSequence) throw Error('Series only accepts Series.Sequence children');
    const {durationInFrames, offset = 0, ...rest} = child.props;
    if (!(durationInFrames > 0) || (Number.isFinite(durationInFrames) && !Number.isInteger(durationInFrames)) || (!Number.isFinite(durationInFrames) && index !== all.length-1) ||
        !Number.isInteger(offset)) throw Error('Invalid Series duration/offset');
    const from = cursor+offset;
    cursor = from+durationInFrames;
    return React.createElement(Sequence, {...rest, key: child.key ?? index, from, durationInFrames});
  });
  return React.createElement(Sequence, {...props, layout}, items);
}
Series.Sequence = SeriesSequence;
function Sequence({from = 0, durationInFrames = Infinity, children, layout = 'absolute-fill', style}) {
  const frame = useCurrentFrame();
  const config = useVideoConfig();
  if (!Number.isInteger(from) || !(durationInFrames > 0) || (Number.isFinite(durationInFrames) && !Number.isInteger(durationInFrames))) throw Error('Invalid Sequence timing');
  if (layout === 'none' && style) throw Error('Sequence style requires absolute-fill layout');
  if (frame < from || frame >= from + durationInFrames) return null;
  const localConfig = config ? {...config, durationInFrames: Math.min(durationInFrames, config.durationInFrames-from)} : config;
  const content = React.createElement(Config.Provider, {value: localConfig}, React.createElement(Frame.Provider, {value: frame-from}, children));
  return layout === 'none' ? content : React.createElement(AbsoluteFill, {style}, content);
}
function Freeze({frame, children}) { return React.createElement(MediaEnabled.Provider, {value: false}, React.createElement(Frame.Provider, {value: frame}, children)); }
function Loop({durationInFrames, children, times = Infinity}) {
  const frame = useCurrentFrame();
  if (!(durationInFrames > 0)) throw Error('Loop duration must be positive');
  return frame >= durationInFrames*times ? null : React.createElement(Frame.Provider, {value: frame%durationInFrames}, children);
}
// Media time is derived from the nearest Sequence/Freeze/Loop frame context.
function media(type, {src, style, trimBefore, startFrom, trimAfter, endAt,
  durationInFrames, playbackRate = 1, volume = 1, muted = false, ...props}) {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const enabled = React.useContext(MediaEnabled);
  const start = trimBefore ?? startFrom ?? 0;
  const end = durationInFrames == null ? (trimAfter ?? endAt ?? Infinity) : start + durationInFrames;
  const gain = typeof volume === 'function' ? volume(frame) : volume;
  if (typeof src !== 'string' || !src || !Number.isFinite(start) || start < 0 ||
      !Number.isFinite(playbackRate) || playbackRate <= 0 || !Number.isFinite(gain) || gain < 0 || gain > 1 ||
      !(end > start)) throw Error('Invalid native media source, trim, rate or volume');
  const sourceFrame = start + frame * playbackRate;
  if (sourceFrame >= end) return null;
  return React.createElement(type, {...props, src,
    style: type === 'ms-audio' ? {display: 'none'} : {objectFit: 'contain', ...style},
    'data-ms-media': {time: sourceFrame / fps, playbackRate, volume: muted || !enabled ? 0 : gain}});
}
const Audio = props => media('ms-audio', props);
const OffthreadVideo = props => media('ms-video', props);
// Files in the project's public/ folder. Native renderers resolve `static:` against that folder.
function staticFile(name) {
  if (typeof name !== 'string' || !name || /^[a-z]+:/i.test(name) || name.split('/').includes('..')) {
    throw Error('staticFile() requires a relative path inside public/: ' + String(name));
  }
  return 'static:' + name.replace(/^\/+/, '').split('/').map(encodeURIComponent).join('/');
}
const Img = props => React.createElement('img', {...props, style: {objectFit: 'contain', ...props.style}});
// Standard cubic Bezier inversion, bounded bisection avoids engine-dependent convergence.
function bezier(x1, y1, x2, y2) {
  if (![x1,y1,x2,y2].every(Number.isFinite) || x1 < 0 || x1 > 1 || x2 < 0 || x2 > 1) throw Error('Invalid Bezier control points');
  const curve = (t, a, b) => 3*(1-t)*(1-t)*t*a+3*(1-t)*t*t*b+t*t*t;
  return x => {
    if (x === 0 || x === 1) return x;
    if (x < 0) return x*(x1 > 0 ? y1/x1 : x2 > 0 ? y2/x2 : 0);
    if (x > 1) return 1+(x-1)*(x2 < 1 ? (1-y2)/(1-x2) : x1 < 1 ? (1-y1)/(1-x1) : 0);
    let low = 0, high = 1;
    for (let i = 0; i < 48; i++) { const mid = (low+high)/2; if (curve(mid,x1,x2) < x) low = mid; else high = mid; }
    return curve((low+high)/2,y1,y2);
  };
}
function random(seed) {
  if (typeof seed !== 'string' && (typeof seed !== 'number' || !Number.isFinite(seed))) throw Error('random requires a finite number or string seed');
  let state = 0;
  if (typeof seed === 'string') for (let i = 0; i < seed.length; i++) state = (31*state+seed.charCodeAt(i))|0;
  else state = seed*10000000000;
  // Mulberry32: public-domain integer PRNG, one sample per seed (no mutable global state).
  let bits = state+0x6D2B79F5;
  bits = Math.imul(bits ^ bits >>> 15, bits | 1);
  bits ^= bits+Math.imul(bits ^ bits >>> 7, bits | 61);
  return ((bits ^ bits >>> 14) >>> 0)/4294967296;
}
const Easing = {
  bezier, ease: bezier(0.42, 0, 1, 1),
  step0: x => x > 0 ? 1 : 0, step1: x => x >= 1 ? 1 : 0,
  poly: n => x => Math.pow(x,n),
  back: (s = 1.70158) => x => x*x*((s+1)*x-s),
  elastic: (b = 1) => x => 1-Math.pow(Math.cos(x*Math.PI/2),3)*Math.cos(x*b*Math.PI),
  bounce: x => { if (x < 1/2.75) return 7.5625*x*x; if (x < 2/2.75) return 7.5625*(x-1.5/2.75)**2+0.75; if (x < 2.5/2.75) return 7.5625*(x-2.25/2.75)**2+0.9375; return 7.5625*(x-2.625/2.75)**2+0.984375; },
  linear: x => x, quad: x => x*x, cubic: x => x*x*x,
  sin: x => 1-Math.cos(x*Math.PI/2), exp: x => Math.pow(2,10*(x-1)),
  circle: x => 1-Math.sqrt(1-x*x),
  in: easing => easing, out: easing => x => 1-easing(1-x),
  inOut: easing => x => x < 0.5 ? easing(x*2)/2 : 1-easing((1-x)*2)/2,
};
module.exports = {AbsoluteFill, Composition, Still: props => Composition({...props, durationInFrames: 1, fps: 1}),
  Folder: ({children}) => children, registerRoot, useCurrentFrame, useVideoConfig, interpolate, spring,
  Sequence, Series, Freeze, Loop, measureSpring, random, Audio, OffthreadVideo, Video: OffthreadVideo, Img, Easing, staticFile, __Frame: Frame, __Config: Config};

// The lifecycle belongs to the worker, rather than the module cache.
module.exports.delayRender = (label, options) => globalThis.__ms_delayRender(label, options);
module.exports.continueRender = handle => globalThis.__ms_continueRender(handle);
module.exports.cancelRender = error => globalThis.__ms_cancelRender(error);

module.exports.__svgHost = require("./svg-host").host;

const CSS_NAMES = {"aliceblue":15792383,"antiquewhite":16444375,"aqua":65535,"aquamarine":8388564,"azure":15794175,"beige":16119260,"bisque":16770244,"black":0,"blanchedalmond":16772045,"blue":255,"blueviolet":9055202,"brown":10824234,"burlywood":14596231,"cadetblue":6266528,"chartreuse":8388352,"chocolate":13789470,"coral":16744272,"cornflowerblue":6591981,"cornsilk":16775388,"crimson":14423100,"cyan":65535,"darkblue":139,"darkcyan":35723,"darkgoldenrod":12092939,"darkgray":11119017,"darkgreen":25600,"darkgrey":11119017,"darkkhaki":12433259,"darkmagenta":9109643,"darkolivegreen":5597999,"darkorange":16747520,"darkorchid":10040012,"darkred":9109504,"darksalmon":15308410,"darkseagreen":9419919,"darkslateblue":4734347,"darkslategray":3100495,"darkslategrey":3100495,"darkturquoise":52945,"darkviolet":9699539,"deeppink":16716947,"deepskyblue":49151,"dimgray":6908265,"dimgrey":6908265,"dodgerblue":2003199,"firebrick":11674146,"floralwhite":16775920,"forestgreen":2263842,"fuchsia":16711935,"gainsboro":14474460,"ghostwhite":16316671,"gold":16766720,"goldenrod":14329120,"gray":8421504,"green":32768,"greenyellow":11403055,"grey":8421504,"honeydew":15794160,"hotpink":16738740,"indianred":13458524,"indigo":4915330,"ivory":16777200,"khaki":15787660,"lavender":15132410,"lavenderblush":16773365,"lawngreen":8190976,"lemonchiffon":16775885,"lightblue":11393254,"lightcoral":15761536,"lightcyan":14745599,"lightgoldenrodyellow":16448210,"lightgray":13882323,"lightgreen":9498256,"lightgrey":13882323,"lightpink":16758465,"lightsalmon":16752762,"lightseagreen":2142890,"lightskyblue":8900346,"lightslategray":7833753,"lightslategrey":7833753,"lightsteelblue":11584734,"lightyellow":16777184,"lime":65280,"limegreen":3329330,"linen":16445670,"magenta":16711935,"maroon":8388608,"mediumaquamarine":6737322,"mediumblue":205,"mediumorchid":12211667,"mediumpurple":9662683,"mediumseagreen":3978097,"mediumslateblue":8087790,"mediumspringgreen":64154,"mediumturquoise":4772300,"mediumvioletred":13047173,"midnightblue":1644912,"mintcream":16121850,"mistyrose":16770273,"moccasin":16770229,"navajowhite":16768685,"navy":128,"oldlace":16643558,"olive":8421376,"olivedrab":7048739,"orange":16753920,"orangered":16729344,"orchid":14315734,"palegoldenrod":15657130,"palegreen":10025880,"paleturquoise":11529966,"palevioletred":14381203,"papayawhip":16773077,"peachpuff":16767673,"peru":13468991,"pink":16761035,"plum":14524637,"powderblue":11591910,"purple":8388736,"rebeccapurple":6697881,"red":16711680,"rosybrown":12357519,"royalblue":4286945,"saddlebrown":9127187,"salmon":16416882,"sandybrown":16032864,"seagreen":3050327,"seashell":16774638,"sienna":10506797,"silver":12632256,"skyblue":8900331,"slateblue":6970061,"slategray":7372944,"slategrey":7372944,"snow":16775930,"springgreen":65407,"steelblue":4620980,"tan":13808780,"teal":32896,"thistle":14204888,"tomato":16737095,"turquoise":4251856,"violet":15631086,"wheat":16113331,"white":16777215,"whitesmoke":16119285,"yellow":16776960,"yellowgreen":10145074};

function colorChannels(input) {
  const value = input.trim().toLowerCase();
  if (value === 'transparent') return [0,0,0,0];
  if (CSS_NAMES[value] !== undefined) { const c = CSS_NAMES[value]; return [c>>>16,(c>>>8)&255,c&255,1]; }
  if (/^#[a-f0-9]{3,8}$/i.test(value)) {
    let hex = value.slice(1);
    if (hex.length === 3 || hex.length === 4) hex = [...hex].map(x=>x+x).join('');
    if (hex.length === 6 || hex.length === 8) return [0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)).concat(hex.length === 8 ? parseInt(hex.slice(6),16)/255 : 1);
  }
  const match = /^(rgba?|hsla?)\((.*)\)$/.exec(value);
  if (match) {
    const tokens = match[2].split(/[,/\s]+/).filter(Boolean);
    const number = (text, scale) => text.endsWith('%') ? parseFloat(text)*scale/100 : Number(text);
    if (tokens.length === 3 || tokens.length === 4) {
      const alpha = tokens.length === 4 ? number(tokens[3],1) : 1;
      let rgb;
      if (match[1].startsWith('rgb')) rgb = tokens.slice(0,3).map(x=>number(x,255));
      else {
        if (!tokens[1].endsWith('%') || !tokens[2].endsWith('%')) throw Error('HSL saturation/lightness require percentages');
        const h = Number(tokens[0].replace(/deg$/, ''));
        const sat = Math.min(1,Math.max(0,number(tokens[1],1))), light = Math.min(1,Math.max(0,number(tokens[2],1)));
        const a = sat*Math.min(light,1-light);
        rgb = [0,8,4].map(n=>{const k = ((n+h/30)%12+12)%12;return 255*(light-a*Math.max(-1,Math.min(k-3,9-k,1)));});
      }
      if ([...rgb,alpha].every(Number.isFinite)) return rgb.map(x=>Math.round(Math.min(255,Math.max(0,x)))).concat(Math.round(255*Math.min(1,Math.max(0,alpha)))/255);
    }
  }
  throw Error('Unsupported color: '+input);
}
function interpolateColors(value, input, output) {
  const colors = output.map(colorChannels);
  const channels = [0,1,2,3].map(i=>interpolate(value,input,colors.map(c=>c[i]),{extrapolateLeft:'clamp',extrapolateRight:'clamp'}));
  return `rgba(${Math.round(channels[0])}, ${Math.round(channels[1])}, ${Math.round(channels[2])}, ${Math.round(channels[3]*1000)/1000})`;
}
module.exports.interpolateColors = interpolateColors;
module.exports.getRemotionEnvironment = () => ({isRendering: true, isStudio: false, isPlayer: false, isClientSideRendering: false});
module.exports.useRemotionEnvironment = module.exports.getRemotionEnvironment;
