import SwiftUI
import XCTest

@testable import Twozz

@MainActor
final class ChatScrollRenderingTests: XCTestCase {
  func testLiveEdgeSurvivesBufferRotationAndResumingFromOldSnapshot() async throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let previousKeyWindow = scene.keyWindow
    let state = ChatRenderState()
    state.messages = try messages(0..<200)
    let host = UIHostingController(rootView: ChatRenderHarness(state: state))
    let window = UIWindow(windowScene: scene)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKey()
    }
    await layout(host)
    let scroll = try XCTUnwrap(findScrollView(in: host.view))
    assertAtLiveEdge(scroll)

    for batch in 1...12 {
      state.messages.removeFirst(20)
      state.messages.append(contentsOf: try messages((200 + batch * 20)..<(220 + batch * 20)))
      await layout(host)
      assertAtLiveEdge(scroll)
    }

    state.autoScroll = false
    state.scrollTarget = ChatScrollTarget(id: state.messages[80].id, anchor: .bottom, nonce: 1, animated: false)
    await layout(host)
    XCTAssertLessThan(scroll.contentOffset.y, bottomOffset(scroll) - 100)

    // A busy channel has trimmed every frozen row by the time reading ends.
    state.messages = try messages(1_000..<1_200)
    state.scrollTarget = nil
    state.autoScroll = true
    await layout(host)
    assertAtLiveEdge(scroll)

    state.width = 680
    await layout(host)
    assertAtLiveEdge(scroll)
    state.messages = try messages(2_000..<2_003)
    await layout(host)
    assertAtLiveEdge(scroll)
  }

  private func messages(_ range: Range<Int>) throws -> [ChatMessage] {
    try range.map { index in
      let text = String(repeating: "Message \(index) ", count: index.isMultiple(of: 3) ? 10 : 2)
      return try XCTUnwrap(ChatMessage(ircLine: ":viewer!viewer@host PRIVMSG #example :\(text)"))
    }
  }

  private func layout(_ host: UIViewController) async {
    try? await Task.sleep(for: .milliseconds(250))
    host.view.layoutIfNeeded()
  }

  private func findScrollView(in view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView { return scroll }
    return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
  }

  private func bottomOffset(_ scroll: UIScrollView) -> CGFloat {
    max(-scroll.adjustedContentInset.top,
        scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
  }

  private func assertAtLiveEdge(_ scroll: UIScrollView, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertGreaterThan(scroll.bounds.height, 0, file: file, line: line)
    XCTAssertEqual(scroll.contentOffset.y, bottomOffset(scroll), accuracy: 3, file: file, line: line)
  }
}

@MainActor
@Observable
private final class ChatRenderState {
  var messages: [ChatMessage] = []
  var autoScroll = true
  var scrollTarget: ChatScrollTarget?
  var width: CGFloat = 460
}

private struct ChatRenderHarness: View {
  let state: ChatRenderState

  var body: some View {
    ChatView(
      channel: "example", messages: state.messages, isConnected: true,
      autoScroll: state.autoScroll, scrollTarget: state.scrollTarget
    )
    .frame(width: state.width, height: 600)
  }
}
