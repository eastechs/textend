import AppKit
import XCTest

@testable import TextendCore

final class ExpansionInputTests: XCTestCase {
  @MainActor func testKeyboardCallbackReturnsBeforeReadingEditorAccessibility() throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()

    try h.type("h")
    XCTAssertEqual(h.accessibilityReads, 0)
    XCTAssertEqual(h.queuedInput.count, 1)
    h.deliverInput()
    XCTAssertGreaterThan(h.accessibilityReads, 0)
    XCTAssertTrue(h.postedEvents.isEmpty)
  }

  @MainActor func testDeliveredKeywordExpandsAtDocumentStartOrAfterWhitespace() async throws {
    for prefix in ["", "Earlier text "] {
      let h = ExpansionInputHarness()
      defer { h.stop() }
      h.fieldText = prefix
      h.start()
      try h.type("hello")
      h.deliverInput()
      try await Task.sleep(for: .milliseconds(50))

      XCTAssertEqual(h.insertedText, "Hi!", prefix)
      XCTAssertEqual(h.backspaceCount, 5)
    }
  }

  @MainActor func testDeliveredKeywordInsideExistingWordDoesNotExpand() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.fieldText = "shell"
    h.start()
    try h.type("hello")
    h.deliverInput()
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertTrue(h.postedEvents.isEmpty)
  }

  @MainActor func testEditorWithoutAccessibilityStillExpands() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.hasAccessibility = false
    h.start()
    try h.type("hello")
    h.deliverInput()
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(h.insertedText, "Hi!")
  }

  @MainActor func testDelayedInputIsDiscardedAndFreshTypingRecovers() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("hello")
    h.now += 1
    h.deliverInput()
    XCTAssertEqual(h.accessibilityReads, 0)
    XCTAssertTrue(h.postedEvents.isEmpty)

    h.fieldText = ""
    try h.type("hello")
    h.deliverInput()
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(h.insertedText, "Hi!")
  }

  @MainActor func testAppSwitchBeforeDeliveryDiscardsOldKeys() throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("hello")
    h.application = .init(processID: 900_002, bundleID: "another.app")
    h.deliverInput()

    XCTAssertEqual(h.accessibilityReads, 0)
    XCTAssertTrue(h.postedEvents.isEmpty)
  }

  @MainActor func testEventDelayedBeforeItsCallbackIsDiscarded() throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.key(code: 0, text: "h", timestamp: h.now - 1)
    h.deliverInput()

    XCTAssertEqual(h.accessibilityReads, 0)
    XCTAssertTrue(h.postedEvents.isEmpty)
  }

  @MainActor func testLifecycleAndContextChangesDiscardQueuedKeys() throws {
    for reason in ["wake", "pause", "palette", "library", "activation", "timeout", "stop"] {
      let h = ExpansionInputHarness()
      defer { h.stop() }
      h.start()
      try h.type("hello")
      switch reason {
      case "wake":
        h.center.post(name: NSWorkspace.willSleepNotification, object: nil)
        h.center.post(name: NSWorkspace.didWakeNotification, object: nil)
      case "pause":
        h.engine.setEnabled(false)
        h.engine.setEnabled(true)
      case "palette":
        h.engine.setPaletteOpen(true)
        h.engine.setPaletteOpen(false)
      case "library": h.engine.updateSnippets([])
      case "activation":
        h.center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
      case "timeout":
        h.receive?(.tapDisabledByTimeout, try XCTUnwrap(CGEvent(source: nil)))
      default: h.engine.stop()
      }
      h.deliverInput()

      XCTAssertEqual(h.accessibilityReads, 0, reason)
      XCTAssertTrue(h.postedEvents.isEmpty, reason)
    }
  }

  @MainActor func testNewKeyCancelsMatchBeforeThatKeysDeferredWorkRuns() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("hello")
    h.deliverInput()
    try h.type("x")
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertTrue(h.postedEvents.isEmpty)
    XCTAssertEqual(h.queuedInput.count, 1)
    h.deliverInput()
  }

  @MainActor func testInputArrivingDuringAccessibilityConfirmationCancelsExpansion() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("hello")
    h.deliverInput()
    // Accessibility IPC can run a nested event loop before returning its result.
    h.onTextRead = {
      do {
        try h.key(code: 0, text: "x")
      } catch {
        XCTFail("Could not simulate incoming input: \(error)")
      }
    }
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertTrue(h.postedEvents.isEmpty)
  }

  @MainActor func testRecoveryDuringAccessibilityReadDoesNotReviveOldPrefix() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("h")
    h.onAttributeRead = {
      h.engine.setEnabled(false)
      h.engine.setEnabled(true)
    }
    h.deliverInput()
    try h.type("ello")
    h.deliverInput()
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertTrue(h.postedEvents.isEmpty)
  }

  @MainActor func testQueuedBackspacePreservesTypoCorrectionOrder() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("hex")
    try h.key(code: 51)
    h.fieldText.removeLast()
    try h.type("llo")
    h.deliverInput()
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(h.insertedText, "Hi!")
  }

  @MainActor func testNavigationDiscardsEarlierKeysWithoutDiscardingNextRun() async throws {
    let h = ExpansionInputHarness()
    defer { h.stop() }
    h.start()
    try h.type("hel")
    try h.key(code: 123)
    h.fieldText = ""
    try h.type("hello")
    h.deliverInput()
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(h.insertedText, "Hi!")
    XCTAssertEqual(h.backspaceCount, 5)
  }
}

@MainActor private final class ExpansionInputHarness {
  let center = NotificationCenter()
  private let suite = "textend-input-tests." + UUID().uuidString
  private lazy var preferences = UserDefaults(suiteName: suite)!
  var application = FocusService.Application(processID: 900_000, bundleID: "editor.app")
  private let element = AXUIElementCreateApplication(900_001)
  var fieldText = ""
  var hasAccessibility = true
  var accessibilityReads = 0
  var now: TimeInterval = 100
  var queuedInput: [@MainActor () -> Void] = []
  var postedEvents: [CGEvent] = []
  var receive: (@MainActor (CGEventType, CGEvent) -> Void)?
  var onAttributeRead: (() -> Void)?
  var onTextRead: (() -> Void)?

  lazy var focus = FocusService(
    application: { [unowned self] in application },
    attribute: { [unowned self] _, name in
      accessibilityReads += 1
      let callback = onAttributeRead
      onAttributeRead = nil
      callback?()
      guard hasAccessibility else { return nil }
      switch name {
      case kAXFocusedUIElementAttribute: return element
      case kAXSelectedTextRangeAttribute:
        var range = CFRange(location: fieldText.utf16.count, length: 0)
        return AXValueCreate(.cfRange, &range)
      default: return nil
      }
    },
    stringForRange: { [unowned self] _, range in
      accessibilityReads += 1
      let text = fieldText as NSString
      let callback = onTextRead
      onTextRead = nil
      callback?()
      guard range.location >= 0, range.length >= 0,
        range.location + range.length <= text.length
      else { return nil }
      return text.substring(with: NSRange(location: range.location, length: range.length))
    }, ownBundleID: "textend.test")

  lazy var engine: ExpansionEngine = {
    preferences.set(true, forKey: "expansionEnabled")
    return ExpansionEngine(
      preferences: preferences, workspaceCenter: center,
      accessibility: { true }, postEventAccess: { true },
      secureInput: { false }, supportsInputSource: { true },
      focus: focus, application: { [unowned self] in application },
      enqueueInput: { [unowned self] in queuedInput.append($0) },
      uptime: { [unowned self] in now },
      postEvent: { [unowned self] in postedEvents.append($0) },
      makeEventTap: { [unowned self] in
        receive = $0
        return InputTestEventTap()
      })
  }()

  func start() {
    engine.updateSnippets([SnippetRecord(name: "Greeting", keyword: "hello", template: "Hi!")])
    engine.start()
  }

  func type(_ text: String) throws {
    for character in text {
      try key(code: 0, text: String(character))
      // The editor receives the key only after Textend returns from its callback.
      fieldText.append(character)
    }
  }

  func key(code: CGKeyCode, text: String = "", timestamp: TimeInterval? = nil) throws {
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
    event.flags = []
    event.timestamp = UInt64((timestamp ?? now) * 1_000_000_000)
    let units = Array(text.utf16)
    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    receive?(.keyDown, event)
  }

  func deliverInput() {
    let pending = queuedInput
    queuedInput.removeAll()
    for work in pending { work() }
  }

  var insertedText: String {
    postedEvents.filter {
      $0.type == .keyDown && $0.getIntegerValueField(.keyboardEventKeycode) != 51
    }
    .map { event in
      var units = [UniChar](repeating: 0, count: 16)
      var length = 0
      event.keyboardGetUnicodeString(
        maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
      return String(utf16CodeUnits: units, count: length)
    }.joined()
  }

  var backspaceCount: Int {
    postedEvents.filter {
      $0.type == .keyDown && $0.getIntegerValueField(.keyboardEventKeycode) == 51
    }
    .count
  }

  func stop() {
    engine.stop()
    preferences.removePersistentDomain(forName: suite)
  }
}

@MainActor private final class InputTestEventTap: ExpansionEventTap {
  var isValid = true
  var isEnabled = true
  func enable() { isEnabled = true }
  func invalidate() {
    isValid = false
    isEnabled = false
  }
}
