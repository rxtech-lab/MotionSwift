import {interpolate, useCurrentFrame} from 'remotion';

export const Title = () => {
  const frame = useCurrentFrame();
  return <div style={{position: 'absolute', left: interpolate(frame, [0, 30], [0, 200])}} />;
};
