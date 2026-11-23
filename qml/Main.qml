// Window of fili-photocraft: header, sidebar (layers, adjustments), the canvas and a footer, the anatomy of every fili-*
// window (app-window.md of the filigrane-ui skill). Every action is a command of the PhotoCraft engine.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
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

    // The tool in hand (the tool strip), and the label of what the pointer rests on (FiliToolStrip asks the window to draw it)
    property string tool: "hand"
    property int propertiesTab: 0
    // The Curves adjustment of the selected layer: its channel (the composite is "points"), the points and the curve to draw
    property string curveChannel: "points"
    readonly property var adjustment: activeLayer && activeLayer.adjustment ? activeLayer.adjustment : null
    readonly property bool curvesShown: adjustment !== null && adjustment.kind === "curves" && adjustment.params.pencil !== true && adjustment.params.points !== undefined
    readonly property var curvePoints: curvesShown ? (adjustment.params[curveChannel] ?? [[0, 0], [255, 255]]) : [[0, 0], [255, 255]]
    property var curveSamples: []
    onCurvePointsChanged: curveSamples = JSON.parse(canvas.curveSamples(JSON.stringify(curvePoints)))
    readonly property var channelColors: ({ points: FiliTheme.text, red: "#e0605a", green: "#5cc06a", blue: "#5a8fe0" })
    property string tipText: ""
    function showTip(item, text) { tipText = text; }
    function hideTip(item) { tipText = ""; }
    // The blend modes of the layer menu, in Photoshop order (the engine reads the labels)
    readonly property var blendModes: ["Normal", "Dissolve", "Darken", "Multiply", "Color Burn", "Linear Burn", "Darker Color", "Lighten", "Screen", "Color Dodge", "Linear Dodge (Add)", "Lighter Color", "Overlay", "Soft Light", "Hard Light", "Vivid Light", "Linear Light", "Pin Light", "Hard Mix", "Difference", "Exclusion", "Subtract", "Divide", "Hue", "Saturation", "Color", "Luminosity"].map(n => ({ label: Fili.tr(n), value: n }))
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
        "tool-hand": { on: () => true, run: () => win.tool = "hand" },
        "tool-zoom": { on: () => true, run: () => win.tool = "zoom" },
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
            tool: tool, loaded: canvas.loaded, name: canvas.title, info: canvas.info, zoom: canvas.zoom, canUndo: canvas.canUndo, canRedo: canvas.canRedo,
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
    Shortcut { sequence: "H"; onActivated: win.runAction("tool-hand") }
    Shortcut { sequence: "Z"; onActivated: win.runAction("tool-zoom") }

    // The layout of PhotoCraft: options bar on top, the tools on the left, the canvas with the tab of its document, the dock of
    // panels on the right and the status bar. The menu is in the fili-bar (no menu bar here); there is no sidebar or header.
    FiliOptionsBar {
        id: optionsBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        closeButton: true
        onCloseRequested: win.runAction("close")
        Text {
            text: win.tool === "zoom" ? Fili.tr("Click to zoom in, Alt+click to zoom out") : Fili.tr("Drag to move the image")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.textSecondary
        }
        FiliButton { label: Fili.tr("Fit Screen"); enabledState: canvas.loaded; onClicked: win.runAction("zoom-fit") }
        FiliButton { label: "100 %"; enabledState: canvas.loaded; onClicked: win.runAction("zoom-actual") }
    }

    FiliToolStrip {
        id: toolStrip
        anchors { left: parent.left; top: optionsBar.bottom; bottom: footer.top }
        current: win.tool
        onPicked: id => win.runAction("tool-" + id)
        swatches: false
        model: [
            { id: "hand", icon: "hand", tip: Fili.tr("Hand"), hint: "H" },
            { id: "zoom", icon: "zoom-in", tip: Fili.tr("Zoom"), hint: "Z" }
        ]
    }

    FiliDock {
        id: dock
        anchors { right: parent.right; top: optionsBar.bottom; bottom: footer.top }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.preferredHeight: win.curvesShown ? 440 : 200
            tabs: [Fili.tr("Properties"), Fili.tr("Adjustments")]
            currentIndex: win.propertiesTab
            onTabClicked: i => win.propertiesTab = i
            Item {
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space3 }
                    spacing: FiliTheme.space3
                    Text {
                        width: parent.width
                        text: win.activeLayer ? win.activeLayer.name : Fili.tr("No layer selected")
                        elide: Text.ElideRight
                        font.family: FiliTheme.font
                        font.pixelSize: FiliTheme.size
                        font.weight: FiliTheme.weightAccent
                        color: win.activeLayer ? FiliTheme.text : FiliTheme.textSecondary
                    }
                    // Curves: the channel, the graph, the point under the pointer, and a way back to the straight line
                    Column {
                        visible: win.curvesShown
                        width: parent.width
                        spacing: FiliTheme.space3
                        FiliSelect {
                            width: parent.width
                            model: [{ label: Fili.tr("RGB"), value: "points" }, { label: Fili.tr("Red"), value: "red" }, { label: Fili.tr("Green"), value: "green" }, { label: Fili.tr("Blue"), value: "blue" }]
                            current: win.curveChannel
                            onPicked: v => win.curveChannel = v
                        }
                        FiliCurveEditor {
                            id: curveEditor
                            width: Math.min(parent.width, 260)
                            height: width
                            anchors.horizontalCenter: parent.horizontalCenter
                            points: win.curvePoints
                            samples: win.curveSamples
                            curveColor: win.channelColors[win.curveChannel]
                            onPointsMoved: p => {
                                win.curveSamples = JSON.parse(canvas.curveSamples(JSON.stringify(p)))
                                canvas.preview("layer.setAdjustment", JSON.stringify(Object.assign({ layer: win.activeLayer.id }, { [win.curveChannel]: p })))
                            }
                            onPointsCommitted: p => {
                                canvas.endPreview()
                                canvas.run("layer.setAdjustment", JSON.stringify(Object.assign({ layer: win.activeLayer.id }, { [win.curveChannel]: p })))
                            }
                        }
                        Text {
                            width: parent.width
                            text: curveEditor.selectedPoint ? Fili.tr("Input") + "  " + curveEditor.selectedPoint[0] + "     " + Fili.tr("Output") + "  " + curveEditor.selectedPoint[1] : " "
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.textSecondary
                        }
                        FiliButton {
                            label: Fili.tr("Reset to defaults")
                            onClicked: canvas.run("layer.setAdjustment", JSON.stringify({ layer: win.activeLayer.id }))
                        }
                    }
                    Column {
                        visible: win.activeLayer !== null && !win.curvesShown
                        width: parent.width
                        spacing: FiliTheme.space3
                        FiliSelect {
                            width: parent.width
                            model: win.blendModes
                            current: win.activeLayer ? win.activeLayer.blend : "Normal"
                            onPicked: v => win.activeLayer && win.setLayer(win.activeLayer.id, { blend: v })
                        }
                    Flow {
                        width: parent.width
                        spacing: FiliTheme.space3
                        Text { text: Fili.tr("Lock"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
                        Repeater {
                            model: [{ key: "transparency", label: "Transparency" }, { key: "pixels", label: "Pixels" }, { key: "position", label: "Position" }, { key: "all", label: "All" }]
                            FiliCheckBox {
                                required property var modelData
                                label: Fili.tr(modelData.label)
                                checked: win.activeLayer && win.activeLayer.locks ? win.activeLayer.locks[modelData.key] === true : false
                                onToggled: win.setLayer(win.activeLayer.id, { locks: { [modelData.key]: !checked } })
                            }
                        }
                    }
                    Item {
                        width: parent.width
                        height: opacity.implicitHeight
                        Text {
                            id: opacityLabel
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: Fili.tr("Opacity")
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.text
                        }
                        Text {
                            id: opacityValue
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: opacityMetrics.advanceWidth
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(opacity.value * 100) + " %"
                            font.family: FiliTheme.font
                            font.pixelSize: FiliTheme.size
                            color: FiliTheme.textSecondary
                            TextMetrics { id: opacityMetrics; font: opacityValue.font; text: "100 %" }
                        }
                        FiliSlider {
                            id: opacity
                            anchors { left: opacityLabel.right; right: opacityValue.left; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                            // Follows the layer, except while the thumb is held
                            Binding on value { when: !opacity.dragging; value: win.activeLayer ? win.activeLayer.opacity : 1 }
                            onMoved: v => value = v
                            onReleased: if (win.activeLayer) win.setLayer(win.activeLayer.id, { opacity: value })
                        }
                    }
                    }
                }
            }
            Column {
                FiliSidebarRow { label: Fili.tr("Curves"); enabled: canvas.loaded; onClicked: win.runAction("adjust-curves") }
                FiliSidebarRow { label: Fili.tr("Invert"); enabled: canvas.loaded; onClicked: win.runAction("adjust-invert") }
            }
        }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tabs: [Fili.tr("Layers")]
            ListView {
                id: layersView
                clip: true
                model: win.layerList
                KineticScroll {}
                delegate: FiliLayerRow {
                    required property var modelData
                    width: layersView.width
                    label: modelData.name
                    subtitle: modelData.blend !== "Normal" && modelData.blend !== undefined ? modelData.kind + " · " + modelData.blend : modelData.kind
                    thumbnail: modelData.thumbnail ?? ""
                    depth: modelData.depth
                    detail: modelData.opacity < 1 ? Math.round(modelData.opacity * 100) + " %" : ""
                    selected: modelData.selected
                    layerVisible: modelData.visible
                    onClicked: canvas.run("layer.select", JSON.stringify({ layer: modelData.id }))
                    onVisibilityToggled: shown => win.setLayer(modelData.id, { visible: shown })
                }
                FiliScrollBar { flick: layersView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }
        }
    }

    // Tab of the document over the canvas
    FiliTabBar {
        id: documentTab
        anchors { left: toolStrip.right; right: dock.left; top: optionsBar.bottom }
        visible: canvas.loaded
        height: visible ? implicitHeight : 0
        closable: false
        detachable: false
        model: [canvas.title]
    }
    Rectangle {
        anchors { left: toolStrip.right; right: dock.left; top: documentTab.bottom; bottom: footer.top }
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
        // The Hand drags the image, the Zoom clicks into it (Alt: out); the wheel zooms at the pointer with either
        MouseArea {
            anchors.fill: parent
            enabled: canvas.loaded
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: win.tool === "zoom" ? Qt.CrossCursor : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point last
            onPressed: e => last = Qt.point(e.x, e.y)
            onPositionChanged: e => {
                if (win.tool === "hand" || pressedButtons & Qt.MiddleButton) {
                    canvas.panBy(e.x - last.x, e.y - last.y);
                    last = Qt.point(e.x, e.y);
                }
            }
            onClicked: e => { if (win.tool === "zoom") canvas.zoomAt(e.modifiers & Qt.AltModifier ? 1 / 1.5 : 1.5, e.x, e.y); }
            onDoubleClicked: if (win.tool === "hand") canvas.zoomFit()
            onWheel: e => canvas.zoomAt(Math.pow(1.0015, e.angleDelta.y), e.x, e.y)
        }
        Text {
            anchors.centerIn: parent
            visible: !canvas.loaded
            text: Fili.tr("Drop an image here, or press Ctrl+O")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.sizeList
            color: FiliTheme.textSecondary
        }
        DropArea {
            anchors.fill: parent
            onDropped: drop => { if (drop.hasUrls) { canvas.open(drop.urls[0].toString()); drop.accept(); } }
        }
    }

    // Status bar of PhotoCraft: zoom, size, layers on the left; the label of the hovered tool or the render time on the right
    FiliFooter {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        error: canvas.error !== ""
        leftText: canvas.error !== "" ? canvas.error : (canvas.loaded ? Math.round(canvas.zoom * 100) + " %   ·   " + canvas.info : Fili.tr("No image"))
        rightText: win.tipText !== "" ? win.tipText : (canvas.loaded ? canvas.timing : "")
    }
}
