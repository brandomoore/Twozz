import AVFoundation
import UIKit

extension PlayerView {
  func monitorWatchRewards() async {
    while !Task.isCancelled {
      updateWatchRewards()
      do { try await Task.sleep(for: .seconds(1)) }
      catch { break }
    }
    model.watchTracker.stop()
  }

  func updateWatchRewards() {
    guard auth.isAuthenticated, let userID = auth.userID, let item = player.currentItem else {
      model.watchTracker.stop()
      return
    }
    let playback = TwitchWatchPlayback(
      target: .init(channel: activeChannel, userID: userID, itemID: ObjectIdentifier(item)),
      uptime: ProcessInfo.processInfo.systemUptime,
      playhead: item.currentTime().seconds,
      rate: Double(player.rate),
      ready: item.status == .readyToPlay && !isLoading && !isOffline
        && videoDecodeFrozenSince == nil,
      playing: player.timeControlStatus == .playing,
      twitchLive: !isVOD && !isUsingAltSource && liveVODHandoff?.isActive != true,
      foreground: UIApplication.shared.applicationState == .active && backgroundedAt == nil,
      visible: channelPageTarget == nil,
      userPaused: isUserPaused,
      seeking: isScrubbing || scrubTargetSeconds != nil || vodHandoffTransitionInFlight,
      sleeping: isSleeping,
      muted: player.isMuted || player.volume == 0)
    model.watchTracker.update(
      playback, session: environment.watchRewards, recorder: model.playbackTelemetry)
  }
}
