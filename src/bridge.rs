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
    }
}

impl qobject::Fili {
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
            r.layers = QString::from(&layers.to_string());
            r.loaded = !detail.as_object().is_none_or(|o| o.is_empty());
            r.can_undo = detail["canUndo"].as_bool().unwrap_or(false);
            r.can_redo = detail["canRedo"].as_bool().unwrap_or(false);
        }
        self.view_changed();
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
