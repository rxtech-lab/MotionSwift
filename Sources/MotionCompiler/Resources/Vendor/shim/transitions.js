// Clean-room transition scheduling against the documented public API.
const React = require('react');
const {Sequence, AbsoluteFill, useCurrentFrame, useVideoConfig} = require('./index');
const positive = (n, label) => { if (!Number.isInteger(n) || n <= 0) throw Error('ms/unsupported-transition: ' + label + ' must be a positive integer'); };
function linearTiming(options) {
  if (!options || Object.keys(options).some(k => !['durationInFrames','easing'].includes(k))) throw Error('ms/unsupported-transition: timing options');
  positive(options.durationInFrames, 'durationInFrames');
  if (options.easing !== undefined && typeof options.easing !== 'function') throw Error('ms/unsupported-transition: easing');
  return {__msTiming:true, duration:options.durationInFrames, easing:options.easing || (x=>x)};
}
const directions = ['from-left','from-right','from-top','from-bottom'];
function presentation(kind, options = {}) {
  const keys = kind === 'fade' ? ['shouldFadeOutExitingScene'] : ['direction'];
  if (Object.keys(options).some(k => !keys.includes(k))) throw Error('ms/unsupported-transition: ' + kind + ' options');
  if (kind !== 'fade' && !directions.includes(options.direction || 'from-left')) throw Error('ms/unsupported-transition: direction');
  if (kind === 'fade' && options.shouldFadeOutExitingScene !== undefined && typeof options.shouldFadeOutExitingScene !== 'boolean') throw Error('ms/unsupported-transition: fade options');
  return {__msPresentation:kind, ...options};
}
const fade = options => presentation('fade',options);
const slide = options => presentation('slide',options);
const wipe = options => presentation('wipe',options);
function SeriesSequence() { throw Error('TransitionSeries.Sequence must be inside TransitionSeries'); }
function SeriesTransition() { throw Error('TransitionSeries.Transition must be inside TransitionSeries'); }
function TransitionSeries({children, ...extra}) {
  if (Object.keys(extra).length) throw Error('ms/unsupported-transition: TransitionSeries props');
  const frame = useCurrentFrame(), {width,height} = useVideoConfig();
  const items = React.Children.toArray(children);
  const sequences = [], transitions = [];
  let start = 0;
  for (let index=0;index<items.length;index++) {
    const item=items[index];
    if (!React.isValidElement(item)) throw Error('ms/unsupported-transition: child');
    if (item.type === SeriesSequence) {
      const {durationInFrames,children:content,...unsupported}=item.props;
      positive(durationInFrames,'sequence duration');
      if (Object.keys(unsupported).length) throw Error('ms/unsupported-transition: sequence props');
      sequences.push({start,duration:durationInFrames,content,incoming:transitions.at(-1)?.after === sequences.length-1 ? transitions.at(-1) : null});
      start += durationInFrames;
    } else if (item.type === SeriesTransition) {
      if (!sequences.length || items[index-1]?.type !== SeriesSequence || items[index+1]?.type !== SeriesSequence) throw Error('ms/unsupported-transition: transitions must separate sequences');
      const {timing,presentation:effect,...unsupported}=item.props;
      if (Object.keys(unsupported).length || !timing?.__msTiming || !['fade','slide','wipe'].includes(effect?.__msPresentation)) throw Error('ms/unsupported-transition: use linearTiming and fade/slide/wipe');
      const duration=timing.duration;
      if (duration >= sequences.at(-1).duration || duration >= items[index+1].props.durationInFrames) throw Error('ms/unsupported-transition: transition must be shorter than both sequences');
      const transition={duration,effect,timing,start:start-duration,after:sequences.length-1};
      sequences.at(-1).outgoing=transition; transitions.push(transition); start-=duration;
    } else throw Error('ms/unsupported-transition: child');
  }
  for (const seq of sequences) if ((seq.incoming?.duration||0)+(seq.outgoing?.duration||0)>seq.duration) throw Error('ms/unsupported-transition: overlapping transitions');
  function effectStyle(transition, entering) {
    if (!transition || (entering && frame >= transition.start+transition.duration) || (!entering && frame < transition.start)) return {};
    const raw = Math.max(0,Math.min(1,(frame-transition.start)/transition.duration));
    const progress = transition.timing.easing(raw);
    if (!Number.isFinite(progress)) throw Error('ms/unsupported-transition: non-finite easing');
    const {effect} = transition;
    if (effect.__msPresentation === 'fade') return {opacity:entering ? progress : effect.shouldFadeOutExitingScene ? 1-progress : 1};
    const direction=effect.direction||'from-left', horizontal=direction==='from-left'||direction==='from-right';
    const sign=direction==='from-left'||direction==='from-top' ? -1 : 1;
    if (effect.__msPresentation === 'slide') {
      // Match the presentation's small overlap at the moving seam.
      const overlap = progress === 1 ? 0 : 0.0001;
      const shift = (entering ? 1-progress : -progress)*sign
        + (entering && sign > 0 ? overlap : !entering && sign < 0 ? -overlap : 0);
      return {transform:`translate${horizontal?'X':'Y'}(${shift*(horizontal?width:height)}px)`};
    }
    // Clip both scenes to complementary rectangles. Polygon coverage at the
    // fractional seam differs from leaving the outgoing scene unbounded.
    const edge = (sign < 0 ? progress : 1-progress)*100;
    const low = entering === (sign < 0) ? 0 : edge;
    const high = entering === (sign < 0) ? edge : 100;
    const points = horizontal ? [[low,0],[high,0],[high,100],[low,100]]
      : [[0,low],[100,low],[100,high],[0,high]];
    return {clipPath:`polygon(${points.map(([x,y])=>`${x}% ${y}%`).join(', ')})`};
  }
  return sequences.map((seq,index)=>React.createElement(Sequence,{key:index,from:seq.start,durationInFrames:seq.duration},
    React.createElement(AbsoluteFill,{style:{...effectStyle(seq.incoming,true),...effectStyle(seq.outgoing,false)}},seq.content)));
}
TransitionSeries.Sequence=SeriesSequence;
TransitionSeries.Transition=SeriesTransition;
module.exports={TransitionSeries,linearTiming,fade,slide,wipe};
