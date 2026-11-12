import React from 'react';
import {AbsoluteFill} from 'remotion';

// Flex children: drag edits transform translate() so siblings keep their places.
export const Row = () => <AbsoluteFill style={{backgroundColor: '#0b132b', justifyContent: 'center', alignItems: 'center'}}>
  <div style={{display: 'flex', flexDirection: 'row', gap: 24}}>
    <div style={{width: 120, height: 120, borderRadius: 16, backgroundColor: '#5bc0be'}} />
    <div style={{width: 120, height: 120, borderRadius: 16, backgroundColor: '#fca311', transform: 'rotate(8deg)'}} />
    <div style={{width: 120, height: 120, borderRadius: 16, backgroundColor: '#e5e5e5'}} />
  </div>
</AbsoluteFill>;
