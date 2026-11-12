import {AbsoluteFill, Sequence, spring, useCurrentFrame} from 'remotion';
export const Valid = () => <AbsoluteFill style={{display: 'flex', backgroundColor: '#14213d'}}>
  <Sequence from={3}><div style={{opacity: spring({frame: useCurrentFrame(),fps:30,config:{overshootClamping:true}})}} /></Sequence>
</AbsoluteFill>;
