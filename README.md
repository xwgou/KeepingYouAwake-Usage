# KeepingYouAwake-Usage

A macOS menu-bar app that keeps your Mac awake and shows remaining **Codex** and
**Kimi Code** subscription quota. Built as a fork of
[KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake).

## Features

- Click the menu-bar icon to see provider status and usage details.
- Open a shared **Usage Panel** from the menu, Spotlight/Finder, or a configurable
  global shortcut (default **Control–Option–Command–U**). Optionally show a Dock icon.
- View separate quota windows, reset times, and last-update timestamps.
- **Red** means 0% remaining (limit reached); other values use normal text.
- Refresh automatically every five minutes, or on menu/panel open when the last check
  is over a minute old. **Refresh Usage** checks immediately.
- Keep your Mac awake indefinitely or for a selected duration.
- Adaptive menu-bar icons stay visible on light and dark backgrounds; distinct
  cup shapes show the awake state.
- Enable **Legacy Click Behavior** to restore click-to-toggle sleep prevention.

## Requirements

- macOS 12 or newer for the app. Provider CLIs may require a newer version.
- Xcode with Swift 6.1 support to build; local development was tested with Xcode 27.2.
- `/usr/bin/python3`, available with the developer tools on the test Mac.
- Official Codex and/or Kimi Code CLI installed and signed in to the account whose
  usage you want to view. You can connect either provider independently.

This MVP is built from source. An installer and notarized release are not yet
provided. Installing the original KeepingYouAwake app does not install this fork.

## Setup

### 1. Check your CLI installation

```sh
command -v codex
command -v kimi
/usr/bin/python3 --version
```

Open each provider's official CLI and complete its normal sign-in flow first.
The app reuses those accounts. No API key or password needs to be entered into
KeepingYouAwake-Usage.

### 2. Clone and build

The MVP currently lives on `feature/ai-usage-menu`:

```sh
git clone --branch feature/ai-usage-menu https://github.com/xwgou/KeepingYouAwake-Usage.git
cd KeepingYouAwake-Usage

xcodebuild \
  -workspace KeepingYouAwake.xcworkspace \
  -scheme KeepingYouAwake \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -onlyUsePackageVersionsFromResolvedFile \
  build
```

The workspace and scheme retain their upstream names. Xcode resolves the locked
package dependencies and bundles/signs the usage helper. The command uses ad-hoc
signing for local testing, which does not provide Developer ID notarization.

### 3. Install and open

Quit any running copy before updating. Copy the built app into your Applications
folder, using the fork's name:

```sh
mkdir -p "$HOME/Applications"
ditto build/Build/Products/Debug/KeepingYouAwake.app \
  "$HOME/Applications/KeepingYouAwake-Usage.app"
open "$HOME/Applications/KeepingYouAwake-Usage.app"
```

This is a menu-bar app: look for its icon at the top of the screen. It does not
open a normal main window.

### 4. Connect your providers

1. Click the menu-bar icon.
2. Choose **Connect Codex…** and confirm access to the installed CLI account.
3. Choose **Connect Kimi Code…** and confirm if you use Kimi.
4. Open the **Codex** or **Kimi Code** submenu to inspect quota and reset times.

The bundled helper manages refreshes. No folder selection, separate bridge
command, or manually started Kimi server is required. **Disconnect Codex** or
**Disconnect Kimi Code** stops future checks for that provider without signing
out its CLI account.

## Usage Panel and keyboard shortcut

Choose **Show Usage Panel…** in the menu, or open the installed app through
Spotlight or Finder—even when it is already running. The panel shares provider
status, quota colors, refreshes, connections, and Keep Awake controls with the menu.
Closing the panel leaves the app running; Escape hides it.

The default global shortcut is **⌃⌥⌘U**. In the panel, choose modifiers and a letter
or F1–F12, then click **Apply Shortcut**. Include Command or Control. Disable
**Global shortcut** and apply to turn it off. If registration fails, the previous
shortcut stays active. Letter choices use physical US-keyboard positions.

Enable **Show in Dock** for Dock and app-switcher access; it is off by default.
The Dock preference and shortcut survive relaunch. Launch at login stays quiet.

## Usage and troubleshooting

- **Keep Awake** toggles sleep prevention. **Activate for Duration** selects a
  duration. Opening the menu does not toggle it in the default click mode.
- **Unavailable:** verify that the official CLI works and is signed in, then
  choose **Refresh Usage**. Missing quota is never displayed as 0%.
- **Not connected:** choose the corresponding Connect action.
- **Stale:** the last successful data is over six minutes old; refresh and check
  your network connection.
- **CLI not found:** the helper checks its PATH and common locations, including
  `~/.local/bin/codex`, `~/.kimi-code/bin/kimi`, `/opt/homebrew/bin`, and
  `/usr/local/bin`. Custom install paths are not yet configurable in the UI.
- **Old menu or styling after an update:** quit and reopen the installed app.
- **Mac sleeps with the lid closed:** the underlying `caffeinate` utility does
  not override closed-lid behavior.

Quota refers to Codex/Kimi Code subscription allowances, not API billing balances.
Kimi's local usage API is experimental and may change with CLI updates.

## Privacy and current limitations

The main app is sandboxed. Its bundled XPC helper runs outside App Sandbox to
read usage through the installed CLIs. The helper returns sanitized quota data;
credentials are not passed to the menu app. Usage checks do not start model turns
or generate model output. Raw provider error details are omitted from the UI.

The MVP still depends on developer tools for Python, uses the upstream icon, and
has English-only usage UI. Automatic app updates are disabled. Release packaging,
a distinct icon, localization, and Developer ID signing/notarization remain work
for a distributable release.

See the [security review](Documentation/AI-Usage/SECURITY_REVIEW.txt) and
[development notes](Documentation/AI-Usage/DEVELOPMENT.txt) for validation details.
Do not commit CLI credentials, server tokens, logs, or runtime snapshots.

## Development and tests

```sh
# Bridge parsers, provider lifecycle, redaction, and menu action routing
python3 -m unittest discover -s Tools/usage_bridge/tests -v

# Native quota-color boundary checks
xcrun clang -fobjc-arc -framework Cocoa Tools/style_tests/main.m -o /tmp/kya-style-tests
/tmp/kya-style-tests

# Existing native suite; builds the app and bundled helper
xcodebuild \
  -workspace KeepingYouAwake.xcworkspace \
  -scheme KeepingYouAwake \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -onlyUsePackageVersionsFromResolvedFile \
  test
```

Current checks: 13 bridge/menu tests, seven color-boundary checks, and 14 native
tests. Live Codex and Kimi usage were also verified through a sandboxed XPC client.

## License and attribution

[MIT](LICENSE). Original KeepingYouAwake by Marcel Dierkes, inspired by Caffeine.
The fork retains upstream attribution. See [CONTRIBUTING.md](CONTRIBUTING.md) for
upstream conventions; development of this MVP takes place in this fork.
