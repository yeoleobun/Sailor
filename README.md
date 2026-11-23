<p align="center">
  <img src="assets/AppIcon.png" width="112" height="112" alt="Sailor Icon" />
</p>

<h1 align="center">Sailor</h1>

<p align="center">
  A lightweight, native macOS menu bar utility that remembers and automatically switches your <b>macOS Network Location</b> based on the current Wi-Fi network.
</p>

## Install (Apple Silicon)

### Option 1: Homebrew (Recommended)

```bash
brew tap yeoleobun/tap
brew install --cask yeoleobun/tap/sailor
```

### Option 2: Manual `.dmg` Download

1. Download **`Sailor-macos-arm64.dmg`** from the [latest GitHub Release](https://github.com/yeoleobun/Sailor/releases/latest) and drag **`Sailor.app`** into `/Applications`.
2. Clear the browser quarantine flag once before first launch:
   ```bash
   xattr -cr /Applications/Sailor.app
   open /Applications/Sailor.app
   ```

## Features

- **Zero-Config Memory:** Simply pick a macOS Network Location (`Automatic`, `Home`, `Work`, …) from Sailor's menu while connected to a Wi-Fi network. Sailor switches immediately and remembers your choice for that SSID—next time you reconnect, it switches back automatically.
- **Native macOS Menu (`NSMenu`):** Pure AppKit `statusItem.menu` with macOS's built-in Liquid Glass translucency, section headers, checkmarks, and submenus—no separate dashboard window needed.
- **Pendulum Anchor Indicator:** Monochrome template anchor icon in the menu bar that adapts to Light & Dark Mode and swings smoothly from its top ring whenever your Network Location changes (toggleable via **Swing Animation**).
- **Zero `sudo` Prompts:** Uses macOS's built-in `/usr/sbin/scselect` to switch existing Network Locations instantly without administrator privileges, plus a 1-click **Network Settings…** shortcut to create or edit Locations in System Settings.
- **Lightweight & Private:** Pure Swift/AppKit, zero external dependencies; stores remembered `SSID → Location` rules in `~/Library/Application Support/Sailor/rules.json` and preferences in `UserDefaults`.

## Permissions

- **Location Services:** macOS 14+ requires Location Services permission for apps to read the current Wi-Fi SSID via `CoreWLAN`. Click **Allow Location to Read Wi-Fi…** in Sailor's menu if prompted.
- **macOS Network Locations:** Manage your Locations (DNS, HTTP/SOCKS Proxy, interfaces) in **System Settings → Network → `•••` → Locations**, and let Sailor handle switching between them automatically.

## Build from Source

```bash
./scripts/build-app.sh
open build/Sailor.app
```

To create release `.zip`, `.dmg`, and `SHA256SUMS.txt` artifacts:

```bash
./scripts/release.sh
```

## Project Structure

- `assets/` — App icon (`AppIcon.png`, `AppIcon.icns`) and menu bar template SVG (`sailor-menubar.svg`)
- `Sources/Sailor/` — Native AppKit menu bar app (`SailorApp.swift`, `AnchorStatusIcon.swift`, `RuleStore.swift`, `WiFiMonitor.swift`, `NetworkLocationManager.swift`)
- `scripts/` — App bundle builder (`build-app.sh`) and release packager (`release.sh`)

## License

MIT
