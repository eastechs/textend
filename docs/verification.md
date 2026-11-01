# Local verification

Date: October 23, 2026.

- Xcode macOS build passes with no compiler warnings.
- All 27 Swift tests pass, covering debounce, resolution, persistence, atomic imports, draft binding lifetime, focus cancellation, generated-event tagging, and clipboard preservation.
- Swift formatting lint, shell syntax checks, project validation, and git whitespace checks pass.
- The local Apple Development signature verifies. This is a development build, not a notarized release.
- The running native three-column window, Git Commit preview, and Settings were inspected. The delay control and native expansion test field render correctly.
- Review-loop is clean on its third review pass. Earlier passes corrected draft discard behavior, caret validation, Shift handling, the Settings label/focus behavior, and dedicated application storage. Earlier development data is retained through migration.
- Permission flow correction: removed the separate Input Monitoring request. [Apple DTS confirms](https://developer.apple.com/forums/thread/828052) that Accessibility provides both event listening and posting. Tapster uses an active event tap and still checks Accessibility and posting access before starting it.
- The current development signature verifies. Tapster-specific macOS permission logs identified a stale Accessibility approval for the original ad-hoc build. Dave re-added Tapster, and the running app now reports Expansion active, including after the latest rebuild.
- The rebuilt permission screen and its Open Accessibility button were inspected. The button opens the correct privacy pane, labeled Device Control and Data Access on this Mac. No permission switch was changed by the agent.
- Editor crash correction: the supplied report and local reports trapped in `BindingOperations.ForceUnwrapping.get(base:)`. Command-clicking the selected snippet reproduced it. Replaced the optional draft binding with a binding scoped to the snippet identity that remains readable during editor teardown and rejects writes after selection changes. Three regression tests cover clearing/deleting a draft, switching snippets, live edits, and discarding into an empty collection.
- The rebuilt app survived the same deselection, selecting another snippet, focusing both name and template fields, switching collections, and creating/editing/discarding a temporary unsaved draft while expansion was active. No new crash report appeared during these checks. All 27 tests, formatting, build, and the first focused crash-fix review-loop pass are clean.
- Live debounce check: with the saved delay at 500 ms, physical typing produced three longer-keyword matches 147, 269, and 161 ms after the shorter match; each cancelled the shorter expansion and expanded the longer keyword. Pausing on the shorter keyword expanded it after approximately 503 ms. The earlier report of immediate expansion was not reproduced after relaunch; no behavioral fix or root cause is claimed. The temporary timing diagnostics were removed after verification at Dave's request.

## Native UI polish

- Followed Apple's [button](https://developer.apple.com/design/human-interface-guidelines/buttons), [toolbar](https://developer.apple.com/design/human-interface-guidelines/toolbars), and [layout](https://developer.apple.com/design/human-interface-guidelines/layout) guidance using native SwiftUI controls, system text styles, and semantic colors.
- Increased Save's label padding, moved New Snippet to the toolbar, aligned editor labels and pickers, reduced excess template height, and standardized section spacing and sheet fields. Keyword badges remain compact, and favorite indicators no longer indent the row text.
- Set the native list minimum row height to prevent newly inserted draft rows from clipping. Drafts and saved snippets share one row renderer. Draft lookup is evaluated once per view update.
- Inspected the running library at normal and minimum window sizes, scrolling, date mappings, the placeholder sheet, new draft rows, and enabled/disabled Save states. Discarded all temporary drafts. Inspected all three Settings tabs; the delay field and stepper are now separately exposed in the accessibility tree. The saved delay remains 500 ms.
- UI automation timed out once while switching windows. A process sample showed the app idle in its normal event loop, with no new crash report. Automation resumed after relaunch. This does not establish the cause of the timeout.
- The Xcode build, all 27 regression tests, formatting, and whitespace checks pass. The final review-loop covered draft identity, row rendering, responsive controls, accessibility labels, and consistency with sibling views. No expansion engine or persistence behavior changed.
- Light appearance was inspected. Dark appearance and a full VoiceOver session remain unverified in this pass.
- Dave reviewed the polish pass and reports a modest improvement with visible issues still remaining. He authorized committing this state; visual acceptance is not complete.

## Editor and preview layout

- The list header shows the active filter or collection and the visible snippet count, including search results and unsaved new snippets. Singular and plural counts are handled separately.
- Favorite moved beside the snippet title. Expansion is a native switch below Collection. Preview now occupies a separate, resizable right panel. Text inputs and the template share an 8-point rounded border; text fields have additional internal padding and a visible focus outline.
- New Collection is visible at the bottom of the sidebar and opens the existing creation sheet. Confirmed that blank names disable Save, entering a name enables it, and Cancel leaves the library unchanged. The File menu shortcut remains available.
- Inspected wide and compact windows in Light appearance, collection/filter selection, search counts, Command-F focus, clipboard/date/multiline previews, and favorite/expansion draft changes. Reversed temporary toggle changes and cancelled the collection test; all four original snippets remain intact.
- Xcode build, all 27 regression tests, formatting, and whitespace checks pass. Review-loop completed on its second pass after correcting the singular count. Reviewed draft binding lifetime, shared input styling, panel sizing, and existing collection actions. Dark appearance and full VoiceOver use were not checked in this pass.

## Sidebar collapse and layout stability

- Replaced geometry-driven SwiftUI toolbar sizing with an `NSSplitViewController` and native tracking separators. SwiftUI continues to render the library and editor content. Native holding priorities keep list and preview widths stable while the editor absorbs sidebar collapse and window resizing.
- Split containers now survive snippet changes and empty selections. The editor stays left-aligned; keyword help reserves two lines, and placeholder help stays below its menu so those controls do not jump between horizontal and vertical arrangements.
- Inspected normal and compact windows, repeated sidebar collapse/expand cycles, switching and clearing selections, temporary drafts, Settings, and the New Collection sheet. Six repeated toggles at each window size returned consistent pane widths and kept New/Save visible without toolbar overflow. The preview and header stayed aligned with their panes.
- Review corrected Save toolbar validation for clean and invalid drafts, and an accessibility value that retained the previous snippet's preview. Verified disabled Save for clean/invalid drafts, enabled Save after a valid edit, and updated preview accessibility values after selection changes. Temporary edits were reversed or discarded.
- The final focused review-loop is clean on its second pass. The Xcode build, all 27 regression tests, Swift formatting, shell syntax, and whitespace checks pass. Reviewed native controller lifetimes, toolbar validation, draft bindings, stable view identity, and sibling-view conventions. No expansion engine or storage behavior changed.
- These checks inspect layout and interaction results, not measured animation frame rates. Automated divider drags did not change widths, so physical divider dragging remains unverified. Dark appearance and a full VoiceOver session remain unverified. The app is left running at its previous window size with all four saved snippets intact and the delay still at 500 ms.

## Divider drag containment correction

- Dave's physical drag check exposed an inset content area that the earlier toggle checks did not cover. The split controller was directly exposed to SwiftUI sizing without an independently pinned container.
- Added a plain AppKit parent with required constraints on all four child edges. The representable accepts the window's finite proposed size, and the outer SwiftUI frame fills available width and height. Native pane constraints now operate within that allocated area.
- Added two layout regression tests: lower-priority internal width pressure cannot inset the child at several outer widths, and actual `NSSplitView.setPosition` changes plus collapse/reveal preserve the split view's outer bounds. These run in a separate local test module with no external dependency.
- Xcode build, all 29 tests, Swift formatting, and whitespace checks pass. The focused review-loop passed its first complete pass, including controller containment, constraint priorities, sizing proposals, lifecycle forwarding, and existing draft behavior.
- Inspected the rebuilt library, four collapse/reveal transitions, selection changes, toolbar alignment, and preview values. Automated mouse dragging did not move a divider. Dave subsequently tested the physical drag, confirmed that the fix resolved the inset-content issue, and authorized committing the UI changes. All four saved snippets are unchanged.

## Remaining acceptance

Dave reports that the app is mostly working after the permission and editor crash fixes. Complete cross-app acceptance is still unverified. Other target applications, alternate layouts, composition, sleep/wake, and Dark appearance have not received physical acceptance checks. Automated insertion tests capture events rather than posting them to other applications.

Tapster is left running with its original four saved snippets and Expansion active. No signed release or notarized distribution has been produced.

Run `./script/check.sh` to repeat formatting, tests, and the Xcode build. The Codex Run action launches through `./script/build_and_run.sh`.

## Textend rename and X2 icon (2026-10-23)

- Created the X2 Continuous mark as two vector ribbon layers, assembled in Icon Composer, and saved the editable `Tapster/Resources/Textend.icon` document. Exported the 1024-pixel PNG with Icon Composer's renderer; `script/export_icon.sh` reproduces it. Default, Dark, and TintedDark renders were visually inspected.
- Renamed the built product, app/window/menu labels, Settings copy, and backup filename to Textend. Retained the existing bundle identifier, Swift module, persistence schema, store location, and preference keys.
- `script/check.sh` passed: formatting, shell syntax, whitespace, 29 tests (27 core and 2 layout), and the development-signed Xcode build. Verified the bundle's Textend metadata, compiled `Assets.car` and compatibility `Textend.icns`, and signature with `codesign --verify --strict`.
- Inspected the running Textend app: all four existing snippets and both collections were present, expansion was active, the delay remained 500 ms, and launch at login remained off. Cross-app typing and older macOS runtime compatibility were not re-tested for this branding change.
- Review-loop iteration 2 was clean after correcting Package.swift line wrapping. Reviewed the rename, stable identity, build/run paths, export script, and icon source consistency. No commit or release was produced.

## Sparkle and local release tooling (2026-10-23)

- Integrated pinned Sparkle 2.10.0, native update commands and Settings, signed feeds, and verification before extraction. Debug builds do not start Sparkle. The public feed is configured as `https://cdn.usetextend.com/macos/appcast.xml`; the private update-signing key remains in the local Keychain.
- `script/check.sh` passed: 29 Swift tests, 14 offline publication guard tests, Swift formatting, shell syntax, whitespace, and the Debug build. Guard tests cover publication order, tampering, existing versions, permission failures, partial-upload retries, monotonic build numbers, and stale CDN feeds.
- Built and exported a universal Developer ID archive locally. Verified bundle metadata, both CPU architectures, the deep strict code signature, and matching release-team signatures with timestamps for Textend and every Sparkle helper. Generated a real test appcast and verified both the feed and archive Ed25519 signatures using Sparkle's tools. These artifacts are local validation builds, not notarized releases.
- Inspected Release Settings: both automatic-update options, the enabled manual-check command, and readable native layout. Sparkle's native automatic-check consent dialog appeared; it was left unanswered by quitting the test build. Inspected Debug Settings and confirmed the controls are disabled with the development-build explanation. Restored the Debug app with expansion active and all four saved snippets intact.
- Review-loop completed a clean first formal pass covering the full diff and new files, tests, formatting, updater lifecycle, unsaved-draft delegate, signing, upload ordering, failure handling, credential boundaries, and sibling conventions. Earlier integration checks corrected custom Info.plist values that Xcode did not emit through generated-key build settings.
- Notarization, Spaces upload, CDN delivery, and an actual update between two released versions remain unverified. No files were published, and no commit was made. Hosting and notarization credentials still require local configuration as described in `docs/releases.md`.

## Release hosting configuration (2026-10-24)

- Configured the ignored local release settings and tracked example for `textend-releases` in `atl1`, the `macos` prefix, and the `textend-notary` Keychain profile. The public feed remains `https://cdn.usetextend.com/macos/appcast.xml`.
- Authenticated the notarization profile with a read-only history request. HTTPS requests to the appcast path on both the Spaces CDN and custom domain returned HTTP 403. This confirms TLS connectivity, not public object access or successful update delivery.
- The local AWS CLI reports that `textend-spaces` is not configured. Upload credentials remain the next setup step. No notarization submission, upload, or publication was performed.
- Focused review-loop passed its first iteration: reviewed configuration and documentation, validated the local configuration and Git ignore rule, and reran all 14 release guard tests plus whitespace checks. Application code is unchanged from the previous verified build.
- After Dave saved the Spaces credentials, authenticated bucket access and listing of `macos/` succeeded. The prefix was empty, and the origin appcast was absent. Both public appcast URLs still returned HTTP 403. Read access is verified; upload permissions and actual update delivery remain untested. No objects were uploaded.

## Spotlight duplicates and About attribution (2026-10-24)

- Spotlight indexed the Debug app, the Release test build, and the exported validation app. Unregistered the two test copies and moved their generated folders into `build/retired-builds.noindex/`, preserving the files. After indexing caught up, `mdfind` returned only the Debug app for Textend's bundle identifier.
- Future release archives and exports now stage under `build/releases.noindex/` to avoid adding duplicate app results. The development app path and saved library remain unchanged.
- Added `Built by Dave Sebek. Copyright Eastechs 2026` through the native About panel's `NSHumanReadableCopyright` metadata. Verified the built plist and visually inspected the full text in the running About panel. Expansion remains active and the four saved snippets are present.
- Focused review-loop passed its first iteration: reviewed the metadata and staging-path changes against existing conventions, validated the plist and whitespace, built the app, and passed all 14 release guard tests. No release was published.

## Accent color setting (2026-10-24)

- Added a native accent picker under Settings → General → Appearance with eight Apple system colors, persisted with AppStorage. Each independent SwiftUI hosting root observes the preference, including the toolbar content. Theme updates preserve view identity, pane geometry, and drafts.
- Template placeholder attributes refresh when the accent changes without replacing the text. Custom input focus borders and native sidebar icons use the same preference. macOS still controls native selection highlights, Settings toolbar icons, and system focus rings; the Settings footer explains this boundary.
- Inspected Blue, Purple, and Green in the running app, immediate control/icon/placeholder updates, a purple search focus border, template typing and Undo, and persistence of Purple across relaunch. Restored Blue and left the final Settings screen open. The original four snippets remain, expansion is active, and the delay remains 500 ms. Dark appearance was not visually checked.
- Review-loop was clean on its second pass after adding explicit native sidebar item tinting. Reviewed preference propagation through AppKit hosts, editor highlighting and undo behavior, accessibility labels, and existing native layout conventions. `script/check.sh` passed all 43 tests, formatting, shell syntax, whitespace, and the Debug build. No commit or publication was performed.

## In-app Help and appearance override (2026-10-24)

- Help → Textend Help opens a single native, searchable offline guide with eight topics. Search covers article text and examples; Command-F targets Help search when that window is active. Reviewed the content against the actual settings, resolver, and library commands.
- Moved the accent picker into a dedicated Settings → Appearance tab alongside System, Light, and Dark. The persisted override uses `NSApplication.appearance` and is restored before app launch finishes, covering SwiftUI and AppKit windows without changing macOS settings.
- Inspected Help, Settings, and the library in the running app. Verified Help menu opening, article filtering, Command-F, empty results, Dark rendering, explicit Light rendering, and Dark persistence after relaunch. Restored System appearance and Blue accent. Help remains open for review.
- Review-loop finished clean on pass two after aligning Help sidebar tinting with the library and removing a redundant Help shortcut. Checked the full diff, native view conventions, preference propagation, document accuracy, and search edge cases. `script/check.sh` passed 29 Swift tests, 14 release tests, formatting, shell syntax, whitespace, and the Debug build. The initial sandboxed run could not write the Swift cache; rerunning with approved cache access passed. No commit or release publication was performed.

## Theme-colored list selections (2026-10-24)

- Fixed blue list selections remaining under the Graphite accent. Library rows, collection filters, and Help topics now share theme-colored backgrounds with readable foregrounds. The native List still owns selection, keyboard navigation, and accessibility selection state.
- SwiftUI row backgrounds alone did not suppress the focused AppKit highlight. Added a narrow bridge that finds the containing `NSTableView` through public view types and disables its default selection paint. No delegate replacement, private API, global appearance mutation, or replacement selection model is involved.
- Inspected focused library and sidebar selections in Dark with Graphite, including Tab and arrow-key navigation. Inspected Help selection in Light, with readable selected icons and text. Restored Dave's Dark appearance and retained Graphite throughout. The four saved snippets remain unchanged.
- Review-loop passed on its third iteration after correcting the focused native highlight and selected icon contrast. Reviewed the complete diff, representable lifecycle, selection bindings, existing view conventions, and updated documentation. The two focused layout tests, strict Swift formatting, whitespace checks, and the Debug build passed. No commit was made.

## First notarized release and Spaces publication (2026-10-24)

- Prepared Textend 0.1.0, build 2, from `e222d9d54a67b3032cbcecbcd70674fcf48a8c37`. All 43 pre-release checks passed. The universal app is signed with Developer ID team `VK288Z42NG`; Apple accepted submission `533720ae-7bed-41d2-b472-b28ba7060da7` and its ticket was stapled.
- Extracted the final ZIP and verified both architectures, bundle metadata, nested signatures, stapled ticket, and Gatekeeper acceptance as Notarized Developer ID. Verified manifest hashes and Sparkle signatures for the ZIP and XML feed. Local release files are in `dist/0.1.0-2/`.
- First publication exposed an AWS CLI error when reading an absent Spaces object: `argument of type 'NoneType' is not a container or iterable`. The script now checks existence with HEAD before downloading an existing feed; permission/network/read failures still stop publication. Added regression checks for a missing feed and a failed download of an existing feed.
- Published `macos/Textend-0.1.0-2.zip` to `textend-releases`, verified its SHA-256 through `cdn.usetextend.com`, then published and verified the exact signed `macos/appcast.xml`. Upload credentials and public CDN delivery are now verified. No keys, manifests, or Apple logs were uploaded.
- The focused review-loop passed its first formal iteration: reviewed the publication diff and guard behavior, checked sibling test conventions, passed all 16 release tests, Python compilation, and whitespace checks. The signed app itself is unchanged. An actual upgrade between two released versions, including unsaved drafts and retained Accessibility permission, remains untested. Publication-tool changes and this note are uncommitted.

## Installed Sparkle update test (2026-10-24)

- Installed the signed, notarized 0.1.0 build 2 release at `/Applications/Textend.app`. Previously, no app was installed in either Applications folder. Dave granted Accessibility to this release identity; the app then showed Expansion active. Enabled automatic update checks through Sparkle's consent prompt, leaving automatic download/install off.
- Prepared signed, notarized 0.1.1 build 3 from `495bab63158d82971f32a3694b8314951ce3af14`, with no application-code or library-format changes. Apple accepted submission `b7646c66-45cd-43a2-86c6-09c34cc7b5ec`. Published the ZIP and signed feed through the existing local script, which verified CDN delivery before completing. The ZIP SHA-256 is `37a52ef3ba26012a7db83f90ac52136ca7e733fb4d98bf87a99cf0743b37643c`.
- The installed 0.1.0 app found 0.1.1 through Check for Updates, displayed its release notes, downloaded it, and reached Ready to Install. With a temporary unsaved name edit, Install and Relaunch presented Save/Discard/Cancel. Cancel retained the draft and left 0.1.0 installed. Retrying and choosing Discard Changes discarded only that temporary edit, installed the update, and relaunched Textend without a manual launch.
- Verified `/Applications/Textend.app` is now 0.1.1 build 3 and the new process runs from that path. Deep strict code-signature verification, Gatekeeper assessment as Notarized Developer ID, and stapler validation all passed. A second Check for Updates reported 0.1.1 is the newest version.
- All four saved snippets and both collections remain present, the temporary name edit is gone, and Save is disabled for the clean draft. Expansion remains active without another Accessibility grant. This establishes the actual download, installation, relaunch, draft cancellation, and permission-retention path. Cross-app physical typing and the Save branch of the update prompt were not retested. The installed release is left running; no development build was launched.

## iCloud sync implementation, October 24, 2026

Status: implemented locally, acceptance still in progress. No feature commit,
release publication, or replacement of `/Applications/Textend.app` was performed.

- Registered Textend's App ID with iCloud and Push Notifications under team
  `VK288Z42NG`, registered `iCloud.chat.eastechs.tapster`, and associated it.
- Generated both named CloudKit profiles. Installed and validated the development
  profile, including this Mac. The Developer ID profile was subsequently installed
  and validated; see the production verification below.
- The provisioned development app builds and launches. Its isolated library was
  initially empty. The real account check reports Signed in.
- Ran the development-only CloudKit schema initializer. The app subsequently
  opened normally, and observed CloudKit import/export events produced successful
  transfer timestamps. Created `CloudKit Development Check` / `;cloudcheck` with
  disposable test text in the development library. Export completion was observed
  in Core Data logs. This does not establish receipt on another Mac.
- Native Settings inspection covered Light and Dark appearances, a green accent,
  enable/disable confirmation, unsaved draft Save/Discard/Cancel presentation,
  cancelling restart, discarding a temporary draft, and disabling/re-enabling with
  restart. The saved test snippet survived both restarts. Appearance preferences
  were restored to System and Blue after inspection.
- One inspection attempt reopened the preview while the restart helper also
  launched it. Stopped only those development processes. The restart helper now
  uses normal application reopening, and the preview script refuses to rebuild
  an already running preview. Subsequent restarts each produced one process with
  `--sync-preview`, keeping expansion initially paused.
- Final `./script/check.sh` passes: 35 Swift tests, 16 release guard tests, 3
  provisioning tests, strict Swift formatting, shell syntax, whitespace checks,
  and the provisioned Xcode development build.
- New tests cover real V1 SQLite migration and reopening its V1 backup; clean and
  dirty editor refresh; field-level saves; remote deletion and Save as New;
  duplicate logical identities; invalid placeholder preservation; duplicate
  keyword suppression and correction; partial collection arrival; recovery
  snapshots; account isolation; restart cancellation/rollback; offline editing;
  and recovery write failure. Remote changes use separate local model contexts
  and injected account providers, so these are not two-device CloudKit tests.
- Review-loop pass 1 corrected existing conflicts blocking unrelated edits,
  validation against stale draft fields, transfer errors being cleared by account
  refresh, recovery failures permitting restart, and duplicate preview launching.
  Pass 2 found no further code defects in the reviewed local scope; its automated
  checks pass. Plan acceptance remains open at the gates below.

Acceptance gates at this initial checkpoint (subsequent results are recorded below):

- Complete the two-Mac matrix in `docs/icloud-sync.md`, including real offline/concurrent edits,
  deletions, conflicts, collection changes, relaunch, and remote expansion.
- Inspect native conflict/deletion/error states from those real sync scenarios.
  Actual account switching and sleep/wake transfer behavior are not yet verified.
- A signed/notarized public release still requires subsequent authorization.


### Production provisioning and CloudKit access

- Installed and validated `Textend CloudKit Developer ID` profile
  `62cdebfb-e76e-4c63-b9fe-1dbd9fd6d283`. It matches the existing Developer ID
  Application certificate and has production CloudKit and APNs entitlements.
- Reviewed CloudKit Console's schema diff against V2: `CD_SavedSnippet`,
  `CD_SavedCollection`, their fields and the framework-generated indexes. Deployed
  the schema and observed Apple's “Changes Deployed” confirmation. No user library
  was uploaded by schema deployment. Apple describes this separation in its
  [schema deployment guidance](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
- Archived and exported an internal 0.1.2 (4) verification build under
  `build/releases.noindex/cloudkit-verification/`. Deep/strict signature verification
  passes. The app contains arm64 and x86_64, the matching embedded profile,
  Production CloudKit, production APNs, and no debugger entitlement.
- Launched with `--sync-preview`. Release previews now use the separate
  `ProductionPreview` library and keep Sparkle disabled. The library began empty;
  `/Applications/Textend.app` and its ordinary library were not replaced or opened
  by this preview.
- The production-signed app reported Signed in. Enabled sync through Settings and
  its restart flow, created `CloudKit Production Check` / `;productioncheck`, and
  observed a completed production transfer at 2:47 PM on October 24. Both the
  rendered Settings status and Core Data export logs confirm completion.
- That test record remains in Dave's private production CloudKit database for the
  two-Mac check. The separate development fixture remains in development.
- This internal artifact is not notarized or published. No Sparkle feed or Spaces
  object was changed. Real second-Mac receipt and the remaining matrix still need
  verification before release acceptance.
- Follow-up review-loop for production preview isolation found no additional
  defects. `./script/check.sh` remains green (35 Swift tests, 19 Python guard tests,
  formatting, shell syntax, whitespace, and signed Debug build). The native
  Updates tab confirms Sparkle is disabled in the production verification preview.
  Closed the verification app after checks. Overall acceptance remains pending
  the second Mac and real multi-device scenarios listed above.


### Mac Studio preparation

- Completed Apple's annual device-list confirmation retaining all three existing
  devices. Registered Dave's Mac Studio and regenerated `Textend CloudKit
  Development` with both the MacBook Pro and Mac Studio selected.
- Installed refreshed development profile `5d7734ec-eb13-46b2-8349-7b9420ac73f3`
  from the user-supplied download and confirmed both registered Macs are included.
  The older profile is retained beside Xcode's profile directory.
- Incremental Xcode build replaced the embedded profile without refreshing its
  resource signature. Deep/strict verification caught it. A clean build corrected
  the signature; both architectures and the two-device embedded profile verify.
- Packaged the development app with a preview launcher and first-sync instructions
  at `build/releases.noindex/two-mac-development/Textend-iCloud-Test.zip`.
  The launcher requires other Textend instances to be quit and passes
  `--sync-preview`. It uses the isolated development library, initially pauses
  expansion, and leaves the installed release untouched.
- Dave confirmed on October 24 that initial sync succeeded on Mac Studio after
  opening the test package. This is user-reported second-Mac receipt, following
  the first Mac's observed development export. The package is
  development-signed and is not notarized or publicly distributed.
- The Studio edit initially did not arrive; Dave reported that the sync switch
  might not have been enabled and requested another check. Subsequently verified
  `Updated from mac studio` in this Mac's saved SQLite record, snippet list,
  clean editor, and preview without relaunching the development app. This confirms
  a real Studio-to-MacBook edit and live clean-editor refresh.
- Saved `Updated from MacBook Pro` through the native editor for the return-direction
  check. Dave confirmed it appeared on the Studio without restarting Textend.
  Real saved edits and clean-editor refresh are now verified in both directions,
  with Studio observations reported by Dave. Concurrent edits, conflicts, and
  the remaining two-Mac matrix are still pending.
- Dave saved an edit while the Studio was offline, reconnected, and later reported
  that it synced. This Mac initially retained the previous value with no recent
  import activity. After relaunching only the development preview, verified
  `Saved offline mac studio` in the saved SQLite record, list, editor, and preview.
  Offline preservation and subsequent cloud delivery are confirmed. Automatic
  receiver delivery after reconnect was not demonstrated in this run; relaunch
  was part of the observation, so this is not a clean pass for that behavior.
- Concurrent draft check: left `CloudKit Draft Check` as an unsaved name here
  while Dave saved `Studio's concurrent edit` as the template on Studio. CloudKit
  logs show a push-triggered import completing at 3:39:41 PM. Without restarting,
  the saved list updated, the local draft remained intact, and the editor displayed
  its changed-on-another-Mac notice. Saving retained both the locally edited name
  and the remotely edited template, verified in the native UI and SQLite record.
  This confirms live import and field-level draft merging for different fields;
  the same-field check is recorded below, and the earlier reconnect delay remains
  a separate observation.
- Remote deletion check: Dave deleted the test snippet on Studio while this Mac
  held an unsaved template. The deletion arrived without restarting. The sidebar
  showed zero saved snippets, while the editor retained the full draft and showed
  “Deleted on another Mac” with Save as New Snippet and Discard Draft actions.
  Choosing Save as New Snippet persisted exactly one record containing
  `Preserved draft after remote deletion`, verified in the UI and SQLite. The
  Discard action was visible but was not exercised in this live two-Mac check.
- Duplicate-keyword check: Dave created `Studio Conflict` offline while this Mac
  saved `MacBook Conflict`, both using `;syncconflict`. After reconnecting, Dave
  confirmed both records and conflict warnings on Studio. Both enabled switches
  remain on by design: the stored preference is preserved while conflicts are
  excluded from the expansion index. Re-ran the focused
  `testRemoteChangesRefreshDraftAndSuppressDuplicateKeywords` test successfully;
  it verifies exclusion, manual-copy eligibility, and restoration after renaming.
  Dave then confirmed real typing on Studio with global expansion resumed:
  `;cloudcheck` expands while `;syncconflict` stays literal. This verifies expansion
  of a remotely received snippet and actual conflict suppression, rather than a
  result caused by globally paused expansion. Dave then changed Studio Conflict's
  keyword to `;studioconflict` and confirmed the warnings cleared and both keywords
  expanded without changing their enabled switches. Live conflict resolution and
  automatic restoration of expansion are confirmed on Studio.
- Collection/favorite check: created `Sync Collection`, assigned MacBook Conflict,
  and favorited it here. Dave confirmed the collection, membership, and star on
  Studio and renamed the collection there. `Studio Collection` arrived here
  without relaunching, including the editor's collection picker. Deleting that
  test collection here retained all three snippets and MacBook Conflict's favorite
  state, with its collection set to None. Dave reported the collection initially
  remained on Studio, then disappeared after a delay while sync stayed enabled.
  Collection deletion delivery is confirmed; this test did not establish an
  exact latency or an immediate-delivery guarantee.
- Disable/re-enable check: Dave disabled sync on Studio, restarted, made a local
  edit, re-enabled sync, and restarted again. He confirmed all three snippets
  remained. This Mac received the edit without restarting: the `;studioconflict`
  snippet's name became `Saved with sync off`, while its template remained
  `Studio conflict test`. The requested edit targeted the template, but the actual
  name edit still verifies local editing and subsequent upload across the mode
  transition. The library retained three snippets with no duplicate examples.
- Same-field draft check: held an unsaved `MacBook same-field edit` template here
  while Dave saved `Studio same-field edit` on Studio. After a delivery delay,
  the incoming version appeared in the saved list and the changed-elsewhere banner
  appeared without replacing the local draft. Explicitly saving here kept the
  locally edited template. Verified one `;cloudcheck` record and three total
  snippets in SQLite. This tests overlapping drafts followed by an explicit save,
  not two disconnected devices racing to upload saved versions.
- Sleep/wake check: after Dave confirmed Studio was asleep with Textend
  running, saved `Received after Studio wakes` as the `;cloudcheck` template here.
  CloudKit logs show the modify-records/export completion at 4:28:16 PM, and the
  rendered Settings view shows a successful transfer at 4:28 PM. Dave then confirmed
  the template updated after waking Studio without restarting Textend, and
  `;cloudcheck` expanded to the new text in TextEdit. The accessibility tree retained an older time;
  the rendered view was checked to avoid treating that stale value as app state.
- Added `provisioning.py --install` to validate and install downloaded profiles,
  preserving superseded copies outside Xcode's search path. Focused review-loop
  passed after covering same-file reinstallation; 5 provisioning and 16 release
  guard tests pass. Tests confirm other apps' profiles remain untouched and wrong
  profile names are rejected before writing.

- Follow-up review-loop corrected the retired-profile archive location: it is now
  beside the provisioning directory so Xcode does not try to parse it. Pass 2 found
  no further defects in this installer/package scope. Five provisioning tests,
  16 release guard tests, launcher syntax, and whitespace checks pass. The extracted
  ZIP app also passes deep/strict signature verification. Overall sync acceptance
  still requires the two-Mac scenarios above.

### Final iCloud verification checkpoint

- Two-Mac observations cover initial delivery, live edits both ways, offline edit
  preservation and eventual delivery, clean/dirty editor refresh, field-level
  saves, remote deletion recovery, duplicate-keyword suppression and resolution,
  collection changes, favorites, disable/re-enable with local edits, restart,
  sleep/wake, and expansion using remotely changed text. Studio observations were
  reported by Dave; this Mac's results were inspected through native UI and,
  where relevant, read-only queries of the isolated test store.
- Delivery sometimes took several minutes. In the first offline-reconnect check,
  this Mac received the edit after its test preview was relaunched. That run
  does not establish automatic receiver delivery without relaunch. Subsequent
  live imports, conflict delivery after reconnect, and sleep/wake succeeded, but
  do not retroactively remove that limitation.
- Actual system iCloud account switching was not performed. Account isolation,
  recovery, and failure behavior are covered by injected-provider tests. Same-field
  testing covered overlapping drafts with a later explicit save, not simultaneous
  disconnected uploads. Discard after remote deletion was not exercised natively.
- Final review-loop completed a clean pass over the cumulative implementation,
  persistence/account boundaries, UI integration, signing/release changes, test
  coverage, and these evidence limits. `./script/check.sh` passes 37 Swift tests
  (35 core and 2 layout) plus 21 Python tests (16 release and 5 provisioning),
  strict Swift formatting, shell syntax, whitespace checks, and the provisioned
  development build. Both the final Debug app and the previously verified
  production artifact pass deep/strict signature verification.
- Closed only the local development preview after testing. Three disposable
  snippets remain in the private development library. The production verification
  fixture remains separate. No source commit, public release, Spaces/feed change,
  or replacement of the installed 0.1.1 app was performed for this implementation.

## Header favorite and optional Dock icon (2026-10-24)

- Moved the favorite control before the snippet title. Inspected the header and
  the new General → App Behavior setting in the isolated development preview.
- Turning off “Show Textend in the Dock” immediately changes the running app to
  AppKit's accessory activation policy. A quit/relaunch retained that policy and
  the off switch value. Turning it back on restored the regular policy. Settings
  remained usable throughout. Restored Dock visibility to on after checking.
- The menu bar extra remains unconditional; its unavailable-library state now
  also provides Quit. Direct menu bar icon clicks were not verified because the
  native inspection surface did not expose the status item. Window-close and
  reopen behavior through that item still needs a physical check.
- The provisioned Debug build, strict Swift formatting, whitespace checks, and
  both layout regression tests pass. Review-loop checked preference defaults,
  persistence, failed-policy handling, menu availability, and header layout.
- No installed release replacement, publication, commit, or push performed.

### Dock transition and duplicate-window follow-up

- Dave reported that hiding the Dock icon hid open windows and that reopening
  once produced multiple library tabs. The first implementation restored only
  the key window synchronously; the library also used a multi-window scene and
  a custom window-identifier lookup that could miss an existing SwiftUI window.
- Dock changes now capture the visible, non-minimized windows and restore them
  in their existing order on the next main-queue turn, after unhiding the app.
  The library uses a unique SwiftUI `Window`; menu bar opening targets that
  scene directly. Automatic window tabbing is disabled, and SwiftUI retains
  ownership of the window identifier.
- Native inspection of the rebuilt preview confirmed both library and Settings
  stay on screen through regular → accessory mode with the same window IDs,
  sizes, and positions. Closing the library leaves the app running with no
  visible windows; reactivation reuses the original library window. Window menu
  inspection shows no tab controls. The inspection tool itself reactivates the
  app, so `swift script/window_state.swift` now provides reusable, read-only
  visibility diagnostics without bringing windows forward.
- The earlier disappearance was not reproduced through the inspection tool.
  Direct physical menu bar reopening remains to be confirmed by Dave. No claim
  is made that this tool-driven check reproduces his original interaction.
- Provisioned Debug build, both layout regression tests, strict formatting, and
  whitespace checks passed. Review-loop iteration 1 was clean after checking
  single-window reuse, asynchronous restoration, minimized-window exclusion,
  unsaved-draft close handling, and the cumulative diff. Dock visibility was
  restored to on; launch-at-login and saved snippets were left unchanged.

### Preventing the Dock-transition flash

- Dave's physical retest invalidated the preceding restoration workaround:
  windows flashed out and back, and a later toggle left them hidden. Removed
  all window reordering from that transition. `DockVisibility` now temporarily
  protects existing windows with AppKit's `canHide` and `hidesOnDeactivate`
  properties before changing policy, then restores their original properties
  after deferred activation work. Startup uses the same helper. Stale cleanup
  callbacks cannot overwrite a later transition's protection.
- Process inspection confirmed the reported two status icons belonged to the
  installed release and development preview. Quit the installed release without
  replacing it. A subsequent rebuild also yielded two development processes,
  one without preview arguments. Quit the extra process and added a post-build
  running-process guard before the preview's `open -n` call. Its exact launch
  source was not established. Only one preview process remained after the final
  rebuild, PID 81399, accessory policy, library window visible.
- Added an AppKit regression test for repeated and back-to-back policy changes,
  visible-window preservation, unchanged frames, keeping a hidden window hidden,
  and restoring original hide flags. All three focused layout/window tests,
  provisioned Debug build, strict formatting, shell syntax, and whitespace
  checks pass. The read-only window diagnostic now offers `--watch` to sample
  on-screen window IDs without activating the app.
- Review-loop found and corrected a Swift formatting issue and broadened the
  pre-build process check to cover any development arguments. The next review
  pass was clean. The physical flash/menu-bar test is still pending; automated
  checks and native control toggles do not establish that it is resolved.
- No commit, push, publication, or replacement of the installed release.

### Persistent protection during menu-bar-only mode

- Dave's next physical test also invalidated the temporary protection: after
  two successful switches, windows flashed again despite waiting several seconds.
  A temporary diagnostic in the actual app observed delayed deactivation after
  the previous cleanup had restored window hide properties.
- Replaced that cleanup with protection lasting for the entire accessory mode.
  Existing and newly opened titled windows retain `canHide = false` and
  `hidesOnDeactivate = false` until Dock visibility returns. Explicit AppKit
  Hide/Unhide restores and reapplies the original properties appropriately.
  There are no delayed window-reopening or reordering callbacks.
- Ten actual-app policy transitions, three seconds apart, kept both library and
  Settings windows in the on-screen window list throughout the diagnostic run.
  Removed the temporary tracing source and launch argument before the final
  build. This observation does not replace Dave's physical no-flash check.
- Four focused tests pass, including repeated transitions, new accessory-mode
  windows, explicit Hide/Unhide, and existing pinned-layout regressions. The
  provisioned Debug build and strict formatting pass. Final review-loop checked
  observer lifetime, weak window references, policy failures, singleton scene
  reuse, process guards, shell syntax, and whitespace without further findings.
- Final preview process 84655 is the only running Textend, in accessory mode
  with its library visible. Saved snippets, launch-at-login, and the installed
  release were left unchanged. Physical verification remains pending.

### Physical Dock-toggle failures and diagnosis

- Dave's physical checks failed the persistent-protection version. They also
  failed subsequent experiments using modern `activate()` and activation of all
  windows. Those experiments are not accepted fixes and were removed.
- Temporary lifecycle and window-order tracing during physical toggles showed
  that the library remained open and `isVisible` stayed true, but its window
  moved behind other applications. Later transitions also deactivated Textend,
  moving Settings behind the foreground app. There were no library-close or
  application-hide notifications during these toggles. Tests of visibility alone
  did not cover the actual failure. Native inspection also changes focus and
  cannot establish that these transitions work physically.
- Removed the temporary trace and restored the prior helper pending a product
  decision. The live Dock-toggle bug remains unresolved. The reusable read-only
  diagnostic now reports active state and the foreground app as well as window
  IDs, so a still-open window cannot be mistaken for an accepted transition.
- Checked the installed Herd app's setting text: “Always Show Dock Icon” and
  “When off, Herd only shows the Dock icon while a window is open.” Adopting that
  behavior would avoid changing process policy while Textend windows are visible;
  it is a proposed behavior change, not implemented or accepted yet.

### Approved window-dependent Dock behavior

- Dave approved matching Herd's behavior. The setting is now “Always show
  Textend in the Dock.” When off, Textend keeps the Dock icon while any titled
  window is open, hides it after the last closes, and restores it when a window
  opens. Minimized windows and application Hide retain Dock access. This
  supersedes the immediate-switch implementations and pending proposal above.
- Replaced the previous protection and activation workarounds with a small
  AppKit window-lifecycle controller. It coalesces notifications and waits until
  a close finishes before evaluating remaining windows. It does not change
  window hide flags, reorder windows, or switch to accessory mode with an open
  editor. Settings and offline Help describe the approved behavior.
- Native inspection of the rebuilt preview confirmed that toggling the setting
  with library and Settings open leaves the app regular and both windows open.
  Closing only the library retains the Dock icon. Closing Settings last leaves
  the same process running in accessory mode with no onscreen windows. Reopening
  restores the library and regular policy in the same process, PID 91023.
  The preference was left off. Direct menu bar status-item clicks are still
  unavailable through the inspection tool and are not claimed as verified.
- Eight focused layout/window tests pass. Coverage includes no policy writes
  while windows are open, last-close and reopen transitions, always-visible
  mode, hidden and minimized windows, transient-window exclusion, and rejected
  policy changes. The provisioned Debug build passes without warnings.
- Review-loop iteration 1 identified actor-isolation warnings in injected
  provider defaults; annotated the closure contracts with `@MainActor` and
  reran the focused tests and build. Iteration 2 completed a clean pass over the
  cumulative diff, lifecycle behavior, observer lifetime, preference persistence,
  singleton scene, process guards, strict formatting, shell syntax, and whitespace.
- Only one Textend preview process is running. No temporary tracing remains in
  the app. Saved snippets, launch-at-login, and the installed release are unchanged.
  No commit, push, release publication, or installed-app replacement performed.

## Textend logo in the menu bar (2026-10-24)

- Replaced the `text.insert` system symbol with a 24 × 18 point template asset
  using the exact two vector paths from the approved X2 app icon. The asset
  retains vector data; macOS supplies its menu bar tint. The menu's accessible
  title remains Textend, and its commands are unchanged. Uses the native
  [MenuBarExtra image initializer](https://developer.apple.com/documentation/swiftui/menubarextra).
- The provisioned Debug build succeeds without warnings. Loaded the image from
  the built app and verified its dimensions and `isTemplate` flag; compared both
  paths with the original logo and inspected the rendered compiled artwork.
  Strict Swift formatting and whitespace checks pass. Review-loop completed a
  clean first pass over the code, asset metadata, packaging, and existing menu.
- Replaced the existing development process with one rebuilt preview. The
  library opens normally. The inspection tool timed out accessing the system
  menu bar, so actual status-item appearance and clicks were not inspected.
  No installed-app replacement, commit, push, or release publication performed.
- Dave subsequently inspected the menu bar logo, approved its appearance, and
  requested this commit. Menu command behavior was not retested by the agent.

## Cursor placeholder (2026-10-24)

- Added one built-in `{cursor}` marker per template, Insert Placeholder → Cursor
  Position, a theme-colored preview indicator, accessible position text, and Help.
  The marker requires no mapping and is omitted from inserted/copied text.
  `{{cursor}}` remains literal, clipboard contents are never reparsed, and trailing
  spaces remain intact. Existing value mappings named cursor are blocked with a
  correction action instead of silently acquiring a different meaning.
- Uses native Accessibility selection positioning after confirming the expected
  caret and the exact inserted span. This also prevents premature movement when
  the replacement and keyword have equal lengths. Editors that reject selection
  writes can use tagged Left events for up to 256 trailing characters. Larger
  moves require Accessibility support. Unconfirmed or unsupported moves leave
  inserted text in place and report that manual caret positioning is needed.
- Physical typing, navigation, focus changes, pause, permission/secure-input
  changes, and index updates cancel pending movement. Synthetic events are ignored.
  Clipboard restoration retains its change-count guard. A deterministic scheduler
  tests delayed consumption, stale callbacks, and cancellation without system input.
- Reviewed existing [Espanso cursor hints](https://espanso.org/docs/matches/basics/#cursor-hints)
  and Apple's Accessibility selection API. Reused Textend's parser, insertion,
  focus, and native editor paths without adding a dependency or changing storage.
- Native inspection confirmed insertion between quotes, the preview marker,
  duplicate-marker validation blocking Save, and native Undo restoring the valid
  template. Saved a disposable development snippet, “Cursor Placement Check,”
  keyword `zzcaret`, template `git commit -m "{cursor}"`, for the physical check.
- All 54 Swift tests pass (46 core, 8 layout), strict formatting and whitespace
  checks pass, and the provisioned Debug build succeeds without warnings.
  Review-loop iteration 1 added equal-length consumption verification and bounded
  navigation fallback; iteration 2 completed a clean code and automated-check pass.
- Dave removed and re-added the development app's Accessibility entry, after
  which the preview reported Expansion active. Automated keystrokes did not
  trigger the global monitor, so Dave performed the physical typing check in
  TextEdit: typing `zzcaret`, pausing, then typing `test` produced
  `git commit -m "test"`, with the new text inside the quotes. Dave confirmed this
  result. This verifies the short, single-line caret path in TextEdit; live
  multiline/paste insertion and caret compatibility in other apps remain unverified.
- No commit, push, release publication, or installed-app replacement performed.

## Snippet sorting and empty sample clipboard (2026-10-24)

- Dave reported that his release tests passed after publishing 0.2.0. The existing
  commits were already pushed; `git push origin main` confirmed up to date.
- Added a native sort menu beside the library title/count: A–Z (default) and
  Created At (Newest First). The local choice persists across launches. Saved
  snippets sort after filtering, with stable name/ID tie breaks; unsaved new
  snippets retain their pinned position. Sorting does not change the current
  selection, dirty draft, stored records, or expansion index.
- Sample clipboard starts empty. A valid clipboard-based template now asks for
  sample text in the preview instead of suggesting its template is incomplete.
- Seven focused draft tests pass, including sorting, filter membership, persisted
  selection of sort order, unknown-preference fallback, and dirty-draft retention.
  Strict formatting, whitespace checks, and the provisioned Debug build pass.
  Review-loop completed a clean first pass over the diff, native-control reuse,
  preference scope, selection behavior, and sibling conventions.
- Native inspection of the changed header/menu is pending. These new changes
  have not been committed, pushed, or released.

## Clipboard file paths and Dock-flash investigation (2026-10-24)

- Clipboard resolution now uses AppKit's `readObjects(forClasses:options:)` with
  `urlReadingFileURLsOnly` to read copied file references as literal full paths,
  joining multiple files with newlines. File references take precedence over
  display-name text; ordinary text remains the fallback. Both automatic expansion
  and Copy Expanded Text use the same reader. No files are opened, image files
  created, shell quoting added, or clipboard contents modified while reading.
- Raw image data without text/file references remains unsupported. Help now
  explains saving and copying the image file first. The existing clipboard
  snapshot and change-count restoration guards remain intact.
- Twelve focused insertion tests pass, including one/multiple file references,
  spaces/Unicode/braces, text fallback, raw PNG data, literal resolution, and
  preservation of original file/name representations. Strict formatting,
  whitespace checks, and the provisioned Debug build pass. Review-loop tightened
  the raw-image fixture in pass 1; pass 2 found no further issues. Physical file
  expansion in a host app is not yet verified. Dave chose to verify the UI himself.
- Inspected DockVisibility and the previously approved Herd-style behavior: after
  the last window closes, it switches from regular to accessory policy. This is
  a plausible cause of the reported whole-menu-bar redraw, but the flash was not
  reproduced or measured by the agent. No speculative timing/activation changes
  were made. A persistent menu-bar-only mode could avoid these policy transitions,
  but would change the approved behavior and requires a separate decision and
  native verification. The running installed release was left untouched.

## Startup-only Dock mode (2026-10-24)

- Dave approved replacing the Herd-style behavior with true menu-bar-only mode.
  Removed all window notification observers and runtime Dock-policy changes.
  `LSUIElement` starts the app as an agent; the saved Show Textend in the Dock
  preference selects regular or accessory policy once in willFinishLaunching.
  Repeated callbacks cannot switch it later. Opening/closing windows has no policy
  effects, and settings changes only save the next-launch preference.
- Settings and Help explain quit/reopen behavior and show a pending-restart label
  when the saved preference differs from the running policy. Normal quit retains
  the existing unsaved-draft Save/Discard/Cancel protection.
- All 54 Swift tests pass (49 core, 5 layout), including startup policies,
  window-close/reopen independence, pending preference changes, rejection handling,
  sorting, and clipboard paths. Strict formatting, whitespace checks, and the
  provisioned Debug build pass; the built plist contains LSUIElement=true.
  Review-loop completed a clean pass over startup order, remaining policy call
  sites, settings persistence, menu reopening paths, docs, and tests.
- Closed the installed 0.2.0 process after confirming no selected/dirty draft,
  then launched the development build with --sync-preview. The library opened;
  Settings showed Show Textend in the Dock off with no restart pending. Closed
  only Settings and left the isolated library open for Dave's check. Expansion is
  paused in this preview. Installed app files and production library are unchanged.
- The full-screen menu-bar flash and menu-bar reopening require Dave's physical
  check; no claim of visual acceptance yet. No commit, push, or release.
- Dave subsequently confirmed that closing/reopening the library with the Dock
  icon hidden is better in the startup-only mode. This is user-reported visual
  acceptance of the revised behavior; the agent did not measure menu-bar frames.

### Sort menu alignment follow-up

- Dave identified excessive trailing space beside the sort control. It was inside
  the library title's preferred-width hosted view, whose SwiftUI spacer could not
  consume the rest of the native toolbar segment.
- Moved sort into a separate 24-point hosted toolbar item immediately before the
  snippet-list tracking separator, with a native flexible space between the title
  and sort item. Restored the title's original sizing. No panel constraints or
  sorting behavior changed.
- Review-loop passed for this layout-only diff; strict formatting, whitespace,
  and the provisioned build pass. Reopened the isolated preview and confirmed
  the separate accessible toolbar control. Dave retains visual verification.

### CleanShot clipboard verification

- Dave recopied directly from CleanShot. A read-only pasteboard inspection found
  one item with public.file-url and public.png. AppKit's file-URL reader returned
  the underlying CleanShot media file with spaces decoded in its path.
- Created Clipboard Path Check / zzclip / {clipboard} with a Clipboard mapping
  in the isolated development library. Invoked Copy Expanded Text in the running
  build; subsequent inspection confirmed plain text containing the exact full
  CleanShot image path. No application error appeared. This action intentionally
  replaced the copied image with the resolved path, as Copy Expanded Text does.
- Automatic typing remains unverified in this build: the preview reported
  Permission required. Its earlier paused state and separate test library also
  explain why production keywords could not be used in the preview. No additional
  clipboard code changes were needed for CleanShot's file-url/png combination.

### User acceptance and commit

- Dave reported testing the pending changes and authorized committing all of them.
  This is user-reported acceptance; no additional specific test matrix or agent
  measurement is implied. The earlier automated/build/review results remain as
  recorded above.

### Theme-colored Dock icons

- Exported eight background-color variants from the existing X2 Icon Composer
  document with Apple's renderer. The original layers, source document, and
  installed blue app icon remain unchanged. A repeatable exporter regenerates
  the asset catalog variants.
- The saved accent applies at launch; changes update the running Dock icon on
  the main actor. Repeated hosting-root notifications do not reassign the same
  icon. Blue restores the installed layered icon. Runtime images include 10%
  transparent margins on every side to match the compiled macOS icon footprint.
- Provisioned Debug build, strict Swift formatting, exporter syntax, asset
  manifests, and whitespace checks pass. A temporary native AppKit harness using
  the production icon-update code loaded all eight assets from the compiled app,
  verified 1024-point dimensions and transparent margins, exercised every color,
  checked duplicate-update suppression, and restored Blue. Its initial actor
  isolation compile error was corrected in the harness before the passing run.
- Review-loop completed with a clean pass covering lifecycle, asset lookup,
  source preservation, documentation, and unchanged Dock activation policy.
  No expansion or persistence changes were made. Dave retains native visual
  acceptance; these checks do not establish actual Dock appearance.
- Finder and Spotlight retain the installed blue icon. The menu-bar template
  remains monochrome, and menu-bar-only mode continues hiding the Dock icon.
- Dave inspected the preview, reported that it looks good, and authorized the
  commit. This records user visual acceptance of the theme-colored icons.

## 2026-10-25: public source and 0.2.1 preparation

- Dave selected MIT for the code. Added the license, a bundled license copy,
  reserved-brand policy, closed-contribution policy, and 0.2.1 release notes.
  Corrected obsolete ad-hoc build instructions to describe CloudKit provisioning
  and independent fork identities. The local release workflow is unchanged.
- GitHub's API confirms pull requests are disabled and Issues remain enabled.
  Before publication, fetched all remote refs and ran a redacted Gitleaks scan
  across all 17 existing commits with zero findings. The remote has only main;
  no tags or additional branches were present. Tracked filenames and identity
  references were also inspected; credentials, profiles, stores, and release
  artifacts are not tracked. This is a scoped audit, not a guarantee that every
  possible secret pattern can be detected.
- Full acceptance checks pass: 54 Swift tests (49 core and 5 layout), 16 offline
  release tests, 5 provisioning tests, strict formatting, shell syntax, whitespace,
  and the provisioned Debug build. The built app contains the exact MIT license.
- Review-loop clean pass: reviewed all new policy files, release notes, README
  corrections, bundled license, and the license-consistency check. No application
  behavior changed during release preparation. Visual acceptance remains Dave's
  earlier reported testing of the included changes.

### Public repository and prepared release

- Committed and pushed the licensing and release preparation as `eb841dd`.
  Made `eastechs/tapster` public and verified it through GitHub's unauthenticated
  API: MIT recognized, pull requests disabled, Issues enabled.
- Prepared `dist/0.2.1-6/` from source
  `eb841dd9ec5c776cc2bc4a5e7f92f0ee9a01b01c`. The universal app includes arm64
  and x86_64, preserves the bundle identity, production CloudKit entitlements,
  and signed-update requirements, and includes the MIT and Sparkle notices.
- Apple accepted notarization submission
  `930481fc-d4db-4138-ac98-db25cd0e28fd`. Stapling, Gatekeeper assessment, and
  nested signature validation passed. Dave approved Sparkle's Keychain prompt;
  feed generation and cryptographic verification then completed successfully.
- Independently verified archive/feed SHA-256 hashes against the manifest, feed
  version 0.2.1/build 6, archive size, download URL, and Sparkle feed signature.
  Archive SHA-256:
  `82629955d1445b5b7385b127638c3832c26148bd85e57dcee76ee745c69ccb63`.
- No release files were uploaded to Spaces, no live feed was changed, and the
  installed app was not replaced. The live feed read during preparation was
  0.2.0 (5). Actual update acceptance is recorded below.

### 0.2.1 publication

- Dave authorized committing, pushing, and publishing the prepared release.
  Preparation notes were pushed as `45be1b2`.
- The local publish script verified the archive/feed hashes and Sparkle
  signatures, confirmed build 6 supersedes the existing feed, and uploaded
  `macos/Textend-0.2.1-6.zip` to Spaces. The downloaded CDN archive matched the
  prepared SHA-256 before the script published `macos/appcast.xml`.
- Publication completed successfully. The public feed's bytes match the signed
  local feed and advertise 0.2.1 (6) at
  `https://cdn.usetextend.com/macos/Textend-0.2.1-6.zip`.
  Publication did not replace the installed app; actual update acceptance is
  recorded below.

### 0.2.1 update acceptance

- On 2026-10-25, Dave reported that the update to Textend 0.2.1 (6) worked.
  This records user-confirmed acceptance of the actual in-app update following
  the verified Spaces/CDN publication. No additional checks of permissions,
  library contents, or sync behavior were reported for this update.

### Textend repository and project naming

- Renamed the GitHub repository to `eastechs/textend` and updated origin. GitHub
  confirms public visibility, MIT, disabled pull requests, and enabled Issues.
- Renamed the Xcode project, target, scheme, Swift module, source directory, app
  entry point, schema types, Swift package targets, test directories/imports,
  reference-image filename, and Codex Run environment to Textend. Updated build,
  release, check, and icon-export scripts plus current documentation and links.
- Retained the released bundle ID, CloudKit container, Application Support and
  preferences identities, and window autosave keys for compatibility. Historical
  verification entries keep names used at the time. No artwork was regenerated.
- Before renaming, compiled the original model code under the released module
  name and wrote synthetic V1/V2 stores outside the repository. A separate probe
  compiled under Textend opened both and verified their records, collections,
  placeholder mappings, favorites, timestamps, and unchanged entity version
  hashes. Added a regression test against those released entity hashes.
- Full checks pass: 55 Swift tests, 16 release tests, 5 provisioning tests, strict
  formatting, shell syntax, license consistency, and the provisioned Debug build.
  Review-loop caught and corrected one formatting issue and a duplicated phrase
  in README; the second pass was clean. Mapped-file comparison confirms the
  source edits are renames and compatibility comments, with artwork unchanged.
- The installed 0.2.1 app and its data were not modified. No new release was
  published and no new two-Mac sync test was performed for this source rename.

## Cross-app keyword detection correction (2026-10-26)

- Dave reported unchanged keywords in Safari and Firefox and earlier reported
  that Mail did not expand. Inspection found mandatory numeric AX selection
  ranges on every keystroke and at expansion, plus a boundary check that treated
  unavailable adjacent text as an interior word position. These are code-level
  blockers; the specific host failures have not yet been reproduced by the agent.
- Keyword tracking now accepts missing numeric ranges and unknown initial
  boundaries. Once a typing run begins, observed word interiors remain excluded.
  Delayed per-key AX offsets no longer reset the run. Available keyword text at
  the caret confirms the replacement even if earlier autocorrection changed the
  predicted offset. Clicks, navigation, shortcuts, focus changes, secure input,
  and generation checks retain cancellation. Expansions and exhausted retries
  clear tracking so an old offset cannot poison subsequent matches.
- Cursor markers without numeric AX ranges use tagged relative Left events for
  at most 256 trailing characters, after a short delivery delay. Input, focus,
  selection, and secure-input changes cancel that pending move. Longer moves
  require AX positioning and otherwise leave the keyword unchanged. Relative
  placement relies on host insertion timing and still needs live acceptance.
- All 32 focused tracking, matcher, insertion, and transaction tests pass.
  Strict formatting and whitespace checks pass. Review-loop reached a clean
  second code pass after correcting post-expansion tracking and autocorrection
  handling. Existing focus and template contracts were also checked.
- The provisioned Debug app builds successfully. Xcode's generated Sparkle
  workspace metadata still contained the old tapster checkout path; corrected
  that one cached artifact path after normal package resolution did not repair
  it. A backup is at /tmp/textend-package-workspace-state-before-path-repair.json.
  Build output also reports stale pre-rename build-product paths, without source
  compilation errors. No build scripts or dependencies were changed.
- No installed-app replacement, process launch, commit, push, or release was
  performed. Safari, Firefox, Mail, and TextEdit live typing remain pending.

### Follow-up after Firefox and desktop-app typing checks

- Dave reported that the first corrected build still worked in TextEdit, partly
  expanded in Firefox without placing the cursor, and did nothing in ChatGPT
  Desktop or Claude Desktop. The first patch did not establish cross-app
  acceptance, despite passing its isolated tests.
- Removed the remaining requirement for a focused AX element. Target identity
  now follows the active process and its window when available. Missing,
  disappearing, or recreated editor elements no longer invalidate a typing run.
  Known secure fields and Textend's own editors remain excluded. Mouse and
  keyboard navigation still cancel pending work. An unreported programmatic
  focus change cannot be detected when the host exposes no usable context.
- Numeric ranges alone no longer veto a match. Optional readable keyword text
  can corroborate delivery; conflicting text gets a bounded retry. Short cursor
  moves use tagged arrow keys even when AX reads work, avoiding dependence on
  effective AX selection writes. Editors with numeric ranges but no readable
  text use the relative path, and loss of text access after insertion also falls
  back. Long moves retain the existing AX requirement and event-count bound.
- Consulted Espanso's macOS detection and injection implementations and cursor
  compensation middleware, and Snippety's documented relative cursor approach.
  Reused Textend's native event and clipboard code; added no dependency or copied
  third-party implementation.
  References: https://github.com/espanso/espanso/tree/dev/espanso-detect/src/mac,
  https://github.com/espanso/espanso/blob/dev/espanso-engine/src/process/middleware/action.rs,
  https://snippety.app/help/macos/creating-template/cursor-position/.
- Added development-only unified logs for engine status, AX availability,
  boundary classification, matched/injected stages, and cursor strategy. Logs
  contain fixed reasons and process IDs, with no typed text, keywords, snippet
  contents, clipboard data, or document text. This gives subsequent physical
  checks a repeatable diagnostic path without adding a setting or recurring job.
- All 38 focused tests pass, along with strict formatting, whitespace, and the
  provisioned Debug build. Review-loop's second pass was clean after tightening
  partial-AX cursor fallback and the delayed-read regression fixtures. The tests
  cover absent/recreated AX elements, app/window changes, secure and own-app
  exclusions, partial and disappearing text APIs, cancellation, matching, and
  clipboard preservation. They do not establish live cross-app behavior.
- Refreshed the already-running development app through its normal Quit action
  after checking that Save was disabled, then reopened the same build. Verified
  one Textend process, PID 28222, Expansion active in the library, and actual
  startup/typing-context diagnostic events. No installed-app replacement,
  production-library changes, commit, push, or release. Dave retains physical
  typing verification in Firefox, ChatGPT Desktop, and Claude Desktop.

### User feedback and 0.2.2 release authorization

- Dave reported that the revised development build "seems to be better," then
  requested committing the fixes and shipping a new release. This records his
  reported improvement and release authorization, not an exhaustive per-app
  acceptance matrix.
- The live feed advertises 0.2.1 (6). Selected 0.2.2 (7) for this compatibility
  patch and added concise release notes. Source tagging follows the current
  release policy: tag the manifest's exact source commit after publication.
- Full acceptance checks pass: 71 Swift tests (66 core, 5 layout), 16 offline
  release tests, 5 provisioning tests, strict formatting, shell syntax, license
  consistency, whitespace checks, and the provisioned Debug build. The final
  pre-commit review-loop pass found no further issues in the cumulative diff.

### 0.2.2 publication

- Committed the compatibility fixes and release notes as
  `a391cc846fd66e93fc1bc0cb27eb1044db8c0084`. Prepared universal 0.2.2 (7) from
  that clean source revision with the existing bundle identity, production
  CloudKit entitlements, and signed-update requirements.
- Apple accepted notarization submission
  `3fc142ae-82f6-4398-853c-9e95cd40ce08`. Nested code signatures, stapling,
  Gatekeeper assessment, Sparkle signatures, archive/feed hashes, and embedded
  release notes passed validation. Archive SHA-256:
  `582ae0f72ed5d6ca856f33e164d6c54a057d94b30bb2f4fd9102ac0527f9895d`.
- The first publication attempt stopped before upload because the cached AWS
  CLI launcher retained the old tapster Python path. Preserved that ignored
  environment as `.build/release-tools.before-rename-repair` and recreated it
  through the existing pinned setup script. No application or release-script
  source changed during this repair.
- Published `macos/Textend-0.2.2-7.zip` to Spaces, verified the public CDN download
  against its prepared SHA-256, then published the signed appcast. An independent
  fetch confirms the live feed matches the prepared feed byte-for-byte and
  advertises 0.2.2 (7). No installed-app replacement or actual Sparkle update was
  performed during publication.
- Dave explicitly approved the public source push. Pushed the source and release
  records to `main` and the annotated `v0.2.2` tag to GitHub. Remote verification
  confirms that the tag targets the exact source revision in the release manifest.

## Expansion recovery after sleep (2026-10-27)

- Found a recovery gap in the keyboard listener: wake notifications only refreshed
  the existing tap, and health checks only tried to re-enable it. An invalid port
  or a listener that remained enabled without delivering events was never replaced.
- Sleep and session departure now cancel pending expansion and remove the listener.
  Wake, display wake, and session return create a fresh listener when expansion is
  allowed. Sleep and session state are tracked separately so either can keep
  monitoring suspended until both have finished.
- Health checks replace invalid listeners and listeners that cannot be re-enabled.
  Failed installation retries automatically and reports `Reconnecting expansion`
  instead of falsely reporting active expansion or requiring an app restart.
  The health timer also runs while macOS menus are open. Repeated start/stop calls
  do not duplicate observers, timers, or listeners.
- Added 12 regression tests for wake recovery, display/session transitions,
  invalidation, disable callbacks, failed installation, and permission, pause,
  Secure Input, and input-method restrictions. All 83 Swift tests pass (78 core,
  5 layout). Strict Swift formatting, whitespace checks, the provisioned Debug
  build, and deep signature verification pass. Xcode reports only the existing
  warnings about not stripping signed Sparkle binaries.
- Review-loop passed on its first iteration, covering the diff, expansion
  requirements, regression tests, formatting, callback ownership, resource
  cleanup, and sibling service conventions.
- This verifies simulated lifecycle transitions and the development build.
  Physical sleep/wake typing has not been tested. The running installed app is
  still 0.2.2; no release, installation, source commit, or publication was performed.

### 0.2.3 release preparation

- Dave requested committing the fix and shipping an update for his installed app.
  The live feed advertises 0.2.2 (7), so this patch uses 0.2.3 (8).
- Full release acceptance checks pass: 83 Swift tests, 16 offline release tests,
  5 provisioning tests, strict formatting, shell syntax, license consistency,
  whitespace checks, and the provisioned Debug build. Review-loop rechecked the
  cumulative diff and release notes with no remaining findings.

### 0.2.3 publication

- Committed the recovery fix, tests, and release notes as
  `d8c3fd530032f090fa4e1fa8f59969a3daa6b108`. Built universal 0.2.3 (8) from that
  clean revision with the existing Developer ID identity, production CloudKit
  entitlements, and Sparkle signing key.
- Apple accepted notarization submission
  `6f448d50-952b-47a5-9adf-3bf3d960f668`. Nested signatures, stapling, Gatekeeper
  assessment, Sparkle signatures, and archive/feed hashes passed validation.
  Archive SHA-256:
  `898833394ce3bfc3c05e2e463896d5e09046f205069d5dc42c3e248502b7c10a`.
- Published `macos/Textend-0.2.3-8.zip`, verified its public CDN download against
  the prepared hash, and published the signed appcast. An independent fetch
  confirms the live feed matches the prepared signed bytes and advertises
  0.2.3 (8), with the expected cache-control header.
- Pushed the release source to `main` and the annotated `v0.2.3` tag to GitHub.
  Remote verification confirms the tag targets the manifest's source revision.
  The installed app was left for Dave to update through Sparkle. Physical
  sleep/wake typing and the installed-app update remain unverified.

## Quick Access, app-specific collections, and Compositions (2026-10-27)

### Implementation and automated verification

- Added a reusable nonactivating Quick Access panel with local configurable
  Command-Shift-Space shortcut, current-app/all-items filtering, favorites-first
  search, preview, Return insertion, Command-Return copy, and Escape dismissal.
  KeyboardShortcuts 3.1.0 provides the recorder and registration; its MIT license
  is bundled. Opening the panel cancels automatic matching. It does not change
  Dock policy or open library windows.
- Manual insertion captures the original AX element and numeric selection plus
  the clipboard value. It resolves saved content once at confirmation and checks
  the destination, saved-library revision, app restrictions, exclusions, Secure
  Input, and permissions before posting events. Both insertion paths share
  serialization, clipboard restoration guards, and caret-placement cancellation.
- Collections store optional app bundle IDs. Shared eligibility logic selects
  app-specific keywords ahead of globals and suppresses equally scoped conflicts
  only in overlapping apps. Missing or malformed collection scopes fail closed.
  Local saves and imports reject newly introduced conflicts, including a wider
  conflicting app region or a missing collection restored by an import.
- Compositions have live snippet references, literal blocks, stable block IDs,
  separators, reorder controls, a combined preview, and at most one cursor across
  included occurrences. Availability intersects every source and the Composition's
  own collection. Missing/invalid sources cannot produce partial output.
- Added schema V3 and JSON backup V2 while preserving frozen V1/V2 model identities
  and V1 JSON imports. Migration creates a pre-v3 SQLite backup. Recovery retains
  malformed raw block data; duplicate Composition rows reconcile deterministically.
  Ordered blocks merge as one draft field. Partial remote arrivals remain visible
  and unavailable until dependencies arrive.
- Added focused tests for resolution, cursor offsets, repeated references,
  restrictions/precedence/conflicts, dirty draft merging, remote deletions, partial
  arrivals, identity reconciliation, raw recovery, migration, atomic imports,
  palette search, exact focus snapshots, selection replacement, and delayed caret
  cancellation. A shared remote-store fixture keeps the persistence checks isolated.
- Final `./script/check.sh` passes: 114 Swift tests (109 core, 5 layout), 16 offline
  release tests, 5 provisioning tests, strict formatting, shell syntax, license
  consistency, whitespace checks, and the provisioned Debug build. Deep/strict
  signature verification succeeds with host certificate trust. The sandbox alone
  could not access the required trust state.
- SwiftPM's new resource bundle exposed globally applied signing overrides and
  mismatched Debug architectures. Signing/profile overrides now use app-specific
  settings; Debug uses the active architecture. Release continues to request both
  arm64 and x86_64. A universal release has not been built for these changes.
- Review-loop reached a clean code/automated pass on iteration 3. Earlier passes
  fixed conflict-region detection, delayed caret cancellation while auto expansion
  is paused, search focus on repeated palette openings, and cursor-only insertion
  over a selection. No native or CloudKit acceptance is inferred from these tests.

### Remaining acceptance

- Dave's UI inspection preference is pending. The development app is built but
  has not been launched for this feature check. The installed application and its
  production library were not replaced or changed.
- Verify the new views, keyboard navigation, shortcut recording, Light/Dark/theme
  colors, repeated panel use, native focus restoration, selection replacement,
  secure/excluded fields, and actual insertion in the target applications.
- Initialize and inspect V3 in the development CloudKit environment, then test
  restrictions, Compositions, sources, remote edits/deletions, partial arrival,
  offline changes, and draft conflicts on two updated Macs. Production schema
  promotion and production-signed access remain release gates.
- The detailed checklist is in `docs/quick-access-compositions.md`. No source
  commit, push, release, schema promotion, or publication was performed.

### Separate development identity (2026-10-27)

- Dave requested a distinct development app to avoid replacing production's
  Accessibility entry while switching builds. Debug now produces `Textend Dev.app`
  with bundle `chat.eastechs.textend.debug`. Release keeps `Textend.app`,
  `chat.eastechs.tapster`, its Developer ID profile, and the production CloudKit
  environment. Resolved Xcode build settings confirm both configurations.
- Development preferences use the new bundle's UserDefaults domain. Its library
  now lives under `Application Support/chat.eastechs.textend.debug`; the old
  development library and production library are preserved. Library/Help windows,
  menu bar labels, startup settings, logs, and build tooling identify Textend Dev.
  Both app identities' editors are excluded from development expansion.
- Provisioning validation rejects interchanged development/production profiles.
  Development accepts an exact-ID Xcode team profile and prefers a named
  `Textend Dev CloudKit Development` profile for multiple test Macs. Added the
  explicit `--setup-development-signing` script mode for initial account-backed
  provisioning; normal builds remain local and fail clearly when it is missing.
- 29 focused Swift tests, 16 release tests, and 7 provisioning tests pass. Strict
  formatting, shell syntax, whitespace checks, and an unsigned Debug compile pass.
  Review-loop found no further code issues in the identity changes. Production
  signing settings remain unchanged.
- The signed build is blocked: Xcode reports that its saved Developer account
  lacks a valid Xcode token, and the new development identity has no profile yet.
  No signing fallback or launch was used. Dave must sign in again through Xcode
  Settings → Accounts before setup can finish. Accessibility for Textend Dev then
  needs a one-time user grant. UI/cross-app and CloudKit acceptance remain pending.

### Textend Dev provisioning and launch

- After Dave refreshed Xcode sign-in, Xcode registered/provisioned
  `chat.eastechs.textend.debug` with the existing CloudKit container. Its managed
  Mac development profile includes both registered test Macs. Signed entitlements
  select Development and development push notifications.
- The first setup attempt exposed a signing-mode mismatch: Xcode-managed profiles
  cannot be passed to a manually managed build. The build script now selects the
  profile's signing mode, keeps production manual signing unchanged, and validates
  the built bundle ID, signature, embedded profile, and signed environment before
  launching. Debug's Xcode default also uses automatic signing.
- Nine provisioning tests and 16 release tests pass, along with shell syntax and
  whitespace checks. Review-loop's follow-up pass found no further code issues.
  The signed Textend Dev build passes the new verification and launches through
  `--preview`, with automatic expansion paused. One development process and one
  library window were observed; no production instance was started.
- Native visual/interaction inspection is pending OS permission. The inspection
  process reports no Accessibility or screen-capture access, and a capture of
  only the Textend Dev window failed. This execution host is ChatGPT.app, not the
  separate Codex.app. No UI acceptance is claimed. Textend Dev also needs its own
  one-time Accessibility grant before insertion checks.

### Preview expansion state (2026-10-27)

- Dave chose to inspect the UI himself. The subsequent screenshots showed Paused
  in the menu and sidebar while Settings was enabled and the menu offered Pause.
  `--sync-preview` skipped engine startup entirely, leaving its initial status
  unchanged even after an explicit enable action.
- Preview startup now starts the engine lifecycle in a session-only paused state.
  Settings and the menu read the same enabled value; Resume starts monitoring or
  reports the actual permission/input availability. Launching a preview does not
  overwrite the saved enabled preference. Regular launches retain saved behavior.
- Added regression coverage for paused startup, retained preferences, wake while
  paused, explicit resume/pause, duplicate starts, and permission recovery.
  All 21 focused lifecycle/draft tests pass. Strict Swift formatting and whitespace
  checks pass. The signed development build passes provisioning/signature
  validation and was reopened through `--preview`.
- Corrected the remaining menu Quit label to identify Textend Dev. The review-loop
  follow-up found no further issues after formatting the new test declaration.
  Dave's native interaction checks remain pending; no UI acceptance is inferred
  from the automated checks. No commit, push, or installed-release change.

### Full control hit areas (2026-10-27)

- Replaced the toolbar New menu's hosted SwiftUI label with a native NSPopUpButton.
  Its entire 56-point control opens the menu, including the space around its icon
  and arrow. Both creation actions, accessible naming, and the selected theme
  color are retained.
- Added a shared label hit-area modifier and applied it inside custom control
  labels after their sizing/padding. The audit covered sort/favorite, New
  Collection, expansion status, Settings, Quick Access close, Composition block
  controls/source rows, and application-removal buttons. Standard native buttons
  retain their normal behavior and disabled states.
- The signed development build, five existing native layout checks, strict Swift
  formatting, and whitespace checks pass. Review-loop reached a clean pass on
  iteration 1. The preview was gracefully closed and reopened without changing
  the installed release. Dave is handling live clicks and visual verification;
  these checks do not establish that acceptance. Nothing committed or pushed.

### New draft name focus (2026-10-27)

- New snippets and Compositions request Name focus after their editor attaches.
  The request runs once per editor and checks cancellation/current draft identity;
  saved or remotely deleted records do not trigger it. The input style accepts
  the editor's focus binding so programmatic focus and its focus ring agree.
- An isolated native NSHostingView check using the actual input style confirmed
  that the Name field became first responder and selected the default name.
  Seven focused draft tests, the signed development build, formatting, and
  whitespace checks pass. Review-loop reached a clean pass on iteration 1.
  Textend Dev was reopened for Dave's full creation-flow check. No commit or push.

### Separate Compositions section (2026-10-27)

- Added Compositions directly below All Snippets, with a separate count. All
  Snippets filters out Compositions; Favorites and collections retain both types.
  Headings, search labels, sorting labels, and empty states match the section.
- New items open their primary section while preserving a collection assignment
  chosen from a collection. Source navigation reveals the source in a matching
  list. Sidebar selection persists with compatible existing stored values.
  Unsaved drafts use the same scope rules and Save/Discard/Cancel safeguards.
- Added seven navigation tests, including source search, type separation,
  creation, cancelled/failed transitions, collection deletion, a Composition-only
  library, and selection storage. All 34 focused navigation/draft/Composition/sync
  tests pass, along with the signed build, strict formatting, and whitespace checks.
- Review-loop reached a clean pass on iteration 2 after fixing a stale collection
  search that could hide the selected item following local or remote deletion.
  Textend Dev was reopened for Dave's UI check. No commit, push, or release change.


### Consecutive spaces beside the cursor (2026-10-27)

- Dave observed a period after `Comp one` when a source contained
  `Comp one {cursor}` and its Composition separator was Space. The resolved text
  contains two adjacent spaces, which the short-text insertion path sent as
  separate keystrokes, allowing macOS's double-space period substitution.
- The shared insertion service now uses its existing guarded paste path whenever
  resolved text contains consecutive ASCII spaces. It preserves both spaces and
  the original caret offset for keyword expansion and Quick Access. Single-space
  short text keeps Unicode insertion; no system typing preferences are changed.
- A regression using the actual Composition resolver failed against the previous
  insertion path. All 35 focused insertion/Composition tests now pass, covering
  both entry points, waiting for paste consumption before moving the caret,
  restoration of clipboard representations, and protection of a newer user copy.
  Strict Swift formatting and whitespace checks pass.
- Review-loop reached a clean pass on iteration 1. The signed development build
  passed its provisioning/signature validation and was reopened as Textend Dev.
  Dave confirmed the rebuilt preview fixes the unwanted period in TextEdit.
  This verifies the reported Composition case; the broader feature and CloudKit
  acceptance checklist remains separate.


### Feature commit verification (2026-10-27)

- Dave authorized committing the accumulated Quick Access, app-specific
  collections, Compositions, development-identity isolation, and subsequent UI
  and insertion fixes. The TextEdit double-space fix is user verified.
- The complete `script/check.sh` passed: 124 Swift core/layout tests, 16 release
  tests, nine provisioning tests, strict Swift formatting, shell syntax, license
  consistency, whitespace checks, and the signed Textend Dev build with profile
  and entitlement validation.
- The commit review-loop completed a clean pass on iteration 1. Reviewed the
  pending source, tests, bundled dependency license, provisioning changes, and
  documentation. The existing feature checklist retains unverified native and
  V3 CloudKit release acceptance items. This commit does not publish a release.


### 0.3.0 release candidate verification (2026-10-27 and 2026-10-28)

#### Artifact and automated checks

- Prepared universal 0.3.0 (9) from clean, pushed source
  `98082485fd2d1183882a2b69af9f3502414ebdd2`, retaining the Developer ID identity,
  Production CloudKit/APNs entitlements, and Sparkle key. Apple accepted
  notarization submission `8ca231e5-e7fb-4ac0-a99c-7423ba5781a1`.
- Nested/deep signatures, architecture and bundle checks, stapling, Gatekeeper,
  and Sparkle signing/verification passed. The package includes Textend,
  KeyboardShortcuts, and Sparkle license notices.
- `dist/0.3.0-9/` contains the signed ZIP, appcast, and manifest. ZIP SHA-256:
  `29af325f6dff63940cf354a7eeded6f69e37e70a5e9e1013d4a688036029a037`.
  ZIP/feed hashes were rechecked against the manifest after the sync tests.
  No app source changed during packaging or acceptance; the manifest revision
  remains the authoritative release/tag target.
- Before commit, `script/check.sh` passed 124 Swift tests, 16 release tests,
  nine provisioning tests, formatting, shell/whitespace/license checks, and
  the signed development build. Those unchanged tests were not rerun for
  documentation-only updates. Actual CloudKit checks below supplement them.

#### Schema review and production deployment

- Ran the existing development schema initializer using its dedicated store.
  Initialization completed and the app subsequently opened its normal library.
  Dave chose CloudKit Console; no CLI management token was created or saved.
- Reviewed Dave's pending-deployment screenshot against the release model. It
  adds `CD_appBundleIDs` (bytes) and its asset companion to `CD_SavedCollection`,
  with two indexes; it creates `CD_SavedComposition` with 25 fields and 33 indexes.
  The fields cover blocks, identity, collection membership, name, keyword,
  template, favorite/enabled state, dates, and Core Data metadata/asset storage.
  No deletions, existing-field type changes, or snippet-type changes were shown.
- The three role changes apply read/create/write permissions to the new type.
  The release explicitly uses the private CloudKit database. Apple's public
  database role permissions do not expose that private library; see
  [Apple's CloudKit design guidance](https://developer.apple.com/icloud/cloudkit/designing/).
- Dave confirmed "Changes Deployed." The agent reviewed the screenshot but did
  not operate the Console in this session. Schema promotion preceded verification
  of the new records using the production-signed app.

#### Signed production and two-Mac evidence

The MacBook Pro ran the exact signed export with `--sync-preview`, a separate
`ProductionPreview` library, expansion initially paused, and Sparkle disabled.
No competing Textend process was launched. That existing preview configuration
already had sync enabled. Its store migrated to V3 with a pre-v3 SQLite backup,
then downloaded six snippets and three collections from production.
Dave ran the signed test build on the Studio and reported its UI results.

| Scenario | Verified result |
| --- | --- |
| Initial upload/download | The preview imported one disposable collection, source, and Composition with empty keywords. At 04:12:02, CloudKit completed a three-object private production export, then found zero remaining objects. Dave confirmed the records and TextEdit restriction arrived on the Studio without importing the JSON there. |
| Reverse source edit | `studio edit` arrived here; the receiver's release resolver used it in the Composition. Dave confirmed the Studio preview updated. |
| Offline edit/reconnect | Dave reported reconnecting after offline edits. `studio offline` and the Notes-only restriction arrived here at 04:49:50. The core allowed Notes and rejected TextEdit. |
| Reverse Composition edit | Literal Block 2 arrived as `edited on studio` at 04:53:28, retaining identity, source reference, and scope. |
| Concurrent dirty draft | Dave confirmed an unsaved local name survived the Studio's block change. Saving retained both actual values: `Draft Composition Check` and `concurrent block`. Both were independently verified in the receiver's saved record. |
| Remote source deletion | Dave confirmed a missing-source warning on the Studio. At 05:08:29, the source was absent here while the Composition remained. The release resolver rejected it and computed an empty scope. |
| Missing dependency arrives later | Dave imported a source-only restore with the original logical ID on the MacBook Pro. He confirmed the Studio warning cleared and its preview updated without restarting. The receiver has exactly one test source, Composition, and collection; resolution yields `Restored source check` followed by a newline and `concurrent block`, restricted to Notes. The observed transfer preference advanced through 05:49:01. |

Times above are America/Chicago on October 28. Transfer timestamps alone were
not treated as proof of second-device delivery. Studio observations are Dave's
reports; receiver data and resolution checks are agent-verified. Missing-dependency
recovery was exercised through deletion and later restoration, not by forcing
CloudKit to split an initial download. Automated tests separately cover partial
source/collection arrival.

A reusable read-only fixture helper selects only the three disposable IDs and
opens SQLite read-only/query-only. Its snapshots were resolved with the release's
existing core code. Syntax, expected values, scope eligibility, and missing-source
rejection passed. This does not claim native UI or physical keyboard verification
on the receiver. Fixture files and the detailed session log remain in the ignored
`build/releases.noindex/0.3.0-9/` directory.

#### Remaining acceptance and publication

- Production CloudKit transfer, offline/reconnect, concurrent drafts, remote
  deletion, and later dependency recovery passed the checks above. Dave also
  confirmed actual Quick Access/Return insertion of the test Composition into
  Notes and its absence from TextEdit's Current App results in the signed preview.
  This is user-verified native behavior, separate from the core eligibility tests.
- The broader visual/accessibility, selection-replacement, shortcut-reconfiguration,
  and additional target-app checklist remains explicitly unverified where no
  result is recorded. The Notes/TextEdit check does not establish universal app
  compatibility. Dave retains UI verification.
- The three disposable test records remain, with empty expansion keywords. The
  installed app has not been replaced.
- Nothing was uploaded to Spaces, no live appcast or tag was changed, and no
  commit or push was performed. The last checked live feed remains 0.2.3 (8).
  Publication and a real updater installation of 0.3.0 are separate steps.
- Final artifact verification rechecked ZIP/feed manifest hashes, build 9's
  CDN URL and archive length, the app's deep/strict signature and version, and
  its stapled notarization ticket. All remained valid; files were not rebuilt.
- Release-evidence review-loop passed after consolidating intermediate status
  notes and clarifying schema-deployment/production-test order. Reviewed the
  full pending documentation diff, release notes, fixture validation results,
  artifact checks, and sibling release instructions. Whitespace checks passed;
  remaining native coverage is explicitly recorded. No app source changed.


### 0.3.0 publication (2026-10-28)

- Dave authorized commit, push, and publication after the signed production
  CloudKit and native Notes/TextEdit checks. Preparation documentation was
  committed and pushed as `c788919`.
- Ran the existing local `script/release.py publish dist/0.3.0-9` workflow. It
  verified the Sparkle feed/archive signatures, uploaded the immutable ZIP to
  Spaces, downloaded it through the CDN and matched its SHA-256, then published
  the update feed last. The command completed successfully for build 9.
- Independently fetched the public feed: HTTP 200, version 0.3.0, build 9, and
  exact SHA-256 match with the signed local feed. Its cache header is
  `no-cache,max-age=0,must-revalidate`. The archive returns HTTP 200 with
  12,831,317 bytes and `public,max-age=31536000,immutable`.
- Created and pushed annotated tag `v0.3.0` at the manifest source revision
  `98082485fd2d1183882a2b69af9f3502414ebdd2`, including version/build and archive
  hash in the annotation. Independently verified its remote peeled target.
- Live download: https://cdn.usetextend.com/macos/Textend-0.3.0-9.zip
  Live feed: https://cdn.usetextend.com/macos/appcast.xml
- No installed application was replaced. An actual Sparkle update to this
  version has not yet been reported; the broader unverified native coverage
  above remains documented. The three disposable sync records remain available.
- The publication-note review-loop passed on iteration 1: reviewed the exact
  documentation diff against publication output, CDN responses, manifest, tag,
  and sibling release instructions. `git diff --check` passed. No code changes
  required a build or test rerun.


### 0.3.1 publication (2026-10-28)

- Dave confirmed the first-launch permission setup works and explicitly approved
  Apple notarization, public CDN/feed publication, and pushing release source/tag.
- Release source: `3f02e98a5755131eaae9973b2ec7d0f586eb2da3`. Both Xcode configurations
  now default to 0.3.1 (10), matching the exported app's About metadata.
- The final app checks passed: 131 Swift tests, 16 release guard tests, 9 provisioning
  tests, Swift formatting, whitespace checks, and the signed development build.
  Release metadata and release-note review-loop passed with no remaining findings.
- Built and exported a universal arm64/x86_64 app with the existing Developer ID
  identity and production CloudKit configuration. Apple accepted notarization
  `8ee63839-1a54-4c88-b0a8-13d446d597b4`. The release script verified the
  nested signatures, stapled ticket, Gatekeeper assessment, and Sparkle signatures.
- Published `Textend-0.3.1-10.zip` through the existing release workflow. The CDN
  download matched SHA-256 `5b522c95792ed933cc03624b16e28d5e6419ff336f304676151c7e56178cd55a`
  before the update feed was published. Download size: 12,859,896 bytes.
- Independently verified the public feed reports 0.3.1 (10) with the exact local
  feed hash `9d501f8f5c363d391f30dbad6dc3a277a8925eaf46f77b8e5caf84f48b8b440d`. Feed and ZIP
  returned HTTP 200 with their expected revalidation and immutable cache policies.
- Pushed source and annotated `v0.3.1`; the remote peeled tag matches the manifest
  source revision above. The tag annotation records version, build, and archive hash.
- The installed app was not replaced. A real Sparkle update to this version has
  not been verified in this release run.

## Keyboard callback delays after sleep (2026-10-30)

- Dave reported that keywords failed in ChatGPT after sleep and after restarting
  Textend, then worked in Notes and subsequently in ChatGPT. The installed app is
  0.3.1 (10). Inspection after recovery showed expansion active and Secure Input
  disabled. The event tap reported substantial latency, but the sampled process
  was idle. The original failure was not reproduced, and release builds had no
  expansion diagnostics to establish its exact cause.
- Found synchronous accessibility queries inside the active keyboard-tap callback.
  Editor inspection now runs after that callback returns, so those queries do not
  hold the current keystroke. The initial word boundary is checked before the full
  confirmed keyword because the editor can already have consumed the typed keys.
- Input older than half a second is discarded using the event timestamp, with
  callback time as the fallback for events without a timestamp. App changes,
  lifecycle recovery, pause, palette changes, and library updates invalidate
  queued input. New physical input invalidates pending replacement immediately,
  including when it arrives during accessibility reads or insertion preparation.
- Release builds now retain the existing fixed-reason expansion diagnostics,
  including listener disable/timeout events. Logs contain no typed text, keywords,
  snippet contents, clipboard contents, or document text.
- Reviewed the existing native pipeline, Apple's event-tap/AX API contracts, and
  [Espanso's macOS detection implementation](https://github.com/espanso/espanso/blob/dev/espanso-detect/src/mac/native.mm).
  Reused Textend's event-tap, insertion, and logging infrastructure without adding
  dependencies or changing permissions.
- Added 14 regression tests. All 83 focused input, focus, lifecycle, tracking,
  matching, insertion, and transaction tests pass. Strict Swift formatting,
  whitespace checks, and the provisioned macOS development build pass. Xcode
  reports an unrelated installed CoreSimulator version mismatch; the macOS build
  succeeds without simulator support.
- Review-loop reached a clean fourth pass. Earlier passes reproduced and fixed
  two accessibility reentrancy races and extended stale-event rejection to cover
  delays before the callback itself, and corrected a test-closure compiler error.
  Reviewed cancellation, clipboard restoration,
  generated-event filtering, logging privacy, and sibling service/test conventions.
- No installed-app replacement, app relaunch, commit, push, or release was made.
  Live ChatGPT and physical sleep/wake acceptance remain pending.

## iCloud preference and account-status correction (2026-10-31)

- Dave reported iCloud sync appearing to turn itself off, including after a Mac
  restart, with an unexpected restart message. Read-only inspection found the
  production configuration still enabled. No production preferences or libraries
  were edited during this investigation.
- Found two direct causes: Settings bound the switch to the current store's
  mirroring state instead of the saved choice, and every `CKAccountChanged`
  notification immediately invoked recovery, persisted sync as disabled, and
  selected a new local library before verifying the account. Apple's
  [notification contract](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ckaccountchanged)
  covers status changes and instructs the app to query account status.
- Notifications now recheck the account. Same-account and temporary-unavailability
  results retain the enabled preference and existing library. Restricted access
  is no longer classified as a sign-out. Confirmed sign-outs and different
  identities retain the existing recovery and account-isolation behavior.
- Cancelled, stopped, or superseded checks cannot disable sync or overwrite a
  newer verified identity. Cache fallback also requires the system identity to
  remain stable during the lookup.
- The switch now represents the saved choice for the current account. A local
  startup while iCloud is unavailable keeps that choice enabled. Once the same
  account is verified, Settings explains the startup condition and offers the
  existing restart action without disabling the preference. Reattaching such a
  locally opened store still requires restarting Textend.
- Added 12 regression tests using isolated temporary libraries and simulated
  CloudKit responses. All 21 focused provider, account, lifecycle, store, and
  persistence-identity tests pass. Formatting, whitespace checks, and the signed
  macOS development build pass. Review-loop completed a clean first pass over the
  notification flow, stale requests, cache ownership, recovery boundaries, switch
  binding, restart configuration, and sibling service/test conventions.
- The earlier keyboard patch remains in the same local working tree. No commit,
  push, release, installed-app replacement, or relaunch was performed. Live
  Settings, reboot/login, and two-Mac sync checks remain pending.

### Development launch and commit acceptance (2026-10-31)

- Subsequently rebuilt and launched Textend Dev with both fixes using
  `./script/build_and_run.sh --verify`; the development process was confirmed
  running. The installed production app was not replaced.
- The complete Swift suite passes: 152 tests, zero failures. Strict formatting and
  whitespace checks pass. The combined pre-commit review-loop reached a clean
  first pass without additional code changes.
- Launch verification does not establish live ChatGPT, sleep/wake, reboot/login,
  or two-Mac sync acceptance. Those checks remain pending.
