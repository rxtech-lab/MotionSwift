import React from 'react';
import {AbsoluteFill, Composition, registerRoot, useCurrentFrame} from 'remotion';

// Five seconds, 150 frames. All movement uses whole cycles for a seamless loop.
const ink = '#101827';
const cream = '#f4efdf';
const orange = '#ff7849';
const lime = '#d6f45b';
const glyphs: Record<string, string[]> = {
  M: ['10001','11011','10101','10101','10001','10001','10001'],
  O: ['01110','10001','10001','10001','10001','10001','01110'],
  T: ['11111','00100','00100','00100','00100','00100','00100'],
  I: ['11111','00100','00100','00100','00100','00100','11111'],
  N: ['10001','11001','11001','10101','10011','10011','10001'],
  S: ['01111','10000','10000','01110','00001','00001','11110'],
  W: ['10001','10001','10001','10101','10101','11011','10001'],
  F: ['11111','10000','10000','11110','10000','10000','10000'],
  A: ['01110','10001','10001','11111','10001','10001','10001'],
  V: ['10001','10001','10001','10001','10001','01010','00100'],
  E: ['11111','10000','10000','11110','10000','10000','11111'],
  K: ['10001','10010','10100','11000','10100','10010','10001'],
  '+': ['00000','00100','00100','11111','00100','00100','00000'],
  ' ': ['00000','00000','00000','00000','00000','00000','00000'],
};
const svg = (body: string, width: number, height: number) =>
  `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${body}</svg>`)}`;
const letter = (char: string, color: string) => svg(
  glyphs[char].flatMap((row, y) => row.split('').map((v, x) =>
    v === '1' ? `<rect x="${x}" y="${y}" width="1" height="1" fill="${color}"/>` : '')).join(''), 5, 7);
const ring = svg('<circle cx="170" cy="170" r="159" fill="none" stroke="#394357" stroke-width="1"/><circle cx="170" cy="170" r="112" fill="none" stroke="#394357" stroke-width="1"/>', 340, 340);

const Word = ({text, x, y, unit, color, phase = 0}: {
  text: string; x: number; y: number; unit: number; color: string; phase?: number;
}) => <>{text.split('').map((char, i) => <img key={i} src={letter(char, color)} style={{
  position: 'absolute', left: x + i * unit * 6, top: y + Math.sin(phase + i * 0.55) * (unit > 5 ? 7 : 0),
  width: unit * 5, height: unit * 7, objectFit: 'contain',
}} />)}</>;

export const ReadmeMotion = () => {
  const frame = useCurrentFrame();
  const t = frame / 150 * Math.PI * 2;
  return <AbsoluteFill style={{backgroundColor: ink, overflow: 'hidden'}}>
    {/* Moving background rules and small navigation marks. */}
    {Array.from({length: 13}, (_, i) => <div key={`grid-${i}`} style={{
      position: 'absolute', left: i * 80 + 16 * Math.sin(t), top: 0, width: 1, height: 540,
      backgroundColor: '#1b2537',
    }} />)}
    <div style={{position: 'absolute', left: 40, top: 43, width: 12, height: 12,
      backgroundColor: lime, transform: `rotate(${frame * 2.4}deg)`}} />
    <Word text="NATIVE MOTION" x={66} y={42} unit={2} color={cream} />
    <Word text="SWIFT + SKIA" x={758} y={42} unit={2} color={cream} />
    <Word text="MOTION" x={46} y={164} unit={11} color={cream} phase={t} />
    <Word text="SWIFT" x={46} y={267} unit={11} color={orange} phase={t + 0.8} />
    {/* Orbiting forms, a breathing core and rotating satellite trails. */}
    <img src={ring} style={{position: 'absolute', left: 523, top: 100, width: 340, height: 340, objectFit: 'contain',
      transform: `scale(${1 + 0.045 * Math.sin(t * 2)})`}} />
    {Array.from({length: 12}, (_, i) => {
      const a = t + i * Math.PI / 6;
      const radius = 145 + 18 * Math.sin(t * 2 + i);
      const size = i % 3 === 0 ? 30 : 10;
      return <div key={`orbit-${i}`} style={{position: 'absolute',
        left: 693 + Math.cos(a) * radius - size / 2,
        top: 270 + Math.sin(a) * radius - size / 2,
        width: size, height: size, borderRadius: i % 2 ? size / 2 : 4,
        backgroundColor: i % 3 === 0 ? orange : cream,
        transform: `rotate(${frame * 2.4 + i * 30}deg)`,
      }} />;
    })}
    <div style={{position: 'absolute', left: 625, top: 202, width: 136, height: 136,
      borderRadius: 28 + 22 * (1 + Math.sin(t * 2)), backgroundColor: lime,
      transform: `rotate(${-frame * 2.4}deg) scale(${0.92 + 0.12 * Math.sin(t * 2)})`}} />
    <div style={{position: 'absolute', left: 669, top: 246, width: 48, height: 48,
      borderRadius: 24, backgroundColor: ink, transform: `translateX(${16 * Math.sin(t * 2)}px)`}} />
    {/* An always-moving audio-like motion strip anchors the lower edge. */}
    {Array.from({length: 58}, (_, i) => {
      const height = 8 + 36 * (0.5 + 0.5 * Math.sin(t * 3 - i * 0.33));
      return <div key={`bar-${i}`} style={{position: 'absolute', left: 46 + i * 15,
        top: 469 - height / 2, width: 7, height, borderRadius: 3,
        backgroundColor: i < 26 ? orange : lime, opacity: 0.5 + 0.5 * Math.pow(Math.sin(t - i * 0.1), 2),
      }} />;
    })}
    <div style={{position: 'absolute', left: 46, top: 510, width: 868, height: 2, backgroundColor: '#394357'}} />
    <div style={{position: 'absolute', left: 46 + (frame / 150) * 820, top: 507, width: 48, height: 8,
      borderRadius: 4, backgroundColor: cream}} />
  </AbsoluteFill>;
};

registerRoot(() => <Composition id="ReadmeMotion" component={ReadmeMotion}
  width={960} height={540} fps={30} durationInFrames={150} />);
