<h1 align="center">
  <img src="docs/banner.png" width="800" alt="Glance Bar: system stats at a glance in your menu bar">
</h1>

<p align="center">
  <a href="https://github.com/RobinVivant/glance-bar/actions/workflows/ci.yml"><img src="https://github.com/RobinVivant/glance-bar/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?logo=apple" alt="macOS 15 or later">
</p>

Glance Bar is a macOS menu bar app that shows CPU, GPU, memory, disk, temperature, battery and
network activity in one compact item, with a detail panel behind a click.

<p align="center">
  <img src="docs/screenshots/menubar.png" width="514" alt="Menu bar item: CPU history graph, GPU, memory and disk gauges, 58 degrees, 84 percent battery, upload and download rates">
</p>

<p align="center">
  <img src="docs/screenshots/panel-dark.png" width="38%" align="top" alt="Detail panel: CPU history and per-core bars, memory split, network chart, disk, battery and temperatures">
  <img src="docs/screenshots/settings-dark.png" width="38%" align="top" alt="Settings: a switch and order arrows per meter, refresh interval, Open at login">
</p>

The screenshots show the made-up readings of [demo mode](#try-it-without-installing).

## Quickstart

You need macOS 15 or later on Apple silicon.

```bash
curl -fsSL https://raw.githubusercontent.com/RobinVivant/glance-bar/main/scripts/get.sh | bash
```

The [script](scripts/get.sh) downloads the latest release, checks it against its SHA-256 file and
its signature, copies `Glance Bar.app` to `~/Applications` and opens it. The item appears in the
menu bar; click it for the panel. The first launch from an Applications folder turns on Open at
Login. Run the same line again to update.

If the item does not show up, the menu bar is full: macOS puts new items behind the `«` chevron
at the left end of the status area. Hold Command and drag the item to where you want it.

### Download by hand

1. Download `Glance-Bar-<version>-arm64.zip` from the
   [latest release](https://github.com/RobinVivant/glance-bar/releases/latest) and unzip it.
2. Move `Glance Bar.app` to `/Applications` or `~/Applications`.
3. Open it. macOS blocks the first launch of a copy downloaded with a browser, because the build
   is not notarized by Apple: choose **Done**, open **System Settings > Privacy & Security**,
   scroll to the message about Glance Bar and choose **Open Anyway**. From a terminal, this does
   the same:

    ```bash
    xattr -dr com.apple.quarantine "/Applications/Glance Bar.app"
    ```

The install script does not hit this block: `curl` does not mark its downloads as coming from
the internet, so macOS has nothing to check.

### Build from source

With a Swift 6 toolchain (Xcode or the Command Line Tools), this builds `Glance Bar.app`, copies
it to `~/Applications` and opens it. A build made on your own Mac opens without the block.

```bash
git clone https://github.com/RobinVivant/glance-bar.git
cd glance-bar
scripts/install.sh
```

### Try it without installing

From a checkout, demo mode runs the app on made-up readings. It reads no sensor and saves no
setting.

```bash
swift run GlanceBar --demo
```

## What it shows

- **Menu bar**: seven meters, each of which you can hide or reorder. Rest the pointer on the
  item for a tooltip that gives every visible reading as text, including the figures behind the
  gauges.

    | Meter | Drawn as | Reading |
    |-------|----------|---------|
    | CPU | History graph, 12 bars | Total load at each refresh |
    | GPU | Gauge | Utilization of the busiest GPU |
    | Memory | Gauge | Memory pressure, the figure Activity Monitor graphs |
    | Disk | Gauge | Used share of the startup volume |
    | Temperature | Text | Average of the CPU core sensors, in °C |
    | Battery | Text | Charge percent; left out on a Mac without a battery |
    | Network | Two lines of text | Upload over download, summed over the `en*` interfaces |

- **Colors**: the item is monochrome and follows the menu bar's appearance. A reading turns
  orange, then red, at fixed thresholds.

    | Reading | Orange | Red |
    |---------|--------|-----|
    | CPU and GPU load | 85% | 95% |
    | Memory | Kernel pressure level "warning" | Kernel pressure level "critical" |
    | Disk used | 90% | 95% |
    | Temperature | 90° | 100° |
    | Battery, on battery power only | 20% | 10% |
    | Battery health, in the panel | Below 80% | Never |

- **Panel** (left click): CPU history and one bar per core, memory split into app, wired and
  compressed with the pressure level, network rates with a chart and the totals since boot, disk
  space, battery time, health and cycle count, and the CPU, GPU, SSD and battery temperatures.
  Battery health is what a full charge holds as a share of the design capacity, the figure macOS
  calls Maximum Capacity. The footer shows what Glance Bar itself uses.
- **Pointing and clicking in the panel**: a part lights up under the pointer when a click does
  something. A figure with more behind it explains itself in a tooltip.

    | Part | Under the pointer | A click |
    |------|-------------------|---------|
    | CPU history and network chart | The reading of that column and how long ago it was taken | Opens Activity Monitor or Network settings, as the rest of the card does |
    | Core bars | The core's number, its kind and its load | Opens Activity Monitor |
    | Memory bar and its legend | What app, wired or compressed memory is, and its share of the total | Opens Activity Monitor |
    | CPU, GPU and memory tiles | What the figures mean | Opens Activity Monitor |
    | Network address | | Copies the address |
    | Disk card | How free space is counted | Opens Storage settings |
    | Battery card | What health means | Opens Battery settings |
    | Temperatures | Which sensors a figure comes from | |
    | Chip name in the header | | Opens About in System Settings |
    | Refresh interval in the footer | | Opens the settings |

    <p align="center">
      <img src="docs/screenshots/panel-hover-dark.png" width="38%" alt="Detail panel with the pointer on a column of the CPU history: the card is lit, the column stands out and the caption reads 55 percent, 48 seconds ago">
    </p>

- **Settings** (the gear in the panel): a switch and order arrows per meter, the refresh interval
  (1, 2, 3 or 5 seconds, 2 by default), Open at Login, Activity Monitor and Quit.
- **Right click**: Open Activity Monitor, Settings and Quit.

## What it costs

Measured on a MacBook Pro M1 Max with three displays, every meter on and a 2 second refresh,
with `ps -o cputime` and `footprint`:

| | CPU | Memory |
|---|-----|--------|
| In the background, the normal case | 1.2% of one core | 18 MB |
| After the panel was opened once | Same | About 33 MB |

In the same minutes, the menu bar process of iStat Menus 7 used 2.2% and 116 MB with a
comparable set of meters.

Most of the cost is not sampling. A profile shows about a tenth of the time in the samplers and
the rest in AppKit, which redraws the item for each display every time its pixels change. Fewer
displays or a longer refresh interval lower it in proportion. macOS runs a background app on
the efficiency cores, where the same work counts as about twice the CPU time: the figure was
0.6% while Glance Bar was the front app.

What keeps it low:

- One timer drives everything, with 10% leeway so macOS can group the wake-up with others. It
  stops while the displays sleep.
- A hidden meter is not sampled while the panel is closed.
- The item redraws only when a pixel would change. Readings are first reduced to what gets
  drawn (bar heights in half points, rounded text), and equal results skip the redraw.
- Each rendering is drawn once per appearance and display scale, then copied.
- Battery changes arrive as system events. Disk space is read once a minute.
- The panel is built when it opens and dropped when it closes.
- There is no helper process, no dependency and no network access.

## What it reads

| Reading | Source |
|---------|--------|
| CPU load | `host_statistics`, and `host_processor_info` per core while the panel is open |
| GPU | `PerformanceStatistics` of the `IOAccelerator` services |
| Memory | `host_statistics64`, `kern.memorystatus_level` and `kern.memorystatus_vm_pressure_level` |
| Temperatures | The System Management Controller, read-only, through the `AppleSMC` service |
| Network | Interface byte counters from `sysctl` (`NET_RT_IFLIST2`) |
| Battery | IOKit power sources, and `AppleSmartBattery` for the capacities and the cycle count |
| Disk | Volume capacity of `/`, counting the space macOS can free on demand |

Settings live in the app's user defaults (`local.glance-bar`). The app writes no other file and
opens no network connection. A click on the network address in the panel puts that address on
the clipboard.

The temperature sensor keys differ per chip generation. The M1 list is checked on real
hardware, where its average matches the CPU temperature iStat Menus shows. The lists for M2 to
M5 follow the [Stats](https://github.com/exelban/stats) project and are not checked here. On an
unknown chip the app tries every known key and keeps the ones the Mac has.

## Uninstall

Turn off Open at login in the settings, choose Quit, then:

```bash
rm -rf "$HOME/Applications/Glance Bar.app"
defaults delete local.glance-bar
```

## Development

```bash
swift test                                            # the GlanceCore test suite
swift run GlanceBar --demo                            # the app on made-up readings
swift run GlanceBar --snapshot /tmp/glance-bar --demo # the item and the panel as PNG files, dark and light
scripts/build-app.sh                                  # the release app bundle in build/
```

- `Sources/GlanceCore`: samplers, the math behind each reading, formatting, settings and the
  render model of the menu bar item. No AppKit. Covered by `Tests/GlanceCoreTests`.
- `Sources/GlanceBar`: the status item and its Core Graphics renderer, the sampling loop, the
  popover and its SwiftUI views.
- `scripts/`: build, install, release packaging, and the icon and brand image generators.

Without `--demo`, `--snapshot` renders the live readings of your Mac. The images in
`docs/screenshots` come from `--snapshot docs/screenshots --demo`.

CI builds, tests and renders the demo snapshots on every pull request. Pushing a tag such as
`v1.0.0` that matches the version in `Resources/Info.plist` publishes `Glance Bar.app` as a
zipped GitHub release.

## Contributing

Bug reports and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) covers the setup,
the checks and the guidelines, and the [Code of Conduct](CODE_OF_CONDUCT.md) applies to every
project space.

## License

[MIT](LICENSE).

Glance Bar is an independent project. It is not affiliated with or endorsed by Apple or by
Bjango, the makers of iStat Menus. The sensor key lists for chips other than the M1 follow the
[Stats](https://github.com/exelban/stats) project, which is also MIT licensed.
