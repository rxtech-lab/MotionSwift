import Foundation
import MotionCompiler
import MotionCore
import MotionPortable
import MotionRender
import MotionRuntime
import Testing

@Test func timelineAnimationMatchesMacExportAndPortablePixelsInsideSequence() throws {
  let project = FileManager.default.temporaryDirectory.appendingPathComponent("motionswift-timeline-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: project) }
  let source = """
    import React from 'react';
    import {AbsoluteFill, Composition, Sequence, registerRoot} from 'remotion';
    const Scene = () => <AbsoluteFill style={{backgroundColor: '#000000'}}>
      <Sequence from={10} durationInFrames={50} layout="none">
        <div style={{position: 'absolute', left: 20, top: 10, width: 20, height: 20, backgroundColor: '#ff0000'}} />
      </Sequence>
    </AbsoluteFill>;
    registerRoot(() => <Composition id="Scene" component={Scene} width={100} height={100} fps={30} durationInFrames={90} />);
    """
  let compiler = try PortableCompiler()
  let tracks = try compiler.timeline(source: source, file: "index.tsx")
  let object = try #require(tracks.first { $0.label == "div" })
  #expect(object.offset == 10)
  let timing = ObjectTiming(from: 5, duration: 30, keyframes: ["left": [
    .init(frame: 0, value: 20, easing: "hold"), .init(frame: 10, value: 40), .init(frame: 20, value: 60),
  ]])
  let edited = try compiler.edit(source: source, operation: .setTimeline(object.src, timing))
  try edited.source.write(to: project.appendingPathComponent("index.tsx"), atomically: true, encoding: .utf8)
  let portable = try Runtime(bundle: GraphLinker.link(compiler.compile(
    files: ["index.tsx": edited.source], entry: "index.tsx", stamp: true)))
  let mac = try Runtime(bundle: Compiler().compile(project: project, entry: "index.tsx"))
  let composition = try #require(try portable.compositions().first)
  let renderer = try Renderer(width: 100, height: 100)
  for (frame, expectedX) in [(14, nil), (15, 20.0), (24, 20.0), (25, 40.0), (30, 50.0), (40, 60.0), (45, nil)] {
    let tree = try portable.frame(composition: composition, number: frame)
    let boxes = try renderer.draw(tree, composition: composition)
    #expect(boxes.first { $0.source == object.src }?.x == expectedX)
    let pixels = try renderer.pixels()
    try renderer.draw(try mac.frame(composition: composition, number: frame), composition: composition)
    #expect(try renderer.pixels() == pixels)
  }
}
