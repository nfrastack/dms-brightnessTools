# nfrastack/dms-brightnessTools

## About

Brightness Tools is a DankMaterialShell (DMS) plugin that lets you place independent brightness sliders for any backlight or LED device the system exposes such as a display backlight, keyboard backlight, microphone-mute LED, etc. Choosing per-device whether each slider lives in the DankBar, the Control Center, or both.

## Features

- One configurable variant per device — display backlight, keyboard backlight, mic LED, ThinkPad indicator LEDs, anything visible in `dms brightness list`
- Per-variant placement: `Show as bar pill` (DankBar) and/or `Include in control center` (CC detail panel)
- Per-variant `Show OSD when adjusting` toggle — slider drag fires DMS's brightness OSD when on, writes silently when off
- Live, reactive updates from `/sys/class/<class>/<dev>/brightness` so external changes (Fn keys, `brightnessctl`, etc.) are reflected immediately
- Auto device discovery via `dms brightness list` with a sysfs scan fallback
- Optional minimum-percent floor and configurable wheel/keyboard step per variant

## Maintainer

- [Nfrastack](mailto:code@nfrastack.com)

## Table of Contents

- [About](#about)
- [Features](#features)
- [Maintainer](#maintainer)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Permissions](#permissions)
- [Caveats](#caveats)
- [Troubleshooting](#troubleshooting)
- [Support & Maintenance](#support--maintenance)
- [License](#license)

## Requirements

- DankMaterialShell with the `brightness` capability (any 1.5-beta build is fine)
- `dms` binary on PATH (used by the Refresh devices button to enumerate devices via `dms brightness list`)
- Optional: `brightnessctl` for the silent (`Show OSD = off`) write path; falls back to `dms ipc` otherwise

## Installation

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/
git clone https://github.com/nfrastack/dms-brightnessTools ~/.config/DankMaterialShell/plugins/brightnessTools
```

Reload DMS, then enable **Brightness Tools** in Settings -> Plugins.

## Configuration

Open Settings -> Plugins -> **Brightness Tools**, click **Refresh devices** to populate the device dropdown, then add one variant per slider you want.

Per-variant fields:

| Key                   | Type      | Description                                                                                   | Default               |
| --------------------- | --------- | --------------------------------------------------------------------------------------------- | --------------------- |
| `name`                | string    | Variant label shown in the list and in Control Center detail.                                 | `Slider <n>`          |
| `device`              | string    | Device id like `backlight:amdgpu_bl1` or `leds:tpacpi::kbd_backlight`.                        | First detected device |
| `icon`                | string    | Material Symbols icon name (fuzzy-search dropdown).                                           | `brightness_6`        |
| `showInBar`           | bool      | Render this variant as a DankBar pill.                                                        | `true`                |
| `showInControlCenter` | bool      | Include this variant in the **Brightness** entry's Control Center detail panel.               | `false`               |
| `useOSD`              | bool      | Adjust via `dms ipc call brightness …` (shows OSD overlay) instead of silent `brightnessctl`. | `true`                |
| `minPercent`          | int 0-100 | Lower bound the slider can't go below.                                                        | `1`                   |
| `step`                | int 1-25  | Wheel/keyboard increment in percent.                                                          | `5`                   |

Plugin-wide:

| Key          | Type  | Description                             | Default |
| ------------ | ----- | --------------------------------------- | ------- |
| `deviceList` | array | Cache populated by **Refresh devices**. | `[]`    |

## Usage

- **Bar pill**: shows the icon + current percentage. Click -> popout slider.
- **Control center**: a single **Brightness** entry whose detail panel renders one slider per variant flagged `Include in control center`.
- **External changes**: pressing a Fn-brightness key updates the pill within via `FileView { watchChanges: true }`.

> The Control Center collapses all variants flagged for CC into a single "Brightness" tile because DMS currently registers one CC entry per plugin id (not per variant). A patch making CC fan out variants like the bar does is at `~/.config/DankMaterialShell/patches/dms-cc-variants.patch` if you want one tile per slider.

## Permissions

The plugin requests these permissions (in `plugin.json`):

- `settings_read` — read configured variants and device cache
- `settings_write` — save variant edits and device list
- `process` — run `dms brightness list` for discovery and `brightnessctl` for silent writes

## Caveats

- Setting brightness via `brightnessctl` (or directly to sysfs) does **not** suppress the DMS OSD if your installed DMS version udev-monitors the device. The plugin avoids this by routing the silent path through `brightnessctl` directly; if your DMS still pops the OSD, switch the variant to `Show OSD when adjusting = on`.
- LEDs that can't span 0–100% (e.g. `leds:platform::micmute` is binary on/off) will still accept slider input but only honour 0 vs non-zero.

## Troubleshooting

- "Device dropdown empty after Refresh" - run `dms brightness list` manually — if it fails or shows nothing, your DMS isn't running with the `brightness` capability. The plugin falls back to a sysfs scan automatically; check the journal for `brightnessTools` messages.
- "Slider doesn't update when I press Fn keys"-  confirm `/sys/class/<class>/<dev>/brightness` is readable by your user.
- "Save doesn't stick / shows blank on reload" -  indicates a stale settings cache; toggle the plugin off then on in Settings -> Plugins to force a reload.

## Support & Maintenance

- For community help, tips, and community discussions, visit the [Discussions board](../../discussions).
- For personalized support or a support agreement, see [Nfrastack Support](https://nfrastack.com/).
- To report bugs, submit a [Bug Report](issues/new). Usage questions may be closed as not-a-bug.
- Feature requests are welcome, but not guaranteed. For prioritized development, consider a support agreement.
- Updates are best-effort, with priority given to active production use and support agreements.

## License

MIT. See the [LICENSE](LICENSE) file.
