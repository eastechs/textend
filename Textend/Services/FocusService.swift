import AppKit
import ApplicationServices
import Carbon

@MainActor final class FocusService: ExpansionFocus {
  struct Application {
    var processID: Int32
    var bundleID: String?
  }

  struct Snapshot {
    let target: ExpansionTarget
    let bundleID: String?
    let element: AXUIElement
    let selection: CFRange
  }

  func capture() -> Snapshot? {
    guard let target = currentTarget(), let element = focusedElement,
      let selection = selectionRange(),
      let role = attribute(element, kAXRoleAttribute) as? String,
      [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
      attribute(element, kAXEnabledAttribute) as? Bool != false
    else { return nil }
    return Snapshot(
      target: target, bundleID: application()?.bundleID, element: element, selection: selection)
  }

  func matches(_ snapshot: Snapshot, selection: Bool) -> Bool {
    guard currentTarget() == snapshot.target, let element = focusedElement,
      CFEqual(element, snapshot.element)
    else { return false }
    if selection {
      guard let range = selectionRange() else { return false }
      return range.location == snapshot.selection.location
        && range.length == snapshot.selection.length
    }
    return true
  }

  private let application: @MainActor () -> Application?
  private let attribute: @MainActor (AXUIElement, String) -> CFTypeRef?
  private let stringForRange: @MainActor (AXUIElement, CFRange) -> String?
  private let ownBundleID: String?
  private var processID: Int32?
  private var focusedWindow: AXUIElement?
  private var focusedElement: AXUIElement?
  private var token = UUID().uuidString
  private var reportedAXAvailability: Bool?

  init(
    application: @escaping @MainActor () -> Application? = {
      NSWorkspace.shared.frontmostApplication.map {
        Application(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier)
      }
    },
    attribute: @escaping @MainActor (AXUIElement, String) -> CFTypeRef? = { element, name in
      var value: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
      }
      return value
    },
    stringForRange: @escaping @MainActor (AXUIElement, CFRange) -> String? = { element, range in
      var range = range
      guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
      var value: CFTypeRef?
      guard
        AXUIElementCopyParameterizedAttributeValue(
          element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value)
          == .success
      else { return nil }
      return value as? String
    }, ownBundleID: String? = Bundle.main.bundleIdentifier
  ) {
    self.application = application
    self.attribute = attribute
    self.stringForRange = stringForRange
    self.ownBundleID = ownBundleID
  }

  func currentTarget() -> ExpansionTarget? {
    guard let application = application() else {
      focusedElement = nil
      focusedWindow = nil
      processID = nil
      return nil
    }
    let app = AXUIElementCreateApplication(application.processID)
    AXUIElementSetMessagingTimeout(app, 0.015)
    let element = elementAttribute(app, kAXFocusedUIElementAttribute)
    focusedElement = element
    if let element { AXUIElementSetMessagingTimeout(element, 0.015) }
    if let bundleID = application.bundleID,
      bundleID == ownBundleID || BuildIdentity.applicationBundleIDs.contains(bundleID)
    {
      guard let element,
        attribute(element, kAXIdentifierAttribute) as? String == "textend-expansion-test"
      else { return nil }
    }
    if let element,
      attribute(element, kAXSubroleAttribute) as? String == "AXSecureTextField"
    {
      return nil
    }

    // Rich editors may expose no focused element or recreate it while typing.
    // Anchor the typing run to the application/window instead. Mouse, navigation,
    // and shortcut events still invalidate the run in ExpansionEngine.
    let window = elementAttribute(app, kAXFocusedWindowAttribute)
    let changedApplication = processID != application.processID
    let changedWindow =
      focusedWindow.map { old in window.map { !CFEqual(old, $0) } ?? false } ?? false
    if changedApplication || changedWindow {
      token = UUID().uuidString
      focusedWindow = window
      reportedAXAvailability = nil
    } else if let window {
      focusedWindow = window
    }
    processID = application.processID
    if reportedAXAvailability != (element != nil) {
      reportedAXAvailability = element != nil
      ExpansionDiagnostics.record(
        element == nil ? "Using keyboard context without AX focus" : "AX focus available",
        processID: application.processID)
    }
    return ExpansionTarget(processID: application.processID, focusID: token)
  }

  private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
      return nil
    }
    return (value as! AXUIElement)
  }

  /// Only inspect the adjacent character and selection, never the document value.
  func startsAtBoundary(beforeUTF16Count length: Int = 0) -> Bool? {
    guard let range = selectionRange(), length >= 0, range.location >= length else { return nil }
    guard range.length == 0 else { return false }
    let start = range.location - length
    if start == 0 { return true }
    guard let text = text(in: CFRange(location: start - 1, length: 1)), let character = text.last
    else { return nil }
    return !character.isLetter && !character.isNumber && character != "_"
  }

  func selectionRange() -> CFRange? {
    guard let element = focusedElement else { return nil }
    guard let rawRange = attribute(element, kAXSelectedTextRangeAttribute),
      CFGetTypeID(rawRange) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range),
      range.location >= 0, range.length >= 0, range.location != kCFNotFound
    else { return nil }
    return range
  }

  static var secureInputEnabled: Bool { IsSecureEventInputEnabled() }

  func moveCaret(to location: Int) -> Bool {
    guard let element = focusedElement, location >= 0 else { return false }
    var range = CFRange(location: location, length: 0)
    guard let value = AXValueCreate(.cfRange, &range) else { return false }
    return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
      == .success
  }

  /// Read only the span just inserted by Textend to confirm paste consumption.
  func text(in range: CFRange) -> String? {
    guard let element = focusedElement else { return nil }
    return stringForRange(element, range)
  }

  static var supportsCurrentInputSource: Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
    else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue())
  }
}
