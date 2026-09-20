import XCTest

@testable import Twozz

@MainActor
final class LivePlaybackStartupTests: XCTestCase {
  func testNonzeroInitialHLSTimestampDoesNotMeanPlaybackStarted() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    XCTAssertFalse(progress.observe(clock: 3597, isPlaying: false, now: 1))
    XCTAssertFalse(progress.observe(clock: 3597, isPlaying: true, now: 2))
    XCTAssertFalse(progress.observe(clock: 3597, isPlaying: true, now: 2.5))
    XCTAssertFalse(progress.hasStarted)
  }

  func testStartupRequiresSustainedAdvancingPlayback() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    XCTAssertFalse(progress.observe(clock: 14, isPlaying: true, now: 1))
    XCTAssertFalse(progress.observe(clock: 14.25, isPlaying: true, now: 1.25))
    XCTAssertTrue(progress.observe(clock: 14.5, isPlaying: true, now: 1.5))
  }

  func testInitialSeekDoesNotCountAsClockProgress() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    XCTAssertFalse(progress.observe(clock: 0, isPlaying: true, now: 1))
    XCTAssertFalse(progress.observe(clock: 3597, isPlaying: true, now: 1.5))
    XCTAssertFalse(progress.observe(clock: 3597.25, isPlaying: true, now: 1.75))
    XCTAssertTrue(progress.observe(clock: 3597.5, isPlaying: true, now: 2))
  }

  func testBufferingResetsStartupProgress() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    _ = progress.observe(clock: 14, isPlaying: true, now: 1)
    _ = progress.observe(clock: 14.25, isPlaying: true, now: 1.25)
    XCTAssertFalse(progress.observe(clock: 14.25, isPlaying: false, now: 1.5))
    XCTAssertFalse(progress.observe(clock: 14.25, isPlaying: true, now: 2))
    XCTAssertFalse(progress.observe(clock: 14.5, isPlaying: true, now: 2.25))
    XCTAssertTrue(progress.observe(clock: 14.75, isPlaying: true, now: 2.5))
  }

  func testInvalidOrRewoundClockDoesNotStartPlayback() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    XCTAssertFalse(progress.observe(clock: .nan, isPlaying: true, now: 0))
    XCTAssertFalse(progress.observe(clock: .infinity, isPlaying: true, now: 1))
    XCTAssertFalse(progress.observe(clock: 14, isPlaying: true, now: 2))
    XCTAssertFalse(progress.observe(clock: 12, isPlaying: true, now: 2.5))
    XCTAssertFalse(progress.hasStarted)
  }

  func testConcurrentMonitorSamplesDoNotEraseUsefulProgress() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    _ = progress.observe(clock: 14, isPlaying: true, now: 1)
    XCTAssertFalse(progress.observe(clock: 14, isPlaying: true, now: 1.01))
    XCTAssertTrue(progress.observe(clock: 14.5, isPlaying: true, now: 1.5))
  }

  func testRateControllerCannotBypassStartupOrRebuffering() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    XCTAssertFalse(progress.allowsRateAdjustment(isPlaying: true, isLoading: false, shouldPlay: true))
    _ = progress.observe(clock: 14, isPlaying: true, now: 1)
    _ = progress.observe(clock: 14.5, isPlaying: true, now: 1.5)
    XCTAssertTrue(progress.allowsRateAdjustment(isPlaying: true, isLoading: false, shouldPlay: true))
    XCTAssertFalse(progress.allowsRateAdjustment(isPlaying: false, isLoading: false, shouldPlay: true))
    XCTAssertFalse(progress.allowsRateAdjustment(isPlaying: true, isLoading: true, shouldPlay: true))
    XCTAssertFalse(progress.allowsRateAdjustment(isPlaying: true, isLoading: false, shouldPlay: false))
  }

  func testNewItemRequiresItsOwnStartupProgress() {
    var progress = LivePlaybackStartup.Progress(now: 0)
    _ = progress.observe(clock: 14, isPlaying: true, now: 1)
    _ = progress.observe(clock: 14.5, isPlaying: true, now: 1.5)
    XCTAssertTrue(progress.hasStarted)
    progress = LivePlaybackStartup.Progress(now: 3)
    XCTAssertEqual(progress.createdAt, 3)
    XCTAssertFalse(progress.hasStarted)
    XCTAssertFalse(progress.observe(clock: 3597, isPlaying: true, now: 4))
  }

  func testYouTubeUsesStableForwardBufferPreference() {
    XCTAssertEqual(LivePlaybackStartup.youtubeForwardBufferSeconds, 8)
  }

  func testStartupSourceIsResolvedOnceAndReturnedForDirectInstallation() async throws {
    let calls = ProbeCalls()
    let source = try await LivePlaybackStartup.resolveYouTube {
      await calls.recordAttempt()
      return Self.source
    }
    let attempts = await calls.attempts
    XCTAssertEqual(attempts, 1)
    XCTAssertEqual(source.target, Self.source.target)
    XCTAssertEqual(source.live.hlsMaster, Self.source.live.hlsMaster)
    XCTAssertEqual(source.live.concurrentViewers, 42)
  }

  func testUnavailableYouTubePropagatesForTwitchFallback() async {
    do {
      _ = try await LivePlaybackStartup.resolveYouTube {
        throw AltSourceService.ResolutionError.noLiveVideo
      }
      XCTFail("An unavailable source must not be selected")
    } catch AltSourceService.ResolutionError.noLiveVideo {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSourceSelectionTimeoutCancelsLookupBeforeReturning() async {
    let calls = ProbeCalls()
    let start = ContinuousClock.now
    do {
      _ = try await LivePlaybackStartup.resolveYouTube(timeout: .milliseconds(50)) {
        await calls.recordAttempt()
        do {
          try await Task.sleep(for: .seconds(30))
          return Self.source
        } catch {
          await calls.recordCancellation()
          throw error
        }
      }
      XCTFail("The slow source must time out")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .timedOut)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
    let cancelled = await calls.cancelled
    XCTAssertTrue(cancelled)
    XCTAssertLessThan(start.duration(to: .now), .seconds(2))
  }

  func testDismissingPlayerCancelsSourceSelection() async {
    let calls = ProbeCalls()
    let task = Task {
      try await LivePlaybackStartup.resolveYouTube {
        await calls.recordAttempt()
        try await Task.sleep(for: .seconds(30))
        return Self.source
      }
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled startup must not install a source")
    } catch is CancellationError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testLateLookupResultCannotReplaceTimedOutSelection() async {
    do {
      _ = try await LivePlaybackStartup.resolveYouTube(timeout: .milliseconds(50)) {
        do {
          try await Task.sleep(for: .seconds(30))
        } catch is CancellationError {
          return Self.source
        }
        return Self.source
      }
      XCTFail("A lookup completing during cancellation must not replace Twitch")
    } catch let error as URLError {
      XCTAssertEqual(error.code, .timedOut)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  nonisolated private static var source: LivePlaybackStartup.YouTubeSource {
    LivePlaybackStartup.YouTubeSource(
      target: "@example",
      live: AltSourceService.YouTubeLive(
        hlsMaster: URL(string: "https://example.com/live.m3u8")!,
        concurrentViewers: 42))
  }

  private actor ProbeCalls {
    var attempts = 0
    var cancelled = false
    func recordAttempt() { attempts += 1 }
    func recordCancellation() { cancelled = true }
  }
}
