// Objects exposed to QML (module Fili.Photocraft): Fili, the environment the kit reads (live theme), and PhotoCanvas, the
// painted item that shows the composite of the PhotoCraft engine (no shader: the session renders Qt Quick in software).
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qpainter.h");
        type QPainter = cxx_qt_lib::QPainter;
        include!("cxx-qt-lib/qsizef.h");
        type QSizeF = cxx_qt_lib::QSizeF;
        include!(<QtQuick/QQuickPaintedItem>);
        type QQuickPaintedItem;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, light, READ, NOTIFY = theme_changed)]
        #[qproperty(QString, accent, READ, NOTIFY = theme_changed)]
        #[qproperty(i32, settings_rev, cxx_name = "settingsRev", READ, NOTIFY = theme_changed)]
        #[qproperty(bool, key_nav, cxx_name = "keyNav")]
        type Fili = super::FiliRust;

        #[qsignal]
        #[cxx_name = "themeChanged"]
        fn theme_changed(self: Pin<&mut Fili>);
        #[qinvokable]
        #[cxx_name = "themeJson"]
        fn theme_json(self: &Fili) -> QString;
        #[qinvokable]
        fn tr(self: &Fili, text: &QString) -> QString;
        // Command of `fili-photocraft ctl` (the menu of the fili-bar, the assistant): number to reply with, verb, argument
        #[qsignal]
        fn command(self: Pin<&mut Fili>, id: i32, verb: &QString, arg: &QString);
        // Answer to a command (see Main.qml, onCommand)
        #[qinvokable]
        fn reply(self: &Fili, id: i32, answer: &QString);
        // About card: rows [[label, value]] as JSON
        #[qinvokable]
        #[cxx_name = "aboutRows"]
        fn about_rows(self: &Fili) -> QString;
        // The file named on the command line, empty when there is none
        #[qinvokable]
        #[cxx_name = "startFile"]
        fn start_file(self: &Fili) -> QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QQuickPaintedItem]
        #[qproperty(QString, title, READ, NOTIFY = changed)]
        #[qproperty(QString, info, READ, NOTIFY = changed)]
        #[qproperty(QString, timing, READ, NOTIFY = changed)]
        #[qproperty(QString, error, READ, NOTIFY = changed)]
        #[qproperty(QString, layers, READ, NOTIFY = changed)]
        #[qproperty(bool, loaded, READ, NOTIFY = changed)]
        #[qproperty(bool, can_undo, cxx_name = "canUndo", READ, NOTIFY = changed)]
        #[qproperty(bool, can_redo, cxx_name = "canRedo", READ, NOTIFY = changed)]
        #[qproperty(f64, zoom, READ, NOTIFY = changed)]
        type PhotoCanvas = super::PhotoCanvasRust;

        #[qsignal]
        fn changed(self: Pin<&mut PhotoCanvas>);
        #[qinvokable]
        fn open(self: Pin<&mut PhotoCanvas>, path: &QString);
        // Runs a command of the engine: its id and its parameters as JSON
        #[qinvokable]
        fn run(self: Pin<&mut PhotoCanvas>, id: &QString, params: &QString);
        // The curve of the engine through these points ([[input, output], …] 0..255): 129 outputs 0..1 at evenly spaced inputs, JSON
        #[qinvokable]
        #[cxx_name = "curveSamples"]
        fn curve_samples(self: &PhotoCanvas, points: &QString) -> QString;
        // Live preview while a control is dragged: applies the command, replacing the previous preview; the layers list and the
        // history are left alone. `endPreview` drops the preview (the final `run` follows, so the history gets one entry)
        #[qinvokable]
        fn preview(self: Pin<&mut PhotoCanvas>, id: &QString, params: &QString);
        #[qinvokable]
        #[cxx_name = "endPreview"]
        fn end_preview(self: Pin<&mut PhotoCanvas>);
        #[qinvokable]
        fn undo(self: Pin<&mut PhotoCanvas>);
        #[qinvokable]
        fn redo(self: Pin<&mut PhotoCanvas>);
        // Size of the item and device pixel ratio, whenever they change
        #[qinvokable]
        fn viewport(self: Pin<&mut PhotoCanvas>, width: f64, height: f64, dpr: f64);
        #[qinvokable]
        #[cxx_name = "zoomAt"]
        fn zoom_at(self: Pin<&mut PhotoCanvas>, factor: f64, x: f64, y: f64);
        #[qinvokable]
        #[cxx_name = "zoomFit"]
        fn zoom_fit(self: Pin<&mut PhotoCanvas>);
        #[qinvokable]
        #[cxx_name = "zoomActual"]
        fn zoom_actual(self: Pin<&mut PhotoCanvas>);
        #[qinvokable]
        #[cxx_name = "panBy"]
        fn pan_by(self: Pin<&mut PhotoCanvas>, dx: f64, dy: f64);

        #[cxx_override]
        unsafe fn paint(self: Pin<&mut PhotoCanvas>, painter: *mut QPainter);
    }

    unsafe extern "RustQt" {
        #[inherit]
        fn size(self: &PhotoCanvas) -> QSizeF;
        #[inherit]
        fn update(self: Pin<&mut PhotoCanvas>);
    }

    impl cxx_qt::Threading for Fili {}
    impl cxx_qt::Constructor<()> for Fili {}
    // QQuickPaintedItem takes a QQuickItem parent, not the QObject of the default constructor; QML sets the parent itself
    impl cxx_qt::Constructor<()> for PhotoCanvas {}
    impl cxx_qt::Threading for PhotoCanvas {}
}

use std::{path::PathBuf, pin::Pin};

use cxx_qt::{CxxQtType, Threading};
use photocraft_engine::doc::adjust::CurvePoint;
use cxx_qt_lib::{QColor, QImage, QImageFormat, QPainterRenderHint, QRect, QRectF, QString, c_void};

use crate::{
    document::{Document, flat_layers},
    render::{Frame, Renderer, Request},
    theme,
    view::View,
};

fn state_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(std::env::var("XDG_STATE_HOME").unwrap_or_else(|_| format!("{home}/.local/state"))).join("filigrane")
}

fn read_light() -> bool {
    std::fs::read_to_string(state_dir().join("theme")).map(|t| t.trim() == "light").unwrap_or(false)
}

fn read_accent() -> String {
    std::fs::read_to_string(state_dir().join("accent")).map(|t| t.trim().to_string()).unwrap_or_else(|_| "default".into())
}

/// Waits for changes in a directory (inotify, blocked on read: nothing wakes up while nothing changes) and calls `then`
/// until it returns false.
fn watch_dir(dir: PathBuf, then: impl Fn() -> bool + Send + 'static) {
    std::thread::spawn(move || {
        let _ = std::fs::create_dir_all(&dir);
        let Ok(c) = std::ffi::CString::new(dir.as_os_str().as_encoded_bytes()) else { return };
        let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
        if fd < 0 || unsafe { libc::inotify_add_watch(fd, c.as_ptr(), libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_CREATE) } < 0 {
            return;
        }
        let mut buf = [0u8; 4096];
        loop {
            if unsafe { libc::read(fd, buf.as_mut_ptr().cast(), buf.len()) } <= 0 || !then() {
                return;
            }
        }
    });
}

#[derive(Default)]
pub struct FiliRust {
    light: bool,
    accent: QString,
    settings_rev: i32,
    key_nav: bool,
}

impl cxx_qt::Initialize for qobject::Fili {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().light = read_light();
        self.as_mut().rust_mut().accent = QString::from(&read_accent());
        let qt = self.qt_thread();
        if let Some(dir) = theme::path().parent() {
            watch_dir(dir.to_path_buf(), move || {
                qt.queue(|mut f| {
                    let rev = f.settings_rev.wrapping_add(1);
                    f.as_mut().rust_mut().settings_rev = rev;
                    f.as_mut().theme_changed();
                })
                .is_ok()
            });
        }
        let qt = self.qt_thread();
        watch_dir(state_dir(), move || {
            let (light, accent) = (read_light(), read_accent());
            qt.queue(move |mut f| {
                if f.light != light || f.accent.to_string() != accent {
                    f.as_mut().rust_mut().light = light;
                    f.as_mut().rust_mut().accent = QString::from(&accent);
                    f.as_mut().theme_changed();
                }
            })
            .is_ok()
        });
        // Commands from `fili-photocraft ctl`
        let qt = self.qt_thread();
        crate::ctl::serve(move |id, verb, arg| {
            let _ = qt.queue(move |mut f| f.as_mut().command(id, &QString::from(&verb), &QString::from(&arg)));
        });
    }
}

impl qobject::Fili {
    pub fn reply(&self, id: i32, answer: &QString) {
        crate::ctl::reply(id, &answer.to_string());
    }

    pub fn about_rows(&self) -> QString {
        let version = option_env!("FILI_PHOTOCRAFT_GIT").map(str::to_string).unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string());
        let rows = [
            ("Also known as", "fili-photocraft".to_string()),
            ("Part of", "Filigrane".to_string()),
            ("Version", version),
            ("Engine", "PhotoCraft (MIT or Apache-2.0)".to_string()),
        ];
        let json: Vec<String> = rows.iter().map(|(k, v)| format!("[{:?},{:?}]", k, v)).collect();
        QString::from(&format!("[{}]", json.join(",")))
    }

    pub fn theme_json(&self) -> QString {
        QString::from(&theme::theme_json())
    }

    pub fn tr(&self, text: &QString) -> QString {
        text.clone()
    }

    pub fn start_file(&self) -> QString {
        QString::from(&std::env::args().nth(1).unwrap_or_default())
    }
}

#[derive(Default)]
pub struct PhotoCanvasRust {
    doc: Document,
    view: View,
    renderer: Option<Renderer>,
    frame: Option<Frame>,
    generation: u64,
    // What the last request asked for: a repaint that changes nothing composites nothing
    last_request: Option<(u64, (i32, i32, i32, i32), u32, u32)>,
    previewing: bool,
    // The rows of the layers list without their pictures, the picture files made so far (layer id → URL) and which run made them
    rows: serde_json::Value,
    thumbs: std::collections::HashMap<u64, String>,
    thumb_run: u64,
    revision: u64,
    title: QString,
    info: QString,
    timing: QString,
    error: QString,
    layers: QString,
    loaded: bool,
    can_undo: bool,
    can_redo: bool,
    zoom: f64,
}

impl cxx_qt::Initialize for qobject::PhotoCanvas {
    fn initialize(self: Pin<&mut Self>) {}
}

// The QImage only borrows the pixels of the frame for the time of one paint
extern "C" fn keep_pixels(_: *mut c_void) {}

impl qobject::PhotoCanvas {
    /// Asks the render thread for what the view shows now
    fn schedule(mut self: Pin<&mut Self>) {
        let Some((rect, w, h)) = self.view.visible() else { return };
        let wanted = (self.revision, rect, w, h);
        if self.last_request == Some(wanted) {
            return;
        }
        let Some(doc) = self.doc.snapshot() else { return };
        if self.renderer.is_none() {
            let qt = self.qt_thread();
            let renderer = Renderer::start(move |frame| qt.queue(move |canvas| canvas.frame_ready(frame)).is_ok());
            self.as_mut().rust_mut().renderer = Some(renderer);
        }
        let generation = self.generation + 1;
        {
            let mut r = self.as_mut().rust_mut();
            r.generation = generation;
            r.last_request = Some(wanted);
        }
        if let Some(renderer) = &self.renderer {
            renderer.request(Request { generation, doc, rect, w, h });
        }
    }

    fn frame_ready(mut self: Pin<&mut Self>, frame: Frame) {
        if self.frame.as_ref().is_some_and(|f| f.generation > frame.generation) {
            return;
        }
        let timing = format!("composite {} ms", frame.ms);
        {
            let mut r = self.as_mut().rust_mut();
            r.timing = QString::from(&timing);
            r.frame = Some(frame);
        }
        self.as_mut().changed();
        self.update();
    }

    /// The view moved: the old frame is drawn at its new place at once, the sharp one follows
    fn view_changed(mut self: Pin<&mut Self>) {
        let zoom = self.view.zoom();
        self.as_mut().rust_mut().zoom = zoom;
        self.as_mut().changed();
        self.as_mut().update();
        self.schedule();
    }

    fn refresh(mut self: Pin<&mut Self>, error: Option<String>) {
        let detail = self.doc.detail();
        let layers = flat_layers(&detail["layers"]);
        let count = layers.as_array().map_or(0, Vec::len);
        let info = format!("{} × {} · {count} {}", detail["width"], detail["height"], if count == 1 { "layer" } else { "layers" });
        let (w, h) = (detail["width"].as_f64().unwrap_or(0.0), detail["height"].as_f64().unwrap_or(0.0));
        {
            let mut r = self.as_mut().rust_mut();
            r.view.keep_document(w, h);
            r.revision = detail["revision"].as_u64().unwrap_or(r.revision + 1);
            r.title = QString::from(detail["name"].as_str().unwrap_or(""));
            r.info = QString::from(&info);
            r.error = QString::from(&error.unwrap_or_default());
            r.rows = layers;
            r.loaded = !detail.as_object().is_none_or(|o| o.is_empty());
            r.can_undo = detail["canUndo"].as_bool().unwrap_or(false);
            r.can_redo = detail["canRedo"].as_bool().unwrap_or(false);
        }
        self.as_mut().publish_layers();
        self.as_mut().make_thumbnails();
        self.view_changed();
    }

    /// The rows of the list with the pictures known so far
    fn publish_layers(mut self: Pin<&mut Self>) {
        let mut rows = self.rows.clone();
        for row in rows.as_array_mut().into_iter().flatten() {
            if let Some(url) = row["id"].as_u64().and_then(|id| self.thumbs.get(&id)) {
                row["thumbnail"] = serde_json::Value::String(url.clone());
            }
        }
        self.as_mut().rust_mut().layers = QString::from(&rows.to_string());
    }

    /// Draws the pictures of the layers on another thread (the previous run is dropped when it is no longer the latest)
    fn make_thumbnails(mut self: Pin<&mut Self>) {
        let Some(doc) = self.doc.snapshot() else { return };
        let run = self.thumb_run + 1;
        self.as_mut().rust_mut().thumb_run = run;
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let dir = state_dir().join("fili-photocraft").join("thumbnails");
            let _ = std::fs::create_dir_all(&dir);
            // Pictures of earlier runs: the ones still shown stay readable until the new list replaces them (older than a minute go)
            for old in std::fs::read_dir(&dir).into_iter().flatten().flatten() {
                if old.metadata().and_then(|m| m.modified()).ok().and_then(|t| t.elapsed().ok()).is_some_and(|age| age.as_secs() > 60) {
                    let _ = std::fs::remove_file(old.path());
                }
            }
            let mut made = std::collections::HashMap::new();
            for (id, w, h, pixels) in crate::document::layer_thumbnails(&doc, 64) {
                let path = dir.join(format!("{id}-{run}.bmp"));
                if std::fs::write(&path, crate::document::bmp(w, h, &pixels)).is_ok() {
                    made.insert(id, format!("file://{}", path.display()));
                }
            }
            let _ = qt.queue(move |mut canvas| {
                if canvas.thumb_run == run {
                    canvas.as_mut().rust_mut().thumbs = made;
                    canvas.as_mut().publish_layers();
                    canvas.changed();
                }
            });
        });
    }

    pub fn open(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        let path = path.strip_prefix("file://").unwrap_or(&path).to_string();
        let result = self.as_mut().rust_mut().doc.open(std::path::Path::new(&path));
        if result.is_ok() {
            let detail = self.doc.detail();
            let (w, h) = (detail["width"].as_f64().unwrap_or(0.0), detail["height"].as_f64().unwrap_or(0.0));
            let mut r = self.as_mut().rust_mut();
            r.view.set_document(w, h);
            r.frame = None;
            r.last_request = None;
        }
        self.refresh(result.err());
    }

    pub fn run(mut self: Pin<&mut Self>, id: &QString, params: &QString) {
        let result = serde_json::from_str(&params.to_string())
            .map_err(|e| e.to_string())
            .and_then(|p| self.as_mut().rust_mut().doc.execute(&id.to_string(), p));
        self.refresh(result.err());
    }

    pub fn curve_samples(&self, points: &QString) -> QString {
        let pairs: Vec<[f64; 2]> = serde_json::from_str(&points.to_string()).unwrap_or_default();
        let points: Vec<CurvePoint> = pairs.iter().map(|p| CurvePoint { input: (p[0] / 255.0) as f32, output: (p[1] / 255.0) as f32 }).collect();
        let samples = photocraft_compose::adjust::curve_samples::<129>(&points);
        QString::from(&serde_json::to_string(&samples).unwrap_or_else(|_| "[]".into()))
    }

    pub fn preview(mut self: Pin<&mut Self>, id: &QString, params: &QString) {
        self.as_mut().drop_preview();
        let Ok(params) = serde_json::from_str(&params.to_string()) else { return };
        if self.as_mut().rust_mut().doc.execute(&id.to_string(), params).is_ok() {
            self.as_mut().rust_mut().previewing = true;
            self.sync_revision();
        }
    }

    pub fn end_preview(mut self: Pin<&mut Self>) {
        if self.as_mut().drop_preview() {
            self.sync_revision();
        }
    }

    /// Undoes the preview in progress, if any
    fn drop_preview(mut self: Pin<&mut Self>) -> bool {
        if !self.previewing {
            return false;
        }
        let mut r = self.as_mut().rust_mut();
        r.previewing = false;
        r.doc.undo();
        true
    }

    /// The picture changed without a refresh of the lists: new revision, new frame
    fn sync_revision(mut self: Pin<&mut Self>) {
        let revision = self.doc.detail()["revision"].as_u64().unwrap_or(self.revision + 1);
        self.as_mut().rust_mut().revision = revision;
        self.view_changed();
    }

    pub fn undo(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().doc.undo();
        self.refresh(None);
    }

    pub fn redo(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().doc.redo();
        self.refresh(None);
    }

    pub fn viewport(mut self: Pin<&mut Self>, width: f64, height: f64, dpr: f64) {
        self.as_mut().rust_mut().view.set_item(width, height, dpr);
        self.view_changed();
    }

    pub fn zoom_at(mut self: Pin<&mut Self>, factor: f64, x: f64, y: f64) {
        self.as_mut().rust_mut().view.zoom_at(factor, x, y);
        self.view_changed();
    }

    pub fn zoom_fit(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().view.zoom_fit();
        self.view_changed();
    }

    pub fn zoom_actual(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().view.zoom_actual();
        self.view_changed();
    }

    pub fn pan_by(mut self: Pin<&mut Self>, dx: f64, dy: f64) {
        self.as_mut().rust_mut().view.pan(dx, dy);
        self.view_changed();
    }

    /// # Safety
    /// Qt calls it with a painter that is active for the whole call.
    pub unsafe fn paint(self: Pin<&mut Self>, painter: *mut qobject::QPainter) {
        let Some(frame) = &self.frame else { return };
        if frame.w <= 0 || frame.h <= 0 || frame.pixels.len() < (frame.w * frame.h * 4) as usize {
            return;
        }
        let Some(painter) = (unsafe { painter.as_mut() }) else { return };
        let mut painter = unsafe { Pin::new_unchecked(painter) };
        let (x0, y0, x1, y1) = frame.rect;
        let a = self.view.to_item(x0 as f64, y0 as f64);
        let b = self.view.to_item(x1 as f64, y1 as f64);
        let (left, top) = (a.0.round() as i32, a.1.round() as i32);
        let target = QRect::new(left, top, b.0.round() as i32 - left, b.1.round() as i32 - top);
        if !frame.opaque {
            // Transparency: the usual checkerboard, only where the image is
            const CELL: i32 = 10;
            let (light, dark) = (QColor::from_rgb(200, 200, 200), QColor::from_rgb(156, 156, 156));
            let (w, h) = (target.width(), target.height());
            for row in 0..=(h / CELL) {
                for col in 0..=(w / CELL) {
                    let (cw, ch) = (CELL.min(w - col * CELL), CELL.min(h - row * CELL));
                    if cw > 0 && ch > 0 {
                        let cell = QRectF::new((left + col * CELL) as f64, (top + row * CELL) as f64, cw as f64, ch as f64);
                        painter.as_mut().fill_rect(&cell, if (row + col) % 2 == 0 { &light } else { &dark });
                    }
                }
            }
        }
        // Pixels stay square from 200 %, so that they can be read
        painter.as_mut().set_render_hint(QPainterRenderHint::SmoothPixmapTransform, self.view.zoom() < 2.0);
        // SAFETY: the pixels outlive `image`, dropped at the end of this call, and are tightly packed RGBA8
        let image = unsafe { QImage::from_raw_parts(frame.pixels.as_ptr(), frame.w, frame.h, QImageFormat::Format_RGBA8888, keep_pixels, std::ptr::null_mut()) };
        painter.as_mut().draw_image(&target, &image);
    }
}
