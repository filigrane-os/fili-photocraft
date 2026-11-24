// The open image: a PhotoCraft session, with no Qt in here.
use std::path::Path;
use std::sync::Arc;
use std::time::Instant;

use photocraft_engine::Session;
use photocraft_engine::doc::Document as EngineDocument;
use serde_json::{Value, json};

use crate::render::{Request, composite};

#[derive(Default)]
pub struct Document {
    session: Option<Session>,
}

impl Document {
    pub fn open(&mut self, path: &Path) -> Result<(), String> {
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let opened = photocraft_io::import_file(&name, path, &photocraft_io::ImportOptions::default(), &photocraft_raster::Interrupt::NONE)
            .map_err(|e| e.to_string())?;
        let mut session = Session::new();
        session.add_document(opened.document, Some(path.to_string_lossy().into_owned()));
        self.session = Some(session);
        Ok(())
    }

    pub fn execute(&mut self, id: &str, params: Value) -> Result<(), String> {
        let session = self.session.as_mut().ok_or("no open image")?;
        session.execute(id, params).map(|_| ()).map_err(|e| e.to_string())
    }

    /// Names of the history states and how many of them are applied (the others can be redone)
    pub fn history(&self) -> (Value, usize) {
        match self.session.as_ref().and_then(|s| s.active()) {
            Some(state) => (json!(state.history.entries()), state.history.past_len()),
            None => (json!([]), 0),
        }
    }

    /// Runs a command and returns what it answers (lists, information)
    pub fn query(&mut self, id: &str, params: Value) -> Result<Value, String> {
        let session = self.session.as_mut().ok_or("no open image")?;
        session.execute(id, params).map_err(|e| e.to_string())
    }

    pub fn undo(&mut self) -> bool {
        self.session.as_mut().is_some_and(|s| s.undo())
    }

    pub fn redo(&mut self) -> bool {
        self.session.as_mut().is_some_and(|s| s.redo())
    }

    /// Name, size, layers and history of the image, as the engine reports them
    pub fn detail(&self) -> Value {
        match self.session.as_ref().and_then(|s| s.active()) {
            Some(state) => photocraft_engine::inspect::document_detail(state),
            None => json!({}),
        }
    }

    /// The bounding box of the selection, `[x, y, width, height]` in pixels (None when nothing is selected)
    pub fn selection_bounds(&self) -> Option<[i32; 4]> {
        let doc = self.session.as_ref().and_then(|s| s.active())?.doc.clone();
        let r = doc.selection.as_ref()?.content_bounds();
        (r.width() > 0 && r.height() > 0).then(|| [r.x0, r.y0, r.width() as i32, r.height() as i32])
    }

    /// The document for the render thread: the engine keeps it in an `Arc`, so this copies no pixels
    pub fn snapshot(&self) -> Option<Arc<EngineDocument>> {
        self.session.as_ref().and_then(|s| s.active()).map(|state| state.doc.clone())
    }
}

/// A small picture of each layer drawn alone (groups and adjustment layers have none): `(id, width, height, RGBA8)`, at most `side` pixels
/// on the longer side. Runs on the thread of the caller, which is not the one of the window.
pub fn layer_thumbnails(doc: &EngineDocument, side: u32) -> Vec<(u64, u32, u32, Vec<u8>)> {
    fn walk(doc: &EngineDocument, layers: &[photocraft_engine::doc::Layer], side: u32, out: &mut Vec<(u64, u32, u32, Vec<u8>)>) {
        for layer in layers {
            if let Some(children) = layer.children() {
                walk(doc, children, side, out);
            } else if layer.surface().is_some() {
                let full = photocraft_compose::render_layer(layer, doc.bounds()).to_rgba8();
                if full.width == 0 || full.height == 0 {
                    continue;
                }
                let scale = (side as f32 / full.width.max(full.height) as f32).min(1.0);
                let (w, h) = (((full.width as f32 * scale).round() as u32).max(1), ((full.height as f32 * scale).round() as u32).max(1));
                // Box average: every source pixel lands in exactly one cell
                let mut sum = vec![[0u32; 5]; (w * h) as usize];
                for y in 0..full.height {
                    let cy = (y as u64 * h as u64 / full.height as u64) as usize;
                    for x in 0..full.width {
                        let cx = (x as u64 * w as u64 / full.width as u64) as usize;
                        let i = (y * full.width + x) as usize * 4;
                        let a = full.pixels[i + 3] as u32;
                        let cell = &mut sum[cy * w as usize + cx];
                        for c in 0..3 {
                            cell[c] += full.pixels[i + c] as u32 * a;
                        }
                        cell[3] += a;
                        cell[4] += 1;
                    }
                }
                let mut pixels = Vec::with_capacity((w * h * 4) as usize);
                for cell in sum {
                    let a = cell[3].max(1);
                    pixels.extend([(cell[0] / a) as u8, (cell[1] / a) as u8, (cell[2] / a) as u8, (cell[3] / cell[4].max(1)) as u8]);
                }
                out.push((layer.id.0 as u64, w, h, pixels));
            }
        }
    }
    let mut out = Vec::new();
    walk(doc, &doc.layers, side, &mut out);
    out
}

/// The locks of each layer (`transparency`, `pixels`, `position`, `all`), by layer id: the engine's layer list does not report them
pub fn layer_locks(doc: &EngineDocument) -> std::collections::HashMap<u64, Value> {
    fn walk(layers: &[photocraft_engine::doc::Layer], out: &mut std::collections::HashMap<u64, Value>) {
        for l in layers {
            let k = l.locks;
            out.insert(l.id.0 as u64, json!({"transparency": k.transparency, "pixels": k.pixels, "position": k.position, "all": k.all}));
            if let Some(children) = l.children() {
                walk(children, out);
            }
        }
    }
    let mut out = std::collections::HashMap::new();
    walk(&doc.layers, &mut out);
    out
}

/// A 32-bit BMP (Qt reads it with its alpha): lets QML show a picture from a file without an image provider
pub fn bmp(w: u32, h: u32, rgba: &[u8]) -> Vec<u8> {
    let size = 54 + rgba.len() as u32;
    let mut out = Vec::with_capacity(size as usize);
    out.extend(b"BM");
    out.extend(size.to_le_bytes());
    out.extend([0, 0, 0, 0]);
    out.extend(54u32.to_le_bytes());
    out.extend(40u32.to_le_bytes());
    out.extend(w.to_le_bytes());
    out.extend((-(h as i32)).to_le_bytes()); // top-down
    out.extend(1u16.to_le_bytes());
    out.extend(32u16.to_le_bytes());
    out.extend([0u8; 4]); // BI_RGB
    out.extend((rgba.len() as u32).to_le_bytes());
    out.extend([0u8; 16]);
    for p in rgba.chunks_exact(4) {
        out.extend([p[2], p[1], p[0], p[3]]);
    }
    out
}

/// The layer tree as a flat list, top first, each row with its depth
pub fn flat_layers(layers: &Value) -> Value {
    fn walk(nodes: &Value, depth: u32, out: &mut Vec<Value>) {
        for node in nodes.as_array().into_iter().flatten() {
            out.push(json!({
                "id": node["id"],
                "name": node["name"],
                "kind": node["kind"],
                "visible": node["visible"],
                "opacity": node["opacity"],
                "blend": node["blend"],
                "fill": node["fill"],
                "bounds": node["bounds"],
                "selected": node["selected"],
                "depth": depth,
                // Kind and parameters of an adjustment layer (what `layer.setAdjustment` takes)
                "adjustment": node.get("adjustment").cloned().unwrap_or(Value::Null),
            }));
            walk(&node["children"], depth + 1, out);
        }
    }
    let mut out = Vec::new();
    walk(layers, 0, &mut out);
    Value::Array(out)
}

/// Opens FILE, applies a curve, hides it, undoes: proves the engine works here, and times it
pub fn probe(file: &str) -> i32 {
    let mut doc = Document::default();
    let start = Instant::now();
    if let Err(e) = doc.open(Path::new(file)) {
        eprintln!("open: {e}");
        return 1;
    }
    println!("open {} ms", start.elapsed().as_millis());
    let frame = |doc: &Document| {
        let d = doc.detail();
        let (w, h) = (d["width"].as_i64().unwrap_or(0) as i32, d["height"].as_i64().unwrap_or(0) as i32);
        let copy = Instant::now();
        let snapshot = doc.snapshot().expect("an open image");
        let copy_us = copy.elapsed().as_micros();
        let f = composite(&Request { generation: 0, doc: snapshot, rect: (0, 0, w, h), w: w as u32, h: h as u32 });
        (f, copy_us)
    };
    let (before, copy_us) = frame(&doc);
    println!("full composite {} ms ({}x{}), snapshot {copy_us} us", before.ms, before.w, before.h);
    if let Err(e) = doc.execute("layer.newAdjustmentLayer.curves", json!({"points": [[0, 0], [64, 40], [192, 216], [255, 255]]})) {
        eprintln!("curve: {e}");
        return 1;
    }
    let (curved, _) = frame(&doc);
    let changed = curved.pixels != before.pixels;
    println!("curve {} ms, pixels changed: {changed}", curved.ms);
    let layers = flat_layers(&doc.detail()["layers"]);
    let top = layers[0]["id"].clone();
    // The Properties panel edits the points of the curve and a channel: the engine takes them and reports them back
    let edited = json!([[0, 0], [128, 200], [255, 255]]);
    if let Err(e) = doc.execute("layer.setAdjustment", json!({"layer": top, "points": edited, "red": [[0, 0], [100, 30], [255, 255]]})) {
        eprintln!("setAdjustment: {e}");
        return 1;
    }
    let params = doc.detail()["layers"][0]["adjustment"]["params"].clone();
    // The engine reports levels as decimals (128.0), so the values are compared as numbers
    let pair = |v: &Value| (v[0].as_f64().unwrap_or(-1.0), v[1].as_f64().unwrap_or(-1.0));
    let readback = params["points"].as_array().map(|a| a.iter().map(pair).collect::<Vec<_>>()) == Some(vec![(0.0, 0.0), (128.0, 200.0), (255.0, 255.0)])
        && pair(&params["red"][1]) == (100.0, 30.0);
    if !readback {
        eprintln!("params after the edit: {params}");
    }
    println!("setAdjustment keeps the points and the red channel: {readback}");
    let (reedited, _) = frame(&doc);
    let moved = reedited.pixels != curved.pixels;
    println!("the new curve changes the pixels: {moved}");
    if !(readback && moved) {
        return 1;
    }
    let hidden = doc.execute("layer.setProps", json!({"layer": top, "visible": false})).is_ok() && frame(&doc).0.pixels == before.pixels;
    println!("hiding the curve restores the pixels: {hidden}");
    let undone = doc.undo() && doc.undo() && doc.undo() && frame(&doc).0.pixels == before.pixels;
    println!("undo restores the pixels: {undone}");
    println!("layers: {layers}");
    // The commands the tools of the window run, with the parameters it sends
    let id = doc.detail()["layers"][0]["id"].clone();
    let pts = json!([[20, 20], [60, 40], [90, 30]]);
    let tools = [
        ("paint.stroke", json!({"layer": id, "points": pts, "size": 12, "hardness": 0.8, "color": "#ff0000"})),
        ("paint.pencil", json!({"layer": id, "points": pts, "size": 4, "hardness": 0.8, "color": "#00ff00"})),
        ("paint.blur", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.sharpen", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.smudge", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.dodge", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.burn", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.sponge", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.spotHealing", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.historyBrush", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8})),
        ("paint.cloneStamp", json!({"layer": id, "points": pts, "size": 20, "hardness": 0.8, "source": [100, 100], "offset": [30, 30]})),
        ("paint.bucket", json!({"x": 10, "y": 10, "tolerance": 32, "color": "#0000ff"})),
        ("paint.gradient", json!({"from": [0, 0], "to": [100, 100], "colors": ["#ff0000", "#ffffff"]})),
        ("paint.gradient", json!({"from": [0, 0], "to": [100, 100], "stops": [[0, "#ff0000"], [1, "#ffffff"]], "transparency": [[0, 100], [1, 0]]})),
        ("pattern.presets.select", json!({"pattern": "Checkerboard"})),
        ("paint.bucket", json!({"x": 20, "y": 20, "tolerance": 32, "contents": "pattern", "pattern": "Checkerboard"})),
        ("shape.create", json!({"kind": "star", "rect": [10, 10, 80, 80], "fill": "#e0605a"})),
        ("shape.create", json!({"kind": "path", "fill": "#336699", "path": {"subpaths": [{"closed": true, "knots": [[10, 10], [80, 20], [40, 70]]}]}})),
        ("shape.create", json!({"kind": "line", "from": [0, 0], "to": [90, 90], "weight": 4, "stroke": {"color": "#000000", "width": 4}, "fill": null})),
        ("type.create", json!({"x": 20, "y": 60, "text": "Hi", "size": 24, "color": "#ffffff"})),
        ("layer.translate", json!({"dx": 5, "dy": 3})),
        ("select.magicWand", json!({"x": 10, "y": 10, "tolerance": 32, "mode": "replace"})),
        ("select.lasso", json!({"points": pts})),
        ("select.rect", json!({"x": 5, "y": 5, "width": 50, "height": 40, "ellipse": true})),
        ("image.crop", json!({"x": 0, "y": 0, "width": 100, "height": 80})),
    ];
    let mut tools_ok = true;
    for (command, params) in tools {
        if let Err(e) = doc.execute(command, params) {
            println!("{command}: {e}");
            tools_ok = false;
        }
    }
    println!("tool commands accepted: {tools_ok}");
    // The commands of the menus (File, Edit, Image, Layer, Filter) with the parameters the window sends
    let menu_ok = probe_menu(file) & probe_selection(file);
    println!("menu commands accepted: {menu_ok}");
    for kind in ["levels", "hueSaturation", "brightnessContrast", "vibrance", "exposure", "colorBalance", "blackWhite", "threshold", "posterize", "photoFilter"] {
        match doc.execute(&format!("layer.newAdjustmentLayer.{kind}"), json!({})) {
            Ok(()) => println!("default {kind}: {}", doc.detail()["layers"][0]["adjustment"]),
            Err(e) => println!("{kind}: {e}"),
        }
    }
    let shape = doc.query("shape.create", json!({"kind": "path", "fill": "#336699", "path": {"subpaths": [{"closed": true, "knots": [[10, 10], [80, 20], [40, 70]]}]}}));
    println!("shape.info: {:?}", shape.and_then(|_| doc.query("shape.info", json!({}))).map(|v| v.to_string().chars().take(600).collect::<String>()));
    let moved = doc.query("path.moveAnchors", json!({"name": "layer", "layer": doc.detail()["layers"][0]["id"], "anchors": [[0, 1]], "move": [5, 5]}));
    println!("path.moveAnchors: {:?}", moved.map(|v| v.to_string().chars().take(200).collect::<String>()));
    if let Ok(list) = doc.query("command.list", json!({})) {
        if let Ok(path) = std::env::var("FILI_COMMANDS_OUT") {
            let _ = std::fs::write(path, list.to_string());
        }
    }
    println!("history: {} applied {}", doc.history().0, doc.history().1);
    doc.undo();
    doc.undo();
    println!("after two undos: {} entries, applied {}", doc.history().0.as_array().map_or(0, Vec::len), doc.history().1);
    for q in ["channel.list", "path.list", "swatches.list", "gradient.presets.list", "pattern.list"] {
        println!("{q}: {:?}", doc.query(q, json!({})).map(|v| v.to_string().chars().take(600).collect::<String>()));
    }
    if changed && hidden && undone && tools_ok { 0 } else { 1 }
}

/// The selection tools and commands, then the ones that need pixels, on a fresh image
fn probe_selection(file: &str) -> bool {
    let mut doc = Document::default();
    if doc.open(Path::new(file)).is_err() {
        return false;
    }
    let commands = [
        ("paint.remove", json!({"points": [[20, 20], [60, 40]], "size": 20, "hardness": 80})),
        ("select.subject", json!({"sampleAllLayers": true})),
        ("select.rect", json!({"x": 10, "y": 10, "width": 200, "height": 160})),
        ("select.object", json!({"rect": [10, 10, 100, 80], "sampleAllLayers": true})),
        ("select.rect", json!({"x": 10, "y": 10, "width": 200, "height": 160})),
        ("select.quick", json!({"points": [[20, 20], [60, 40]], "size": 20, "mode": "add"})),
        ("select.modify.expand", json!({"radius": 5})),
        ("select.modify.smooth", json!({"radius": 5})),
        ("select.modify.feather", json!({"radius": 5})),
        ("select.modify.contract", json!({"radius": 3})),
        ("select.refineEdge", json!({"radius": 0, "smooth": 0, "feather": 0, "contrast": 0, "shiftEdge": 0})),
        ("select.grow", json!({})),
        ("select.similar", json!({})),
        ("select.colorRange", json!({"select": "sampledColors", "color": "#336699", "fuzziness": 40})),
        ("select.focusArea", json!({})),
        ("edit.contentAwareFill", json!({})),
        ("select.editInQuickMaskMode", json!({})),
        ("select.editInQuickMaskMode", json!({})),
        ("select.toWorkPath", json!({})),
        ("select.convertToShape", json!({})),
        ("select.deselect", json!({})),
        ("select.reselect", json!({})),
        ("edit.transform", json!({"scaleX": 90, "scaleY": 90, "rotate": 5, "dx": 3, "dy": 3})),
    ];
    let mut ok = true;
    for (command, params) in commands {
        if let Err(e) = doc.execute(command, params) {
            println!("{command}: {e}");
            ok = false;
        }
    }
    ok
}

/// The commands of the window's menus, one by one; prints the ones the engine refuses
fn probe_menu(file: &str) -> bool {
    let mut doc = Document::default();
    if doc.open(Path::new(file)).is_err() {
        return false;
    }
    let out = std::env::temp_dir().join("fili-photocraft-probe.png");
    let commands = [
        ("select.rect", json!({"x": 0, "y": 0, "width": 50, "height": 40})),
        ("edit.copy", json!({})),
        ("edit.paste", json!({})),
        ("edit.pasteSpecial.pasteInPlace", json!({})),
        ("edit.fill", json!({"contents": "color", "color": "#ff8800"})),
        ("edit.stroke", json!({"width": 3, "color": "#00ff00"})),
        ("edit.clear", json!({})),
        ("image.autoTone", json!({})),
        ("image.autoContrast", json!({})),
        ("image.autoColor", json!({})),
        ("filter.blur.gaussianBlur", json!({"radius": 3})),
        ("filter.blur.boxBlur", json!({"radius": 3})),
        ("filter.blur.motionBlur", json!({"angle": 10, "distance": 12})),
        ("filter.blur.surfaceBlur", json!({"radius": 5, "threshold": 15})),
        ("filter.sharpen.unsharpMask", json!({"amount": 80, "radius": 1, "threshold": 0})),
        ("filter.sharpen.smartSharpen", json!({"amount": 100, "radius": 1, "reduceNoise": 10})),
        ("filter.noise.addNoise", json!({"amount": 12.5})),
        ("filter.noise.median", json!({"radius": 2})),
        ("filter.stylize.emboss", json!({"angle": 135, "height": 3, "amount": 100})),
        ("filter.other.highPass", json!({"radius": 10})),
        ("filter.other.offset", json!({"horizontal": 5, "vertical": 5, "undefinedAreas": "wrap"})),
        ("filter.blur.blur", json!({})),
        ("filter.sharpen.sharpen", json!({})),
        ("filter.stylize.findEdges", json!({})),
        ("filter.stylize.oilPaint", json!({})),
        ("layer.pickAt", json!({"x": 10, "y": 10, "target": "layer", "select": true})),
        ("layer.new.layer", json!({})),
        ("layer.duplicate", json!({})),
        ("layer.groupLayers", json!({})),
        ("layer.arrange.bringToFront", json!({})),
        ("layer.mergeVisible", json!({})),
        ("image.imageRotation.90cw", json!({})),
        ("image.imageRotation.90ccw", json!({})),
        ("image.imageRotation.180", json!({})),
        ("image.imageRotation.flipCanvasHorizontal", json!({})),
        ("image.imageRotation.flipCanvasVertical", json!({})),
        ("image.imageSize", json!({"width": 600, "height": 400})),
        ("image.canvasSize", json!({"width": 700, "height": 500})),
        ("image.trim", json!({})),
        ("image.mode.grayscale", json!({})),
        ("image.mode.rgb", json!({})),
        ("image.mode.bits16", json!({})),
        ("image.mode.bits8", json!({})),
        ("layer.layerMask.revealAll", json!({})),
        ("layer.layerMask.hideAll", json!({})),
        ("layer.layerMask.apply", json!({})),
        ("layer.layerStyle.dropShadow", json!({})),
        ("layer.layerStyle.innerShadow", json!({})),
        ("layer.layerStyle.outerGlow", json!({})),
        ("layer.layerStyle.innerGlow", json!({})),
        ("layer.layerStyle.bevelEmboss", json!({})),
        ("layer.layerStyle.colorOverlay", json!({"color": "#336699"})),
        ("layer.layerStyle.gradientOverlay", json!({"from": "#336699", "to": "#ffffff"})),
        ("layer.layerStyle.stroke", json!({"size": 3, "color": "#336699"})),
        ("layer.layerStyle.copyLayerStyle", json!({})),
        ("layer.layerStyle.pasteLayerStyle", json!({})),
        ("layer.layerStyle.clear", json!({})),
        ("layer.createClippingMask", json!({})),
        ("layer.releaseClippingMask", json!({})),
        ("layer.flattenImage", json!({})),
        ("file.saveACopy", json!({"path": out.to_string_lossy()})),
        ("file.new", json!({"width": 640, "height": 480})),
    ];
    let mut ok = true;
    for (command, params) in commands {
        if let Err(e) = doc.execute(command, params) {
            println!("{command}: {e}");
            ok = false;
        }
    }
    println!("saved copy: {} bytes", std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0));
    let _ = std::fs::remove_file(out);
    ok
}
