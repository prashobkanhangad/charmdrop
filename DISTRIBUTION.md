# Distributing CharmDrop

How to sign, notarize and ship CharmDrop for direct download from your own
website (not the Mac App Store).

Nothing here has been run for you: every command below touches your Apple
Developer identity, so you need to supply your own Team ID, certificate and
credentials.

---

## 0. What you need

| Item | Where it comes from |
|---|---|
| Apple Developer Program membership | <https://developer.apple.com/programs/> ($99/year) |
| A **Developer ID Application** certificate | Xcode or the Developer portal |
| Your **Team ID** | <https://developer.apple.com/account> → Membership |
| An **app-specific password** or an App Store Connect API key | <https://appleid.apple.com> → Sign-In and Security |
| Full Xcode (not just Command Line Tools) | Required for `notarytool` and `stapler` |

Direct distribution requires all three of: a Developer ID signature, the
hardened runtime, and notarization. Miss any one and Gatekeeper will tell your
users the app is damaged or from an unidentified developer.

---

## 1. Get a Developer ID certificate

In Xcode: **Settings → Accounts → your Apple ID → Manage Certificates → + →
Developer ID Application**.

Confirm it landed in your keychain, and note the exact identity string:

```bash
security find-identity -v -p codesigning
```

You are looking for a line like:

```
1) A1B2C3D4E5F6... "Developer ID Application: Your Name (AB12CD34EF)"
```

`AB12CD34EF` is your Team ID. Keep the full quoted string; it is what you pass
to `codesign`.

> A **Developer ID Application** certificate is the right one. An *Apple
> Development* certificate only works on machines registered to your team, and a
> *Mac App Store* certificate cannot be notarized for direct distribution.

---

## 2. Configure signing

Set the identity and identifier once, as environment variables consumed by
`Scripts/build-app.sh`:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (AB12CD34EF)"
export BUNDLE_ID="com.yourcompany.charmdrop"
export MARKETING_VERSION="1.0.0"
export BUILD_VERSION="1"
export COPYRIGHT="Copyright © 2026 Your Company. All rights reserved."
```

To make them permanent, edit the defaults at the top of
`Scripts/build-app.sh`, and change `BUNDLE_ID` in
`Constants.App.bundleIdentifier` so the log subsystem matches.

The script already applies `--options runtime` (hardened runtime) and, when a
real identity is supplied, `--timestamp` for a secure timestamp. Notarization
rejects builds missing either.

CharmDrop needs **no entitlements**: it is not sandboxed, requires no
Accessibility or Screen Recording permission, and makes no network requests.
Adding Sparkle does not change that. If you later add sandboxing, you will need
an entitlements file and `--entitlements` on the `codesign` call.

---

## 3. Build a signed universal release

```bash
Scripts/build-app.sh --release --universal
```

Verify what you got:

```bash
# Both architectures present
lipo -archs build/CharmDrop.app/Contents/MacOS/CharmDrop
# Expect: x86_64 arm64

# Signature is valid and satisfies its designated requirement
codesign --verify --deep --strict --verbose=2 build/CharmDrop.app

# Hardened runtime is on: look for "flags=0x10000(runtime)"
codesign -dvvv build/CharmDrop.app 2>&1 | grep -E "flags|Authority|Timestamp"
```

Expect `Authority=Developer ID Application: ...`, `Authority=Developer ID
Certification Authority`, `Authority=Apple Root CA`, and a real `Timestamp=`.

> ### If you use Xcode instead
>
> With an Xcode project the equivalent steps are:
>
> ```bash
> xcodebuild -scheme CharmDrop -configuration Release \
>   -archivePath build/CharmDrop.xcarchive archive
>
> xcodebuild -exportArchive \
>   -archivePath build/CharmDrop.xcarchive \
>   -exportOptionsPlist Scripts/ExportOptions.plist \
>   -exportPath build/export
> ```
>
> `ExportOptions.plist` needs `method` set to `developer-id` and `teamID` set to
> your Team ID. You will have to create it; it is not in this repo because the
> project builds with SwiftPM.

---

## 4. Create a DMG

```bash
Scripts/build-dmg.sh --universal
```

That rebuilds a release app, stages it next to an Applications shortcut, and
writes `build/CharmDrop-<version>.dmg`. The shortcut is what makes the
drag-to-install gesture work.

To also notarize and staple (Developer ID identity required):

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (AB12CD34EF)" \
  NOTARY_PROFILE="charmdrop-notary" \
  Scripts/build-dmg.sh --universal
```

For a polished window background and icon layout, use
[`create-dmg`](https://github.com/create-dmg/create-dmg) instead of raw
`hdiutil`. The signing and notarization steps are identical.

---

## 5. Store notarization credentials

Once, so later commands stay short:

```bash
xcrun notarytool store-credentials "charmdrop-notary" \
  --apple-id "you@example.com" \
  --team-id "AB12CD34EF" \
  --password "abcd-efgh-ijkl-mnop"
```

That password is an **app-specific password** from
<https://appleid.apple.com>, not your Apple ID password. The credentials are
stored in your keychain under the profile name.

---

## 6. Notarize

```bash
xcrun notarytool submit "build/CharmDrop-$MARKETING_VERSION.dmg" \
  --keychain-profile "charmdrop-notary" \
  --wait
```

`--wait` blocks until Apple finishes, usually a few minutes. You want
`status: Accepted`.

If it is `Invalid`, get the reason — the summary alone is rarely enough:

```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "charmdrop-notary" \
  developer_log.json
```

Common causes:

| Message | Fix |
|---|---|
| `The signature does not include a secure timestamp` | Sign with `--timestamp` (a real identity, not ad-hoc `-`) |
| `The executable does not have the hardened runtime enabled` | Sign with `--options runtime` |
| `The binary is not signed with a valid Developer ID certificate` | You used an Apple Development or ad-hoc signature |
| `The signature of the binary is invalid` | Re-sign after your last modification; editing a bundle breaks its seal |

Anything you change inside the bundle invalidates the signature, so always sign
last.

---

## 7. Staple

Notarization records a ticket on Apple's servers. Stapling attaches it to the
file so Gatekeeper can validate it offline:

```bash
xcrun stapler staple "build/CharmDrop-$MARKETING_VERSION.dmg"
xcrun stapler validate "build/CharmDrop-$MARKETING_VERSION.dmg"
```

Skip this and users on a slow or absent network get a scary warning.

---

## 8. Verify as a user would

The single most useful check, since it evaluates exactly the policy Gatekeeper
applies to a fresh download:

```bash
spctl --assess --type open --context context:primary-signature \
  --verbose=2 "build/CharmDrop-$MARKETING_VERSION.dmg"
```

Expect `accepted` and `source=Notarized Developer ID`.

Then check the app inside:

```bash
hdiutil attach "build/CharmDrop-$MARKETING_VERSION.dmg"
spctl --assess --verbose=2 /Volumes/CharmDrop/CharmDrop.app
xcrun stapler validate /Volumes/CharmDrop/CharmDrop.app
hdiutil detach /Volumes/CharmDrop
```

Finally, test on a Mac that has never seen the app, ideally a fresh VM. Your own
machine has development certificates and cached trust that mask problems your
users will hit.

---

## 9. Ship it

Host the DMG over HTTPS. If you are using Sparkle, the appcast entry must point
at the same signed, notarized, stapled DMG:

```xml
<item>
  <title>Version 1.0.0</title>
  <sparkle:version>1</sparkle:version>
  <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://yoursite.example/downloads/CharmDrop-1.0.0.dmg"
    length="4812345"
    type="application/octet-stream"
    sparkle:edSignature="..." />
</item>
```

Generate `sparkle:edSignature` with Sparkle's `sign_update` tool using the
private key from `generate_keys`. See [Configuring
Sparkle](README.md#configuring-sparkle).

Keep the private key backed up and out of the repository. Lose it and you cannot
ship updates to existing installs.

---

## Checklist

```
[ ] Developer ID Application certificate in keychain
[ ] BUNDLE_ID and Constants.App.bundleIdentifier updated
[ ] SUFeedURL / SUPublicEDKey placeholders replaced (if using Sparkle)
[ ] Version and build numbers bumped
[ ] Built --release --universal
[ ] lipo shows x86_64 and arm64
[ ] codesign --verify passes; flags include runtime; Timestamp present
[ ] DMG created and signed
[ ] notarytool reports Accepted
[ ] stapler staple and validate pass
[ ] spctl reports "source=Notarized Developer ID"
[ ] Launched on a clean Mac
```
