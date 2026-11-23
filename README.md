# fili-photocraft

The image editor of Filigrane: a Qt Quick window (the `Fili.UI` kit) on the [PhotoCraft](https://github.com/storytold/photocraft)
engine. The layout is PhotoCraft's (options bar, tools, document tab, panels, status bar); the menu lives in the fili-bar.

## Development

A release build takes minutes (link-time optimisation over the whole engine). To iterate:

- `make dev` builds `target/fast`: the engine stays optimised, there is no link-time optimisation.
- `make run` (`make run ARGS=image.jpg`) starts it with the QML read from `qml/` and from `../fili-ui/qml`: after a change of a `.qml`
  file, run it again, no build. Only a change of the Rust code needs `make dev`.
- The kit's components are best worked on in the `fili-ui` demo (`make demo` there), which needs no Rust at all.
- `make test` runs the unit tests and the checks of the bar menu and of the ctl catalog; `make install PREFIX=~/.local` builds the
  release version and installs it.

License: GPL-3.0-or-later (the engine is MIT or Apache-2.0).
