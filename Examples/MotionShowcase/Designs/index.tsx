import React from 'react';
import {MapMarker, MapView} from '@motionswift/map';
import {AbsoluteFill, Composition, Img, registerRoot} from 'remotion';


// SVG lettering uses the renderer's supported text shaping. The image box remains editable.
const lettering = (text: string, size: number, color: string, width: number, height: number) => {
  const words = text.split(' ');
  const lines: string[] = [];
  let line = '';
  for (const word of words) {
    if (line && (line.length + word.length + 1) * size * 0.52 > width) {
      lines.push(line); line = word;
    } else { line += (line ? ' ' : '') + word; }
  }
  if (line) lines.push(line);
  const escape = (value: string) => value.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  return 'data:image/svg+xml,' + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">` +
    lines.map((line, index) => `<text x="0" y="${size + index * size * 1.05}" font-family="Helvetica Neue" font-size="${size}" fill="${color}">${escape(line)}</text>`).join('') + '</svg>');
};

// Literal styles and MotionSwift timing metadata keep the art editable on the canvas,
// in the property inspector and on keyframe lanes. No hidden frame expressions.
const Ribbon = () => <AbsoluteFill style={{backgroundColor: '#101427', overflow: 'hidden'}}>
  <div style={{position: 'absolute', left: 620, top: -100, width: 420, height: 740,
    backgroundColor: '#ff785b', borderRadius: 210, transform: 'rotate(28deg)'}} />
  <div data-ms-timeline={{"from":0,"duration":240,"keyframes":{"top":[{"frame":0,"value":420,"easing":"linear"},{"frame":36,"value":100,"easing":"linear"},{"frame":200,"value":70,"easing":"linear"}]}}}
    style={{position: 'absolute', left: 650, top: 100, width: 190, height: 330,
      backgroundColor: '#ffcc7c', borderRadius: 95, transform: 'rotate(28deg)'}} />
  <Img src={lettering('MOTION STUDIES / 001', 16, '#ffae94', 800, 30)} style={{position: 'absolute', left: 54, top: 44, width: 800, height: 30}} />
  <Img data-ms-properties={{width: {label: 'Title width', group: 'Typography'}, height: {label: 'Title height', group: 'Typography'}}}
    data-ms-timeline={{"from":8,"duration":232,"keyframes":{"left":[{"frame":0,"value":-480,"easing":"linear"},{"frame":24,"value":54,"easing":"linear"}]}}}
    src={lettering("Make it move.", 88, "#fff4e8", 590, 230)} style={{position: 'absolute', left: 54, top: 145, width: 590, height: 230}} />
  <Img data-ms-timeline={{"from":36,"duration":204,"keyframes":{"opacity":[{"frame":0,"value":0,"easing":"linear"},{"frame":20,"value":1,"easing":"linear"}]}}}
    src={lettering("Small ideas. Extraordinary motion.", 21, "#b8bfd6", 450, 60)} style={{position: 'absolute', left: 58, top: 389, width: 450, height: 60, opacity: 1}} />
  <div style={{position: 'absolute', left: 56, top: 487, width: 840, height: 2, backgroundColor: '#34394e'}} />
  <Img src={lettering('MOTION SWIFT / DESIGN IN TIME / 2026', 12, '#b8bfd6', 840, 20)} style={{position: 'absolute', left: 56, top: 502, width: 840, height: 20}} />
</AbsoluteFill>;

const Orbit = () => <AbsoluteFill style={{backgroundColor: '#e9e8de', overflow: 'hidden'}}>
  <Img src={lettering("FORM / PLAY / REPEAT", 16, "#24524d", 852, 24)} style={{position: 'absolute', left: 48, top: 40, width: 852, height: 24}} />
  <div data-ms-timeline={{"from":0,"duration":240,"keyframes":{"left":[{"frame":0,"value":960,"easing":"linear"},{"frame":40,"value":380,"easing":"linear"},{"frame":120,"value":420,"easing":"linear"},{"frame":239,"value":380,"easing":"linear"}]}}}
    data-ms-properties={{backgroundColor: {label: 'Sphere color', group: 'Palette'}}}
    style={{position: 'absolute', left: 380, top: 75, width: 480, height: 480,
      borderRadius: 240, backgroundColor: '#24524d'}} />
  <div data-ms-timeline={{"from":18,"duration":222,"keyframes":{"top":[{"frame":0,"value":-220,"easing":"linear"},{"frame":40,"value":103,"easing":"linear"},{"frame":170,"value":60,"easing":"linear"}]}}}
    style={{position: 'absolute', left: 580, top: 103, width: 200, height: 200,
      backgroundColor: '#d9f36c', borderRadius: 100}} />
  <Img src={lettering("In good shape.", 76, "#162d2a", 320, 220)} data-ms-timeline={{"from":0,"duration":240,"keyframes":{"top":[{"frame":0,"value":540,"easing":"linear"},{"frame":30,"value":180,"easing":"linear"}]}}}
    style={{position: 'absolute', left: 54, top: 180, width: 320, height: 220}} />
  <Img src={lettering("02 \u2014 A study in balance, scale and a little surprise.", 18, "#24524d", 844, 27)} style={{position: 'absolute', left: 56, top: 482, width: 844, height: 27}} />
</AbsoluteFill>;

const Signal = () => <AbsoluteFill style={{backgroundColor: '#151226', overflow: 'hidden'}}>
  <Img src={lettering("SIGNAL / SOUND IN COLOUR", 16, "#c9baff", 850, 24)} style={{position: 'absolute', left: 50, top: 42, width: 850, height: 24}} />
  <Img src={lettering("Find your frequency.", 72, "#faf1ff", 850, 108)} style={{position: 'absolute', left: 50, top: 110, width: 850, height: 108}} />
  <div data-ms-timeline={{"from":0,"duration":240,"keyframes":{"height":[{"frame":0,"value":30,"easing":"linear"},{"frame":45,"value":180,"easing":"linear"},{"frame":100,"value":65,"easing":"linear"},{"frame":160,"value":180,"easing":"linear"},{"frame":239,"value":30,"easing":"linear"}]}}}
    data-ms-properties={{backgroundColor: {label: 'Bass color', group: 'Sound palette'}}}
    style={{position: 'absolute', left: 70, top: 245, width: 170, height: 180, borderRadius: 32, backgroundColor: '#b69bff'}} />
  <div data-ms-timeline={{"from":0,"duration":240,"keyframes":{"height":[{"frame":0,"value":150,"easing":"linear"},{"frame":60,"value":45,"easing":"linear"},{"frame":120,"value":180,"easing":"linear"},{"frame":180,"value":45,"easing":"linear"},{"frame":239,"value":150,"easing":"linear"}]}}}
    style={{position: 'absolute', left: 275, top: 245, width: 170, height: 180, borderRadius: 32, backgroundColor: '#ff916f'}} />
  <div data-ms-timeline={{"from":0,"duration":240,"keyframes":{"height":[{"frame":0,"value":60,"easing":"linear"},{"frame":80,"value":180,"easing":"linear"},{"frame":160,"value":35,"easing":"linear"},{"frame":239,"value":60,"easing":"linear"}]}}}
    style={{position: 'absolute', left: 480, top: 245, width: 170, height: 180, borderRadius: 32, backgroundColor: '#e1f08b'}} />
  <div data-ms-timeline={{"from":0,"duration":240,"keyframes":{"height":[{"frame":0,"value":180,"easing":"linear"},{"frame":80,"value":40,"easing":"linear"},{"frame":160,"value":180,"easing":"linear"},{"frame":239,"value":180,"easing":"linear"}]}}}
    style={{position: 'absolute', left: 685, top: 245, width: 170, height: 180, borderRadius: 32, backgroundColor: '#80d8ce'}} />
  <Img src={lettering('FOUR VOICES. ONE RHYTHM. / MOTION STUDIES 003', 16, '#c9baff', 850, 30)} style={{position: 'absolute', left: 54, top: 483, width: 850, height: 30}} />
</AbsoluteFill>;

const Atlas = () => <AbsoluteFill style={{backgroundColor: '#112b29', overflow: 'hidden'}}>
  <Img src={lettering("ATLAS / SAN FRANCISCO AIRPORT", 16, "#b9d5bd", 360, 30)} style={{position: 'absolute', left: 45, top: 42, width: 360, height: 30}} />
  <Img src={lettering("Every place has a story.", 66, "#f0efd9", 350, 235)} style={{position: 'absolute', left: 45, top: 130, width: 350, height: 235}} />
  <Img src={lettering("Pan the map. Follow the marker. Make the journey yours.", 18, "#b9d5bd", 330, 60)} style={{position: 'absolute', left: 45, top: 420, width: 330, height: 60}} />
  <div style={{position: 'absolute', left: 440, top: 48, width: 472, height: 414,
    borderRadius: 28, overflow: 'hidden', backgroundColor: '#dbe8ce'}}>
    <MapView center={[-122.3790, 37.6213]} zoom={13.2} provider="openstreetmap" mapStyle="standard"
      data-ms-timeline={{"from":0,"duration":240,"keyframes":{"centerLongitude":[{"frame":0,"value":-122.397,"easing":"linear"},{"frame":239,"value":-122.379,"easing":"linear"}]}}}>
      <MapMarker coordinate={[-122.3790, 37.6213]} color="#f56749" label="SFO Airport" />
    </MapView>
  </div>
  <Img src={lettering('SFO AIRPORT / OPENSTREETMAP', 12, '#b9d5bd', 472, 30)} style={{position: 'absolute', left: 444, top: 485, width: 472, height: 30}} />
</AbsoluteFill>;

registerRoot(() => <>
  <Composition id="Ribbon" component={Ribbon} width={960} height={540} fps={30} durationInFrames={240} />
  <Composition id="Orbit" component={Orbit} width={960} height={540} fps={30} durationInFrames={240} />
  <Composition id="Signal" component={Signal} width={960} height={540} fps={30} durationInFrames={240} />
  <Composition id="Atlas" component={Atlas} width={960} height={540} fps={30} durationInFrames={240} />
</>);
