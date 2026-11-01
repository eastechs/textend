import AppKit
import ApplicationServices
import Observation

@MainActor @Observable final class ExpansionEngine {
  private static let maximumInputAge: TimeInterval = 0.5

  enum Status: String {
    case paused = "Paused"
    case permission = "Permission required"
    case secure = "Secure input unavailable"
    case composition = "Input method unavailable"
    case unavailable = "Reconnecting expansion"
    case active = "Expansion active"
  }

  private(set) var status: Status = .paused
  private(set) var lastMessage: String?
  private(set) var isEnabled: Bool
  private(set) var accessibilityGranted = false
  private(set) var postingGranted = false
  var hasRequiredPermissions: Bool { accessibilityGranted && postingGranted }
  var excludedBundleIDs: [String] {
    didSet {
      preferences.set(excludedBundleIDs, forKey: "excludedBundleIDs")
      cancel()
    }
  }
  private(set) var library = ExpansionLibrary()
  private var indexedBundleID: String?
  private(set) var paletteIsOpen = false
  private var tracking = ExpansionTracking()
  private let focus: FocusService
  @ObservationIgnored private lazy var insertion = TextInsertionService(
    focus: focus, secureInput: secureInput, postEvent: postEvent,
    cursorFailure: { [weak self] message in self?.lastMessage = message })
  private var eventTap: (any ExpansionEventTap)?
  private var timer: Timer?
  private var healthTimer: Timer?
  private var workspaceObservers: [NSObjectProtocol] = []
  private let preferences: UserDefaults
  private let workspaceCenter: NotificationCenter
  private let accessibility: @MainActor () -> Bool
  private let postEventAccess: @MainActor () -> Bool
  private let secureInput: @MainActor () -> Bool
  private let supportsInputSource: @MainActor () -> Bool
  private let application: @MainActor () -> FocusService.Application?
  private let enqueueInput: @MainActor (@escaping @MainActor () -> Void) -> Void
  private let uptime: @MainActor () -> TimeInterval
  private let postEvent: @MainActor (CGEvent) -> Void
  private let makeEventTap:
    @MainActor (@escaping @MainActor (CGEventType, CGEvent) -> Void) -> (any ExpansionEventTap)?
  private var isStarted = false
  private var isSleeping = false
  private var isSessionActive = true
  private var inputGeneration: UInt64 = 0
  private var inputSequence: UInt64 = 0

  init(
    preferences: UserDefaults = .standard,
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    accessibility: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
    postEventAccess: @escaping @MainActor () -> Bool = { CGPreflightPostEventAccess() },
    secureInput: @escaping @MainActor () -> Bool = { FocusService.secureInputEnabled },
    supportsInputSource: @escaping @MainActor () -> Bool = {
      FocusService.supportsCurrentInputSource
    },
    focus: FocusService? = nil,
    application: @escaping @MainActor () -> FocusService.Application? = {
      NSWorkspace.shared.frontmostApplication.map {
        FocusService.Application(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier)
      }
    },
    enqueueInput: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { work in
      DispatchQueue.main.async { work() }
    },
    uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    postEvent: @escaping @MainActor (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
    makeEventTap:
      @escaping @MainActor (@escaping @MainActor (CGEventType, CGEvent) -> Void) -> (
        any ExpansionEventTap
      )? = { SystemExpansionEventTap(receive: $0) }
  ) {
    self.preferences = preferences
    self.workspaceCenter = workspaceCenter
    self.accessibility = accessibility
    self.postEventAccess = postEventAccess
    self.secureInput = secureInput
    self.supportsInputSource = supportsInputSource
    self.focus = focus ?? FocusService()
    self.application = application
    self.enqueueInput = enqueueInput
    self.uptime = uptime
    self.postEvent = postEvent
    self.makeEventTap = makeEventTap
    isEnabled = preferences.bool(forKey: "expansionEnabled")
    excludedBundleIDs = preferences.stringArray(forKey: "excludedBundleIDs") ?? []
    updateDelay(preferences.object(forKey: "debounceMilliseconds") as? Int ?? 250)
  }

  func start(initiallyPaused: Bool = false) {
    guard !isStarted else { return }
    // Preview launches pause this session without changing the saved preference.
    // Keep the lifecycle running so Resume can install monitoring normally.
    if initiallyPaused { isEnabled = false }
    isStarted = true
    for name in [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidResignActiveNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      workspaceObservers.append(
        workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.workspaceChanged(name)
          }
        })
    }
    let healthTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    self.healthTimer = healthTimer
    RunLoop.main.add(healthTimer, forMode: .common)
    refresh()
  }

  private func workspaceChanged(_ name: Notification.Name) {
    guard isStarted else { return }
    rebuildIndex()
    switch name {
    case NSWorkspace.willSleepNotification:
      isSleeping = true
    case NSWorkspace.didWakeNotification:
      isSleeping = false
    case NSWorkspace.sessionDidResignActiveNotification:
      isSessionActive = false
    case NSWorkspace.sessionDidBecomeActiveNotification:
      isSessionActive = true
    default: break
    }
    if name != NSWorkspace.didActivateApplicationNotification {
      // A tap can survive a wake/session transition but stop delivering events.
      // Recreate it even if Core Graphics still reports it as enabled.
      removeTap()
      insertion.finish()
    }
    refresh()
  }

  func updateSnippets(_ snippets: [SnippetRecord]) {
    updateLibrary(ExpansionLibrary(items: snippets))
  }

  func updateLibrary(_ library: ExpansionLibrary) {
    self.library = library
    rebuildIndex()
  }

  private func rebuildIndex() {
    cancel()
    indexedBundleID = application()?.bundleID
    tracking.matcher.update(library.automaticItems(in: indexedBundleID))
  }

  func setPaletteOpen(_ value: Bool) {
    cancel()
    paletteIsOpen = value
  }

  func captureInsertionTarget() -> FocusService.Snapshot? {
    guard accessibility(), postEventAccess(), !secureInput(), !insertion.isBusy,
      let app = application(),
      !excludedBundleIDs.contains(app.bundleID ?? "")
    else { return nil }
    return focus.capture()
  }

  func insertManually(_ expansion: ResolvedExpansion, itemID: UUID, target: FocusService.Snapshot)
    throws
  {
    guard accessibility(), postEventAccess(), !secureInput(), supportsInputSource(),
      !excludedBundleIDs.contains(target.bundleID ?? ""),
      let item = library.items.first(where: { $0.id == itemID }),
      library.allows(item, in: target.bundleID),
      focus.matches(target, selection: true)
    else {
      throw TemplateError.invalid(
        "Insertion cancelled. Return to the original field and open Quick Access again.")
    }
    try library.validateContent(item)
    try insertion.insert(expansion, target: target.target, selection: target.selection) {
      [weak self] in
      self?.focus.matches(target, selection: false) == true
    }
  }
  func updateDelay(_ milliseconds: Int) {
    cancel()
    tracking.matcher.delay = Double(min(1000, max(100, milliseconds))) / 1000
  }

  func setEnabled(_ enabled: Bool, requestPermission: Bool = false) {
    isEnabled = enabled
    preferences.set(enabled, forKey: "expansionEnabled")
    cancel()
    if enabled && requestPermission { requestAccessibility() }
    refresh()
  }

  func requestAccessibility() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    refresh()
  }

  func openAccessibilitySettings() {
    requestAccessibility()
    // Repeated permission requests may not show a prompt. Always provide a route to Settings.
    let settingsURL = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    if !NSWorkspace.shared.open(settingsURL) {
      lastMessage =
        "Open System Settings → Privacy & Security → Accessibility, then enable Textend."
    }
  }

  func stop() {
    isStarted = false
    cancel()
    healthTimer?.invalidate()
    healthTimer = nil
    for observer in workspaceObservers {
      workspaceCenter.removeObserver(observer)
    }
    workspaceObservers = []
    removeTap()
    insertion.finish()
    isSleeping = false
    isSessionActive = true
    status = .paused
  }

  func refresh() {
    guard isStarted else { return }
    accessibilityGranted = accessibility()
    postingGranted = postEventAccess()
    var newStatus: Status
    if !isEnabled || isSleeping || !isSessionActive {
      newStatus = .paused
    } else if !hasRequiredPermissions {
      newStatus = .permission
    } else if secureInput() {
      newStatus = .secure
    } else if !supportsInputSource() {
      newStatus = .composition
    } else {
      newStatus = .active
    }
    if newStatus == .active, !ensureTap() { newStatus = .unavailable }
    if newStatus != status {
      cancel()
      status = newStatus
      ExpansionDiagnostics.record("Engine status: \(newStatus.rawValue)", processID: 0)
    }
    guard status == .active else {
      removeTap()
      return
    }
    if let target = tracking.target, focus.currentTarget() != target { cancel() }
  }

  private func ensureTap() -> Bool {
    if let eventTap {
      if eventTap.isValid && eventTap.isEnabled { return true }
      cancel()
      if eventTap.isValid {
        eventTap.enable()
        if eventTap.isValid && eventTap.isEnabled { return true }
      }
      removeTap()
    }
    guard
      let tap = makeEventTap({ [weak self] type, event in
        self?.receive(type: type, event: event)
      })
    else { return false }
    eventTap = tap
    tap.enable()
    guard tap.isValid && tap.isEnabled else {
      removeTap()
      return false
    }
    ExpansionDiagnostics.record("Keyboard listener installed", processID: 0)
    return true
  }

  private func removeTap() {
    eventTap?.invalidate()
    eventTap = nil
  }

  private func receive(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      ExpansionDiagnostics.record(
        type == .tapDisabledByTimeout
          ? "Keyboard listener timed out" : "Keyboard listener disabled",
        processID: 0)
      cancel()
      eventTap?.enable()
      return
    }
    if event.getIntegerValueField(.eventSourceUserData) == TextInsertionService.eventMarker {
      return
    }
    if type != .flagsChanged { insertion.cancelCursorPlacement() }
    if type == .flagsChanged {
      if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        || event.getIntegerValueField(.keyboardEventKeycode) == 57
      {
        cancel()
      }
      return
    }
    guard type == .keyDown else {
      cancel()
      return
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    guard !paletteIsOpen, status == .active, !insertion.isBusy, !secureInput(),
      !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl),
      !event.flags.contains(.maskAlternate),
      event.getIntegerValueField(.keyboardEventAutorepeat) == 0 || code == 51,
      let app = application(),
      !excludedBundleIDs.contains(app.bundleID ?? "")
    else {
      cancel()
      return
    }
    if indexedBundleID != app.bundleID { rebuildIndex() }
    guard ![36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(code) else {
      cancel()
      return
    }
    var characters = [UniChar](repeating: 0, count: 16)
    var length = 0
    event.keyboardGetUnicodeString(
      maxStringLength: 16, actualStringLength: &length, unicodeString: &characters)
    guard length > 0 || code == 51 else {
      cancel()
      return
    }
    let text = String(utf16CodeUnits: characters, count: length)
    inputSequence &+= 1
    let sequence = inputSequence
    let generation = inputGeneration
    let receivedAt =
      event.timestamp == 0 ? uptime() : min(uptime(), Double(event.timestamp) / 1_000_000_000)
    // An active event tap holds the host's key until its callback returns.
    // Never ask that host to answer synchronous accessibility queries here.
    enqueueInput { [weak self] in
      guard let self, self.inputGeneration == generation else { return }
      guard self.uptime() - receivedAt <= Self.maximumInputAge,
        self.application()?.processID == app.processID
      else {
        self.cancel()
        ExpansionDiagnostics.record("Discarded delayed input", processID: app.processID)
        return
      }
      self.processInput(
        text, code: code, processID: app.processID, sequence: sequence,
        generation: generation, receivedAt: receivedAt)
    }
  }

  private func processInput(
    _ text: String, code: Int64, processID: Int32, sequence: UInt64,
    generation: UInt64, receivedAt: TimeInterval
  ) {
    guard status == .active, !paletteIsOpen, !insertion.isBusy, !secureInput(),
      let current = focus.currentTarget(), current.processID == processID
    else {
      cancel()
      return
    }
    let selection = focus.selectionRange()
    // AX messaging can run a nested event loop. A pause, app switch, or wake
    // during a read must not let this older input recreate a cancelled run.
    guard generation == inputGeneration else { return }
    guard uptime() - receivedAt <= Self.maximumInputAge, application()?.processID == processID
    else {
      cancel()
      return
    }
    if code == 51 {
      timer?.invalidate()
      timer = nil
      tracking.backspace(target: current, selection: selection)
      return
    }
    let starting = tracking.target != current
    if starting {
      ExpansionDiagnostics.record("Typing run started", processID: current.processID)
    }
    timer?.invalidate()
    guard
      let match = tracking.input(
        text, target: current, selection: selection,
        startsAtBoundary: nil, now: uptime())
    else { return }
    ExpansionDiagnostics.record("Keyword matched", processID: current.processID)
    if let deadline = match.deadline {
      timer = Timer.scheduledTimer(
        withTimeInterval: max(0, deadline - uptime()), repeats: false
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.expand(match, target: current, sequence: sequence)
        }
      }
    } else {
      // Give the editor time to publish its selection after receiving the final key.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
        self?.expand(match, target: current, sequence: sequence)
      }
    }
  }

  private func expand(
    _ match: TriggerMatch, target: ExpansionTarget, sequence: UInt64, attempt: Int = 0
  ) {
    let generation = inputGeneration
    guard sequence == inputSequence, !paletteIsOpen, status == .active, !secureInput(),
      accessibility(), postEventAccess(), focus.currentTarget() == target,
      match.generation == tracking.matcher.generation
    else { return }
    let selection = focus.selectionRange()
    var matchingKeyword: Bool?
    if let selection {
      let length = match.snippet.keyword.utf16.count
      if selection.location >= length {
        matchingKeyword = focus.text(
          in: CFRange(location: selection.location - length, length: length)
        )
        .map { $0 == match.snippet.keyword }
      }
    }
    // Accessibility can trail delivery of the physical final key to another process.
    switch tracking.readiness(selection: selection, matchingKeyword: matchingKeyword) {
    case .cancelled:
      cancel()
      return
    case .waiting:
      if attempt < 14 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
          self?.expand(match, target: target, sequence: sequence, attempt: attempt + 1)
        }
      } else {
        ExpansionDiagnostics.record(
          "AX keyword confirmation timed out", processID: target.processID)
        cancel()
      }
      return
    case .ready: break
    }
    // Reads now happen after delivery, so test the character before the whole
    // confirmed keyword, not the character before the first key's new caret.
    if matchingKeyword == true,
      focus.startsAtBoundary(beforeUTF16Count: match.snippet.keyword.utf16.count) == false
    {
      ExpansionDiagnostics.record("Keyword is inside a word", processID: target.processID)
      cancel()
      return
    }
    guard sequence == inputSequence, generation == inputGeneration,
      let snippet = tracking.matcher.take(match, now: uptime())
    else {
      return
    }
    defer { tracking.reset() }
    do {
      let result = try library.resolve(
        snippet, clipboard: library.needsClipboard(snippet) ? insertion.readText() : nil)
      guard focus.currentTarget() == target,
        library.allows(snippet, in: application()?.bundleID)
      else { return }
      try insertion.replace(
        keyword: snippet.keyword, with: result.text, target: target,
        cursorUTF16Offset: result.cursorUTF16Offset,
        validate: { self.inputSequence == sequence && self.inputGeneration == generation })
      ExpansionDiagnostics.record("Expansion events posted", processID: target.processID)
      lastMessage = nil
    } catch { lastMessage = error.localizedDescription }
  }

  private func cancel() {
    inputGeneration &+= 1
    insertion.cancelCursorPlacement()
    timer?.invalidate()
    timer = nil
    tracking.reset()
  }
}
