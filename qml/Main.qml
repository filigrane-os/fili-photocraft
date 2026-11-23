// Window of fili-photocraft: header, sidebar (layers, adjustments), the canvas and a footer, the anatomy of every fili-*
// window (app-window.md of the filigrane-ui skill). Every action is a command of the PhotoCraft engine.
import QtQuick
import QtQuick.Controls.Basic
import Fili.Photocraft
import Fili.UI

ApplicationWindow {
    id: win
    // The kit reads the theme through the application's object. Evaluated first: the tokens must be right from the first binding
    readonly property bool kitReady: { FiliHost.backend = Fili; return true; }
    FontLoader { source: "qrc:/qt/qml/Fili/Photocraft/fonts/Jost-Variable.ttf" }
    FontLoader { source: "qrc:/qt/qml/Fili/Photocraft/fonts/JetBrainsMono-Variable.ttf" }
    FontLoader { source: "qrc:/qt/qml/Fili/Photocraft/fonts/FiliIcons.ttf" }
    width: 1180
    height: 760
    minimumWidth: 720
    minimumHeight: 480
    visible: true
    color: FiliTheme.background
    title: canvas.title !== "" ? canvas.title + " · PhotoCraft" : "PhotoCraft"

    readonly property var layerList: { try { return JSON.parse(canvas.layers) || []; } catch (e) { return []; } }

    Shortcut { sequence: "Ctrl+Z"; enabled: canvas.canUndo; onActivated: canvas.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; enabled: canvas.canRedo; onActivated: canvas.redo() }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }

    FiliHeader {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        title: canvas.title !== "" ? canvas.title : "PhotoCraft"
        closeButton: true
        onCloseRequested: Qt.quit()
        FiliButton { label: Fili.tr("Undo"); enabledState: canvas.canUndo; onClicked: canvas.undo() }
        FiliButton { label: Fili.tr("Redo"); enabledState: canvas.canRedo; onClicked: canvas.redo() }
    }

    FiliSidebar {
        id: sidebar
        anchors { left: parent.left; top: header.bottom; bottom: footer.top }
        FiliSidebarSection {
            title: Fili.tr("Layers")
            Repeater {
                model: win.layerList
                FiliSidebarRow { required property var modelData; label: modelData.name || "" }
            }
        }
        FiliSidebarSection {
            title: Fili.tr("Adjustments")
            FiliSidebarRow {
                label: Fili.tr("Contrast curve")
                onClicked: canvas.run("layer.newAdjustmentLayer.curves", '{"points":[[0,0],[64,40],[192,216],[255,255]]}')
            }
            FiliSidebarRow {
                label: Fili.tr("Invert")
                onClicked: canvas.run("layer.newAdjustmentLayer.invert", "{}")
            }
        }
    }

    Rectangle {
        anchors { left: sidebar.right; right: parent.right; top: header.bottom; bottom: footer.top }
        color: FiliTheme.backgroundDeep

        PhotoCanvas {
            id: canvas
            anchors { fill: parent; margins: FiliTheme.space3 }
            Component.onCompleted: { const f = Fili.startFile(); if (f !== "") open(f); }
        }
        Text {
            anchors.centerIn: parent
            visible: !canvas.loaded
            text: Fili.tr("Drop an image here")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
        }
        DropArea {
            anchors.fill: parent
            onDropped: drop => { if (drop.hasUrls) { canvas.open(drop.urls[0].toString()); drop.accept(); } }
        }
    }

    FiliFooter {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        error: canvas.error !== ""
        leftText: canvas.error !== "" ? canvas.error : (canvas.loaded ? canvas.info : Fili.tr("No image"))
    }
}
