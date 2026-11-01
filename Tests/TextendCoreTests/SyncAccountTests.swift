import CloudKit
import XCTest

@testable import TextendCore

final class SyncAccountTests: XCTestCase {
  @MainActor func testAvailabilityNotificationsKeepPreferenceAndLibrary() async throws {
    for account in [CloudAccount.available("account-a"), .unavailable("Temporarily unavailable")] {
      let h = try SyncAccountHarness()
      defer { h.stop() }
      try await h.open()
      let original = h.sync.configuration
      let originalArchive = try XCTUnwrap(h.store).archive
      let checked = expectation(description: "Notification rechecks the account")
      h.provider.onRead = { checked.fulfill() }
      h.provider.account = account
      h.center.post(name: .CKAccountChanged, object: nil)
      await fulfillment(of: [checked], timeout: 1)

      XCTAssertEqual(h.sync.account, account)
      XCTAssertTrue(h.sync.isActive)
      XCTAssertTrue(h.sync.isEnabledForCurrentAccount)
      XCTAssertFalse(h.sync.requiresRestart)
      XCTAssertEqual(h.sync.configuration, original)
      XCTAssertEqual(try SyncConfiguration.load(in: h.directory), original)
      XCTAssertFalse(try XCTUnwrap(h.store).isSuspended)
      XCTAssertEqual(h.store?.archive, originalArchive)
      XCTAssertFalse(h.hasRecovery)
    }
  }

  @MainActor func testConfirmedAccountChangeNotificationsStillProtectTheLibrary() async throws {
    for account in [CloudAccount.signedOut, .available("account-b")] {
      let h = try SyncAccountHarness()
      defer { h.stop() }
      try await h.open()
      let checked = expectation(description: "Notification confirms account change")
      h.provider.onRead = { checked.fulfill() }
      h.provider.account = account
      h.center.post(name: .CKAccountChanged, object: nil)
      await fulfillment(of: [checked], timeout: 1)

      XCTAssertTrue(h.sync.requiresRestart)
      XCTAssertFalse(h.sync.isActive)
      XCTAssertFalse(h.sync.configuration.enabled)
      XCTAssertFalse(try SyncConfiguration.load(in: h.directory).enabled)
      XCTAssertTrue(try XCTUnwrap(h.store).isSuspended)
      XCTAssertTrue(h.hasRecovery)
      XCTAssertFalse(h.sync.canResumeAfterRestart)
    }
  }

  @MainActor func testUnavailableStartupKeepsSyncOnAndOffersRestartForSameAccount() async throws {
    let h = try SyncAccountHarness()
    defer { h.stop() }
    h.provider.account = .unavailable("Account not ready at login")
    try await h.open()
    let original = h.sync.configuration

    XCTAssertTrue(h.sync.configuration.enabled)
    XCTAssertTrue(h.sync.isEnabledForCurrentAccount)
    XCTAssertFalse(h.sync.isActive)
    XCTAssertFalse(h.sync.canResumeAfterRestart)
    XCTAssertEqual(h.sync.activity, "Waiting for iCloud")
    XCTAssertEqual(try SyncConfiguration.load(in: h.directory), original)
    XCTAssertEqual(h.cloudRequests.count, 1)
    XCTAssertNil(h.cloudRequests[0])

    h.provider.account = .available("account-a")
    await h.sync.checkAccount()
    XCTAssertTrue(h.sync.configuration.enabled)
    XCTAssertTrue(h.sync.canResumeAfterRestart)
    XCTAssertEqual(h.sync.activity, "Restart required")
    var next: SyncConfiguration?
    h.sync.onRestart = { next = $0 }
    h.sync.requestChange(h.sync.configuration.enabled)
    XCTAssertEqual(next, original)
    XCTAssertEqual(try SyncConfiguration.load(in: h.directory), original)
  }

  @MainActor func testDifferentAccountAfterUnavailableStartupCannotResumeOldLibrary() async throws {
    let h = try SyncAccountHarness()
    defer { h.stop() }
    h.provider.account = .unavailable("Offline")
    try await h.open()
    h.provider.account = .available("account-b")
    await h.sync.checkAccount()

    XCTAssertTrue(h.sync.changesAccount)
    XCTAssertFalse(h.sync.isEnabledForCurrentAccount)
    XCTAssertFalse(h.sync.canResumeAfterRestart)
    XCTAssertFalse(h.sync.isActive)
    XCTAssertTrue(h.sync.configuration.enabled)
    var next: SyncConfiguration?
    h.sync.onRestart = { next = $0 }
    h.sync.requestChange(true)
    XCTAssertNotEqual(try XCTUnwrap(next).libraryName, h.sync.configuration.libraryName)
  }

  @MainActor func testLateAccountResultCannotOverrideNewerCheck() async throws {
    let h = try SyncAccountHarness()
    defer { h.stop() }
    try await h.open()
    let original = h.sync.configuration
    h.provider.delay = true
    let firstRead = expectation(description: "First check started")
    h.provider.onRead = { firstRead.fulfill() }
    let first = Task { await h.sync.checkAccount() }
    await fulfillment(of: [firstRead], timeout: 1)
    let secondRead = expectation(description: "Second check started")
    h.provider.onRead = { secondRead.fulfill() }
    let second = Task { await h.sync.checkAccount() }
    await fulfillment(of: [secondRead], timeout: 1)

    h.provider.pending.removeLast().resume(returning: .available("account-a"))
    await second.value
    h.provider.pending.removeLast().resume(returning: .signedOut)
    await first.value
    XCTAssertTrue(h.sync.isActive)
    XCTAssertFalse(h.sync.requiresRestart)
    XCTAssertEqual(h.sync.configuration, original)
    XCTAssertEqual(try SyncConfiguration.load(in: h.directory), original)
  }

  @MainActor func testCancelledOrStoppedCheckCannotDisableSync() async throws {
    for stop in [false, true] {
      let h = try SyncAccountHarness()
      defer { h.stop() }
      try await h.open()
      let original = h.sync.configuration
      h.provider.delay = true
      let checked = expectation(description: "Delayed check started")
      h.provider.onRead = { checked.fulfill() }
      let task = Task { await h.sync.checkAccount() }
      await fulfillment(of: [checked], timeout: 1)
      if stop { h.sync.stop() } else { task.cancel() }
      h.provider.pending.removeLast().resume(returning: .signedOut)
      await task.value

      XCTAssertEqual(h.sync.configuration, original)
      XCTAssertEqual(try SyncConfiguration.load(in: h.directory), original)
      XCTAssertFalse(try XCTUnwrap(h.store).isSuspended)
      XCTAssertFalse(h.hasRecovery)
    }
  }
}

@MainActor private final class SyncAccountHarness {
  let directory: URL
  let defaults: UserDefaults
  private let suite = "TextendSyncAccountTests." + UUID().uuidString
  let provider = DelayedCloudAccount()
  let center = NotificationCenter()
  var cloudRequests: [String?] = []
  var store: LibraryStore?

  lazy var sync: SyncCoordinator = {
    // Initialization was validated against the same file in init.
    try! SyncCoordinator(
      directory: directory, provider: provider, defaults: defaults,
      notificationCenter: center, workspaceCenter: NotificationCenter(),
      makeStore: { [unowned self] url, container in
        cloudRequests.append(container)
        return try LibraryStore(url: url)
      })
  }()

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defaults = UserDefaults(suiteName: suite)!
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try SyncConfiguration().changingSync(to: true, account: .available("account-a"))
      .save(in: directory)
  }

  func open() async throws {
    store = try await sync.openLibrary()
    try store?.save(.init(name: "Keep", keyword: "keep", template: "Saved locally"))
  }

  var hasRecovery: Bool {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
      .contains(where: { $0.hasSuffix(".recovery.json") }) == true
  }

  func stop() {
    sync.stop()
    store?.suspend()
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: directory)
  }
}

@MainActor private final class DelayedCloudAccount: CloudAccountProviding {
  var isProvisioned = true
  var account: CloudAccount = .available("account-a")
  var delay = false
  var onRead: (() -> Void)?
  var pending: [CheckedContinuation<CloudAccount, Never>] = []

  func currentAccount() async -> CloudAccount {
    if delay {
      return await withCheckedContinuation { continuation in
        pending.append(continuation)
        onRead?()
      }
    }
    onRead?()
    return account
  }
}
