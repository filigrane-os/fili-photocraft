// The open image: a PhotoCraft session and the last composite, with no Qt in here.
use std::path::Path;
use std::time::Instant;

use photocraft_engine::Session;
use serde_json::{Value, json};

// Longest side of the composite shown on the canvas: a full-size composite waits for the tile renderer
const PREVIEW_SIDE: u32 = 2048;

#[derive(Default)]
pub struct Document {
    session: Option<Session>,
    pub pixels: Vec<u8>,
    pub width: i32,
    pub height: i32,
    pub render_ms: u128,
}

impl Document {
    pub fn open(&mut self, path: &Path) -> Result<(), String> {
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let opened = photocraft_io::import_file(&name, path, &photocraft_io::ImportOptions::default(), &photocraft_raster::Interrupt::NONE)
            .map_err(|e| e.to_string())?;
        let mut session = Session::new();
        session.add_document(opened.document, Some(path.to_string_lossy().into_owned()));
        self.session = Some(session);
        self.render();
        Ok(())
    }

    pub fn execute(&mut self, id: &str, params: Value) -> Result<(), String> {
        let session = self.session.as_mut().ok_or("no open image")?;
        session.execute(id, params).map_err(|e| e.to_string())?;
        self.render();
        Ok(())
    }

    pub fn undo(&mut self) -> bool {
        let done = self.session.as_mut().is_some_and(|s| s.undo());
        if done {
            self.render();
        }
        done
    }

    pub fn redo(&mut self) -> bool {
        let done = self.session.as_mut().is_some_and(|s| s.redo());
        if done {
            self.render();
        }
        done
    }

    /// Name, size, layers and history of the image, as the engine reports them
    pub fn detail(&self) -> Value {
        match self.session.as_ref().and_then(|s| s.active()) {
            Some(state) => photocraft_engine::inspect::document_detail(state),
            None => json!({}),
        }
    }

    fn render(&mut self) {
        let Some(state) = self.session.as_ref().and_then(|s| s.active()) else { return };
        let start = Instant::now();
        let image = photocraft_compose::thumbnail(&state.doc, PREVIEW_SIDE);
        self.render_ms = start.elapsed().as_millis();
        self.width = image.width as i32;
        self.height = image.height as i32;
        self.pixels = image.pixels;
    }
}

/// Opens FILE, applies a curve, undoes it: proves the engine works here, and times it
pub fn probe(file: &str) -> i32 {
    let mut doc = Document::default();
    let start = Instant::now();
    if let Err(e) = doc.open(Path::new(file)) {
        eprintln!("open: {e}");
        return 1;
    }
    let before = doc.pixels.clone();
    println!("open {} ms, composite {} ms, {}x{}", start.elapsed().as_millis(), doc.render_ms, doc.width, doc.height);
    if let Err(e) = doc.execute("layer.newAdjustmentLayer.curves", json!({"points": [[0, 0], [64, 40], [192, 216], [255, 255]]})) {
        eprintln!("curve: {e}");
        return 1;
    }
    let changed = doc.pixels != before;
    println!("curve {} ms, pixels changed: {changed}", doc.render_ms);
    let undone = doc.undo() && doc.pixels == before;
    println!("undo restores the pixels: {undone}");
    println!("layers: {}", doc.detail()["layers"]);
    if changed && undone { 0 } else { 1 }
}
