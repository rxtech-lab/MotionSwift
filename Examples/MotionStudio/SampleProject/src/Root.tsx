import React from 'react';
import {Composition} from 'remotion';
import {Cards} from './Cards';
import {Pulse} from './Pulse';
import {Row} from './Row';

export const Root = () => <>
  <Composition id="Cards" component={Cards} width={640} height={360} fps={30} durationInFrames={90} />
  <Composition id="Row" component={Row} width={640} height={360} fps={30} durationInFrames={90} />
  <Composition id="Pulse" component={Pulse} width={640} height={360} fps={30} durationInFrames={90} />
</>;
