# Hublot

A small floating window for macOS that stays above every other window, including full-screen apps, without taking the keyboard focus.

## Build and run

Requires macOS 13 or later and the Swift toolchain.

```sh
./scripts/build-app.sh
open build/Hublot.app
```

Hublot has no Dock icon. Use its menu bar icon to show, hide or quit it.

## Reading documents

Hublot displays PDF and Markdown files. To open one:

- drop it on the window;
- click the folder button in the title bar;
- choose Hublot in the Finder's "Open With" menu.

To zoom in a PDF, pinch on the trackpad or use the buttons in the title bar.

The books button lists the notes of your Obsidian vaults. Wikilinks, embedded images, callouts and front matter are supported in notes.
