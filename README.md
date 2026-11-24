# fili-photocraft

The image editor of Filigrane: a Qt Quick window (the `Fili.UI` kit) on the [PhotoCraft](https://github.com/storytold/photocraft)
engine. The layout is PhotoCraft's (options bar, tools, document tab, panels, status bar); the menu lives in the fili-bar.

## Tools and panels

Move (with Auto-Select), marquees (rectangle, ellipse), lasso, magic wand, quick and object selection, crop, eyedropper, brush, pencil, clone stamp, history brush, spot healing, remove,
gradient, paint bucket, pen, direct selection, text, shapes, eraser, blur, sharpen, smudge, dodge, burn, sponge, hand, zoom (a key or a click on the
tool in hand goes to the next of its group). Menus: File (New, Open, Save a Copy), Edit (clipboard, fills, stroke, Content-Aware Fill, Free Transform), Image (mode, size, canvas, rotation, crop, trim, auto tone), Layer (styles, masks, clipping, arrange, merge), Select (subject, sky, color range, modify, refine edge), Filter (blur, sharpen, noise, stylize, other), Window (every panel). Panels: Properties (opacity, blend mode, locks, adjustment sliders, curves with histogram),
Adjustments, Color, Navigator, Layers (thumbnails), Channels, Paths, History, and a Debug log (Ctrl+Shift+L).

## Development

A release build takes minutes (link-time optimisation over the whole engine). To iterate:

- `make dev` builds `target/fast`: the engine stays optimised, there is no link-time optimisation.
- `make run` (`make run ARGS=image.jpg`) starts it with the QML read from `qml/` and from `../fili-ui/qml`: after a change of a `.qml`
  file, run it again, no build. Only a change of the Rust code needs `make dev`.
- The kit's components are best worked on in the `fili-ui` demo (`make demo` there), which needs no Rust at all.
- `make test` runs the unit tests and the checks of the bar menu and of the ctl catalog; `make install PREFIX=~/.local` builds the
  release version and installs it.

License: GPL-3.0-or-later (the engine is MIT or Apache-2.0).
