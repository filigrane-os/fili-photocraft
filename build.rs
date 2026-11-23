// QML interface compiled into the binary (module Fili.Photocraft, qrc:/qt/qml/Fili/Photocraft/qml/), Rust objects of src/bridge.rs
use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // Version of the About card: tag or commit of the repository (absent outside a repository)
    if let Ok(o) = std::process::Command::new("git").args(["describe", "--tags", "--always", "--dirty"]).output()
        && o.status.success()
    {
        println!("cargo:rustc-env=FILI_PHOTOCRAFT_GIT={}", String::from_utf8_lossy(&o.stdout).trim());
    }
    CxxQtBuilder::new_qml_module(
        QmlModule::new("Fili.Photocraft")
            .qml_files(["qml/Main.qml"])
            .depend("Fili.UI")
            .depend("QtQuick")
            .depend("QtQuick.Controls"),
    )
    // Fonts of the interface travel with the binary: the application looks the same on any distribution
    .qrc_resources(["fonts/Jost-Variable.ttf", "fonts/JetBrainsMono-Variable.ttf", "fonts/FiliIcons.ttf"])
    .qt_module("Quick")
    .files(["src/bridge.rs"])
    .build();
}
