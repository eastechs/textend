import CloudKit
import Foundation
import Security

@MainActor protocol CloudAccountProviding {
  var isProvisioned: Bool { get }
  func currentAccount() async -> CloudAccount
}

@MainActor final class CloudAccountProvider: CloudAccountProviding {
  private let defaults: UserDefaults
  private let provisioned: @MainActor () -> Bool
  private let identityToken: @MainActor () -> String?
  private let accountStatus: @MainActor () async throws -> CKAccountStatus
  private let userRecordName: @MainActor () async throws -> String
  private var checkGeneration: UInt64 = 0

  init(
    defaults: UserDefaults,
    provisioned: @escaping @MainActor () -> Bool = { CloudAccountProvider.hasCloudKitEntitlements },
    identityToken: @escaping @MainActor () -> String? = {
      FileManager.default.ubiquityIdentityToken.flatMap {
        try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false)
      }.map { SyncConfiguration.accountKey($0.base64EncodedString()) }
    },
    accountStatus: @escaping @MainActor () async throws -> CKAccountStatus = {
      try await CKContainer(identifier: SyncConfiguration.containerIdentifier).accountStatus()
    },
    userRecordName: @escaping @MainActor () async throws -> String = {
      try await CKContainer(identifier: SyncConfiguration.containerIdentifier).userRecordID()
        .recordName
    }
  ) {
    self.defaults = defaults
    self.provisioned = provisioned
    self.identityToken = identityToken
    self.accountStatus = accountStatus
    self.userRecordName = userRecordName
  }

  var isProvisioned: Bool { provisioned() }

  private static var hasCloudKitEntitlements: Bool {
    guard let task = SecTaskCreateFromSelf(nil),
      let containers = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String],
      let services = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-services" as CFString, nil) as? [String]
    else { return false }
    return containers.contains(SyncConfiguration.containerIdentifier)
      && services.contains("CloudKit")
  }

  func currentAccount() async -> CloudAccount {
    checkGeneration &+= 1
    let generation = checkGeneration
    let superseded = CloudAccount.unavailable(
      "The iCloud account check was interrupted. Check again.")
    guard isProvisioned else {
      return .unavailable(
        "This build needs a CloudKit provisioning profile. Local snippets remain available.")
    }
    let identity = identityToken()
    do {
      let status = try await accountStatus()
      guard !Task.isCancelled, generation == checkGeneration else { return superseded }
      switch status {
      case .available:
        let id = SyncConfiguration.accountKey(try await userRecordName())
        guard !Task.isCancelled, generation == checkGeneration else { return superseded }
        guard identity == identityToken() else {
          return .unavailable("The iCloud account is updating. Check the account again.")
        }
        defaults.set(id, forKey: "accountKey")
        defaults.set(identity, forKey: "identityToken")
        return .available(id)
      case .noAccount:
        defaults.removeObject(forKey: "accountKey")
        defaults.removeObject(forKey: "identityToken")
        return .signedOut
      case .restricted:
        return .unavailable("Access to iCloud is restricted. Your sync setting has been kept.")
      default: return cachedAccount(identity: identity)
      }
    } catch {
      guard !Task.isCancelled, generation == checkGeneration else { return superseded }
      return cachedAccount(identity: identity)
    }
  }

  private func cachedAccount(identity: String?) -> CloudAccount {
    // Offline use is permitted only while the system's iCloud identity still matches.
    if let identity, identity == identityToken(),
      identity == defaults.string(forKey: "identityToken"),
      let account = defaults.string(forKey: "accountKey")
    {
      return .available(account)
    }
    return .unavailable(
      "iCloud is temporarily unavailable. Check your connection, then check the account again.")
  }
}
