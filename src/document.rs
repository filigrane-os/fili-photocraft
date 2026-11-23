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

    /// The document for the render thread: the engine keeps it in an `Arc`, so this copies no pixels
    pub fn snapshot(&self) -> Option<Arc<EngineDocument>> {
        self.session.as_ref().and_then(|s| s.active()).map(|state| state.doc.clone())
    }
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
    if changed && hidden && undone { 0 } else { 1 }
}
