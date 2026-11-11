# Textend local releases

Sparkle 2.10.0 checks `https://cdn.usetextend.com/macos/appcast.xml`. The app uses
Sparkle's native update UI, daily automatic checks with user consent, and optional
automatic downloads/installation. Debug builds never start the updater. Release
builds use a signed feed and verify signed downloads before extraction. An update
restart uses the existing Save/Discard/Cancel check for unsaved snippets.

Everything builds and signs on this Mac. Apple provides notarization, and
DigitalOcean Spaces serves the resulting files. No GitHub Actions, update backend,
or CI service is involved.

Hosting uses the `textend-releases` bucket in `atl1`, with origin API endpoint
`https://atl1.digitaloceanspaces.com`. Its Spaces CDN address is
`https://textend-releases.atl1.cdn.digitaloceanspaces.com`; the app uses the custom
domain `https://cdn.usetextend.com`.

## One-time configuration

1. Resolve Sparkle with `./script/build_and_run.sh --build-only`.
2. Run `./script/setup_release_tools.sh` to install the pinned AWS CLI into the
   ignored `.build/release-tools` virtual environment. A system `aws` installation
   also works. The CLI uses the Spaces S3-compatible API.
3. Copy `Config/release.example.json` to `Config/release.local.json`. The example
   contains Textend's bucket and regional endpoint. Keep `spaces_prefix` as `macos`.
   This local file holds configuration names, not passwords or API secrets.
4. Set up the Spaces CDN custom domain `cdn.usetextend.com`, including its TLS
   certificate and DNS record. It must map `/macos/` to the bucket's `macos/`
   prefix. Allow public reads for the release objects; the script sets each
   uploaded object's ACL to `public-read`. Grant the local Spaces access key
   read/write access to the intended bucket.
5. Configure upload credentials locally:

   ```sh
   .build/release-tools/bin/aws configure --profile textend-spaces
   ```

   Use the Spaces access key and secret, with `us-east-1` as the CLI signing region.
   The configured endpoint selects the actual Spaces region. The release script
   accepts an existing AWS profile through `aws_profile`, or the CLI's normal
   credential chain if that value is empty. Credentials never enter the app.
6. Store notarization credentials interactively in Keychain:

   ```sh
   xcrun notarytool store-credentials textend-notary --team-id VK288Z42NG
   ```

   Follow Apple's prompts for your Apple ID and app-specific password, or use
   an existing notarization Keychain profile and set `notary_profile` to its name.
   The release team is `VK288Z42NG` and a matching Developer ID Application
   certificate with its private key is required.

Development and release now use team `VK288Z42NG` with separate CloudKit
environments and provisioning profiles. Follow [iCloud provisioning](icloud-sync.md)
before building. Installing a differently signed build may require granting
Accessibility and Input Monitoring again. Keep the release bundle ID and Developer
ID team stable for subsequent updates.

Textend's Sparkle signing key has already been generated under Keychain account
`chat.eastechs.textend`. Only its public key is tracked in `Config/Updates.xcconfig`.
Back up the private key securely using Sparkle's `generate_keys --account
chat.eastechs.textend -x <secure-path>` tool. Do not generate a replacement key for
an app already distributed. A different Mac must import the same key; release
preflight verifies it matches the checked-in public key.

## Prepare a release

Commit the intended source changes first. Create Markdown release notes and choose
an increasing integer build number. The marketing version uses `major.minor.patch`;
the build number controls update ordering, including patch releases with the same
marketing version.

```sh
python3 script/release.py build --version 0.1.0 --build 2 --notes docs/release-notes/0.1.0.md
```

The notes file is supplied by you for that release. The command:

1. Checks the clean source tree, signing key, certificate, and notarization profile.
2. Archives a universal Release build and exports with Xcode's Developer ID workflow,
   which signs Sparkle's nested helpers correctly.
3. Validates bundle identity, update settings, architectures, and signatures.
4. Submits a ZIP to Apple, requires `Accepted`, then staples and validates the app.
5. Packages the final stapled app with `ditto`, preserving framework symlinks.
6. Generates and verifies a signed appcast using Sparkle's own tools, with embedded
   release notes. Produces `dist/0.1.0-2/` containing the ZIP, appcast, and hash manifest.

The archive and notarization record stay under `build/releases.noindex/`, keeping
staging copies of Textend out of Spotlight. Failed operations
stop before producing a prepared release. A failed notarization can be investigated
with its saved submission ID and `xcrun notarytool log`. Re-running `build` rebuilds
and resubmits; there is no automatic retry or background publication.

## Publish explicitly

```sh
python3 script/release.py publish dist/0.1.0-2
```

The command verifies hashes and Sparkle signatures, reads the current feed from the
Spaces origin, and refuses a reused or lower build number. It uploads the immutable
ZIP first, downloads it through `cdn.usetextend.com`, and checks its SHA-256 before
publishing `appcast.xml`. It then fetches the public feed to confirm publication.
The manifest and Apple/signing logs are never uploaded. An interrupted archive
upload can be retried; an already published identical release is verified without
uploading again. Keep one publishing Mac at a time; a local lock prevents overlapping
operations on this Mac, not concurrent publishers on different computers.

The ZIP uses a one-year immutable cache policy. The feed uses
`no-cache,max-age=0,must-revalidate`. Configure the CDN to honor that header. If
Spaces serves a stale feed, purge **only `macos/appcast.xml`** in the CDN settings
and retry the publish command. It will recognize the already-published origin
feed and recheck the CDN. Never overwrite a versioned ZIP.

The feed currently advertises the latest universal macOS 14+ release. Previous ZIPs
remain hosted. Before changing the minimum macOS version, introduce a feed that
retains older compatible releases rather than dropping those users' update path.

## Tag every published release

Every release must have an annotated Git tag pushed to GitHub. After publication
and CDN verification succeed, create `v<version>` at the exact `source_revision`
recorded in that release's `dist/<version>-<build>/release.json`. Do not tag the
current HEAD unless it is that recorded commit; verification notes may have been
committed after the app was built. Include the version, build number, and archive
SHA-256 in the tag annotation, then push that specific tag and verify its remote
target before considering release work complete.

Never move or overwrite a published tag. If another build ships with the same
marketing version, use `v<version>-build.<build>` for that additional release.
Creating a source tag does not publish another binary or change the update feed.

| Release tag | Build | Source commit |
| --- | --- | --- |
| `v0.1.0` | 2 | `e222d9d54a67b3032cbcecbcd70674fcf48a8c37` |
| `v0.1.1` | 3 | `495bab63158d82971f32a3694b8314951ce3af14` |
| `v0.2.0` | 5 | `4de2845dff3bd80c9d1db3b08f74b7c64fd38022` |
| `v0.2.1` | 6 | `eb841dd9ec5c776cc2bc4a5e7f92f0ee9a01b01c` |
| `v0.2.2` | 7 | `a391cc846fd66e93fc1bc0cb27eb1044db8c0084` |
| `v0.2.3` | 8 | `d8c3fd530032f090fa4e1fa8f59969a3daa6b108` |
| `v0.3.0` | 9 | `98082485fd2d1183882a2b69af9f3502414ebdd2` |
| `v0.3.1` | 10 | `3f02e98a5755131eaae9973b2ec7d0f586eb2da3` |
| `v0.3.2` | 11 | `1f8812ca1b62e28c0fe167cf21624a033f7e5e7b` |
| `v0.3.3` | 12 | `fbd71ac5113fb2747ed9bba5e8f122ce841fd69a` |

## Verification before the first public release

`./script/check.sh` runs app tests, offline release guards, formatting checks, and a
Debug build. Release guard tests simulate publication failures and ordering without
contacting Spaces. Inspect the Updates settings and manual menu command in a Release
build. Then use two signed, notarized versions on a test Mac to verify an actual
update, unsaved-draft cancellation, and relaunch with the existing library and
Accessibility authorization. Local signing/feed tests do not establish this final
end-to-end acceptance.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[Sparkle publishing](https://sparkle-project.org/documentation/publishing/), and
[Spaces S3 compatibility](https://docs.digitalocean.com/products/spaces/reference/s3-compatibility/).
