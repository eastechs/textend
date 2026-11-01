# Textend iCloud sync

Sync is opt-in. SwiftData mirrors saved snippets and collections into the user's
private `iCloud.chat.eastechs.tapster` database. Preferences, permissions and launch
settings remain local. The app remains unsandboxed for text expansion.

The container identifier and team ID are public configuration, not credentials.
CloudKit access requires the app's signed entitlements; private database contents
belong to the current iCloud user. See [Apple's container documentation](https://developer.apple.com/documentation/cloudkit/ckcontainer).
Signing keys, provisioning profiles, and service credentials stay outside Git.
Independent forks need their own team and CloudKit container.

## Signing and environments

Production keeps bundle `chat.eastechs.tapster` and team `VK288Z42NG`.
Development builds are named **Textend Dev** with the separate bundle
`chat.eastechs.textend.debug`. Both App IDs need CloudKit and Push Notifications
and association with the existing container. Separate bundle identities let macOS
retain separate Accessibility permissions and UserDefaults for each app.

Install these profiles into Xcode's provisioning profile directory:

- `Textend Dev CloudKit Development`: Apple Development certificate, development
  APS and CloudKit entitlement, and every test Mac registered in the profile.
- `Textend CloudKit Developer ID`: Developer ID Application certificate, production
  APS and CloudKit entitlement, valid for all devices.

`script/provisioning.py development` or `release` validates profile identity,
container, services, environment, expiration and the matching local signing key.
Builds fail if provisioning is missing. Profiles and private keys stay outside Git.
For the initial development identity setup, sign in to Xcode Settings → Accounts
and run:

```sh
./script/build_and_run.sh --setup-development-signing
```

This explicitly lets Xcode register/provision only the development App ID using
its signed-in account. Normal builds use cached, validated provisioning and do
not silently switch to production or ad hoc signing. The validator also accepts
Xcode's `Mac Team Provisioning Profile` for the exact development identity and
CloudKit configuration. Xcode-managed profiles use automatic signing; a named
manual profile uses manual signing and takes precedence for two-Mac tests.
Before launch, the script checks the built app's bundle ID, deep signature,
embedded profile, and signed CloudKit environment.
After downloading a renewed manual profile, install it with:

```sh
python3 script/provisioning.py development --install ~/Downloads/Textend_Dev_CloudKit_Development.provisionprofile
```

Use `release` with the Developer ID profile. The installer validates the profile,
installs it atomically, and moves superseded Textend profiles to
`TextendRetiredProfiles` beside their existing profile folder. Other apps' profiles
remain untouched. This prevents duplicate-profile build failures while retaining
recoverable old copies.
The local release script embeds and validates the production profile and signed
entitlements before notarization. Sparkle and Spaces publication are unchanged.

Debug builds use `Application Support/chat.eastechs.textend.debug`. Release
builds retain `Application Support/chat.eastechs.tapster`. The old shared-identity
development library at `chat.eastechs.tapster/Development` is retained without
being automatically imported. Development and production CloudKit data are separate. A Release build launched with
`--sync-preview` uses `ProductionPreview` below the release support directory,
starts with expansion paused, and disables Sparkle. Use that mode for signed
production access checks without opening the installed app's library. It still
connects to the account's production CloudKit database when explicitly enabled.
Do not copy a development database into
the release directory or run two builds against the same store.

Use `./script/build_and_run.sh --preview` for Textend Dev with expansion initially
paused. Quit that preview before rebuilding. It does not replace the installed
release. Enable Accessibility for Textend Dev once, keeping the production
Textend entry enabled separately. New builds keep the same development identity
and certificate requirements so switching between them does not replace one
app's permission entry with the other. Fresh libraries are empty; File > Add Example Snippets is
explicit and available only when the library is empty.

## Migration, account binding and recovery

Schema V2 removed uniqueness constraints and added CloudKit-compatible defaults.
Schema V3 adds collection app restrictions and a separate Composition entity;
released V1/V2 schemas remain unchanged.
Migration preserves logical IDs, timestamps and placeholder data. Before opening
an existing database, SQLite's online backup creates a consistent
`*.store.pre-v3.sqlite` file, including committed WAL contents. Backup failure
stops opening the library. Retain that backup until the migration is accepted.

`SyncConfiguration.json` binds a library to a hashed CloudKit account identity.
Enabling or disabling sync persists only after the restart confirmation and draft
Save/Discard/Cancel flow. Disabling retains the downloaded local library and does
not delete cloud records. A different account receives a separate store after
explicit enablement, without importing the previous account's library.

A confirmed sign-out or different account identity suspends the current store and expansion index,
preserves the last observed library in a private `*.recovery.json` file, and
requires restart. That recovery is opened locally before sync can be enabled
again. A failed recovery write blocks the automatic restart action and asks for a
backup. Do not remove old account stores or recovery files automatically.
Ordinary connection failures keep local editing available while Apple's framework
handles retries. Account unavailability alone is not treated as an account change.
CloudKit's account notification triggers a fresh status and identity check before
recovery is considered; the notification can also indicate temporary availability
changes. Restricted access does not erase the saved account identity or sync choice.
Cancelled or superseded account checks cannot change the library or cached account.

The iCloud switch shows the saved choice for the current account, separately from
the Activity status. If the account cannot be verified at startup, Textend opens
the library locally while keeping sync enabled in its settings. When the same
account becomes available, Settings offers Restart Textend to attach the store to
iCloud without turning the preference off. An already attached store can wait for
temporary outages without a restart. A confirmed different account still requires
explicit enablement and a separate library.

Public JSON backup format is version 2; version 1 imports remain supported. It is a user backup/interchange
format, not the synchronization transport. Recovery snapshots also retain raw
invalid placeholder and Composition block payloads so an account change cannot silently discard them.

## Merge and expansion

CloudKit handles saved-record conflicts. Logical duplicate IDs are reconciled to
the smallest persisted row identifier, using the newest timestamp and then row
identifier to choose values. Duplicate nonempty keywords within the same priority and overlapping app scopes
pause affected automatic expansions, preserving enabled preferences. A valid
app-specific item overrides a global keyword; conflicting app-specific items do
not fall back to a global item. Manual
copying remains available for valid templates. New local saves and imports still
reject newly introduced scope conflicts.

Remote imports, app activation and wake refresh saved records and the expansion
index. Clean editors reload; dirty editors preserve their draft. Saving applies
only fields changed from the original baseline. Remote deletion offers Save as
New or Discard. Missing collections never hide snippets. Invalid records remain
visible with an explanation and are excluded from expansion.

The Settings activity describes observed transfers. A successful transfer does
not prove that another Mac received it. No global "fully synced" promise is made.

## Development schema and acceptance

Quit the development preview, then run:

```sh
./script/build_and_run.sh --initialize-cloudkit-schema
```

This opens a provisioned Debug app and initializes the schema from V3 through
Apple's `NSPersistentCloudKitContainer.initializeCloudKitSchema` API using a
separate development initialization store. It is not compiled into Release.
Inspect the schema in Apple's CloudKit Console before promoting it to production.
Do not deploy a partially reviewed schema. Production deployment and a signed
production-access test are release gates, independent of development success.

Automated checks:

```sh
./script/check.sh
```

Two-Mac acceptance requires development provisioning for both Macs and the same
iCloud account. Use disposable test snippets in the development environment:

1. Enable on both Macs. Confirm initial upload/download without duplicate examples.
2. Edit each direction; verify the other Mac and expansion of the changed keyword.
3. Edit offline, reconnect and confirm transfer.
4. Edit the same snippet simultaneously, including dirty drafts with different fields.
5. Create a keyword conflict on separate offline Macs; reconnect and verify both
   snippets are retained and excluded from expansion until one keyword changes.
6. Delete a remotely edited snippet; verify Save as New and Discard.
7. Add, rename and delete collections; snippets must remain visible.
8. Disable, edit locally, restart and re-enable; verify retained records.
9. Verify sleep/wake, relaunch, keyboard navigation, both appearances and theme colors.
10. Separately verify production schema, Developer ID entitlement access and the
    existing update workflow before publishing a release.

See `docs/verification.md` for completed checks and outstanding acceptance gates.

## V3 release gates

Update every synced Mac before enabling app restrictions. Older clients cannot
respect new scopes and do not display Compositions. JSON V2 prevents older
importers from silently dropping either feature.

Before publishing this feature release, complete the two-Mac checks in
`docs/quick-access-compositions.md`, promote the reviewed V3 schema, and verify
transfers of the new records and fields using the production-signed app.
Production transfer checks require the schema to be deployed first. Schema
initialization or deployment alone is not release acceptance.
