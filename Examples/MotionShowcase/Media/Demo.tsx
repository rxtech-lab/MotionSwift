import React from 'react';
import {AbsoluteFill, Audio, Composition, Img, OffthreadVideo, Sequence,
  interpolate, registerRoot, useCurrentFrame} from 'remotion';

const video = __VIDEO__;
const image = __IMAGE__;
const audio = __AUDIO__;
type Clip = {id: string; compositionID?: string; start: number; duration: number;
  bounds?: {left: number; top: number; width: number; height: number}};
const layers: Record<string, Clip[]> = __LAYERS__;

// A reusable small clip. Every instance gets its own local frame from Sequence.
const Card = ({kind}: {kind: 'image' | 'video'}) => {
  const frame = useCurrentFrame();
  const entrance = interpolate(frame, [0, 18], [32, 0], {extrapolateRight: 'clamp'});
  return <AbsoluteFill style={{backgroundColor: '#182437', padding: 12,
    transform: `translateY(${entrance}px)`, overflow: 'hidden'}}>
    {kind === 'image' ? <Img src={image} style={{width: '100%', height: '100%', objectFit: 'cover'}} /> :
      <OffthreadVideo src={video} trimBefore={30} playbackRate={1} volume={0.18}
        style={{width: '100%', height: '100%', objectFit: 'cover'}} />}
  </AbsoluteFill>;
};

const Film = () => {
  const frame = useCurrentFrame();
  return <AbsoluteFill style={{backgroundColor: '#090f1e'}}>
    <Audio src={audio} volume={0.45} />
    <div style={{position: 'absolute', left: 36, top: 36, width: 888, height: 8, backgroundColor: '#243449'}}>
      <div style={{width: 888 * frame / 359, height: 8, backgroundColor: '#42e5bf'}} />
    </div>
    {layers.MediaMontage.filter(clip => clip.compositionID).map(clip =>
      <Sequence key={clip.id} from={clip.start} durationInFrames={clip.duration} layout="none">
        <div style={{position: 'absolute', ...clip.bounds, overflow: 'hidden'}}>
          <Sequence from={0} durationInFrames={clip.duration}>
            {clip.compositionID === 'ImageClip' ? <Card kind="image" /> : <Card kind="video" />}
          </Sequence>
        </div>
      </Sequence>)}
  </AbsoluteFill>;
};
const ImageClip = () => <Card kind="image" />;
const VideoClip = () => <Card kind="video" />;
const components: Record<string, React.ComponentType> = {MediaMontage: Film, ImageClip, VideoClip};
const Master = () => <AbsoluteFill style={{backgroundColor: '#090f1e'}}>
  {layers.MasterComposition.map(clip => {
    const Component = components[clip.compositionID!];
    return <Sequence key={clip.id} from={clip.start} durationInFrames={clip.duration} layout="none">
      <div style={{position: 'absolute', ...clip.bounds, overflow: 'hidden'}}>
        <Sequence from={0} durationInFrames={clip.duration}><Component /></Sequence>
      </div>
    </Sequence>;
  })}
</AbsoluteFill>;
registerRoot(() => <>
  <Composition id="MediaMontage" component={Film} width={960} height={540} fps={30} durationInFrames={360} />
  <Composition id="MasterComposition" component={Master} width={1280} height={720} fps={30} durationInFrames={720} />
  <Composition id="ImageClip" component={ImageClip} width={416} height={300} fps={30} durationInFrames={150} />
  <Composition id="VideoClip" component={VideoClip} width={416} height={300} fps={30} durationInFrames={150} />
</>);
