import React from 'react';
import {Composition} from 'remotion';
import {CrystalOrbit} from './scenes/CrystalOrbit';
import {NeonCity} from './scenes/NeonCity';
import {ProbeFleet} from './scenes/ProbeFleet';
import {GeometryLab} from './scenes/GeometryLab';

// 3D fixtures shared by the Remotion goldens, native visual tests, the 3D benchmark and the showcase.
export const Root = () => <>
  <Composition id="CrystalOrbit" component={CrystalOrbit} width={640} height={360} fps={30} durationInFrames={90} />
  <Composition id="NeonCity" component={NeonCity} width={640} height={360} fps={30} durationInFrames={90} />
  <Composition id="ProbeFleet" component={ProbeFleet} width={640} height={360} fps={30} durationInFrames={90} />
  <Composition id="GeometryLab" component={GeometryLab} width={640} height={360} fps={30} durationInFrames={60} />
</>;
