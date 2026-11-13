import React from 'react';
import {AbsoluteFill, Easing, Series, Sequence, spring, random, useCurrentFrame, useVideoConfig} from 'remotion';

export const BorderOrder = () => <AbsoluteFill style={{backgroundColor: '#14213d', color: 'orange'}}>
  <div style={{position:'absolute',left:20,top:20,width:100,height:80,boxSizing:'border-box',border:'6px solid currentColor',backgroundColor:'hsl(210, 50%, 40%)',zIndex:2}} />
  <div style={{position:'absolute',left:90,top:50,width:100,height:80,border:'4px solid rgba(255, 255, 255, 0.5)',borderTop:'8px solid red',borderLeftColor:'lime',backgroundColor:'rebeccapurple',zIndex:1}} />
  <div style={{position:'absolute',left:210,top:20,width:70,height:70,boxSizing:'border-box',border:'4px solid white',borderRadius:14,backgroundColor:'rgb(20, 90, 120)',pointerEvents:'none',userSelect:'none'}} />
</AbsoluteFill>;
export const FlexOrigin = () => <AbsoluteFill style={{backgroundColor:'#14213d'}}>
  <div style={{display:'inline-flex',flexDirection:'row',width:240,height:50,position:'absolute',left:20,top:20,gap:10}}>
    <div style={{display:'inline-block',flex:1,backgroundColor:'orange'}} />
    <div style={{flex:'2 1 0%',border:'3px solid white',boxSizing:'border-box',backgroundColor:'teal'}} />
    <div style={{display:'inline',flex:'none',width:40,backgroundColor:'lime'}} />
  </div>
  <div style={{position:'absolute',left:70,top:110,width:100,height:40,backgroundColor:'yellow',transformOrigin:'left top',transform:'scale(0.5)'}} />
  <div style={{position:'absolute',left:180,top:110,width:80,height:40,backgroundColor:'#ff00ff',transformOrigin:'25% 10px',transform:'scale(0.5)'}} />
</AbsoluteFill>;
const LocalBox = ({color}:{color:string}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const progress = spring({frame,fps,durationInFrames:8,delay:2,reverse:true,config:{overshootClamping:true}});
  return <div style={{position:'absolute',left:20+frame*3,top:20,width:80,height:60,backgroundColor:color,transform:`scale(${progress})`,transformOrigin:'0% 0%',opacity:Easing.bezier(0.42,0,1,1)(Math.min(1,frame/4))}} />;
};
export const SeriesTiming = () => <AbsoluteFill style={{backgroundColor:'#14213d'}}>
  <Sequence from={2} durationInFrames={26} layout="none">
    <Series>
      <Series.Sequence durationInFrames={10}><LocalBox color="orange" /></Series.Sequence>
      <Series.Sequence durationInFrames={12} offset={-3}>
        <Sequence from={2} layout="none"><LocalBox color="cyan" /></Sequence>
      </Series.Sequence>
      <Series.Sequence durationInFrames={5} offset={2}><div style={{width:40+random('box')*30,height:40,backgroundColor:'red'}} /></Series.Sequence>
    </Series>
  </Sequence>
</AbsoluteFill>;

export const NestedOrder = () => <AbsoluteFill style={{backgroundColor:'#14213d'}}>
  <div style={{position:'absolute',left:20,top:20,width:120,height:100}}>
    <div style={{position:'absolute',inset:0,zIndex:10,backgroundColor:'orange'}} />
  </div>
  <div style={{position:'absolute',left:70,top:60,width:120,height:100,zIndex:2,backgroundColor:'cyan'}} />
  <div style={{position:'absolute',left:200,top:20,width:80,height:80,zIndex:1}}>
    <div style={{position:'absolute',inset:0,zIndex:10,backgroundColor:'orange'}} />
  </div>
  <div style={{position:'absolute',left:230,top:60,width:60,height:80,zIndex:2,backgroundColor:'cyan'}} />
</AbsoluteFill>;
