import AppKit
import XCTest

@testable import TextendCore

final class InsertionTests: XCTestCase {
  @MainActor func testInputDuringInsertionPreparationLeavesKeywordAndClipboardIntact() throws {
    for invalidatedOnCheck in 1...3 {
      let h = CursorHarness()
      defer { h.stop() }
      var checks = 0
      XCTAssertThrowsError(
        try h.service.replace(
          keyword: "gc", with: "First line\nSecond line", target: h.target,
          cursorUTF16Offset: nil,
          validate: {
            checks += 1
            return checks < invalidatedOnCheck
          }))
      XCTAssertTrue(h.keys.isEmpty)
      XCTAssertFalse(h.service.isBusy)
      XCTAssertEqual(h.pasteboard.string(forType: .string), "Original clipboard")
    }
  }

  @MainActor func testClipboardFilesResolveToLiteralPathsAndPreserveRepresentations() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let paths = ["/tmp/Test image {one}.png", "/tmp/Café #2.jpg"]
    XCTAssertTrue(pasteboard.writeObjects([URL(fileURLWithPath: paths[0]) as NSURL]))
    XCTAssertEqual(TextInsertionService.clipboardText(from: pasteboard), paths[0])
    pasteboard.clearContents()
    let items = paths.map { path in
      let item = NSPasteboardItem()
      item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
      item.setString(URL(fileURLWithPath: path).lastPathComponent, forType: .string)
      return item
    }
    XCTAssertTrue(pasteboard.writeObjects(items))
    let originalChangeCount = pasteboard.changeCount
    let focus = Focus()
    let service = TextInsertionService(
      focus: focus, pasteboard: pasteboard, secureInput: { false }, postEvent: { _ in })
    defer { service.finish() }
    XCTAssertEqual(service.readText(), paths.joined(separator: "\n"))
    XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
    let snippet = SnippetRecord(
      name: "Files", keyword: "files", template: "Files:\n{clipboard}",
      placeholders: [PlaceholderDefinition(name: "clipboard")])
    let result = try TemplateResolver.resolve(snippet, clipboard: service.readText())
    XCTAssertEqual(result, "Files:\n" + paths.joined(separator: "\n"))
    try service.replace(keyword: "files", with: result, target: XCTUnwrap(focus.value))
    service.finish()
    XCTAssertEqual(service.readText(), paths.joined(separator: "\n"))
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
    XCTAssertEqual(
      pasteboard.pasteboardItems?.first?.string(forType: .string), "Test image {one}.png")
  }

  @MainActor func testManualCursorReplacesSelectionAndCancelsOnElementChange() throws {
    for changesElement in [false, true] {
      let h = CursorHarness()
      defer { h.stop() }
      h.focus.range = CFRange(location: 2, length: 5)
      h.focus.fieldText = "hiWORLD!"
      var sameElement = true
      try h.service.insert(
        .init(text: "a\nB", cursorUTF16Offset: 1), target: h.target,
        selection: XCTUnwrap(h.focus.range), validate: { sameElement })
      XCTAssertFalse(h.keys.contains(51))
      h.focus.fieldText = "hia\nB!"
      h.focus.range = CFRange(location: 5, length: 0)
      sameElement = !changesElement
      h.tick()
      XCTAssertEqual(h.keys.filter { $0 == 123 }.count, changesElement ? 0 : 4)
    }
  }

  @MainActor func testCursorOnlyManualItemDeletesOnlyAnExistingSelection() throws {
    for length in [0, 5] {
      let h = CursorHarness()
      defer { h.stop() }
      h.focus.range = CFRange(location: 2, length: length)
      try h.service.insert(
        .init(text: "", cursorUTF16Offset: 0), target: h.target,
        selection: XCTUnwrap(h.focus.range), validate: { true })
      XCTAssertEqual(h.keys, length == 0 ? [] : [51, 51])
    }
  }

  @MainActor func testCompositionSpaceBesideCursorPreservesTextDuringBothInsertionPaths() throws {
    let first = SnippetRecord(name: "Comp One", template: "Comp one {cursor}")
    let second = SnippetRecord(name: "Comp Two", template: "and a second comp.")
    let composition = SnippetRecord(
      name: "Composition", keyword: "gc",
      blocks: [.init(snippetID: first.id, separator: .space), .init(snippetID: second.id)])
    let library = ExpansionLibrary(items: [first, second, composition])
    let result = try library.resolve(composition, clipboard: nil)
    XCTAssertEqual(result.text, "Comp one  and a second comp.")
    XCTAssertEqual(result.cursorUTF16Offset, 9)

    for manual in [false, true] {
      let h = CursorHarness()
      defer { h.stop() }
      let html = Data("<b>Original clipboard</b>".utf8)
      h.pasteboard.setData(html, forType: .html)
      if manual {
        h.focus.range = CFRange(location: 0, length: 2)
        try h.service.insert(
          result, target: h.target, selection: XCTUnwrap(h.focus.range), validate: { true })
      } else {
        try h.service.replace(
          keyword: composition.keyword, with: result.text, target: h.target,
          cursorUTF16Offset: result.cursorUTF16Offset)
      }
      // Pasting preserves adjacent spaces instead of typing macOS's double-space shortcut.
      XCTAssertEqual(h.keys, manual ? [9, 9] : [51, 51, 51, 51, 9, 9])
      XCTAssertTrue(h.flags.suffix(2).allSatisfy { $0.contains(.maskCommand) })
      XCTAssertEqual(h.pasteboard.string(forType: .string), result.text)
      h.tick()
      XCTAssertFalse(h.keys.contains(123), "Wait until the host consumes the paste.")
      h.focus.fieldText = result.text
      h.focus.range = CFRange(location: result.text.utf16.count, length: 0)
      h.tick()
      XCTAssertEqual(
        h.keys.filter { $0 == 123 }.count, " and a second comp.".count * 2,
        "Place the caret between the source's trailing space and the separator.")
      XCTAssertTrue(h.failures.isEmpty)
      XCTAssertTrue(h.markers.allSatisfy { $0 == TextInsertionService.eventMarker })
      let restore = try XCTUnwrap(h.jobs.first(where: { $0.0 == 0.3 })?.1)
      restore.perform()
      XCTAssertEqual(h.pasteboard.string(forType: .string), "Original clipboard")
      XCTAssertEqual(h.pasteboard.data(forType: .html), html)
      XCTAssertFalse(h.service.isBusy)
    }
  }

  @MainActor func testClipboardTextAndImagesWithoutFileReferences() {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("https://example.com/image.png", forType: .string)
    XCTAssertEqual(
      TextInsertionService.clipboardText(from: pasteboard), "https://example.com/image.png")
    pasteboard.clearContents()
    let png = Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII="
    )!
    XCTAssertTrue(pasteboard.setData(png, forType: .png))
    XCTAssertTrue(pasteboard.types?.contains(.png) == true)
    XCTAssertNil(TextInsertionService.clipboardText(from: pasteboard))
    pasteboard.clearContents()
    XCTAssertNil(TextInsertionService.clipboardText(from: pasteboard))
  }

  @MainActor final class Focus: ExpansionFocus {
    var value: ExpansionTarget? = ExpansionTarget(processID: 1, focusID: "test")
    var range: CFRange?
    var fieldText: String?
    var moves: [Int] = []
    var acceptsCaretMove = true
    func currentTarget() -> ExpansionTarget? { value }
    func selectionRange() -> CFRange? { range }
    func text(in range: CFRange) -> String? {
      guard let text = fieldText as NSString?, range.location >= 0,
        range.location + range.length <= text.length
      else { return nil }
      return text.substring(with: NSRange(location: range.location, length: range.length))
    }
    func moveCaret(to location: Int) -> Bool {
      guard acceptsCaretMove else { return false }
      moves.append(location)
      range = CFRange(location: location, length: 0)
      return true
    }
  }

  @MainActor func testClipboardRestoresAllRepresentationsWithoutReturnEvent() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let item = NSPasteboardItem()
    let html = Data("<b>Original</b>".utf8)
    item.setString("Original", forType: .string)
    item.setData(html, forType: .html)
    pasteboard.writeObjects([item])
    let focus = Focus()
    var keys: [Int64] = []
    let service = TextInsertionService(
      focus: focus, pasteboard: pasteboard, secureInput: { false },
      postEvent: {
        keys.append($0.getIntegerValueField(.keyboardEventKeycode))
        XCTAssertEqual(
          $0.getIntegerValueField(.eventSourceUserData), TextInsertionService.eventMarker)
      })
    defer { service.finish() }
    try service.replace(keyword: "gc", with: "Line one\nLine two", target: XCTUnwrap(focus.value))
    XCTAssertEqual(pasteboard.string(forType: .string), "Line one\nLine two")
    XCTAssertFalse(keys.contains(36))
    service.finish()
    XCTAssertEqual(pasteboard.string(forType: .string), "Original")
    XCTAssertEqual(pasteboard.data(forType: .html), html)
  }

  @MainActor func testNewUserCopyIsNeverOverwritten() throws {
    for text in ["First\nSecond", "First  Second"] {
      let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
      defer { pasteboard.releaseGlobally() }
      pasteboard.setString("Original", forType: .string)
      let focus = Focus()
      let service = TextInsertionService(
        focus: focus, pasteboard: pasteboard, secureInput: { false }, postEvent: { _ in })
      defer { service.finish() }
      try service.replace(keyword: "x", with: text, target: XCTUnwrap(focus.value))
      XCTAssertEqual(pasteboard.string(forType: .string), text)
      pasteboard.clearContents()
      pasteboard.setString("New user copy", forType: .string)
      service.finish()
      XCTAssertEqual(pasteboard.string(forType: .string), "New user copy")
    }
  }

  @MainActor func testChangedFocusAndSecureInputPreventInsertion() throws {
    let focus = Focus()
    let target = try XCTUnwrap(focus.value)
    var count = 0
    let service = TextInsertionService(
      focus: focus, secureInput: { false }, postEvent: { _ in count += 1 })
    focus.value = nil
    XCTAssertThrowsError(try service.replace(keyword: "gc", with: "Hello", target: target))
    XCTAssertEqual(count, 0)
    focus.value = target
    let secure = TextInsertionService(
      focus: focus, secureInput: { true }, postEvent: { _ in count += 1 })
    XCTAssertThrowsError(try secure.replace(keyword: "gc", with: "Hello", target: target))
    XCTAssertEqual(count, 0)
  }

  @MainActor func testCursorWaitsForInsertionThenMovesByCompleteCharacters() throws {
    let h = CursorHarness()
    defer { h.stop() }
    let text = "👩🏽‍💻\nhello"
    h.focus.range = CFRange(location: 12, length: 0)
    h.focus.fieldText = String(repeating: " ", count: 10) + "gc"
    try h.service.replace(
      keyword: "gc", with: text, target: h.target,
      cursorUTF16Offset: "👩🏽‍💻\n".utf16.count)
    XCTAssertEqual(h.pasteboard.string(forType: .string), text)
    h.tick()
    XCTAssertTrue(h.focus.moves.isEmpty, "Pasting may not have been consumed yet.")
    XCTAssertFalse(h.keys.contains(123))
    h.focus.range = CFRange(location: 10 + text.utf16.count, length: 0)
    h.focus.fieldText = String(repeating: " ", count: 10) + text
    h.tick()
    XCTAssertTrue(h.focus.moves.isEmpty)
    XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 10, "Move left over hello after delivery.")
    XCTAssertFalse(h.keys.contains(36))
    h.service.finish()
    XCTAssertEqual(h.pasteboard.string(forType: .string), "Original clipboard")
  }

  @MainActor func testCursorFallbackCountsCompleteCharactersAndTagsEvents() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.acceptsCaretMove = false
    let text = "A👩🏽‍💻e\u{301}"
    try h.service.replace(keyword: "gc", with: text, target: h.target, cursorUTF16Offset: 1)
    h.focus.range = CFRange(location: text.utf16.count, length: 0)
    h.focus.fieldText = text
    h.tick()
    XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 4, "Two complete characters, down/up each.")
    XCTAssertTrue(h.markers.allSatisfy { $0 == TextInsertionService.eventMarker })
  }

  @MainActor func testCursorCancellationRejectsStaleCallbacksAndNewTargets() throws {
    for reason in ["input", "focus", "secure", "finish"] {
      let h = CursorHarness()
      defer { h.stop() }
      try h.service.replace(keyword: "gc", with: "hello", target: h.target, cursorUTF16Offset: 2)
      h.focus.range = CFRange(location: 5, length: 0)
      h.focus.fieldText = "hello"
      switch reason {
      case "input": h.service.cancelCursorPlacement()
      case "focus": h.focus.value = ExpansionTarget(processID: 2, focusID: "other")
      case "secure": h.secure = true
      default: h.service.finish()
      }
      let keyCount = h.keys.count
      h.tick()
      XCTAssertTrue(h.focus.moves.isEmpty, reason)
      XCTAssertEqual(h.keys.count, keyCount, reason)
    }
  }

  @MainActor func testCursorTimeoutReportsWithoutMovingAndPreservesNewCopy() throws {
    let h = CursorHarness()
    defer { h.stop() }
    try h.service.replace(keyword: "gc", with: "A\nB", target: h.target, cursorUTF16Offset: 1)
    h.focus.range = CFRange(location: 20, length: 0)  // Host added unexpected text.
    h.focus.fieldText = String(repeating: "x", count: 20)
    h.pasteboard.clearContents()
    h.pasteboard.setString("New copy", forType: .string)
    for _ in 0..<30 { h.tick() }
    XCTAssertEqual(h.failures.count, 1)
    XCTAssertTrue(h.focus.moves.isEmpty)
    XCTAssertFalse(h.keys.contains(123))
    h.service.finish()
    XCTAssertEqual(h.pasteboard.string(forType: .string), "New copy")
  }

  @MainActor func testEqualLengthReplacementRequiresConfirmedText() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.fieldText = "gc"
    try h.service.replace(keyword: "gc", with: "ab", target: h.target, cursorUTF16Offset: 1)
    h.tick()
    XCTAssertTrue(h.focus.moves.isEmpty)
    XCTAssertFalse(h.keys.contains(123))
    h.focus.fieldText = "ab"
    h.tick()
    XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 2)
    XCTAssertTrue(h.focus.moves.isEmpty)
  }

  @MainActor func testLongCursorMoveUsesAXWithoutFloodingHostWithArrows() throws {
    for acceptsAX in [true, false] {
      let h = CursorHarness()
      defer { h.stop() }
      h.focus.acceptsCaretMove = acceptsAX
      let text = String(repeating: "x", count: 300)
      try h.service.replace(keyword: "gc", with: text, target: h.target, cursorUTF16Offset: 0)
      h.focus.range = CFRange(location: 300, length: 0)
      h.focus.fieldText = text
      h.tick()
      XCTAssertEqual(h.focus.moves, acceptsAX ? [0] : [])
      XCTAssertEqual(h.failures.count, acceptsAX ? 0 : 1)
      XCTAssertFalse(h.keys.contains(123))
    }
  }

  @MainActor func testEndMarkerNeedsNoMoveAndInvalidMarkerCannotDeleteKeyword() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.range = nil
    try h.service.replace(
      keyword: "gc", with: "git commit ", target: h.target, cursorUTF16Offset: 11)
    XCTAssertFalse(h.jobs.contains { $0.0 == 0.01 })
    XCTAssertFalse(h.keys.contains(9), "A single trailing space still uses Unicode insertion.")
    XCTAssertEqual(h.pasteboard.string(forType: .string), "Original clipboard")
    h.service.finish()
    let count = h.keys.count
    for offset in [-1, 1, 4] {
      XCTAssertThrowsError(
        try h.service.replace(
          keyword: "gc", with: "😀", target: h.target,
          cursorUTF16Offset: offset))
    }
    XCTAssertEqual(h.keys.count, count)
  }

  @MainActor func testCursorWithoutAXRangeUsesBoundedRelativeNavigation() throws {
    for text in ["A👩🏽‍💻e\u{301}", "A\nB"] {
      let h = CursorHarness()
      defer { h.stop() }
      h.focus.range = nil
      try h.service.replace(keyword: "gc", with: text, target: h.target, cursorUTF16Offset: 1)
      XCTAssertFalse(h.keys.contains(123))
      let delay = text.contains("\n") ? 0.15 : 0.04
      let work = try XCTUnwrap(h.jobs.last(where: { $0.0 == delay })?.1)
      work.perform()
      XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 4)
      XCTAssertTrue(h.markers.allSatisfy { $0 == TextInsertionService.eventMarker })
      XCTAssertTrue(h.focus.moves.isEmpty)
    }
  }

  @MainActor func testNumericRangeWithoutReadableTextStillPlacesCursor() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.fieldText = nil
    h.focus.range = CFRange(location: 2, length: 0)
    try h.service.replace(keyword: "gc", with: "A\nB", target: h.target, cursorUTF16Offset: 1)
    let work = try XCTUnwrap(h.jobs.first(where: { $0.0 == 0.15 })?.1)
    work.perform()
    XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 4)
    XCTAssertTrue(h.focus.moves.isEmpty)
    XCTAssertTrue(h.failures.isEmpty)
  }

  @MainActor func testCursorFallsBackWhenEditorStopsExposingTextAfterInsertion() throws {
    let h = CursorHarness()
    defer { h.stop() }
    try h.service.replace(keyword: "gc", with: "A\nB", target: h.target, cursorUTF16Offset: 1)
    h.focus.fieldText = nil
    for _ in 0..<16 { h.tick() }
    XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 4)
    XCTAssertTrue(h.failures.isEmpty)
  }

  @MainActor func testRelativeCursorCancelsOnInputFocusSecureInputAndSelection() throws {
    for reason in ["input", "focus", "secure", "selection", "finish"] {
      let h = CursorHarness()
      defer { h.stop() }
      h.focus.range = nil
      try h.service.replace(keyword: "gc", with: "A\nB", target: h.target, cursorUTF16Offset: 1)
      let work = try XCTUnwrap(h.jobs.first(where: { $0.0 == 0.15 })?.1)
      switch reason {
      case "input": h.service.cancelCursorPlacement()
      case "focus": h.focus.value = nil
      case "secure": h.secure = true
      case "selection": h.focus.range = CFRange(location: 0, length: 2)
      default: h.service.finish()
      }
      work.perform()
      XCTAssertFalse(h.keys.contains(123), reason)
    }
  }

  @MainActor func testLongRelativeCursorMoveLeavesKeywordAndClipboardUntouched() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.range = nil
    XCTAssertThrowsError(
      try h.service.replace(
        keyword: "gc", with: String(repeating: "x", count: 300), target: h.target,
        cursorUTF16Offset: 0))
    XCTAssertTrue(h.keys.isEmpty)
    XCTAssertEqual(h.pasteboard.string(forType: .string), "Original clipboard")
  }
}

@MainActor private final class CursorHarness {
  let focus = InsertionTests.Focus()
  let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
  var target: ExpansionTarget { focus.value! }
  var secure = false
  var keys: [Int64] = []
  var markers: [Int64] = []
  var flags: [CGEventFlags] = []
  var jobs: [(TimeInterval, DispatchWorkItem)] = []
  var failures: [String] = []
  lazy var service = TextInsertionService(
    focus: focus, pasteboard: pasteboard,
    secureInput: { [unowned self] in secure },
    postEvent: { [unowned self] event in
      keys.append(event.getIntegerValueField(.keyboardEventKeycode))
      markers.append(event.getIntegerValueField(.eventSourceUserData))
      flags.append(event.flags)
    }, schedule: { [unowned self] delay, work in jobs.append((delay, work)) },
    cursorFailure: { [unowned self] in failures.append($0) })

  init() {
    focus.range = CFRange(location: 2, length: 0)
    focus.fieldText = "gc"
    pasteboard.setString("Original clipboard", forType: .string)
  }
  func tick() {
    guard let index = jobs.firstIndex(where: { $0.0 == 0.01 }) else {
      XCTFail("Missing cursor callback")
      return
    }
    jobs.remove(at: index).1.perform()
  }
  func stop() {
    service.finish()
    jobs.removeAll()
    pasteboard.releaseGlobally()
  }
}
