import React from 'react';
import {AbsoluteFill, Img, staticFile, useCurrentFrame} from 'remotion';
import {makeCircle, makeRect, makeEllipse} from '@remotion/shapes';
import {evolvePath, translatePath, scalePath} from '@remotion/paths';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {slide} from '@remotion/transitions/slide';
import {wipe} from '@remotion/transitions/wipe';

export const Gradients = () => <AbsoluteFill style={{backgroundColor:'#172030'}}>
  <div style={{position:'absolute',left:12,top:20,width:140,height:140,
    backgroundImage:'linear-gradient(45deg, #ff6644 0%, #2244ee 100%)',borderRadius:12}}/>
  <div style={{position:'absolute',left:168,top:20,width:140,height:140,
    backgroundImage:'radial-gradient(ellipse 70px 55px at 50% 50%, #ffffff 0%, #00aacc 60%, #003344 100%)'}}/>
</AbsoluteFill>;
export const Shadows = () => <AbsoluteFill style={{backgroundColor:'#dde4ee'}}>
  <div style={{position:'absolute',left:32,top:32,width:100,height:100,borderRadius:8,backgroundColor:'#ffffff',
    boxShadow:'4px 6px 8px 2px #00000080, -4px -3px 0px 1px #ee6644'}}/>
  <div style={{position:'absolute',left:180,top:32,width:100,height:100,backgroundColor:'#55aabb',
    boxShadow:'inset 4px 6px 8px 2px #00000080'}}/>
</AbsoluteFill>;
export const Filters = () => <AbsoluteFill style={{backgroundColor:'#182433'}}>
  {['blur(3px)','brightness(0.7) contrast(1.2)','grayscale(1)','saturate(0.3)','invert(0.6)','sepia(0.8)'].map((filter,index)=><div key={filter}
    style={{position:'absolute',left:12+(index%3)*104,top:12+Math.floor(index/3)*84,width:84,height:64,filter}}>
      <div style={{position:'absolute',width:42,height:64,backgroundColor:'#ee6633'}}/>
      <div style={{position:'absolute',left:42,width:42,height:64,backgroundColor:'#3366ee'}}/>
    </div>)}
</AbsoluteFill>;
const blends = ['multiply','screen','overlay','darken','lighten','color-dodge','color-burn','hard-light','soft-light',
  'difference','exclusion','hue','saturation','color','luminosity'] as const;
export const Blending = () => <AbsoluteFill style={{backgroundColor:'#336699'}}>
  {blends.map((mixBlendMode,index)=><div key={mixBlendMode} style={{position:'absolute',left:8+(index%5)*62,top:8+Math.floor(index/5)*56,
    width:48,height:40,backgroundColor:'#cc8844',mixBlendMode}}/>)}
</AbsoluteFill>;
export const ClipMask = () => <AbsoluteFill style={{backgroundColor:'#223344'}}>
  <div style={{position:'absolute',left:12,top:20,width:136,height:136,opacity:0.7,filter:'blur(2px)',
    backgroundImage:'linear-gradient(90deg, #ff4422, #4488ff)',clipPath:'polygon(0% 0%, 100% 20%, 80% 100%, 20% 80%)',
    maskImage:'linear-gradient(90deg, #00000000, #000000ff)'}}>
    <div style={{position:'absolute',left:40,top:30,width:90,height:90,backgroundColor:'#ffffff80'}}/>
  </div>
  <div style={{position:'absolute',left:174,top:30,width:120,height:120,backgroundColor:'#eeaa33',
    clipPath:'ellipse(50px 40px at 50% 50%)',filter:'brightness(0.8)'}}/>
</AbsoluteFill>;
export const Backdrop = () => <AbsoluteFill style={{backgroundColor:'#ffffff'}}>
  {Array.from({length:16},(_,index)=><div key={index} style={{position:'absolute',left:index*20,width:10,height:180,backgroundColor:'#335577'}}/>)}
  <div style={{position:'absolute',left:40,top:30,width:240,height:120,backdropFilter:'blur(4px)',backgroundColor:'#ffffff40'}}/>
</AbsoluteFill>;
export const Transform3D = () => <AbsoluteFill style={{backgroundColor:'#182433'}}>
  <div style={{position:'absolute',left:30,top:35,width:110,height:110,backgroundColor:'#ff7744',
    transform:'perspective(400px) rotateY(35deg) rotateX(15deg) translateZ(20px)'}}/>
  <div style={{position:'absolute',left:186,top:35,width:100,height:110,backgroundColor:'#44aacc',
    transform:'matrix3d(1,0,0,0,0,1,0,0,0,0,1,0,5,0,0,1) rotateX(35deg)'}}/>
</AbsoluteFill>;
export const InlineSVG = () => {
  const frame=useCurrentFrame();
  const circle=makeCircle({radius:20}), ellipse=makeEllipse({rx:30,ry:14});
  const rect=makeRect({width:70,height:40,cornerRadius:6});
  const path=translatePath(scalePath(rect.path,1.2,1),20,20);
  return <AbsoluteFill style={{backgroundColor:'#182433'}}>
    <svg width={300} height={160} viewBox="0 0 300 160" style={{position:'absolute',left:10,top:10}}>
      <defs>
        <linearGradient id="paint"><stop offset="0%" stopColor="#ff7744"/><stop offset="100%" stopColor="#4488ff"/></linearGradient>
        <clipPath id="cut"><circle cx={150} cy={80} r={65}/></clipPath>
        <mask id="mask"><rect width={300} height={160} fill="#ffffff"/><circle cx={240} cy={50} r={10} fill="#000000"/></mask>
      </defs>
      <path d={path} fill="url(#paint)"/>
      <g transform={`translate(${110+frame} 20)`}><path d={circle.path} fill="#66ccaa"/></g>
      <path d={translatePath(ellipse.path,200,28)} fill="#eeaaff" mask="url(#mask)"/>
      <path d="M20 100 L100 140 L180 90 L280 140" fill="none" stroke="#ffffff" strokeWidth={4} {...evolvePath((frame+10)/40,'M20 100 L100 140 L180 90 L280 140')}/>
      <g clipPath="url(#cut)"><rect x={130} y={70} width={80} height={65} fill="#ffcc44"/></g>
      <polyline points="15,80 45,65 75,80" fill="none" stroke="#ffcc44" strokeWidth={2}/>
      <polygon points="240,90 270,140 210,140" fill="#66ccaa"/>
      <line x1={10} y1={155} x2={290} y2={155} stroke="#ffffff"/>
    </svg>
  </AbsoluteFill>;
};
export const ExternalSVG = () => <AbsoluteFill style={{backgroundColor:'#182433'}}><Img src={staticFile('effects.svg')} style={{width:320,height:180}}/></AbsoluteFill>;
function TransitionDemo({kind}: {kind:'fade'|'slide'|'wipe'}) {
  const presentation=kind==='fade'?fade():kind==='slide'?slide({direction:'from-left'}):wipe({direction:'from-left'});
  return <TransitionSeries>
    <TransitionSeries.Sequence durationInFrames={22}><AbsoluteFill style={{backgroundColor:'#ee6633'}}/></TransitionSeries.Sequence>
    <TransitionSeries.Transition timing={linearTiming({durationInFrames:12})} presentation={presentation}/>
    <TransitionSeries.Sequence durationInFrames={20}><AbsoluteFill style={{backgroundColor:'#3366dd'}}/></TransitionSeries.Sequence>
  </TransitionSeries>;
}
export const FadeTransition=()=> <TransitionDemo kind="fade"/>;
export const SlideTransition=()=> <TransitionDemo kind="slide"/>;
export const WipeTransition=()=> <TransitionDemo kind="wipe"/>;
