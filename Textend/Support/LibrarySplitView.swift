import AppKit
import SwiftUI

/// AppKit owns panel geometry and toolbar tracking; the hosted SwiftUI views own content and drafts.
struct LibrarySplitView: NSViewControllerRepresentable {
  var state: AppState
  var canSave: Bool
  @Environment(\.textendAccent) private var accent

  func makeNSViewController(context: Context) -> PinnedContentController<LibrarySplitController> {
    PinnedContentController(content: LibrarySplitController(state: state))
  }

  func updateNSViewController(
    _ controller: PinnedContentController<LibrarySplitController>, context: Context
  ) {
    controller.content.saveItem?.isEnabled = canSave
    controller.content.toolbarAccent = accent.nsColor
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    nsViewController: PinnedContentController<LibrarySplitController>, context: Context
  ) -> CGSize? {
    // The window determines the outer size. Pane holding constraints must not negotiate it.
    guard let width = proposal.width, let height = proposal.height,
      width.isFinite, height.isFinite
    else { return nil }
    return CGSize(width: width, height: height)
  }
}

@MainActor final class LibrarySplitController: NSSplitViewController, NSToolbarDelegate {
  private let state: AppState
  private(set) weak var saveItem: SaveSnippetToolbarItem?
  private weak var newItemButton: NSPopUpButton?
  var toolbarAccent: NSColor? {
    didSet { newItemButton?.contentTintColor = toolbarAccent }
  }
  private var libraryToolbar: NSToolbar?
  private static let sidebarDivider = NSToolbarItem.Identifier("textend.sidebarDivider")
  private static let listDivider = NSToolbarItem.Identifier("textend.listDivider")
  private static let libraryTitle = NSToolbarItem.Identifier("textend.libraryTitle")
  private static let snippetSort = NSToolbarItem.Identifier("textend.snippetSort")
  private static let snippetTitle = NSToolbarItem.Identifier("textend.snippetTitle")
  private static let newSnippet = NSToolbarItem.Identifier("textend.newSnippet")
  private static let saveSnippet = NSToolbarItem.Identifier("textend.saveSnippet")

  init(state: AppState) {
    self.state = state
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("Use init(state:)") }

  private func makeNewItemButton() -> NSPopUpButton {
    let newItemButton = NSPopUpButton(frame: .zero, pullsDown: true)
    newItemButton.bezelStyle = .texturedRounded
    newItemButton.contentTintColor = toolbarAccent
    newItemButton.imagePosition = .imageOnly
    newItemButton.addItem(withTitle: "New")
    newItemButton.item(at: 0)?.image = NSImage(
      systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
    for (title, action) in [
      ("New Snippet", #selector(newSnippet)), ("New Composition", #selector(newComposition)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      newItemButton.menu?.addItem(item)
    }
    newItemButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
    newItemButton.setAccessibilityLabel("New Snippet or Composition")
    return newItemButton
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    splitView.isVertical = true
    splitView.dividerStyle = .thin
    // Keep persisted panel widths across the project rename.
    splitView.autosaveName = "TapsterLibraryPanels"

    let sidebar = NSSplitViewItem(sidebarWithViewController: host(SidebarView(state: state)))
    sidebar.minimumThickness = 170
    sidebar.maximumThickness = 260
    sidebar.holdingPriority = .init(260)
    sidebar.canCollapseFromWindowResize = false
    sidebar.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
    sidebar.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
    addSplitViewItem(sidebar)

    let list = NSSplitViewItem(contentListWithViewController: host(SnippetListView(state: state)))
    list.minimumThickness = 280
    list.maximumThickness = 400
    list.holdingPriority = .init(260)
    list.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
    addSplitViewItem(list)

    let editor = NSSplitViewItem(viewController: host(SnippetDetailView(state: state)))
    editor.minimumThickness = 380
    editor.holdingPriority = .init(240)
    addSplitViewItem(editor)

    let preview = NSSplitViewItem(viewController: host(SnippetPreviewPanel(state: state)))
    preview.minimumThickness = 240
    preview.maximumThickness = 340
    preview.holdingPriority = .init(270)
    addSplitViewItem(preview)

    // Seed the pane sizes; AppKit owns subsequent resizing and divider restoration.
    sidebar.viewController.view.setFrameSize(NSSize(width: 190, height: 600))
    list.viewController.view.setFrameSize(NSSize(width: 280, height: 600))
    editor.viewController.view.setFrameSize(NSSize(width: 600, height: 600))
    preview.viewController.view.setFrameSize(NSSize(width: 270, height: 600))
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    guard let window = view.window else { return }
    if libraryToolbar == nil {
      let toolbar = NSToolbar(identifier: "TapsterLibraryToolbar")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = false
      libraryToolbar = toolbar
    }
    guard window.toolbar !== libraryToolbar else { return }
    window.titleVisibility = .hidden
    window.toolbarStyle = .unified
    window.toolbar = libraryToolbar
  }

  private func host<Content: View>(_ content: Content) -> NSHostingController<some View> {
    let controller = NSHostingController(rootView: content.textendTheme())
    controller.sizingOptions = []
    return controller
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [
      .toggleSidebar, Self.sidebarDivider, Self.libraryTitle, .flexibleSpace,
      Self.snippetSort, Self.listDivider,
      Self.snippetTitle, .flexibleSpace, Self.newSnippet, Self.saveSnippet,
    ]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch identifier {
    case Self.sidebarDivider:
      return NSTrackingSeparatorToolbarItem(
        identifier: identifier, splitView: splitView, dividerIndex: 0)
    case Self.listDivider:
      return NSTrackingSeparatorToolbarItem(
        identifier: identifier, splitView: splitView, dividerIndex: 1)
    case Self.libraryTitle:
      return hostedItem(
        identifier, label: "Collection", content: LibraryHeaderView(state: state),
        minimum: 40, preferred: 120, maximum: 240)
    case Self.snippetSort:
      return hostedItem(
        identifier, label: "Sort", content: SnippetSortMenu(state: state),
        minimum: 24, preferred: 24, maximum: 24)
    case Self.snippetTitle:
      return hostedItem(
        identifier, label: "Snippet", content: SnippetHeaderView(state: state),
        minimum: 100, preferred: 260, maximum: 400)
    case Self.saveSnippet:
      // AppKit can request an identifier again while loading a sheet's toolbar.
      // Each request must get a new item, never an instance owned by a toolbar.
      let item = SaveSnippetToolbarItem(identifier: identifier, state: state)
      item.label = "Save"
      item.toolTip = "Save (⌘S)"
      // The title convenience initializer calls sizeToFit, which can reenter
      // SwiftUI's sheet toolbar updates before AppKit finishes loading its items.
      let saveButton = NSButton(frame: .zero)
      saveButton.title = "Save"
      saveButton.bezelStyle = .texturedRounded
      saveButton.target = self
      saveButton.action = #selector(save)
      saveButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
      item.view = saveButton
      item.visibilityPriority = .high
      item.validate()
      if flag && toolbar === libraryToolbar { saveItem = item }
      return item
    case Self.newSnippet:
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.label = "New"
      item.toolTip = "New Snippet or Composition"
      let button = makeNewItemButton()
      item.view = button
      item.visibilityPriority = .high
      if flag && toolbar === libraryToolbar { newItemButton = button }
      return item
    case .toggleSidebar:
      let item = NSToolbarItem(itemIdentifier: identifier)
      item.target = self
      item.action = #selector(toggleSidebar(_:))
      return item
    default: return nil
    }
  }

  private func hostedItem<Content: View>(
    _ identifier: NSToolbarItem.Identifier, label: String,
    content: Content, minimum: CGFloat, preferred: CGFloat, maximum: CGFloat
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = label
    let view = NSHostingView(rootView: content.textendTheme())
    view.sizingOptions = []
    let preferredWidth = view.widthAnchor.constraint(equalToConstant: preferred)
    preferredWidth.priority = .defaultLow
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(greaterThanOrEqualToConstant: minimum),
      view.widthAnchor.constraint(lessThanOrEqualToConstant: maximum),
      view.heightAnchor.constraint(equalToConstant: 36), preferredWidth,
    ])
    item.view = view
    item.visibilityPriority = .high
    if #available(macOS 26.0, *) { item.isBordered = false }
    return item
  }

  @objc private func newSnippet() { state.newSnippet() }
  @objc private func newComposition() { state.newComposition() }
  @objc private func save() { state.save() }
}

@MainActor final class SaveSnippetToolbarItem: NSToolbarItem {
  private let state: AppState

  init(identifier: NSToolbarItem.Identifier, state: AppState) {
    self.state = state
    super.init(itemIdentifier: identifier)
  }

  override func validate() {
    isEnabled = state.isDirty && state.draftError == nil
  }
}
