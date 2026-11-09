<p align="center">
  <img src="images/logo.png" alt="NP++ logo" width="128">
</p>

# NP++ for macOS

NP++ is a native macOS port of Notepad++, written in Objective-C++ with AppKit and the
vendored Scintilla and Lexilla editing components. It runs as a standard Mac app with
native menus, toolbars, file dialogs, and light and dark appearance.

## Screenshots

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="images/layout-light-v2.png" alt="NP++ in light mode" width="480"><br>
      <em>Light mode</em>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="images/layout-dark-v2.png" alt="NP++ in dark mode" width="480"><br>
      <em>Dark mode</em>
    </td>
  </tr>
</table>

## Window layout

From top to bottom, the main window has:

- **Menu row:** File, Edit, Search and the other document menus. The macOS menu bar keeps only the NP++ app menu.
- **Toolbar row:** the editing and view buttons. When the window is narrow, buttons that don't fit move behind the » button, which opens a vertical list of their icons.
- **Tabs and editor:** open documents, with the editor below them and the status bar at the bottom.

Keyboard shortcuts work the same as before.

## Customisable toolbar

One layout drives both looks, Classic and Tahoe (Liquid Glass). Open **Settings → Toolbar** (or **Tahoe**) to:

- show or hide whole groups, or individual buttons;
- put each button on the toolbar, in the group's overflow menu, or hide it;
- reorder buttons by dragging or with Move Up and Move Down;
- turn Tahoe mode on or off (takes effect after a restart), or reset to the defaults.

The layout is saved in `~/Library/Application Support/NP++/toolbarLayout.xml`. New-tab and close-tab stay visible at any window width. Groups include Look (editor theme and window opacity) and Large (large file sections).

## Large files

Opening a file above the size limit lets you open just a section of it, or load the whole file. **View → Large File Sections** moves to the next or previous section or to a byte offset, and saving writes the section back into the file without rewriting the rest.

## Editor theme

The editor text area can use light or dark colours independently of the window. Choose **View → Editor Theme → Follow App Theme, Light or Dark**, or click the half-circle button in the toolbar to flip between light and dark. The setting applies to every open editor and is kept between launches.

## Requirements

- macOS 11 (Big Sur) or later
- Xcode command-line tools (`xcode-select --install`)
- CMake 3.20 or later

## Build the app

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release --parallel
open build/NP++.app
```

The app is built as a universal binary (arm64 and x86_64).

## Independent configuration directories

Launch a separate instance with `-settingsDir` to keep its preferences, plugins,
backups and session separate from the default profile:

```bash
open -n 'build/NP++.app' --args '-settingsDir=~/Library/Application Support/NP++ Dev'
```

Relative paths resolve against the launch working directory. Custom profiles keep
their preferences in `preferences.plist` inside that directory; they do not import
or migrate the default profile. An empty or unusable path stops startup with an
error. Omitting the option preserves the existing default directory and migration.

## Line endings

Opening or reloading a file detects its first CRLF, LF or CR line ending and uses
that format for newly inserted text. Existing bytes, including mixed line endings,
are preserved until an explicit EOL conversion. Empty files and files without line
endings use the New Document preference. Themes do not change the document's EOL
mode.

## Run the tests

The XCTest suite covers file loading and saving across encodings (UTF-8 with and without
BOM, UTF-16 LE and BE, Windows-1252, empty files), save state after edits and failed saves,
and the lossy-encoding warning for saves and conversions. Additional tests cover
line-ending detection, insertion after theme changes, and independent configuration
directories (including persistence and legacy migration).

```bash
cmake -S . -B build-tests -DNPP_BUILD_TESTS=ON
cmake --build build-tests --target NppEncodingTests --parallel
xcrun xctest build-tests/NppEncodingTests.xctest
```

Continuous integration builds and runs the suite on both Apple Silicon and Intel
on every push to `master` and on pull requests (see `.github/workflows/macos.yml`).
Each job publishes a Universal app ZIP preserving the bundle's executable bits
and resource metadata.

## Project layout

- `src/` — application code (windows, controllers, editor view, plugins, theming)
- `resources/` — icons, XML configuration (languages, styles, shortcuts), localization
- `scintilla/`, `lexilla/`, `regex/` — vendored editing, lexing, and regex components
- `tests/` — XCTest sources
- `test_plugins/` — sample plugin used during development

## Icon

The app icon is `resources/npp.icns`, generated from a 1024×1024 master.

## License

GPL-3.0. See [LICENSE](LICENSE).

This macOS port is based on [Nextpad++ for macOS](https://github.com/nextpad-plus-plus/nextpad-plus-plus-macos) and on [Notepad++](https://notepad-plus-plus.org), both by their original authors.
