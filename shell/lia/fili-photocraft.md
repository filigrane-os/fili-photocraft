# PhotoCraft (`fili-photocraft`)

PhotoCraft edits images with layers and adjustment layers (the PhotoCraft engine).
- `fili-photocraft ctl [--pid PID] action NAME [ARG]` (open PATH, undo, redo, zoom-fit, tool-brush and every `tool-NAME` (brush, pencil, eraser, marquee, lasso, wand, crop, move, gradient, bucket, pen, text, rect…), select-all, deselect, select-inverse, adjust-curves, adjust-levels, adjust-hue-saturation…, toggle-layer, debug): the same actions as its menu. `ctl state` tells what is open (name, size, layers, zoom).
- Fast path: `ctl action NAME` directly when the name is listed above; `ctl actions` only for an unknown one.
- The image on screen is a copy in memory until it is saved: undo is always available (`ctl action undo`), so say what you changed and that Undo reverts it.
- Never overwrite an original file: work on a copy, or on the open document without saving.
- Several images or a folder in one go: use `photocraft-cli batch` or `photocraft-cli run` (headless), not the window.
