# CharmDrop

A native macOS menu bar app that hangs a lucky charm from the top of your
screen on a rope you can grab, pull, and flick. The rope is a real Verlet
physics simulation, the overlay floats above your other windows, and everything
except the charm itself is click-through, so it never gets in your way.

Built with Swift, SwiftUI, AppKit and Core Animation. No Electron, no web views,
no bundled browser.

> **Status:** Modules 1–4, 7, 17, 20 and 22 are complete — app shell, menu bar,
> transparent overlay, rope physics, drag and flick, the ritual engine with
> per-charm behaviours and sound, launch at login, and deep links. See
> [Roadmap](#roadmap) for what is next.

---

## Contents

- [Requirements](#requirements)
- [Building and running](#building-and-running)
- [Running the checks](#running-the-checks)
- [Architecture](#architecture)
- [How the rope physics works](#how-the-rope-physics-works)
- [How click-through works](#how-click-through-works)
- [Adding a new charm](#adding-a-new-charm)
- [Adding a new ritual](#adding-a-new-ritual)
- [Sound](#sound)
- [Deep links](#deep-links)
- [Launch at login](#launch-at-login)
- [Settings](#settings)
- [Debug overlay](#debug-overlay)
- [Configuring Sparkle](#configuring-sparkle)
- [Distribution](#distribution)
- [Website](#website)
- [Placeholders to change](#placeholders-to-change)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Privacy](#privacy)

---

## Requirements

- macOS 14 Sonoma or later
- Swift 5.9 or later
- Xcode 15+ *(optional — only needed to run the XCTest suite; see
  [Running the checks](#running-the-checks))*

Apple Silicon and Intel are both supported. `--universal` produces a fat binary.

---

## Building and running

The project is a Swift package. A shell script wraps the build to produce a real
`.app` bundle:

```bash
# Debug build, native architecture
Scripts/build-app.sh

# Release build
Scripts/build-app.sh --release

# Release build, arm64 + x86_64
Scripts/build-app.sh --release --universal

open build/CharmDrop.app
```

The charm appears hanging from the top edge of the screen, its rope crossing the
menu bar, and a small cord-and-bead icon appears in the menu bar.

### Why a script instead of an Xcode project

SwiftPM emits a bare executable, but a menu bar app needs a genuine bundle:
`MenuBarExtra`, `LSUIElement` (no Dock icon), the Settings scene, URL scheme
registration and window levels all depend on `Info.plist` and a bundle identity.
`Scripts/build-app.sh` assembles and signs that bundle. It also means the whole
project builds and its checks run on a machine with only the Command Line Tools
installed.

If you prefer Xcode, create a macOS App target and add `Sources/CharmDrop` to
it. The source tree has no SwiftPM-specific dependencies — no `Bundle.module`,
no resource bundles — so it drops straight in. Use
`Scripts/Info.plist.template` as the target's `Info.plist` and set the
deployment target to macOS 14.

### Running without a bundle

```bash
swift run CharmDrop
```

This works for iterating on physics, but the app will not have a bundle
identity, so the menu bar item and Settings window behave less predictably.
Prefer the script.

---

## Running the checks

There are two ways to run the same set of expectations.

**Anywhere, no Xcode required:**

```bash
swift run CharmDrop --self-check
```

```
CharmDrop self-check: 32 checks

  pass  physics/rope hangs below the anchor at rest
  pass  physics/segment lengths converge on the rest length
  ...
All 32 checks passed.
```

**With Xcode installed:**

```bash
swift test
```

### Why the checks are structured this way

Every expectation is declared once, in `SelfCheck.allChecks`. The XCTest suite
in `Tests/CharmDropTests/InvariantTests.swift` enumerates that list and asserts
on each entry, and the `--self-check` flag runs the same list from the command
line. One list, two runners, no drift.

`Tests/CharmDropTests/RopePhysicsTests.swift` holds the tests that are more
natural in XCTest, such as determinism, refresh-rate independence, and a
`measure` block for step cost. Those require Xcode.

Note that `swift test` needs a full Xcode install; the Command Line Tools alone
do not ship XCTest, which is exactly why `--self-check` exists.

---

## Architecture

MVVM where it earns its keep, plain types where it does not. There are no
singletons and no global mutable state: `AppEnvironment` is the composition root
and everything else is injected.

```
Sources/CharmDrop/
├── App/
│   ├── main.swift                    entry point; handles --self-check
│   ├── CharmDropApp.swift            SwiftUI App: MenuBarExtra + Settings
│   ├── AppDelegate.swift             activation policy, sleep/wake, teardown
│   └── AppEnvironment.swift          composition root
│
├── Overlay/
│   ├── OverlayManager.swift          one overlay per target display
│   ├── CharmOverlayController.swift  per-screen panel + engine + loop
│   ├── CharmPanel.swift              transparent non-activating NSPanel
│   ├── CharmOverlayView.swift        layer host and drag event receiver
│   ├── CharmRenderLayer.swift        rope, charm and debug CALayers
│   ├── MouseInteractionManager.swift pointer poll and velocity tracking
│   ├── DisplayLoop.swift             CADisplayLink wrapper
│   └── OverlayConfiguration.swift    immutable render/behaviour snapshot
│
├── Physics/
│   ├── RopePhysicsEngine.swift       Verlet solver
│   ├── RopePoint.swift               one particle
│   ├── RopeConstraint.swift          distance constraint
│   ├── PhysicsConfiguration.swift    every tunable number
│   └── PhysicsMath.swift             angle and sanitisation helpers
│
├── Charms/
│   ├── Models/Charm.swift            declarative charm definition
│   ├── CharmCatalog.swift            catalog protocol + built-in charms
│   ├── CharmRenderer.swift           artwork resolution and caching
│   └── PlaceholderCharmArtwork.swift generated vector placeholders
│
├── MenuBar/
│   ├── MenuBarView.swift
│   └── MenuBarIcon.swift             template icon drawn in code
│
├── Settings/
│   ├── SettingsManager.swift         all preferences + persistence
│   ├── SettingsView.swift            tabbed Settings window
│   ├── GeneralSettingsView.swift
│   ├── AppearanceSettingsView.swift
│   ├── InteractionSettingsView.swift
│   └── AdvancedSettingsView.swift
│
├── System/
│   ├── AppStateManager.swift         observable state + command entry point
│   └── ScreenManager.swift           display tracking and resolution
│
├── Updates/UpdateManager.swift       update protocol + unconfigured default
├── Diagnostics/SelfCheck.swift       invariant definitions
└── Utilities/                        Constants, Logger, Extensions
```

### How data flows

```
     menu bar / settings / (later) shortcuts and deep links
                              │
                              ▼
                      AppStateManager  ──── commands ────┐
                              │                          │
                      SettingsManager                     │
                              │                          │
                  OverlayConfiguration (value type)      │
                              │                          │
                              ▼                          ▼
                        OverlayManager ──────────► CharmOverlayController
                                                          │
                                              ┌───────────┴───────────┐
                                              ▼                       ▼
                                     RopePhysicsEngine        CharmRenderLayer
                                              │                       │
                                          DisplayLoop ────────────────┘
                                        (CADisplayLink)
```

Three rules hold this together:

1. **The physics engine knows nothing about AppKit, Core Animation or
   settings.** It handles points, constraints and a rectangle it must stay
   inside. That is what makes new charms and ropes addable without touching the
   solver.
2. **The 60/120Hz path never touches SwiftUI.** The display loop writes straight
   into `CALayer` properties. SwiftUI only ever sees discrete configuration
   changes, so no view is invalidated by the animation.
3. **State travels one way as a value type.** `OverlayConfiguration` is an
   `Equatable` snapshot, so the overlay can cheaply skip work when an unrelated
   preference changes, and no view holds a reference to a panel or an engine.

### One coordinate space

Screen-coordinate bugs are the usual source of grief in overlay apps, so there
is only one space: **panel-local, y-up**, which is AppKit's default for a
non-flipped view and layer. Physics, hit-testing and rendering all share it, and
gravity is simply negative on y. The only conversion in the codebase is at the
screen boundary, in `CharmOverlayController.convertToViewCoordinates(_:)`.

---

## How the rope physics works

The rope is a chain of particles solved with **Verlet integration**. Each
particle stores where it is and where it was; velocity is the gap between those
two, which is why an impulse is applied by *rewriting history* rather than by
storing a velocity field.

```
  anchor (pinned to the top edge of the display)
    ●
    │
    ●   ← 15 particles by default
    │
    ●
    │
    ●
    │
    ●
  charm (attachment point; artwork hangs below it)
```

Each frame:

1. Clamp the wall-clock delta to `maximumDeltaTime` (1/20 s).
2. Split it into fixed 1/120 s substeps, at most six per frame.
3. For each substep:
   - integrate: `next = position + (position - previous) × damping + gravity × dt²`
   - relax every distance constraint eight times
   - re-pin the anchor
   - reflect any particle that left the screen
4. Smooth the charm's rotation toward the direction of the final rope segment.
5. Update the rest state.

The fixed substep is why the simulation behaves identically on a 60Hz display
and a 120Hz one — verified by `testSimulationIsRefreshRateIndependent`.

### Stability

Five separate guards keep the rope from exploding, because a physics overlay
that goes haywire once is a physics overlay the user turns off:

| Risk | Guard |
|---|---|
| Waking from sleep produces a delta of minutes | `maximumDeltaTime` clamp plus `resetTiming()` on wake |
| A violent flick outruns the constraint solver | `maximumParticleSpeed` (4000 px/s) clamped per substep |
| A stalled main thread causes a catch-up avalanche | `maximumSubstepsPerFrame`, with any backlog discarded |
| A single NaN poisons the simulation | `PhysicsMath.sanitized` on every integration result |
| Coincident particles give a constraint no direction | Fixed-axis nudge instead of dividing by zero |

### Rotation

The charm's angle comes from the last two particles:

```swift
angle = atan2(dy, dx) + .pi / 2
```

The `+ π/2` makes "hanging straight down" read as zero rotation, so a charm's
`rotationOffset` stays intuitive. The result is smoothed exponentially and
interpolated along the shorter arc, so crossing ±π does not spin the charm the
long way round.

### Sleeping

When every particle has been slower than 1.2 px/s for 30 consecutive frames the
engine reports `isAtRest` and the controller **stops the display link
entirely**. Any interaction, command or settings change calls `wakeSimulation()`
to start it again. A settled charm therefore costs no frames at all, which is
how idle CPU stays near zero.

Measured on an M-series MacBook: **0.0–2.1% CPU idle, ~16 MB resident**;
roughly **3–4% CPU** while the rope is actually swinging.

---

## How click-through works

The overlay is one transparent panel covering an entire display. A panel sized
to just the charm would clip the rope, break hit-testing during fast drags, and
need constant repositioning.

Because it covers everything, it must be inert almost all of the time:

- `CharmPanel.ignoresMouseEvents` is `true` by default, so clicks pass straight
  through to whatever is underneath.
- `MouseInteractionManager` polls the pointer at 30Hz. When it enters the
  charm's hitbox, `ignoresMouseEvents` flips to `false` and the cursor becomes an
  open hand; when it leaves, the panel goes inert again.
- `CharmOverlayView.hitTest(_:)` independently rejects anything outside the
  hitbox, as a second line of defence.
- The panel is `.nonactivatingPanel` and refuses to become key or main, so
  grabbing the charm never steals focus from the app you are working in.

The hitbox is the charm's artwork plus 30pt of padding on each axis. Padding is
not scaled with the charm, so small charms stay comfortably clickable.

### Why polling rather than event monitors

This is the one genuinely counter-intuitive decision in the codebase, and it is
documented at the top of `MouseInteractionManager`:

- A **global** event monitor never sees events delivered to our own process. The
  moment the overlay became interactive we would stop hearing about movement and
  could never detect the pointer leaving.
- A **local** monitor is unreliable for a non-activating panel belonging to an
  inactive app, which is the overlay's normal state.
- `NSEvent.mouseLocation` needs **no Accessibility permission** and is a cheap
  window-server query.

The poll runs only while a charm is on screen, and it uses timer tolerance so
the OS can coalesce its wakeups. Separately, the render loop re-checks hover when
the charm itself has moved more than a point, since the charm can swing out from
under a stationary cursor.

### Drag and flick

`mouseDown` pins only the **final** rope particle and records the grab offset,
so the charm does not snap under the cursor and the rest of the rope follows
through constraint solving — it feels like rope, not a stick.

On release, `PointerVelocityTracker` averages the recent pointer samples and
that velocity is written into the charm's Verlet history, scaled by the
**Flick strength** setting. Samples older than 90ms are discarded, so pausing
before letting go produces a gentle drop rather than replaying a stale flick.

A press that travels under 5pt in under 0.4s is treated as a click rather than a
drag, and triggers the charm's ritual.

---

## Adding a new charm

Charm definitions are pure data, so this is a one-file change. Add a `Charm` to
`BuiltInCharmCatalog.charms`:

```swift
Charm(
    id: "peacock-feather",
    displayName: "Peacock Feather",
    assetName: "charm_peacock_feather",
    visualSize: CGSize(width: 70, height: 130),
    defaultRopeLength: 170,
    ritualType: .pulse,
    description: "A single feather that sways more than it swings."
)
```

Then drop a transparent PNG named `charm_peacock_feather` (with `@2x`) into the
app bundle's resources. `CharmRenderer` prefers bundled artwork and silently
falls back to generated placeholder art, so the charm works before the artwork
exists and starts using the real asset the moment you add it — no code change.

Author artwork **hanging straight down**; if you cannot, set `rotationOffset`
(in radians) instead of rotating the file.

The menu, the settings picker and the thumbnail grid are all driven by the
catalog, so the new charm appears everywhere automatically. Nothing in
`Physics/` or `Overlay/` needs to change.

To source charms from somewhere else entirely — a downloaded pack, a remote
catalog, a folder of user imports — implement `CharmCatalogProviding` and inject
it into `AppEnvironment`.

---

## Adding a new ritual

A ritual is what a charm *does* when you click it. The four built-ins live in
`Charms/Rituals/`:

| Charm | Type | Behaviour |
| --- | --- | --- |
| Nazar | `.pulse` | Widens slightly with a blue glow, then settles. |
| Temple Bell | `.swing` | Hard shove, a synthesised ring, then a return swing. |
| Nimbu Mirchi | `.replace` | Twists and shrinks out, swaps artwork, pops back. |
| Diya | `.toggle` | Lights or snuffs the lamp; flickers while lit. |

### Rituals are state machines, not `CAAnimation`s

This is the one design decision worth knowing before writing a ritual. The
overlay's display loop rewrites the charm's transform every frame with implicit
animations disabled, so a Core Animation animation on that property would be
overwritten on the very next frame.

Instead, a ritual is stepped with the same delta as the physics and returns a
`RitualPresentation` describing how the charm should look *right now*. The
render layer composes that with the rope's physics rotation. One clock, one
writer, nothing fighting — and ritual timing is frame-rate independent for the
same reason the rope's is.

```swift
protocol CharmRitual: AnyObject {
    var duration: CFTimeInterval { get }
    func begin(_ context: RitualContext)                       // impulses, sound, swaps
    func update(_ context: RitualContext, progress: Double)    // per-frame appearance
    func finish(_ context: RitualContext)
    func ambient(_ context: RitualContext, time: CFTimeInterval)  // continuous effects
    func wantsAmbientFrames(_ context: RitualContext) -> Bool
}
```

Every method has a default no-op, so a ritual overrides only the phases it
needs. To add one:

1. Add a case to `RitualType` if none of the four fit.
2. Write a class in `Charms/Rituals/` conforming to `CharmRitual`.
3. Register it in `RitualManager.makeBuiltInRituals()`.
4. Point a charm at it via `Charm.ritualType`.

Nothing in the physics engine, the render loop or the overlay changes.
`RitualPhysicsControlling` deliberately exposes only `applyImpulse` and
`charmVelocity`, so a ritual can push the charm but cannot destabilise the
solver.

### Presentation

`RitualPresentation` carries a `variant`, a `scale`, a `rotationBias` and an
optional `glow`. Glow is drawn as the charm layer's own zero-offset shadow,
which avoids a second layer and a second compositing pass. Keep durations in
the 0.5–2s window; a self-check enforces it.

### Artwork variants

Charms that change appearance declare `hasAlternateArtwork: true` and get a
second placeholder drawing (an unlit and a lit Diya, a dried and a fresh Nimbu
Mirchi). Bundled assets follow the same convention with an `_alt` suffix.
Requesting a variant a charm does not have falls back to `.primary` rather than
returning nothing, so a stale toggle can never blank the charm.

### Ambient effects and the idle budget

`ambient` runs when no ritual is active — the Diya's flame flicker is the only
built-in user. Because `wantsAmbientFrames` gates whether the display link may
stop, **a lit Diya keeps rendering**; every other charm returns to zero frames
once the rope settles. Ambient-only frames skip rebuilding the rope path, which
is most of the cost of a frame.

---

## Sound

`SoundPlaying` is a protocol; `SoundPlayer` is the `AVAudioEngine`
implementation. Only the Temple Bell makes a sound today.

Like the charm artwork, sound has a **procedural fallback**: if no audio file is
bundled, `ProceduralTone` synthesises the bell by additive synthesis — seven
inharmonic partials, each with its own decay, plus attack and release ramps so
the buffer neither clicks nor cuts off. The app is therefore audible with no
licensed media, and drops in real files (`bell.wav`, `bell.caf`, …) with no code
change.

Everything — resolution, synthesis, scheduling — happens on a private serial
queue, so a ritual that plays a sound never risks a frame. Effects sit at 35%
output volume by design.

The engine is built **on first playback, not at launch**. Merely constructing an
`AVAudioEngine` measured at roughly 3% of a core at idle, which for an app whose
whole point is being invisible until poked was worth avoiding. It is torn down
again after five seconds of silence; synthesised buffers stay cached, so
restarting is cheap.

---

## Deep links

CharmDrop registers the `charmdrop://` URL scheme, so it can be driven from the
shell, Shortcuts, Alfred, Raycast or a script:

```bash
open "charmdrop://ritual"          # perform the current charm's ritual
open "charmdrop://charm/diya"      # switch charms
open "charmdrop://toggle"          # show or hide the charm
open "charmdrop://show"
open "charmdrop://hide"
open "charmdrop://reset"           # return the rope to a straight hang
open "charmdrop://settings"        # open the Settings window
```

Both `charmdrop://ritual` and `charmdrop://ritual/` work, as does the
scheme-only form `charmdrop:ritual`, because which one a given launcher
produces is not something a user should have to think about. Commands and charm
identifiers are case-insensitive.

Parsing lives in `DeepLink`, which is deliberately pure: a URL from outside the
process is untrusted input, so the code that interprets it holds no app state
and can be tested exhaustively. Anything unrecognised — an unknown command, a
missing charm identifier, a stray path segment, a foreign scheme — is rejected
and logged rather than guessed at. `AppStateManager` then applies the action,
and it is the catalog, not the parser, that decides whether a charm identifier
is real.

Two behaviours worth knowing: a ritual requested while the charm is hidden is
refused rather than performed invisibly, and there is deliberately **no deep
link for Launch at Login** — a URL that any web page could fire has no business
changing your login items.

Deep links are also how the ritual engine is verified at runtime, since
synthetic clicks need Accessibility permission and deep links need none.

---

## Launch at login

`SMAppService.mainApp` registers the running app itself: no helper target, no
privileged helper, no login-item bundle. It does require a real `.app`, so
running the bare SPM executable reports the feature as unavailable rather than
failing confusingly.

**macOS is the source of truth.** A user who removes CharmDrop under System
Settings › General › Login Items has changed their mind, so `synchronize()`
copies the system state into the stored preference at every launch and whenever
the General pane appears — never the other way around. The app will not
silently re-register itself, and the toggle cannot show a state the system does
not actually hold.

`LaunchAtLoginStatus` is richer than a `Bool` because macOS can hold a
registration pending user approval, which otherwise looks identical to "off".
When approval is pending the Settings pane says so and offers a button straight
to the Login Items pane.

One subtlety worth recording, since it is easy to get wrong: macOS reports
`.notFound` for an app it has never registered — measured on a signed build both
inside and outside `/Applications`. Treating that as unavailable would disable
the toggle, and since the only escape from `.notFound` is to call `register()`,
the feature would be permanently unreachable. `.notFound` is therefore offered
as plain "off"; a registration that truly cannot succeed reports itself by
throwing, and the reason is shown to the user.

### Signing

`SMAppService` wants a properly signed app. The build script takes an identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./Scripts/build-app.sh --release
```

---

## Settings

`SettingsManager` owns every preference and all of its persistence. No view
touches `UserDefaults`, and values are validated on read: anything missing,
non-finite or out of range falls back to a sane default, so a corrupted or
hand-edited defaults file cannot leave the app unusable.

Persisted today: selected charm, charm visibility, charm scale, rope length,
rope thickness, rope opacity, anchor position, custom anchor fraction, screen
selection, selected screen, sound enabled, drag sensitivity, flick strength,
ritual trigger, launch at login, show on all Spaces, show in fullscreen apps,
and the debug overlay flag.

The Settings window (⌘, or **Settings…** in the menu) has four tabs: General,
Appearance, Interactions and Advanced. **Shortcuts** arrives with Module 21.

Anchor positions are stored as a **fraction of screen width**, not as pixels, so
the charm stays where you put it when the resolution changes or it moves to
another display.

`SettingsManager.didChange` fires once per write; `AppStateManager` rebuilds
`OverlayConfiguration` from it and republishes only when the value actually
differs. **Reset All Settings** batches its writes so observers see a single
change rather than eighteen.

---

## Debug overlay

**Settings → Advanced → Show physics debug overlay** draws, in green:

- every rope particle, with pinned ones larger
- the straight constraint lines between them
- the charm's interaction hitbox
- live FPS, charm speed, particle count and drag state

It is off by default and costs nothing when off — the debug layers are hidden
and never receive a path.

---

## Configuring Sparkle

Not wired up yet, deliberately. `UpdateManaging` is the protocol; the shipping
implementation is `UnconfiguredUpdateManager`, which explains itself in an alert
rather than pretending to check. Pointing an updater at a placeholder feed would
either fail silently or, worse, look like it worked.

To enable updates:

1. Add Sparkle 2 via SwiftPM: `https://github.com/sparkle-project/Sparkle`,
   `from: "2.6.0"`. Add it to the `CharmDrop` target's dependencies in
   `Package.swift`.
2. Generate signing keys with Sparkle's `generate_keys` tool.
3. In `Scripts/Info.plist.template`, replace:
   - `SUFeedURL_PLACEHOLDER` → the HTTPS URL of your `appcast.xml`
   - `SUPublicEDKey_PLACEHOLDER` → the public key from step 2
   - set `SUEnableAutomaticChecks` to `true` if you want background checks
4. Add a `SparkleUpdateManager: UpdateManaging` wrapping
   `SPUStandardUpdaterController` and inject it in `AppEnvironment`.

Nothing else changes: the menu item and the Advanced tab already call through
the protocol.

---

## Distribution

See **[DISTRIBUTION.md](DISTRIBUTION.md)** for the full walkthrough: Developer
ID certificates, signing, hardened runtime, archiving, DMG creation,
notarization with `notarytool`, stapling, and Gatekeeper verification.

```bash
Scripts/build-dmg.sh --universal
```

Writes `build/CharmDrop-<version>.dmg`. Notarization still needs a Developer ID
identity; the script will say so if you are still on an ad-hoc signature.

---

## Website

The public landing page lives in `web/`: Astro, TypeScript, and Tailwind.
English, Hindi, and Spanish. The hero is an interactive rope you can drag.
Licenses are one-time Razorpay payments: ₹101 (was ₹401) for one Mac, or ₹501
(was ₹1201) for up to five Macs. The DMG unlocks only after a verified payment.

```bash
cd web
cp .env.example .env
npm install
npm run dev
```

`npm run build` writes a Node standalone server to `web/dist`. See
`web/README.md`.

---

## Placeholders to change

Everything you must edit before shipping, in one place:

| Placeholder | Where | What to set it to |
|---|---|---|
| `com.company.charmdrop` | `Scripts/build-app.sh` (`BUNDLE_ID`), `Constants.App.bundleIdentifier` | Your reverse-DNS bundle identifier |
| `SIGN_IDENTITY="-"` | `Scripts/build-app.sh` | `Developer ID Application: Name (TEAMID)` |
| `SUFeedURL_PLACEHOLDER` | `Scripts/Info.plist.template` | Your appcast URL |
| `SUPublicEDKey_PLACEHOLDER` | `Scripts/Info.plist.template` | Your Sparkle public key |
| `__COPYRIGHT__` | `Scripts/build-app.sh` (`COPYRIGHT`) | Your copyright line |
| Team ID | `DISTRIBUTION.md` commands | Your Apple Developer Team ID |
| App icon | `Resources/AppIcon.icns` | Regenerated by `Scripts/generate-app-icon.sh` |
| Razorpay keys | `web/.env` | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `LICENSE_SIGNING_SECRET` |

Renaming the product means changing `APP_NAME` in `Scripts/build-app.sh` and
`Constants.App.displayName`. The name is not hardcoded anywhere else — menus,
alerts and logs all read it from `Constants`.

---

## Known limitations

- **Drag, flick and clicking the charm are not covered by automated tests.**
  Posting synthetic mouse events needs Accessibility permission, so these paths
  were verified by inspection and need a human to confirm the feel. Hover
  detection *is* verified end to end (warping the cursor onto the charm toggles
  click-through in the log), and every ritual is verified through deep links,
  which need no permission at all.
- **The Finder icon is a generated hanging Nimbu Mirchi on a green tile**,
  assembled into `Resources/AppIcon.icns`. The menu bar icon remains the
  template cord-and-bead drawn in `MenuBarIcon`.
- **All charm artwork is generated placeholder vector art**, drawn in
  `PlaceholderCharmArtwork`. Original designs are meant to replace it; the
  renderer already prefers bundled assets when present. Nimbu Mirchi is drawn
  as a lit, shaded object; Nazar, the bell and the Diya are still flat
  two-stop gradients and look plainer next to it.
- **Launch at Login registration is not verified end to end.** Every branch of
  the reconciliation logic is covered against a stub backend, and the toggle is
  live on a signed build, but nobody has yet confirmed that macOS actually
  accepts the registration — that needs one click and a logout.
- **A lit Diya never idles.** Its flame flicker is a continuous ambient effect,
  so the display link keeps running while the lamp is lit (roughly 2-3% of a
  core). Every other charm returns to zero frames once the rope settles.
- **The bell is synthesised, not recorded.** `ProceduralTone` is a decent
  approximation, not a sampled temple bell; a bundled recording would sound
  better and needs no code change.
- **No global keyboard shortcuts yet.** Deep links cover the same actions in
  the meantime, and a Shortcuts tab arrives with Module 21.
- **Multi-monitor is implemented but only lightly exercised.** The manager
  reconciles one overlay per target display and handles displays appearing and
  disappearing, but the Settings UI does not expose a display picker yet, so
  only "Main Display" is reachable.
- **`swift test` needs full Xcode.** Use `--self-check` otherwise.
- **The charm body cannot swing over the menu bar.** The rope is anchored to the
  physical top edge and the panel sits one window level above the menu bar, so
  the rope crosses it, but boundary clamping keeps the charm itself a full
  artwork height below the top edge. That is deliberate — a charm resting over
  the menu bar would swallow clicks inside its hitbox — though it does mean a
  hard upward flick stops short.

---

## Roadmap

Completed: Modules 1–4 — app shell, menu bar, transparent overlay, Verlet rope,
drag and flick, click-through, settings persistence. Modules 7 and 17 — the
ritual engine, per-charm behaviours, artwork variants and sound. Modules 20 and
22 — launch at login and deep links.

Next, in dependency order:

1. **Module 21 — Global shortcuts.** Carbon `RegisterEventHotKey` avoids
   Accessibility permission entirely; no third-party package needed.
2. **Module 23 — Multi-monitor UI.** Expose the display picker.
3. **Module 31 — Sparkle.**

The architecture is deliberately extensible toward user-uploaded charms, charm
packs, remote catalogs, custom ropes, scheduled rituals and multiple charms.
None of that is built; the seams are simply in place — `CharmCatalogProviding`,
`CharmArtworkProviding`, `CharmRitual`, `SoundPlaying`, `LaunchAtLoginBackend`,
`UpdateManaging`, and rituals as commands rather than state.

---

## Privacy

CharmDrop needs no account, no login and no network access. It collects nothing
and transmits nothing. There is no analytics, no telemetry and no cloud sync.

All preferences are stored locally in `UserDefaults`. Logs are written to the
local unified log via `os.Logger` and never leave the machine.

The app reads the pointer's coordinates — and nothing else about it — solely to
decide whether the cursor is over the charm. It does not read keystrokes, files,
screenshots or screen recordings, and it requests no Accessibility or
Screen Recording permission.
