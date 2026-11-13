import Foundation
import MotionCore
import MotionRuntime
import MotionSwiftUI
import Testing

@Test @MainActor
func nativeMediaUsesLocalFramesTrimsRatesAndFreezeSilence() async throws {
  let code = """
    import React from 'react';
    import {AbsoluteFill, Audio, Composition, Freeze, Loop, Sequence, registerRoot} from 'remotion';
    const Clip = () => <Audio src="/tmp/example.wav" trimBefore={15} trimAfter={45} playbackRate={2} volume={f => f / 100} />;
    const Film = () => <AbsoluteFill>
      <Sequence from={10} durationInFrames={50}>
        <Sequence from={5} durationInFrames={20}><Clip /></Sequence>
      </Sequence>
      <Freeze frame={8}><Audio src="/tmp/frozen.wav" /></Freeze>
      <Loop durationInFrames={10}><Audio src="/tmp/loop.wav" /></Loop>
    </AbsoluteFill>;
    registerRoot(() => <Composition id="Media" component={Film} width={32} height={32} fps={30} durationInFrames={90} />);
    """
  let player = MotionPlayer(configuration: .init(scale: 1))
  await player.load(.files(["index.tsx": code], entry: "index.tsx"))
  let bundle = try #require(player.bundle)
  let composition = try #require(player.composition)
  let runtime = try Runtime(bundle: bundle)
  func voices(_ frame: Int) throws -> [ActiveMedia] {
    try runtime.frame(composition: composition, number: frame).activeMedia
  }
  #expect(try voices(14).count == 2)
  let atStart = try #require(voices(15).first { $0.src.hasSuffix("example.wav") })
  #expect(atStart.sample.time == 0.5)
  let later = try #require(voices(20).first { $0.src.hasSuffix("example.wav") })
  #expect(abs(later.sample.time - 25.0 / 30) < 0.000001)
  #expect(later.sample.volume == 0.05)
  #expect(later.sample.playbackRate == 2)
  #expect(try voices(30).count == 2) // trimAfter is exclusive
  #expect(try voices(20).first { $0.src.hasSuffix("frozen.wav") }?.sample.volume == 0)
  #expect(try voices(21).first { $0.src.hasSuffix("loop.wav") }?.sample.time == 1.0 / 30)
}
