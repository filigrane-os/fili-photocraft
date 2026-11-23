// Window of fili-photocraft: header, sidebar (layers, adjustments), the canvas and a footer, the anatomy of every fili-*
// window (app-window.md of the filigrane-ui skill). Every action is a command of the PhotoCraft engine.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
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
    readonly property var activeLayer: layerList.find(l => l.selected) ?? null

    function setLayer(id, props) { canvas.run("layer.setProps", JSON.stringify(Object.assign({ layer: id }, props))); }
    function zoomStep(factor) { canvas.zoomAt(factor, canvas.width / 2, canvas.height / 2); }

    FileDialog {
        id: openDialog
        title: Fili.tr("Open Image")
        onAccepted: canvas.open(selectedFile.toString())
    }

    Shortcut { sequence: "Ctrl+Z"; enabled: canvas.canUndo; onActivated: canvas.undo() }
    Shortcut { sequence: "Ctrl+Shift+Z"; enabled: canvas.canRedo; onActivated: canvas.redo() }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
    Shortcut { sequence: "Ctrl+0"; onActivated: canvas.zoomFit() }
    Shortcut { sequence: "Ctrl+1"; onActivated: canvas.zoomActual() }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoomStep(1.25) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoomStep(0.8) }

    FiliHeader {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        title: canvas.title !== "" ? canvas.title : "PhotoCraft"
        closeButton: true
        onCloseRequested: Qt.quit()
        FiliButton { label: Fili.tr("Open…"); onClicked: openDialog.open() }
        FiliButton { label: Fili.tr("Fit"); enabledState: canvas.loaded; onClicked: canvas.zoomFit() }
        FiliButton { label: "100 %"; enabledState: canvas.loaded; onClicked: canvas.zoomActual() }
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
                FiliLayerRow {
                    required property var modelData
                    label: modelData.name
                    depth: modelData.depth
                    detail: modelData.opacity < 1 ? Math.round(modelData.opacity * 100) + " %" : ""
                    selected: modelData.selected
                    layerVisible: modelData.visible
                    onClicked: canvas.run("layer.select", JSON.stringify({ layer: modelData.id }))
                    onVisibilityToggled: shown => win.setLayer(modelData.id, { visible: shown })
                }
            }
            Item {
                visible: win.activeLayer !== null
                width: parent.width
                height: FiliTheme.sideRowHeight + FiliTheme.space2
                Text {
                    id: opacityValue
                    anchors { right: parent.right; rightMargin: FiliTheme.margin; verticalCenter: parent.verticalCenter }
                    width: opacityMetrics.advanceWidth
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(opacity.value * 100) + " %"
                    font.family: FiliTheme.font
                    font.pixelSize: FiliTheme.sizeSmall
                    color: FiliTheme.textSecondary
                    TextMetrics { id: opacityMetrics; font: opacityValue.font; text: "100 %" }
                }
                FiliSlider {
                    id: opacity
                    anchors { left: parent.left; right: opacityValue.left; leftMargin: FiliTheme.margin; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                    // Follows the layer, except while the thumb is held
                    Binding on value { when: !opacity.dragging; value: win.activeLayer ? win.activeLayer.opacity : 1 }
                    onMoved: v => value = v
                    onReleased: if (win.activeLayer) win.setLayer(win.activeLayer.id, { opacity: value })
                }
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
            anchors.fill: parent
            clip: true
            readonly property real pixelRatio: win.screen ? win.screen.devicePixelRatio : 1
            onWidthChanged: viewport(width, height, pixelRatio)
            onHeightChanged: viewport(width, height, pixelRatio)
            onPixelRatioChanged: viewport(width, height, pixelRatio)
            Component.onCompleted: {
                viewport(width, height, pixelRatio);
                const f = Fili.startFile();
                if (f !== "") open(f);
            }
        }
        // Drag to move the image, wheel to zoom at the pointer
        MouseArea {
            anchors.fill: parent
            enabled: canvas.loaded
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point last
            onPressed: e => last = Qt.point(e.x, e.y)
            onPositionChanged: e => { canvas.panBy(e.x - last.x, e.y - last.y); last = Qt.point(e.x, e.y); }
            onDoubleClicked: canvas.zoomFit()
            onWheel: e => canvas.zoomAt(Math.pow(1.0015, e.angleDelta.y), e.x, e.y)
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
        rightText: canvas.loaded ? canvas.timing + " · " + Math.round(canvas.zoom * 100) + " %" : ""
    }
}
