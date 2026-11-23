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
        #[qproperty(QString, error, READ, NOTIFY = changed)]
        #[qproperty(QString, layers, READ, NOTIFY = changed)]
        #[qproperty(bool, loaded, READ, NOTIFY = changed)]
        #[qproperty(bool, can_undo, cxx_name = "canUndo", READ, NOTIFY = changed)]
        #[qproperty(bool, can_redo, cxx_name = "canRedo", READ, NOTIFY = changed)]
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
}

use std::{path::PathBuf, pin::Pin};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QImage, c_void, QImageFormat, QPainterRenderHint, QRect, QString};

use crate::{document::Document, theme};

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
    title: QString,
    info: QString,
    error: QString,
    layers: QString,
    loaded: bool,
    can_undo: bool,
    can_redo: bool,
}

impl cxx_qt::Initialize for qobject::PhotoCanvas {
    fn initialize(self: Pin<&mut Self>) {}
}

// The QImage only borrows the pixels of the Document for the time of one paint
extern "C" fn keep_pixels(_: *mut c_void) {}

impl qobject::PhotoCanvas {
    fn refresh(mut self: Pin<&mut Self>, error: Option<String>) {
        let detail = self.doc.detail();
        let layers = detail["layers"].as_array().map(|l| l.len()).unwrap_or(0);
        let info = format!("{} × {} · {layers} layers · composite {} ms", detail["width"], detail["height"], self.doc.render_ms);
        {
            let mut r = self.as_mut().rust_mut();
            r.title = QString::from(detail["name"].as_str().unwrap_or(""));
            r.info = QString::from(&info);
            r.error = QString::from(&error.unwrap_or_default());
            r.layers = QString::from(&detail["layers"].to_string());
            r.loaded = !detail.as_object().is_none_or(|o| o.is_empty());
            r.can_undo = detail["canUndo"].as_bool().unwrap_or(false);
            r.can_redo = detail["canRedo"].as_bool().unwrap_or(false);
        }
        self.as_mut().changed();
        self.update();
    }

    pub fn open(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        let path = path.strip_prefix("file://").unwrap_or(&path).to_string();
        let result = self.as_mut().rust_mut().doc.open(std::path::Path::new(&path));
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

    /// # Safety
    /// Qt calls it with a painter that is active for the whole call.
    pub unsafe fn paint(self: Pin<&mut Self>, painter: *mut qobject::QPainter) {
        let (w, h) = (self.doc.width, self.doc.height);
        if w <= 0 || h <= 0 || self.doc.pixels.len() < (w * h * 4) as usize {
            return;
        }
        let Some(painter) = (unsafe { painter.as_mut() }) else { return };
        let mut painter = unsafe { Pin::new_unchecked(painter) };
        // Fit the image in the item, centred, never above its size
        let area = self.size();
        let scale = (area.width() / w as f64).min(area.height() / h as f64).min(1.0);
        let (dw, dh) = ((w as f64 * scale).round() as i32, (h as f64 * scale).round() as i32);
        let target = QRect::new((area.width() as i32 - dw) / 2, (area.height() as i32 - dh) / 2, dw, dh);
        painter.as_mut().set_render_hint(QPainterRenderHint::SmoothPixmapTransform, true);
        // SAFETY: the pixels outlive `image`, dropped at the end of this call, and are tightly packed RGBA8
        let image = unsafe { QImage::from_raw_parts(self.doc.pixels.as_ptr(), w, h, QImageFormat::Format_RGBA8888, keep_pixels, std::ptr::null_mut()) };
        painter.as_mut().draw_image(&target, &image);
    }
}
