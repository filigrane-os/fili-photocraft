# fili-photocraft: where things stand and what is left

Read this first when resuming (the previous conversation was cleared). Repository: `~/Projects/fili-photocraft` (branch `develop`,
remote `git@github.com:filigrane-os/fili-photocraft.git`, public). The interface kit is `~/Projects/fili-ui` (branch `layer-row`).
Memory notes of the assistant: `fili-photocraft-project` (in the Filigrane project memory).

## What it is

An image editor: a Qt Quick window (module `Fili.UI`) on the PhotoCraft engine (crates `photocraft-engine|io|compose|raster`, pinned
by commit in `Cargo.toml`, no egui). The interface follows PhotoCraft's own (captures in `~/.cache/photocraft-ref/repo/docs/images/`,
the installed original is `photocraft`): options bar, tool strip, document tab with rulers and scroll bars, dock of panels, strip of
panel icons, status bar. The menu lives in the fili-bar (fallback menu `shell/appmenu/fili-photocraft.json`, actions through
`fili-photocraft ctl --pid PID action NAME`).

## Done (all on `origin/develop`)

- **Tools** (one button per group, a key or a click on the tool in hand goes to the next of its group): move (Auto-Select), marquees
  (rectangle, ellipse), lasso, magic wand, quick and object selection, crop, eyedropper, brush, pencil, clone stamp, history brush,
  spot healing, remove, gradient, paint bucket, pen, direct selection, text (edits an existing type layer), seven shapes, eraser,
  blur, sharpen, smudge, dodge, burn, sponge, hand, zoom.
- **Panels**: Color (picker), Swatches, Gradients, Patterns | Properties (layer, size, fill, Document; adjustment sliders; curves with
  histogram), Adjustments, Navigator | Layers (blend, opacity, locks, filter, thumbnails, buttons), Channels, Paths, History
  (snapshots). Window menu shows any of them (`panel-NAME`).
- **Menus**: File (New, Open, Save a Copy, Export Layers), Edit, Image, Layer (styles, masks, clipping), Select, Filter, Window, View,
  Tools. 181 actions, each also a `ctl` action.
- **Debug**: panel (Ctrl+Shift+L), log file, incidents (`src/logs.rs`, same as the other fili-* applications).

## How to work on it

- `make dev` (release profile without link-time optimisation, ~1 min after a Rust change) then `make run ARGS=image.jpg`: the QML is
  read from `qml/` and `../fili-ui/qml`, so a QML change needs no build. **Never `make install` to iterate.**
- `make test`: unit tests, `scripts/check-shell-menu.py` (menu = window) and the ctl catalog lint (`scripts/fili-api-lint`).
  The first run compiles the test profile (minutes).
- `make test-tools`: drives every tool without a mouse (`ctl action pointer-press|pointer-move|pointer-release X,Y`) on a generated
  image, off screen, and checks `ctl state` (`lastStep`, `layers`, `selection`). Run it after any change to the pointer code.
- `target/fast/fili-photocraft probe FILE`: opens FILE and runs, on the engine alone, the commands every tool and every menu sends,
  with the parameters the window sends. A new command goes in `probe_menu`/`probe_selection` (`src/document.rs`) first.
- `scripts/gen-menu.py`: the menus File/Edit/Image/Layer/Select/Filter come from two tables in it (`simple` = a command with fixed
  parameters, `dialogs` = a command that asks for numbers). It rewrites the `BEGIN/END generated` blocks of `qml/Main.qml`, the ctl
  catalog and the menu file; idempotent. Tools (`tool-NAME`) and panels (`panel-NAME`) are written by hand in `Main.qml`: an action
  name is lowercase letters and dashes only (the checker refuses digits).
- Seeing it: `scripts/niri-shot.sh fili-photocraft NAME` (captures go to `~/Screenshots/`). niri cannot capture a window that is off
  screen or a locked session (swaylock): close the original `photocraft` window, `niri msg action focus-window --id N` and
  `set-window-width --id N 1900` first. **Check the dock structure on a capture after any edit near `FiliDockGroup`**: the offscreen
  load does not notice a group nested in the previous one (it happened once).
- The engine's command list with parameters: run `FILI_COMMANDS_OUT=/some/file target/fast/fili-photocraft probe FILE`, it writes the
  whole `command.list` there (1000+ commands).
- Commits: no attribution line to Claude, English messages. The repository is public: scan the diff first.

## Left to do

Code:
1. **Edit a shape** after creating it: fill and outline colours in Properties (the data is `shape.info`; `shape.edit`), the live
   shape (rounded radius, polygon sides, star ratio) as options of the shape tools.
2. **Transform on screen**: Free Transform is only a dialog (scale, rotate, move). A box with handles over the layer
   (`edit.transform` with `quad`), also for the selection (`select.transformSelection`).
3. **Move > Show Transform Controls** (the checkbox PhotoCraft has in the move options).
4. **Text**: a character/paragraph panel (`type.setStyle`: size, tracking, leading, alignment, colour of the existing layer), paragraph
   text (`box`), text on a path.
5. **Layer styles**: a dialog per effect with all its parameters (today the menu applies the defaults), Effects rows in the layer list
   (the reference shows "Effects > Drop Shadow" under a layer).
6. **Masks**: a mask thumbnail next to the layer thumbnail, painting on the mask (`target: "mask"` of the stroke commands), the
   Channels panel selection (`channel.target`) feeding the stroke target.
7. **Adjustment layers**: a Properties panel for every kind that only has defaults today (selective color, channel mixer, gradient
   map, color lookup), clip to layer below, adjustment visible.
8. **Smart objects and filters** (`layer.smartObjects.*`, `layer.smartFilter.*`) and Camera RAW-style develop: none of it has an entry.
9. **Selection**: marching ants (the outline is a plain accent rectangle of the bounding box; the engine gives the mask surface),
   Select and Mask workspace, quick mask painting, save/load selection.
10. **Open/save**: Save (overwrite the opened file, with a confirmation), several documents (tabs, `file.openAs`), recent files,
    drag and drop between documents, export presets (`file.export.presets.*`), Save for Web, `photocraft-cli batch` entry.
11. **Settings** (`~/.config/filigrane/fili-photocraft.toml` and a "Settings…" menu entry): default brush, units, rulers, autosave.
    Only create it when there is a real setting.
12. **Header/footer**: the footer follows `fili-theme footer`; there is no header (the options bar replaces it); decide if the header
    option should show the standard anatomy header.
13. **Brief for Lia** (`shell/lia/fili-photocraft.md`) and the ctl catalog: add worked examples for the pointer actions and the dialogs.
14. Translations (`Fili.tr` strings; `i18n/fr.json` like the other applications).

Publishing (outward actions: ask the user first, he tests everything live before any tag):
15. Merge `layer-row` of **fili-ui** into its `main` (it is 0.5.0: image editor parts, `FiliTabBar.maxTabWidth`, icons; CHANGELOG already
    merged with the 0.4.0 of another session). The CI of `main` then creates the tag `v0.5.0`. `make check` of the kit must pass
    (it needs `QMAKE=/usr/lib/qt6/bin/qmake6`; the lock file `Cargo.lock` was updated for 0.5.0, commit it).
16. In `Cargo.toml` of this repository replace `fili-ui = { path = "../fili-ui" }` by the tag `v0.5.0` (see how fili-recorder pins it),
    so that the CI of `develop` can build.
17. `.github/workflows/ci.yml` (copy from fili-recorder: build and tests in a Void container, creates `vX.Y.Z` from `Cargo.toml` +
    `CHANGELOG.md` on `main`; never tag by hand), `CHANGELOG.md`, branch `main`.
18. In the **filigrane** repository (`~/Projects/filigrane`): `apps/fili-photocraft/upstream` (url + tag), the xbps package (see how
    `apps/fili-recorder` and `packages/` do it), README table of versions with CPU and RAM per release, alias name if wanted.
19. The README of this repository and `docs/` for users.

## Known limits and traps

- cxx-qt watches the whole folder (`rerun-if-changed`): adding a file triggers a full rebuild. Run the app with
  `QT_QUICK_BACKEND=software`. No C++ in the project, ever (Rust only, `cxx-qt` bridge in `src/bridge.rs`).
- `history` only holds the applied states (no redo states in the list): `historyGoto` undoes down to the chosen state.
- The live preview of a drag applies the command, then undoes it at the next move (`preview`/`endPreview` in the bridge), so a
  slow command makes the drag slow; `paint.remove` is a background job and has no preview.
- Strokes on a Shape or Type layer are refused by the engine (`is not available right now`): the message shows in the footer.
- `paint.stroke`-like commands take `layer`, `points`, `size`, `hardness`, `opacity`, `flow`; `select.quick` takes only `points`,
  `size`, `mode`, `sampleAllLayers`: the parameters are built per tool in `strokeParams()`.
