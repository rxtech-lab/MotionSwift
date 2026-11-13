import Testing
@testable import motionswift_showcase

@Test func timelineScrubbingMapsFramesAndClampsDraggingOutsideTheTrack() {
  #expect(MediaTimelineScrubbing.frame(at: 0, width: 600, duration: 720) == 0)
  #expect(MediaTimelineScrubbing.frame(at: 300, width: 600, duration: 720) == 360)
  #expect(MediaTimelineScrubbing.frame(at: 600, width: 600, duration: 720) == 719)
  #expect(MediaTimelineScrubbing.frame(at: -100, width: 600, duration: 720) == 0)
  #expect(MediaTimelineScrubbing.frame(at: 900, width: 600, duration: 720) == 719)
  // Nested compositions and resized windows use the same frame conversion.
  #expect(MediaTimelineScrubbing.frame(at: 240, width: 480, duration: 150) == 75)
  #expect(MediaTimelineScrubbing.frame(at: 100, width: 0, duration: 150) == 0)
}
