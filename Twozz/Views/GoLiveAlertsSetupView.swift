import SwiftUI

/// A one-time invitation, not a permission request to Twitch or tvOS.
struct GoLiveAlertsSetupView: View {
  let follows: FollowedChannelsService
  let settings: GoLiveNotificationSettings
  let auth: TwitchAuthSession

  @Environment(\.dismiss) private var dismiss
  @Environment(\.themePalette) private var palette
  @FocusState private var keepOffFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 28) {
        Text("Turn on Go Live Alerts?")
          .font(.title)
        Text("Choose all channels, pick individual channels, or leave alerts off.")
          .font(.body)
        Text("All Channels includes future follows. Turning any channel off switches to a custom list, where new follows start off.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text("These alerts appear only inside Twozz on this Apple TV. They do not sync with Twitch's notification bell.")
          .font(.callout)
          .foregroundStyle(.secondary)

        HStack(spacing: 24) {
          Button("Keep Off", role: .cancel) {
            settings.disableAll()
            dismiss()
          }
          .focused($keepOffFocused)
          Button("All Channels") {
            settings.enableAll()
            dismiss()
          }
          NavigationLink("Choose Channels") {
            GoLiveAlertsSettingsView(follows: follows, settings: settings, auth: auth)
              .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                  Button("Done") { dismiss() }
                }
              }
          }
        }
        .buttonStyle(.bordered)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: 1050)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { AppBackground(palette: palette) }
      .defaultFocus($keepOffFocused, true)
      .onAppear { settings.markPromptPresented() }
      .onExitCommand { dismiss() }
    }
  }
}
