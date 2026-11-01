import CloudKit
import XCTest

@testable import TextendCore

final class CloudAccountProviderTests: XCTestCase {
  @MainActor func testRestrictedAccessDoesNotReportSignOutOrEraseCachedIdentity() async throws {
    let h = try CloudAccountHarness()
    defer { h.stop() }
    h.status = .restricted
    let result = await h.provider.currentAccount()

    guard case .unavailable = result else { return XCTFail("Restriction is not a sign-out") }
    XCTAssertEqual(h.defaults.string(forKey: "accountKey"), "cached-a")
    XCTAssertEqual(h.defaults.string(forKey: "identityToken"), "identity-a")
    XCTAssertEqual(h.recordReads, 0)
  }

  @MainActor func testTemporaryAccessUsesCacheOnlyForMatchingSystemIdentity() async throws {
    for status in [CKAccountStatus.temporarilyUnavailable, .couldNotDetermine] {
      for identity in ["identity-a", "identity-b", nil] {
        let h = try CloudAccountHarness()
        defer { h.stop() }
        h.status = status
        h.identity = identity
        let result = await h.provider.currentAccount()

        if identity == "identity-a" {
          XCTAssertEqual(result, .available("cached-a"))
        } else {
          guard case .unavailable = result else { return XCTFail("Unverified identity used cache") }
        }
        XCTAssertEqual(h.defaults.string(forKey: "accountKey"), "cached-a")
        XCTAssertEqual(h.recordReads, 0)
      }
    }
  }

  @MainActor func testConfirmedSignOutClearsCachedIdentity() async throws {
    let h = try CloudAccountHarness()
    defer { h.stop() }
    h.status = .noAccount
    let result = await h.provider.currentAccount()

    XCTAssertEqual(result, .signedOut)
    XCTAssertNil(h.defaults.string(forKey: "accountKey"))
    XCTAssertNil(h.defaults.string(forKey: "identityToken"))
  }

  @MainActor func testIdentityChangeDuringLookupDoesNotCacheMixedAccounts() async throws {
    let h = try CloudAccountHarness()
    defer { h.stop() }
    h.onRecordRead = { h.identity = "identity-b" }
    let result = await h.provider.currentAccount()

    guard case .unavailable = result else { return XCTFail("Identity changed during lookup") }
    XCTAssertEqual(h.defaults.string(forKey: "accountKey"), "cached-a")
    XCTAssertEqual(h.defaults.string(forKey: "identityToken"), "identity-a")
  }

  @MainActor func testLateSignOutCannotEraseNewerVerifiedIdentity() async throws {
    let h = try CloudAccountHarness()
    defer { h.stop() }
    h.delayStatus = true
    let checked = expectation(description: "First lookup started")
    h.onStatusRead = { checked.fulfill() }
    let first = Task { await h.provider.currentAccount() }
    await fulfillment(of: [checked], timeout: 1)

    h.delayStatus = false
    h.onStatusRead = nil
    let verified = await h.provider.currentAccount()
    let expected = SyncConfiguration.accountKey("record-a")
    XCTAssertEqual(verified, .available(expected))
    h.pending.removeLast().resume(returning: .noAccount)
    let stale = await first.value

    guard case .unavailable = stale else { return XCTFail("Outdated lookup was accepted") }
    XCTAssertEqual(h.defaults.string(forKey: "accountKey"), expected)
    XCTAssertEqual(h.defaults.string(forKey: "identityToken"), "identity-a")
  }

  @MainActor func testCancelledCheckDoesNotEraseCachedIdentity() async throws {
    let h = try CloudAccountHarness()
    defer { h.stop() }
    h.delayStatus = true
    let checked = expectation(description: "Lookup started")
    h.onStatusRead = { checked.fulfill() }
    let task = Task { await h.provider.currentAccount() }
    await fulfillment(of: [checked], timeout: 1)
    task.cancel()
    h.pending.removeLast().resume(returning: .noAccount)
    let result = await task.value

    guard case .unavailable = result else { return XCTFail("Cancelled lookup was accepted") }
    XCTAssertEqual(h.defaults.string(forKey: "accountKey"), "cached-a")
  }
}

@MainActor private final class CloudAccountHarness {
  private let suite = "TextendCloudProviderTests." + UUID().uuidString
  let defaults: UserDefaults
  var identity: String? = "identity-a"
  var status = CKAccountStatus.available
  var recordReads = 0
  var onRecordRead: (() -> Void)?
  var onStatusRead: (() -> Void)?
  var delayStatus = false
  var pending: [CheckedContinuation<CKAccountStatus, Error>] = []

  lazy var provider = CloudAccountProvider(
    defaults: defaults, provisioned: { true }, identityToken: { [unowned self] in identity },
    accountStatus: { [unowned self] in
      if delayStatus {
        return try await withCheckedThrowingContinuation { continuation in
          pending.append(continuation)
          onStatusRead?()
        }
      }
      onStatusRead?()
      return status
    },
    userRecordName: { [unowned self] in
      recordReads += 1
      onRecordRead?()
      return "record-a"
    })

  init() throws {
    defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.set("cached-a", forKey: "accountKey")
    defaults.set("identity-a", forKey: "identityToken")
  }

  func stop() { defaults.removePersistentDomain(forName: suite) }
}
