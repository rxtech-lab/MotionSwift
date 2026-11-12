import React from 'react';
import {AbsoluteFill} from 'remotion';

// Absolutely positioned cards: drag edits left/top, corner handles edit width/height.
export const Cards = () => <AbsoluteFill style={{backgroundColor: '#14213d'}}>
  <div style={{position: 'absolute', left: 48, top: 48, width: 220, height: 140, borderRadius: 24, backgroundColor: '#fca311'}} />
  <div style={{position: 'absolute', left: 320, top: 120, width: 180, height: 180, borderRadius: 90, backgroundColor: '#e5e5e5'}} />
  <div style={{position: 'absolute', right: 40, bottom: 32, width: 120, height: 64, borderRadius: 12, backgroundColor: '#ff0000'}} />
</AbsoluteFill>;
