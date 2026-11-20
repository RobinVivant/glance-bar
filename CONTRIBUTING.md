# Contributing to Glance Bar

Bug reports, fixes and features are welcome. For anything larger than a fix, open an issue first
so the approach can be agreed before you write the code. The app is small on purpose: a new meter
or option has to earn the CPU time and the menu bar space it takes.

## Set up

You need macOS 15 or later on Apple silicon and a Swift 6 toolchain (Xcode or the Command Line
Tools). The package has no dependencies.

```bash
git clone https://github.com/RobinVivant/glance-bar.git
cd glance-bar
swift build
swift test
```

Demo mode runs the app on made-up readings. It reads no sensor and saves no setting:

```bash
swift run GlanceBar --demo
```

## Check your change

| Command | What it checks |
|---------|----------------|
| `swift test` | The math behind each reading, formatting, thresholds, settings and the render model |
| `swift run GlanceBar --demo` | The real menu bar item and panel, on made-up readings |
| `swift run GlanceBar --snapshot /tmp/glance-bar --demo` | The item, the panel, the panel under the pointer and the settings in dark and light, as PNG files |
| `scripts/package-release.sh` | The release build, the app bundle and the release zip |
| `.github/scripts/check-settings-panes.sh` | That this Mac has every System Settings pane the panel opens |

CI runs the tests, the pane check, the release packaging and the demo snapshots on every pull
request, and attaches the snapshots to the run.

Do not launch `build/Glance Bar.app` (even with `--snapshot`) on a Mac that already has Glance Bar
installed: macOS silently repoints the "Open at login" entry (`SMAppService.mainApp`) to whichever
copy of the bundle ran last. Use `swift run GlanceBar --demo` or `swift run GlanceBar --snapshot`
instead, or run `scripts/install.sh` to replace the installed copy.

GitHub sometimes never hands a macOS job to a runner and cancels it after 15 minutes in the
queue. The "Retry dropped runs" workflow re-runs such a CI or Release run, up to its third
attempt. A run that failed for any other reason stays failed.

## Where things live

- `Sources/GlanceCore`: samplers, the math behind each reading, formatting, settings and the
  render model of the menu bar item. It has no AppKit code, and `Tests/GlanceCoreTests` covers it.
- `Sources/GlanceBar`: the status item and its Core Graphics renderer, the sampling loop, the
  popover and its SwiftUI views. `DemoData.swift` holds the made-up readings for `--demo`.
- `scripts/`: build, install, release, icon and brand image scripts. `get.sh` is the installer
  the README's Quickstart pipes to `bash`; it must keep working when run that way.
- `docs/`: the README images.

## Guidelines

- **Test the logic.** A change to `GlanceCore` comes with a test. Views are checked with the demo
  snapshots. What the pointer does lives in `PanelModel` (`hover` and `point(at:)`), so a snapshot
  can show a hover state by setting it, as `SnapshotRunner` does for `panel-hover-*.png`.
- **Measure what you add to the loop.** The app exists to cost little. For a change to sampling
  or drawing, compare the CPU time of the old and the new build over the same minute, with both
  running, and put the figures in the pull request:

    ```bash
    ps -o cputime= -p <pid of the old build> -p <pid of the new build>
    ```

    One run on its own varies by a factor of two with what else the Mac is doing.
- **Say which Mac a sensor was checked on.** Temperature keys differ per chip. A change to
  `TemperatureSampler.swift` names the chip it was tried on.
- **Keep real data out.** Screenshots come from demo mode. Do not commit a snapshot of your own
  Mac's readings, a serial number or a network address.
- **Add no dependencies** without discussing it in an issue first.
- **Match the code around you**: 120 columns, doc comments that say what a thing is for, and no
  comments that restate the code.
- **Update the README** when what a user sees changes.

A change to a view should update the README screenshots:

```bash
swift run GlanceBar --snapshot docs/screenshots --demo
```

The README uses the dark renders as plain images. A `<picture>` that follows the reader's theme
does not load in the GitHub mobile app.

`swift scripts/make-icon.swift` redraws the app icon, and `swift scripts/make-brand.swift` the
README banner and the social preview from it.

## Pull requests

1. Branch from `main`.
2. Keep one change per pull request, with a title that says what changes for the user, such as
   `fix: keep the network rates inside their slot`.
3. Say in the description how you checked it. Add before and after snapshots for a view change.
4. CI must pass.

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).

## Releases

A maintainer publishes a release by bumping `CFBundleShortVersionString` and `CFBundleVersion` in
`Resources/Info.plist` through a pull request, then pushing a tag of the same version from `main`:

```bash
git tag v1.2.3 && git push origin v1.2.3
```

The Release workflow tests the tag, builds the app with `scripts/package-release.sh` and publishes
the zip and its SHA-256 file. The build is signed ad hoc and not notarized, which is why the
README tells users how to allow it.

## Security issues

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).
