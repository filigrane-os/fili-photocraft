// fili-photocraft: the image editor of Filigrane, a Qt Quick window (Fili.UI) on the PhotoCraft engine.
use fili_ui as _;

mod bridge;
mod ctl;
mod document;
mod render;
#[allow(dead_code)]
mod theme;
mod view;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("-V" | "--version") => {
            println!("fili-photocraft {}", env!("CARGO_PKG_VERSION"));
            return;
        }
        Some("-h" | "--help") => {
            println!("fili-photocraft {}: the image editor of Filigrane\n\nUsage: fili-photocraft [FILE]   open the window\n       fili-photocraft ctl [--pid PID] action NAME [ARG] | state | actions", env!("CARGO_PKG_VERSION"));
            return;
        }
        Some("ctl") => {
            match ctl::client(&args[2..]) {
                Ok(answer) => println!("{answer}"),
                Err(e) => {
                    eprintln!("fili-photocraft ctl: {e}");
                    std::process::exit(1);
                }
            }
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
    if let Some(mut engine) = engine.as_mut() {
        // Development (`make run`): the QML is read from the source folders instead of the binary, so a change of a .qml file
        // needs no build. FILI_QML_DIR holds Main.qml; FILI_UI_QML the kit's folder, searched before the compiled-in Fili.UI.
        // The Rust types (Fili, PhotoCanvas) still come from the binary.
        if let Ok(dir) = std::env::var("FILI_UI_QML") {
            engine.as_mut().add_import_path(&QString::from(&dir));
        }
        match std::env::var("FILI_QML_DIR") {
            Ok(dir) => engine.load(&QUrl::from(&format!("file://{dir}/Main.qml"))),
            Err(_) => engine.load(&QUrl::from("qrc:/qt/qml/Fili/Photocraft/qml/Main.qml")),
        }
    }
    if let Some(app) = app.as_mut() {
        std::process::exit(app.exec());
    }
}
