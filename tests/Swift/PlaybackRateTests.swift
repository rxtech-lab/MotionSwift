import Testing
@testable import MotionSwiftUI

@Test func liveFPSCountsDeliveredFramesAndDecaysWhenRenderingStalls() {
  var rate = PlaybackRate()
  rate.start(at: 10)
  #expect(rate.value(at: 10.1) == nil)
  // These are deliveries, not playhead positions: skipping source frames cannot inflate FPS.
  for index in 1...15 { rate.record(at: 10 + Double(index) / 30) }
  #expect(rate.value(at: 10.5) == 30)
  #expect(rate.value(at: 11) == 15)
  #expect(rate.value(at: 11.6) == 0)
  rate.start(at: 20)
  #expect(rate.value(at: 20.5) == 0)
}
