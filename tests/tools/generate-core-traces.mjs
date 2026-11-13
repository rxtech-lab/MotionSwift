// Reference values come exclusively from the installed, pinned Remotion package.
import fs from 'node:fs';
import {spring,measureSpring,Easing,random} from 'remotion';
const samples=Array.from({length:30},(_,frame)=>({frame,values:[
  ...[10,30].flatMap(fps=>[5,10,35].map(damping=>spring({frame,fps,config:{damping}}))),
  spring({frame,fps:30,durationInFrames:12,delay:3,reverse:true}),
  spring({frame:frame+0.25,fps:10,durationInFrames:18,config:{damping:35},from:3,to:-2}),
  measureSpring({fps:30,config:{damping:5},threshold:0.001}),
  Easing.bezier(0.16,1,0.3,1)(frame/29), Easing.back(2)(frame/29), Easing.ease(frame/29),random('hello'),random(frame),
]}));
fs.writeFileSync(new URL('../compiler-fixtures/motion/expected.json',import.meta.url),JSON.stringify(samples,null,2)+'\n');
