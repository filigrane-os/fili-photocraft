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

    FiliAboutCard {
        id: about
        appName: "PhotoCraft"
        tagline: Fili.tr("The image editor of Filigrane")
    }

    // Every command of the window, by name: the menu of the fili-bar, `fili-photocraft ctl action NAME` and the shortcuts below
    // all come here (scripts/check-shell-menu.py keeps this table, the menu and the shortcuts in agreement)
    readonly property var actions: ({
        "about": { on: () => true, run: () => about.visible ? about.close() : about.show() },
        "open": { on: () => true, run: arg => arg ? canvas.open(arg) : openDialog.open() },
        "undo": { on: () => canvas.canUndo, run: () => canvas.undo() },
        "redo": { on: () => canvas.canRedo, run: () => canvas.redo() },
        "zoom-in": { on: () => canvas.loaded, run: () => win.zoomStep(1.25) },
        "zoom-out": { on: () => canvas.loaded, run: () => win.zoomStep(0.8) },
        "zoom-fit": { on: () => canvas.loaded, run: () => canvas.zoomFit() },
        "zoom-actual": { on: () => canvas.loaded, run: () => canvas.zoomActual() },
        "toggle-layer": { on: () => win.activeLayer !== null, run: () => win.setLayer(win.activeLayer.id, { visible: !win.activeLayer.visible }) },
        "adjust-curves": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.curves", '{"points":[[0,0],[64,40],[192,216],[255,255]]}') },
        "adjust-invert": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.invert", "{}") },
        "close": { on: () => true, run: () => Qt.quit() }
    })
    function runAction(name, arg) {
        const a = actions[name];
        if (!a)
            return { ok: false, error: "unknown action: " + name + " (fili-photocraft ctl actions lists them)" };
        if (!a.on())
            return { ok: false, error: "action disabled now: " + name };
        a.run(arg);
        return { ok: true, error: canvas.error };
    }
    function stateJson() {
        return {
            loaded: canvas.loaded, name: canvas.title, info: canvas.info, zoom: canvas.zoom, canUndo: canvas.canUndo, canRedo: canvas.canRedo,
            layers: layerList.length, activeLayer: activeLayer ? activeLayer.name : "", error: canvas.error
        };
    }
    Connections {
        target: Fili
        function onCommand(id, verb, arg) {
            let answer;
            const space = arg.indexOf(" ");
            if (verb === "action")
                answer = win.runAction(space < 0 ? arg : arg.slice(0, space), space < 0 ? "" : arg.slice(space + 1));
            else if (verb === "actions")
                answer = { ok: true, actions: Object.keys(win.actions).map(n => ({ name: n, enabled: win.actions[n].on() })) };
            else if (verb === "state")
                answer = Object.assign({ ok: true }, win.stateJson());
            else
                answer = { ok: false, error: "unknown command: " + verb };
            Fili.reply(id, JSON.stringify(answer));
        }
    }

    Shortcut { sequence: "Ctrl+Z"; onActivated: win.runAction("undo") }
    Shortcut { sequence: "Ctrl+Shift+Z"; onActivated: win.runAction("redo") }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.runAction("close") }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.runAction("close") }
    Shortcut { sequence: "Ctrl+O"; onActivated: win.runAction("open") }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.runAction("zoom-fit") }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.runAction("zoom-actual") }
    Shortcut { sequence: "Ctrl+="; onActivated: win.runAction("zoom-in") }
    Shortcut { sequence: "Ctrl++"; onActivated: win.runAction("zoom-in") }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.runAction("zoom-out") }

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
