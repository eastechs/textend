import AppKit
import CoreGraphics

@MainActor final class TextInsertionService: ExpansionClipboard, ExpansionInsertion {
  static let eventMarker: Int64 = 0x54_4150_5354_4552
  private let focus: any ExpansionFocus
  private let pasteboard: NSPasteboard
  private let postEvent: @MainActor (CGEvent) -> Void
  private let secureInput: @MainActor () -> Bool
  private let schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void
  private let cursorFailure: @MainActor (String) -> Void
  private(set) var isBusy = false
  private var manualInputMonitors: [Any] = []
  private var manualTargetCheck: (@MainActor () -> Bool)?
  private var restoreWork: DispatchWorkItem?
  private var cursorWork: DispatchWorkItem?
  private var cursorGeneration = 0
  private var savedClipboard: [[NSPasteboard.PasteboardType: Data]]?
  private var ownChangeCount: Int?

  init(
    focus: any ExpansionFocus, pasteboard: NSPasteboard = .general,
    secureInput: @escaping @MainActor () -> Bool = { FocusService.secureInputEnabled },
    postEvent: @escaping @MainActor (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
    schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    },
    cursorFailure: @escaping @MainActor (String) -> Void = { _ in }
  ) {
    self.focus = focus
    self.pasteboard = pasteboard
    self.secureInput = secureInput
    self.postEvent = postEvent
    self.schedule = schedule
    self.cursorFailure = cursorFailure
  }
  func readText() -> String? { Self.clipboardText(from: pasteboard) }

  static func clipboardText(from pasteboard: NSPasteboard) -> String? {
    // Finder can supply a display name alongside a file URL. Use the actual
    // path for copied files, without reading files or materializing image data.
    let urls =
      pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    let paths = urls.filter(\.isFileURL).map(\.path)
    if !paths.isEmpty { return paths.joined(separator: "\n") }
    return pasteboard.string(forType: .string)
  }

  func replace(
    keyword: String, with text: String, target: ExpansionTarget, cursorUTF16Offset: Int? = nil
  ) throws {
    try perform(keyword: keyword, text: text, target: target, cursorUTF16Offset: cursorUTF16Offset)
  }

  func replace(
    keyword: String, with text: String, target: ExpansionTarget, cursorUTF16Offset: Int?,
    validate: @MainActor () -> Bool
  ) throws {
    try perform(
      keyword: keyword, text: text, target: target, cursorUTF16Offset: cursorUTF16Offset,
      validate: validate)
  }

  func insert(
    _ expansion: ResolvedExpansion, target: ExpansionTarget, selection: CFRange,
    validate: @escaping @MainActor () -> Bool
  ) throws {
    guard !isBusy else { throw TemplateError.invalid("Another insertion is finishing. Try again.") }
    manualTargetCheck = validate
    do {
      try perform(
        keyword: "", text: expansion.text, target: target,
        cursorUTF16Offset: expansion.cursorUTF16Offset, selectedRange: selection)
    } catch {
      manualTargetCheck = nil
      throw error
    }
  }

  private func perform(
    keyword: String, text: String, target: ExpansionTarget,
    cursorUTF16Offset: Int?, selectedRange: CFRange? = nil,
    validate: @MainActor () -> Bool = { true }
  ) throws {
    guard !isBusy, focus.currentTarget() == target, !secureInput(), validManualTarget, validate()
    else {
      throw TemplateError.invalid(
        "Expansion cancelled because the target changed or another expansion is finishing.")
    }
    // Prepare every event and clipboard representation before deleting the keyword.
    // Consecutive space keystrokes can trigger macOS's double-space period
    // substitution. Paste them literally, preserving template spacing and cursor offsets.
    let usesPasteboard =
      text.count > 200 || text.contains("\n") || text.contains("\r") || text.contains("\t")
      || text.contains("  ")
    var placement: (end: Int, destination: Int, arrows: [CGEvent]?)?
    var relativeArrows: [CGEvent]?
    if let offset = cursorUTF16Offset {
      guard let index = ResolvedExpansion(text: text, cursorUTF16Offset: offset).cursorIndex else {
        throw TemplateError.invalid("The cursor marker must be between complete characters.")
      }
      if index != text.endIndex {
        // AX can position Unicode and multiline text directly. Prepare a fallback
        // for editors that expose a selection but do not let accessibility set it.
        // Never flood a host with thousands of navigation events for a large paste.
        // Long moves require the native accessibility setter below.
        var arrows: [CGEvent]?
        if text[index...].count <= 256 {
          arrows = []
          for _ in text[index...] { arrows! += try keyEvents(123) }
        }
        let range = focus.selectionRange()
        if let range, range.length != 0, selectedRange == nil {
          throw TemplateError.invalid("Expansion cancelled because the selection changed.")
        }
        // A numeric range does not imply that a web editor supports reading text
        // or setting its caret. Use AX positioning only with readable context.
        let readableContext = range.flatMap { range -> String? in
          guard range.location >= keyword.utf16.count else { return nil }
          return focus.text(
            in: CFRange(
              location: range.location - keyword.utf16.count, length: keyword.utf16.count))
        }
        if let range, selectedRange != nil || readableContext == keyword || arrows == nil {
          guard range.location >= keyword.utf16.count else {
            throw TemplateError.invalid(
              "Expansion cancelled because the caret position changed.")
          }
          let start = range.location - keyword.utf16.count
          placement = (start + text.utf16.count, start + offset, arrows)
        } else {
          guard let arrows else {
            throw TemplateError.invalid(
              "This app cannot position the cursor across more than 256 characters. Your keyword was left unchanged."
            )
          }
          relativeArrows = arrows
        }
      }
    }
    var events: [CGEvent] = []
    for _ in keyword {
      events += try keyEvents(51)
    }
    // A cursor-only manual item replaces an existing selection with empty text.
    if text.isEmpty, let selectedRange, selectedRange.length > 0 {
      events += try keyEvents(51)
    }
    if usesPasteboard {
      events += try keyEvents(9, flags: .maskCommand)
    } else {
      // Keep surrogate pairs and composed characters together in each Unicode event.
      for character in text {
        let units = Array(String(character).utf16)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
          throw TemplateError.invalid("macOS could not create insertion events.")
        }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        events += [down, up]
      }
    }
    guard focus.currentTarget() == target, !secureInput(), validManualTarget, validate() else {
      throw TemplateError.invalid("Expansion cancelled because focus changed.")
    }
    if usesPasteboard {
      savedClipboard =
        try pasteboard.pasteboardItems?.map { item in
          var representations: [NSPasteboard.PasteboardType: Data] = [:]
          for type in item.types {
            guard let data = item.data(forType: type) else {
              throw TemplateError.invalid(
                "The clipboard could not be preserved. Your keyword was left unchanged.")
            }
            representations[type] = data
          }
          return representations
        } ?? []
      pasteboard.clearContents()
      guard pasteboard.setString(text, forType: .string) else {
        ownChangeCount = pasteboard.changeCount
        restoreClipboard()
        throw TemplateError.invalid("The expansion could not be written to the clipboard.")
      }
      ownChangeCount = pasteboard.changeCount
    }
    guard focus.currentTarget() == target, !secureInput(), validManualTarget, validate() else {
      restoreClipboard()
      throw TemplateError.invalid("Expansion cancelled because focus changed.")
    }
    if let selectedRange {
      guard let current = focus.selectionRange(), current.location == selectedRange.location,
        current.length == selectedRange.length, validManualTarget
      else {
        restoreClipboard()
        throw TemplateError.invalid("Insertion cancelled because the selection changed.")
      }
    }
    isBusy = true
    if selectedRange != nil { monitorManualInput() }
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
      postEvent(event)
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.restoreClipboard()
      self.restoreWork = nil
      self.isBusy = self.cursorWork != nil
      if !self.isBusy { self.finishManualInput() }
    }
    restoreWork = work
    schedule(usesPasteboard ? 0.3 : 0.04, work)
    if let placement {
      ExpansionDiagnostics.record("Cursor uses readable AX context", processID: target.processID)
      scheduleCursor(
        target: target, end: placement.end, destination: placement.destination,
        text: text, arrows: placement.arrows, generation: cursorGeneration, attempt: 0)
    } else if let relativeArrows {
      ExpansionDiagnostics.record("Cursor uses relative keys", processID: target.processID)
      scheduleRelativeCursor(
        target: target, arrows: relativeArrows, generation: cursorGeneration,
        delay: usesPasteboard ? 0.15 : 0.04)
    }
  }

  /// Hosts without numeric AX ranges can still navigate relative to the inserted text.
  /// Give the host time to consume the insertion; real input invalidates this callback.
  private func scheduleRelativeCursor(
    target: ExpansionTarget, arrows: [CGEvent], generation: Int, delay: TimeInterval
  ) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.cursorGeneration == generation else { return }
      defer { self.cancelCursorPlacement() }
      guard self.focus.currentTarget() == target, !self.secureInput(), self.validManualTarget,
        self.focus.selectionRange().map({ $0.length == 0 }) ?? true
      else { return }
      for event in arrows {
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        self.postEvent(event)
      }
    }
    cursorWork = work
    schedule(delay, work)
  }

  func finish() {
    cancelCursorPlacement()
    restoreWork?.cancel()
    restoreWork = nil
    restoreClipboard()
    isBusy = false
    finishManualInput()
  }

  private func finishManualInput() {
    manualTargetCheck = nil
    for monitor in manualInputMonitors { NSEvent.removeMonitor(monitor) }
    manualInputMonitors = []
  }

  private func monitorManualInput() {
    // Manual insertion must observe interruption even when automatic expansion is paused.
    let mask: NSEvent.EventTypeMask = [
      .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .flagsChanged,
    ]
    let interrupt: (NSEvent) -> Void = { [weak self] event in
      guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.eventMarker else {
        return
      }
      self?.cancelCursorPlacement()
    }
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: interrupt) {
      manualInputMonitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(
      matching: mask,
      handler: { event in
        interrupt(event)
        return event
      })
    {
      manualInputMonitors.append(monitor)
    }
  }

  private var validManualTarget: Bool { manualTargetCheck?() ?? true }

  /// Physical input, focus changes, pause, and index changes must never be
  /// followed by a delayed cursor move from an earlier expansion.
  func cancelCursorPlacement() {
    cursorGeneration += 1
    cursorWork?.cancel()
    cursorWork = nil
    isBusy = restoreWork != nil
    if !isBusy { finishManualInput() }
  }

  private func scheduleCursor(
    target: ExpansionTarget, end: Int, destination: Int,
    text: String, arrows: [CGEvent]?, generation: Int, attempt: Int
  ) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.cursorGeneration == generation else { return }
      guard self.focus.currentTarget() == target, !self.secureInput(), self.validManualTarget else {
        self.cancelCursorPlacement()
        return
      }
      // Equal-length replacements can leave the caret unchanged. Confirm the
      // inserted span too, rather than mistaking the original keyword for completion.
      let insertedRange = CFRange(location: end - text.utf16.count, length: text.utf16.count)
      let insertedText = self.focus.text(in: insertedRange)
      if let range = self.focus.selectionRange(), range.length == 0, range.location == end,
        insertedText == text
      {
        // Web editors can report a successful AX write without moving the caret.
        // Prefer keyboard navigation for bounded moves, even with readable AX text.
        if let arrows {
          guard self.focus.currentTarget() == target, !self.secureInput(), self.validManualTarget,
            let range = self.focus.selectionRange(), range.length == 0, range.location == end
          else {
            self.cancelCursorPlacement()
            return
          }
          for event in arrows {
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
            self.postEvent(event)
          }
        } else if !self.focus.moveCaret(to: destination) {
          self.cancelCursorPlacement()
          self.cursorFailure(
            "Text was inserted, but this app doesn’t support this long caret move. Place the caret manually."
          )
          return
        }
        self.cancelCursorPlacement()
      } else if insertedText == nil, attempt >= 14, let arrows {
        // Some editors expose the keyword but stop exposing text after the paste
        // rebuilds their editing node. Do not strand the cursor on a partial API.
        ExpansionDiagnostics.record(
          "AX cursor read unavailable; using keys", processID: target.processID)
        self.scheduleRelativeCursor(
          target: target, arrows: arrows, generation: generation, delay: 0.01)
      } else if attempt < 29 {
        self.scheduleCursor(
          target: target, end: end, destination: destination,
          text: text, arrows: arrows, generation: generation, attempt: attempt + 1)
      } else {
        self.cancelCursorPlacement()
        self.cursorFailure(
          "Text was inserted, but the app didn’t confirm its final caret position. Place the caret manually."
        )
      }
    }
    cursorWork = work
    schedule(0.01, work)
  }

  private func restoreClipboard() {
    defer {
      savedClipboard = nil
      ownChangeCount = nil
    }
    guard let savedClipboard, ownChangeCount == pasteboard.changeCount else { return }
    let items = savedClipboard.map { representations in
      let item = NSPasteboardItem()
      for (type, data) in representations { item.setData(data, forType: type) }
      return item
    }
    pasteboard.clearContents()
    if !items.isEmpty { pasteboard.writeObjects(items) }
  }

  private func keyEvents(_ key: CGKeyCode, flags: CGEventFlags = []) throws -> [CGEvent] {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
    else {
      throw TemplateError.invalid("macOS could not create insertion events.")
    }
    down.flags = flags
    up.flags = flags
    return [down, up]
  }
}
