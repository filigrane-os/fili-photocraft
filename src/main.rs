// fili-photocraft: the image editor of Filigrane, a Qt Quick window (Fili.UI) on the PhotoCraft engine.
use fili_ui as _;

mod bridge;
mod document;
#[allow(dead_code)]
mod theme;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("-V" | "--version") => {
            println!("fili-photocraft {}", env!("CARGO_PKG_VERSION"));
            return;
        }
        Some("-h" | "--help") => {
            println!("fili-photocraft {}: the image editor of Filigrane\n\nUsage: fili-photocraft [FILE]", env!("CARGO_PKG_VERSION"));
            return;
        }
        Some("probe") => {
            // Exercises the engine without a window: fili-photocraft probe FILE
            std::process::exit(document::probe(args.get(2).map(String::as_str).unwrap_or("")));
        }
        _ => {}
    }
    let mut app = QGuiApplication::new();
    // Wayland app-id (niri rules, the .desktop file)
    QGuiApplication::set_desktop_file_name(&QString::from("fili-photocraft"));
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/Fili/Photocraft/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        std::process::exit(app.exec());
    }
}
