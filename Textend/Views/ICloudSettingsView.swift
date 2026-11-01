import SwiftUI

struct ICloudSettingsView: View {
  @Bindable var sync: SyncCoordinator
  @State private var proposedEnabled = false
  @State private var showingConfirmation = false

  var body: some View {
    Form {
      Section {
        Toggle(
          "Sync snippets with iCloud",
          isOn: Binding(
            get: { sync.isEnabledForCurrentAccount },
            set: {
              proposedEnabled = $0
              showingConfirmation = true
            })
        )
        .disabled(sync.requiresRestart || (!sync.isEnabledForCurrentAccount && !sync.canEnable))
        LabeledContent("Account", value: sync.accountDescription)
        LabeledContent("Activity", value: sync.activity)
        if let last = sync.lastTransfer {
          LabeledContent("Last successful transfer") {
            Text(last, format: .dateTime.month().day().hour().minute())
          }
        }
      } header: {
        Text("iCloud Sync")
      } footer: {
        Text(
          "Saved snippets, collections, favorites, and placeholder mappings sync between Macs signed into the same iCloud account. App preferences stay on each Mac."
        )
      }
      Section {
        if let message = sync.message {
          Text(message).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if sync.requiresRestart || sync.canResumeAfterRestart {
          Button("Restart Textend…") { sync.requestChange(sync.configuration.enabled) }
            .disabled(sync.recoveryFailed)
        } else {
          Button("Check iCloud Account") { Task { await sync.checkAccount() } }
        }
      } footer: {
        Text(
          "Changes sync when iCloud is available. A completed transfer does not confirm that every Mac has received it. Turning sync off keeps your local library and leaves your iCloud data intact."
        )
      }
    }
    .confirmationDialog(
      proposedEnabled ? "Enable iCloud Sync and Restart?" : "Turn Off iCloud Sync and Restart?",
      isPresented: $showingConfirmation, titleVisibility: .visible
    ) {
      Button(proposedEnabled ? "Enable and Restart" : "Turn Off and Restart") {
        sync.requestChange(proposedEnabled)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        proposedEnabled
          ? sync.changesAccount
            ? "Textend will open a separate library for this account. Your previous library stays on this Mac."
            : "Your saved local library will join this account’s Textend library. You’ll be asked to resolve unsaved edits before restarting."
          : "Textend will keep its downloaded library on this Mac. Changes made after restarting will stay local until you enable sync again."
      )
    }
    .task { await sync.checkAccount() }
  }
}
