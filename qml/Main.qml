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
    property int layersTab: 0
    property string pathName: ""
    // The Curves adjustment of the selected layer: its channel (the composite is "points"), the points and the curve to draw
    property string curveChannel: "points"
    readonly property var adjustment: activeLayer && activeLayer.adjustment ? activeLayer.adjustment : null
    readonly property bool curvesShown: adjustment !== null && adjustment.kind === "curves" && adjustment.params.pencil !== true && adjustment.params.points !== undefined
    readonly property var curvePoints: curvesShown ? (adjustment.params[curveChannel] ?? [[0, 0], [255, 255]]) : [[0, 0], [255, 255]]
    property var curveSamples: []
    onCurvePointsChanged: curveSamples = JSON.parse(canvas.curveSamples(JSON.stringify(curvePoints)))
    readonly property var channelColors: ({ points: FiliTheme.text, red: "#e0605a", green: "#5cc06a", blue: "#5a8fe0" })
    // Brush and Eraser: the stroke being drawn (document points), its size, hardness and colour
    // Every tool (icon, name, key) and the groups the strip shows: one button per group, a click on the tool in hand goes to the next one
    readonly property var toolInfo: ({
        move: { icon: "move", tip: "Move", hint: "V" }, eyedropper: { icon: "pipette", tip: "Eyedropper", hint: "I" },
        bucket: { icon: "paint-bucket", tip: "Paint Bucket", hint: "G" }, gradient: { icon: "gradient", tip: "Gradient", hint: "G" },
        rect: { icon: "square", tip: "Rectangle", hint: "U" },
        rounded: { icon: "square", tip: "Rounded Rectangle", hint: "U" },
        shapeellipse: { icon: "circle", tip: "Ellipse", hint: "U" },
        triangle: { icon: "triangle", tip: "Triangle", hint: "U" },
        star: { icon: "star", tip: "Star", hint: "U" },
        polygon: { icon: "hexagon", tip: "Polygon", hint: "U" },
        line: { icon: "minus", tip: "Line", hint: "U" },
        text: { icon: "type", tip: "Text", hint: "T" },
        hand: { icon: "hand", tip: "Hand", hint: "H" }, zoom: { icon: "zoom-in", tip: "Zoom", hint: "Z" },
        marquee: { icon: "square-dashed", tip: "Rectangular Marquee", hint: "M" }, ellipse: { icon: "circle", tip: "Elliptical Marquee", hint: "M" },
        lasso: { icon: "lasso", tip: "Lasso", hint: "L" }, wand: { icon: "wand", tip: "Magic Wand", hint: "W" }, crop: { icon: "crop", tip: "Crop", hint: "C" },
        brush: { icon: "brush", tip: "Brush", hint: "B" }, pencil: { icon: "pencil", tip: "Pencil", hint: "B" },
        eraser: { icon: "eraser", tip: "Eraser", hint: "E" },
        blur: { icon: "droplet", tip: "Blur", hint: "R" }, sharpen: { icon: "triangle", tip: "Sharpen", hint: "R" }, smudge: { icon: "pointer", tip: "Smudge", hint: "R" },
        dodge: { icon: "sun", tip: "Dodge", hint: "O" }, burn: { icon: "moon", tip: "Burn", hint: "O" }, sponge: { icon: "sponge", tip: "Sponge", hint: "O" },
        heal: { icon: "bandage", tip: "Spot Healing Brush", hint: "J" }, history: { icon: "history", tip: "History Brush", hint: "Y" }, stamp: { icon: "stamp", tip: "Clone Stamp", hint: "S" }
    })
    readonly property var toolGroups: [
        ["move"], ["marquee", "ellipse"], ["lasso"], ["wand"], ["crop"], ["eyedropper"], ["brush", "pencil"], ["stamp", "history", "heal"], ["gradient", "bucket"], ["text"], ["rect", "rounded", "shapeellipse", "triangle", "star", "polygon", "line"], ["eraser"], ["blur", "sharpen", "smudge"], ["dodge", "burn", "sponge"], ["hand"], ["zoom"]
    ]
    property var groupPick: ({})
    readonly property var toolModel: {
        const out = [];
        toolGroups.forEach((g, i) => {
            const id = g.indexOf(tool) >= 0 ? tool : (groupPick[i] ?? g[0]);
            const t = toolInfo[id];
            if (i === 1 || i === 6 || i === 14) out.push({ sep: true });
            out.push({ id: id, icon: t.icon, tip: Fili.tr(t.tip), hint: t.hint, variants: g.length > 1 });
        });
        return out;
    }
    function selectTool(id) {
        const i = toolGroups.findIndex(g => g.indexOf(id) >= 0);
        groupPick = Object.assign({}, groupPick, { [i]: id });
        tool = id;
    }
    // A key: the first tool of its group, or the next one when the group is already in hand
    function keyTool(key) { pickTool(toolKeys[key]); }
    function pickTool(id) {
        const i = toolGroups.findIndex(g => g.indexOf(id) >= 0);
        const g = toolGroups[i];
        const next = id === tool && g.length > 1 ? g[(g.indexOf(id) + 1) % g.length] : id;
        groupPick = Object.assign({}, groupPick, { [i]: next });
        tool = next;
    }
    readonly property var toolKeys: ({ V: "move", I: "eyedropper", G: "bucket", U: "rect", T: "text", H: "hand", Z: "zoom", M: "marquee", L: "lasso", W: "wand", C: "crop", B: "brush", E: "eraser", R: "blur", O: "dodge", J: "heal", Y: "history", S: "stamp" })
    // The tools that draw a stroke: the command of the engine each one runs
    readonly property var strokeTools: ({ brush: "paint.stroke", pencil: "paint.pencil", eraser: "paint.stroke", blur: "paint.blur", sharpen: "paint.sharpen",
        smudge: "paint.smudge", dodge: "paint.dodge", burn: "paint.burn", sponge: "paint.sponge", heal: "paint.spotHealing", history: "paint.historyBrush", stamp: "paint.cloneStamp" })
    readonly property bool painting: strokeTools[tool] !== undefined
    readonly property bool usesColor: shapeTool || tool === "text" || tool === "brush" || tool === "pencil" || tool === "bucket" || tool === "gradient"
    // Clone Stamp: the point sampled with Alt+click and the offset it keeps to the strokes that follow (aligned)
    property var stampSource: null
    property var stampOffset: null
    property var stroke: []
    property real brushSize: 24
    property real brushHardness: 0.8
    property string brushColor: "#000000"
    function strokeParams() {
        const p = { layer: activeLayer ? activeLayer.id : 0, points: stroke, size: brushSize, hardness: brushHardness };
        if (tool === "eraser") p.erase = true; else if (usesColor) p.color = brushColor;
        if (tool === "stamp" && stampSource && stroke.length > 0) {
            if (stampOffset === null) stampOffset = [stampSource[0] - stroke[0][0], stampSource[1] - stroke[0][1]];
            p.offset = stampOffset;
        }
        return JSON.stringify(p);
    }
    // The rectangular selection in document pixels ({x, y, w, h}) and the one being dragged out (item coordinates), for the outline
    readonly property var marquee: { try { const b = JSON.parse(canvas.selection); return { x: b[0], y: b[1], w: b[2], h: b[3] }; } catch (e) { return null; } }
    property var drag: null
    property var lasso: []
    property int wandTolerance: 32
    property string bgColor: "#ffffff"
    // Move: where the drag began (document), so the preview moves the layer by the whole distance each time
    property var moveFrom: null
    readonly property var shapeKinds: ({ rect: "rect", rounded: "roundedRect", shapeellipse: "ellipse", triangle: "triangle", star: "star", polygon: "polygon" })
    readonly property var dragTools: ({ marquee: 1, ellipse: 1, crop: 1, rect: 1, rounded: 1, shapeellipse: 1, triangle: 1, star: 1, polygon: 1 })
    readonly property bool shapeTool: shapeKinds[tool] !== undefined || tool === "line"
    // Text: where the field is open (item and document coordinates) and the size in points
    property var textAt: null
    property int textSize: 48
    function itemRect(m) {
        const a = JSON.parse(canvas.toItem(m.x, m.y)), b = JSON.parse(canvas.toItem(m.x + m.w, m.y + m.h));
        return Qt.rect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
    }
    // Panels fed by read-only commands of the engine; they follow `canvas.layers`, which changes with every refresh
    readonly property var channelList: { canvas.layers; try { const c = JSON.parse(canvas.ask("channel.list", "{}")); return c ? [{ name: c.composite, visible: c.compositeVisible, composite: true }].concat(c.colors, c.alpha) : []; } catch (e) { return []; } }
    readonly property var pathList: { canvas.layers; try { const p = JSON.parse(canvas.ask("path.list", "{}")); return p ? p.paths.map(x => typeof x === "string" ? { name: x } : x) : []; } catch (e) { return []; } }
    readonly property var historyState: { try { return JSON.parse(canvas.history); } catch (e) { return { names: [], applied: 0 }; } }
    readonly property var swatchGroups: { try { return JSON.parse(canvas.ask("swatches.list", "{}")).groups; } catch (e) { return []; } }
    property var penPoints: []
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
        "undo": { on: () => canvas.canUndo, run: () => { canvas.undo()} },
        "redo": { on: () => canvas.canRedo, run: () => { canvas.redo()} },
        "tool-move": { on: () => true, run: () => win.selectTool("move") },
        "tool-eyedropper": { on: () => true, run: () => win.selectTool("eyedropper") },
        "tool-bucket": { on: () => true, run: () => win.selectTool("bucket") },
        "tool-gradient": { on: () => true, run: () => win.selectTool("gradient") },
        "tool-rect": { on: () => true, run: () => win.selectTool("rect") },
        "tool-rounded": { on: () => true, run: () => win.selectTool("rounded") },
        "tool-shapeellipse": { on: () => true, run: () => win.selectTool("shapeellipse") },
        "tool-triangle": { on: () => true, run: () => win.selectTool("triangle") },
        "tool-star": { on: () => true, run: () => win.selectTool("star") },
        "tool-polygon": { on: () => true, run: () => win.selectTool("polygon") },
        "tool-line": { on: () => true, run: () => win.selectTool("line") },
        "tool-text": { on: () => true, run: () => win.selectTool("text") },
        "tool-hand": { on: () => true, run: () => win.selectTool("hand") },
        "tool-zoom": { on: () => true, run: () => win.selectTool("zoom") },
        "tool-marquee": { on: () => true, run: () => win.selectTool("marquee") },
        "tool-ellipse": { on: () => true, run: () => win.selectTool("ellipse") },
        "tool-lasso": { on: () => true, run: () => win.selectTool("lasso") },
        "tool-wand": { on: () => true, run: () => win.selectTool("wand") },
        "tool-crop": { on: () => true, run: () => win.selectTool("crop") },
        "tool-brush": { on: () => true, run: () => win.selectTool("brush") },
        "tool-pencil": { on: () => true, run: () => win.selectTool("pencil") },
        "tool-eraser": { on: () => true, run: () => win.selectTool("eraser") },
        "tool-blur": { on: () => true, run: () => win.selectTool("blur") },
        "tool-sharpen": { on: () => true, run: () => win.selectTool("sharpen") },
        "tool-smudge": { on: () => true, run: () => win.selectTool("smudge") },
        "tool-dodge": { on: () => true, run: () => win.selectTool("dodge") },
        "tool-burn": { on: () => true, run: () => win.selectTool("burn") },
        "tool-sponge": { on: () => true, run: () => win.selectTool("sponge") },
        "tool-heal": { on: () => true, run: () => win.selectTool("heal") },
        "tool-history": { on: () => true, run: () => win.selectTool("history") },
        "tool-stamp": { on: () => true, run: () => win.selectTool("stamp") },
        "select-all": { on: () => canvas.loaded, run: () => { canvas.run("select.all", "{}")} },
        "deselect": { on: () => canvas.loaded, run: () => { canvas.run("select.deselect", "{}")} },
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
    Shortcut { sequence: "V"; onActivated: win.keyTool("V") }
    Shortcut { sequence: "I"; onActivated: win.keyTool("I") }
    Shortcut { sequence: "G"; onActivated: win.keyTool("G") }
    Shortcut { sequence: "U"; onActivated: win.keyTool("U") }
    Shortcut { sequence: "T"; onActivated: win.keyTool("T") }
    Shortcut { sequence: "H"; onActivated: win.keyTool("H") }
    Shortcut { sequence: "Z"; onActivated: win.keyTool("Z") }
    Shortcut { sequence: "M"; onActivated: win.keyTool("M") }
    Shortcut { sequence: "L"; onActivated: win.keyTool("L") }
    Shortcut { sequence: "W"; onActivated: win.keyTool("W") }
    Shortcut { sequence: "C"; onActivated: win.keyTool("C") }
    Shortcut { sequence: "B"; onActivated: win.keyTool("B") }
    Shortcut { sequence: "E"; onActivated: win.keyTool("E") }
    Shortcut { sequence: "R"; onActivated: win.keyTool("R") }
    Shortcut { sequence: "O"; onActivated: win.keyTool("O") }
    Shortcut { sequence: "J"; onActivated: win.keyTool("J") }
    Shortcut { sequence: "Y"; onActivated: win.keyTool("Y") }
    Shortcut { sequence: "S"; onActivated: win.keyTool("S") }
    Shortcut { sequence: "Ctrl+A"; onActivated: win.runAction("select-all") }
    Shortcut { sequence: "Ctrl+D"; onActivated: win.runAction("deselect") }

    // The layout of PhotoCraft: options bar on top, the tools on the left, the canvas with the tab of its document, the dock of
    // panels on the right and the status bar. The menu is in the fili-bar (no menu bar here); there is no sidebar or header.
    FiliOptionsBar {
        id: optionsBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        closeButton: true
        onCloseRequested: win.runAction("close")
        Text {
            visible: !win.painting && !win.shapeTool && win.tool !== "text" && !win.dragTools[win.tool] && win.tool !== "lasso" && win.tool !== "wand"
            text: win.tool === "zoom" ? Fili.tr("Click to zoom in, Alt+click to zoom out") : Fili.tr("Drag to move the image")
            font.family: FiliTheme.font
            font.pixelSize: FiliTheme.size
            color: FiliTheme.textSecondary
        }
        Row {
            visible: win.tool === "text"
            spacing: FiliTheme.space3
            Text { anchors.verticalCenter: parent.verticalCenter; text: Fili.tr("Size") + " " + win.textSize + " pt"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
            FiliSlider { width: 160; anchors.verticalCenter: parent.verticalCenter; value: (win.textSize - 6) / 294; onMoved: v => win.textSize = Math.round(6 + v * 294) }
            Repeater {
                model: win.usesColor && win.tool === "text" ? ["#000000", "#ffffff", "#e0605a", "#5cc06a", "#5a8fe0", "#e8c547"] : []
                Rectangle {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 3; color: modelData
                    border { width: win.brushColor === modelData ? 2 : 1; color: win.brushColor === modelData ? FiliTheme.accentColor : FiliTheme.border }
                    MouseArea { anchors.fill: parent; onClicked: win.brushColor = parent.modelData }
                }
            }
        }
        Row {
            visible: win.shapeTool
            spacing: FiliTheme.space3
            Text { anchors.verticalCenter: parent.verticalCenter; text: Fili.tr("Drag to draw a shape in the colour of") ; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
            Repeater {
                model: win.shapeTool ? ["#000000", "#ffffff", "#e0605a", "#5cc06a", "#5a8fe0", "#e8c547"] : []
                Rectangle {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 3; color: modelData
                    border { width: win.brushColor === modelData ? 2 : 1; color: win.brushColor === modelData ? FiliTheme.accentColor : FiliTheme.border }
                    MouseArea { anchors.fill: parent; onClicked: win.brushColor = parent.modelData }
                }
            }
        }
        Row {
            visible: win.tool === "wand" || win.tool === "bucket"
            spacing: FiliTheme.space3
            Text { anchors.verticalCenter: parent.verticalCenter; text: Fili.tr("Tolerance") + " " + win.wandTolerance; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
            FiliSlider { width: 160; anchors.verticalCenter: parent.verticalCenter; value: win.wandTolerance / 255; onMoved: v => win.wandTolerance = Math.round(v * 255) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: win.tool === "wand" ? Fili.tr("Shift adds to the selection, Alt subtracts") : ""; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
        }
        Text {
            visible: win.tool === "marquee" || win.tool === "ellipse" || win.tool === "lasso" || win.tool === "crop"
            text: win.tool === "crop" ? Fili.tr("Drag the area to keep") : Fili.tr("Drag to select, click to deselect")
            font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary
        }
        Row {
            visible: win.painting
            spacing: FiliTheme.space3
            Text { anchors.verticalCenter: parent.verticalCenter; text: Fili.tr("Size") + " " + Math.round(win.brushSize) + " px"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
            FiliSlider { width: 120; anchors.verticalCenter: parent.verticalCenter; value: (win.brushSize - 1) / 199; onMoved: v => win.brushSize = 1 + v * 199 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: Fili.tr("Hardness") + " " + Math.round(win.brushHardness * 100) + " %"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
            FiliSlider { width: 120; anchors.verticalCenter: parent.verticalCenter; value: win.brushHardness; onMoved: v => win.brushHardness = v }
            Repeater {
                model: win.usesColor ? ["#000000", "#ffffff", "#e0605a", "#5cc06a", "#5a8fe0", "#e8c547"] : []
                Rectangle {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 3; color: modelData
                    border { width: win.brushColor === modelData ? 2 : 1; color: win.brushColor === modelData ? FiliTheme.accentColor : FiliTheme.border }
                    MouseArea { anchors.fill: parent; onClicked: win.brushColor = parent.modelData }
                }
            }
        }
        FiliButton { label: Fili.tr("Fit Screen"); enabledState: canvas.loaded; onClicked: win.runAction("zoom-fit") }
        FiliButton { label: "100 %"; enabledState: canvas.loaded; onClicked: win.runAction("zoom-actual") }
    }

    FiliToolStrip {
        id: toolStrip
        anchors { left: parent.left; top: optionsBar.bottom; bottom: footer.top }
        current: win.tool
        onPicked: id => win.pickTool(id)
        swatches: false
        model: win.toolModel
    }

    FiliDock {
        id: dock
        anchors { right: parent.right; top: optionsBar.bottom; bottom: footer.top }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.preferredHeight: win.curvesShown || win.propertiesTab === 2 ? 440 : 200
            tabs: [Fili.tr("Properties"), Fili.tr("Adjustments"), Fili.tr("Color")]
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
            Flickable {
                id: colorView
                clip: true
                contentHeight: colorColumn.height + FiliTheme.space3
                KineticScroll {}
                Column {
                    id: colorColumn
                    x: FiliTheme.space3
                    width: colorView.width - 2 * FiliTheme.space3
                    y: FiliTheme.space3
                    spacing: FiliTheme.space2
                    Row {
                        spacing: FiliTheme.space3
                        Rectangle { width: 28; height: 28; radius: 3; color: win.brushColor; border { width: 1; color: FiliTheme.border } }
                        Rectangle { width: 28; height: 28; radius: 3; color: win.bgColor; border { width: 1; color: FiliTheme.border } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.brushColor; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                        FiliButton { anchors.verticalCenter: parent.verticalCenter; label: Fili.tr("Swap"); onClicked: { const c = win.brushColor; win.brushColor = win.bgColor; win.bgColor = c; } }
                    }
                    Repeater {
                        model: win.swatchGroups
                        Column {
                            required property var modelData
                            width: colorColumn.width
                            spacing: FiliTheme.space1
                            Text { text: modelData.name; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeSmall; color: FiliTheme.muted }
                            Flow {
                                width: parent.width
                                spacing: 3
                                Repeater {
                                    model: modelData.swatches
                                    Rectangle {
                                        required property var modelData
                                        width: 18; height: 18; radius: 2; color: modelData.hex
                                        border { width: win.brushColor === modelData.hex ? 2 : 1; color: win.brushColor === modelData.hex ? FiliTheme.accentColor : FiliTheme.border }
                                        MouseArea { anchors.fill: parent; onClicked: e => { if (e.modifiers & Qt.AltModifier) win.bgColor = parent.modelData.hex; else win.brushColor = parent.modelData.hex; } }
                                    }
                                }
                            }
                        }
                    }
                }
                FiliScrollBar { flick: colorView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }
        }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tabs: [Fili.tr("Layers"), Fili.tr("Channels"), Fili.tr("Paths"), Fili.tr("History")]
            currentIndex: win.layersTab
            onTabClicked: i => win.layersTab = i
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
            ListView {
                id: channelsView
                clip: true
                model: win.channelList
                KineticScroll {}
                delegate: FiliLayerRow {
                    required property var modelData
                    width: channelsView.width
                    label: modelData.name
                    layerVisible: modelData.visible !== false
                    onClicked: canvas.run("channel.target", JSON.stringify({ channel: modelData.composite ? "composite" : modelData.name }))
                    onVisibilityToggled: canvas.run("channel.setVisible", JSON.stringify({ channel: modelData.composite ? "composite" : modelData.name }))
                }
                FiliScrollBar { flick: channelsView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }
            Item {
                ListView {
                    id: pathsView
                    anchors { fill: parent; bottomMargin: pathButtons.height }
                    clip: true
                    model: win.pathList
                    KineticScroll {}
                    delegate: FiliSidebarRow {
                        required property var modelData
                        width: pathsView.width
                        label: modelData.name
                        selected: win.pathName === modelData.name
                        onClicked: win.pathName = modelData.name
                    }
                    FiliScrollBar { flick: pathsView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
                }
                Text {
                    anchors.centerIn: parent
                    visible: win.pathList.length === 0
                    text: Fili.tr("No paths. The Pen tool makes shapes.")
                    font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary
                }
                Row {
                    id: pathButtons
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: FiliTheme.space2 }
                    spacing: FiliTheme.space2
                    FiliButton { label: Fili.tr("Make Selection"); enabledState: win.pathName !== ""; onClicked: canvas.run("path.toSelection", JSON.stringify({ name: win.pathName })) }
                    FiliButton { label: Fili.tr("Delete"); enabledState: win.pathName !== ""; onClicked: { canvas.run("path.delete", JSON.stringify({ name: win.pathName })); win.pathName = ""; } }
                }
            }
            ListView {
                id: historyView
                clip: true
                model: win.historyState.names
                KineticScroll {}
                onCountChanged: positionViewAtEnd()
                delegate: FiliSidebarRow {
                    required property string modelData
                    required property int index
                    width: historyView.width
                    label: modelData
                    selected: index === win.historyState.names.length - 1
                    onClicked: canvas.historyGoto(index)
                }
                FiliScrollBar { flick: historyView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }
        }
    }

    // Tab of the document over the canvas
    FiliTabBar {
        id: documentTab
        anchors { left: toolStrip.right; right: dock.left; top: optionsBar.bottom }
        visible: canvas.loaded
        height: canvas.loaded ? implicitHeight : 0
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
            cursorShape: win.tool === "text" ? Qt.IBeamCursor : win.shapeTool ? Qt.CrossCursor : win.tool === "move" ? Qt.SizeAllCursor : win.painting || win.tool === "bucket" || win.tool === "gradient" || win.tool === "eyedropper" || win.tool === "zoom" || win.dragTools[win.tool] || win.tool === "lasso" || win.tool === "wand" ? Qt.CrossCursor : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point last
            function addPoint(e) {
                win.stroke = win.stroke.concat([JSON.parse(canvas.toDoc(e.x, e.y))]);
                canvas.preview(win.strokeTools[win.tool], win.strokeParams());
            }
            onPressed: e => {
                last = Qt.point(e.x, e.y);
                if (win.dragTools[win.tool] && e.button === Qt.LeftButton) win.drag = Qt.rect(e.x, e.y, 0, 0);
                if ((win.tool === "lasso" || win.tool === "gradient" || win.tool === "line") && e.button === Qt.LeftButton) win.lasso = [Qt.point(e.x, e.y)];
                if (win.tool === "text" && e.button === Qt.LeftButton) { win.textAt = { x: e.x, y: e.y, doc: JSON.parse(canvas.toDoc(e.x, e.y)) }; textInput.text = ""; textInput.forceActiveFocus(); }
                if (win.tool === "move" && e.button === Qt.LeftButton && win.activeLayer) win.moveFrom = JSON.parse(canvas.toDoc(e.x, e.y));
                if (win.tool === "eyedropper" && e.button === Qt.LeftButton) {
                    const p = JSON.parse(canvas.toDoc(e.x, e.y)), c = canvas.pixelAt(p[0], p[1]);
                    if (c !== "") { if (e.modifiers & Qt.AltModifier) win.bgColor = c; else win.brushColor = c; }
                }
                if (win.tool === "bucket" && e.button === Qt.LeftButton) {
                    const p = JSON.parse(canvas.toDoc(e.x, e.y));
                    canvas.run("paint.bucket", JSON.stringify({ x: Math.round(p[0]), y: Math.round(p[1]), tolerance: win.wandTolerance, color: win.brushColor }));
                }
                if (win.tool === "wand" && e.button === Qt.LeftButton) {
                    const p = JSON.parse(canvas.toDoc(e.x, e.y));
                    canvas.run("select.magicWand", JSON.stringify({ x: Math.round(p[0]), y: Math.round(p[1]), tolerance: win.wandTolerance, mode: e.modifiers & Qt.ShiftModifier ? "add" : e.modifiers & Qt.AltModifier ? "subtract" : "replace" }));
                }
                if (win.tool === "stamp" && e.button === Qt.LeftButton && e.modifiers & Qt.AltModifier) {
                    win.stampSource = JSON.parse(canvas.toDoc(e.x, e.y)); win.stampOffset = null;
                } else if (win.painting && e.button === Qt.LeftButton && win.activeLayer) { win.stroke = []; addPoint(e); }
            }
            onReleased: e => {
                if (win.drag) {
                    const d = win.drag, a = JSON.parse(canvas.toDoc(d.x, d.y)), b = JSON.parse(canvas.toDoc(d.x + d.width, d.y + d.height));
                    win.drag = null;
                    const r = { x: Math.round(Math.min(a[0], b[0])), y: Math.round(Math.min(a[1], b[1])), w: Math.round(Math.abs(b[0] - a[0])), h: Math.round(Math.abs(b[1] - a[1])) };
                    if (r.w > 0 && r.h > 0) {
                        if (win.shapeKinds[win.tool] !== undefined) {
                            canvas.run("shape.create", JSON.stringify({ kind: win.shapeKinds[win.tool], rect: [r.x, r.y, r.w, r.h], fill: win.brushColor }));
                        } else {
                            const params = { x: r.x, y: r.y, width: r.w, height: r.h };
                            if (win.tool === "ellipse") params.ellipse = true;
                            canvas.run(win.tool === "crop" ? "image.crop" : "select.rect", JSON.stringify(params));
                        }
                        if (win.tool === "crop") canvas.zoomFit();
                    } else if (win.tool === "marquee" || win.tool === "ellipse") {
                        canvas.run("select.deselect", "{}");
                    }
                }
                if (win.moveFrom) {
                    canvas.endPreview();
                    const p = JSON.parse(canvas.toDoc(e.x, e.y));
                    const dx = Math.round(p[0] - win.moveFrom[0]), dy = Math.round(p[1] - win.moveFrom[1]);
                    win.moveFrom = null;
                    if (dx !== 0 || dy !== 0) canvas.run("layer.translate", JSON.stringify({ layer: win.activeLayer.id, dx: dx, dy: dy }));
                }
                if (win.lasso.length > 0 && (win.tool === "gradient" || win.tool === "line")) {
                    const a = JSON.parse(canvas.toDoc(win.lasso[0].x, win.lasso[0].y)), z = win.lasso[win.lasso.length - 1];
                    const b = JSON.parse(canvas.toDoc(z.x, z.y));
                    win.lasso = [];
                    if (a[0] !== b[0] || a[1] !== b[1]) {
                        if (win.tool === "line") canvas.run("shape.create", JSON.stringify({ kind: "line", from: a, to: b, weight: Math.max(1, Math.round(win.brushSize / 4)), stroke: { color: win.brushColor, width: Math.max(1, Math.round(win.brushSize / 4)) }, fill: null }));
                        else canvas.run("paint.gradient", JSON.stringify({ from: a, to: b, colors: [win.brushColor, win.bgColor] }));
                    }
                } else if (win.lasso.length > 0) {
                    const pts = win.lasso.map(p => JSON.parse(canvas.toDoc(p.x, p.y)));
                    win.lasso = [];
                    if (pts.length >= 3) canvas.run("select.lasso", JSON.stringify({ points: pts })); else canvas.run("select.deselect", "{}");
                }
                if (win.stroke.length > 0) {
                    canvas.endPreview();
                    canvas.run(win.strokeTools[win.tool], win.strokeParams());
                    win.stroke = [];
                }
            }
            onPositionChanged: e => {
                if (win.drag) win.drag = Qt.rect(win.drag.x, win.drag.y, e.x - win.drag.x, e.y - win.drag.y);
                if (win.lasso.length > 0 && pressedButtons & Qt.LeftButton)
                    win.lasso = win.tool === "gradient" || win.tool === "line" ? [win.lasso[0], Qt.point(e.x, e.y)] : win.lasso.concat([Qt.point(e.x, e.y)]);
                if (win.moveFrom && pressedButtons & Qt.LeftButton) {
                    const p = JSON.parse(canvas.toDoc(e.x, e.y));
                    canvas.preview("layer.translate", JSON.stringify({ layer: win.activeLayer.id, dx: Math.round(p[0] - win.moveFrom[0]), dy: Math.round(p[1] - win.moveFrom[1]) }));
                }
                if (win.stroke.length > 0 && pressedButtons & Qt.LeftButton) addPoint(e);
                if (win.tool === "hand" || pressedButtons & Qt.MiddleButton) {
                    canvas.panBy(e.x - last.x, e.y - last.y);
                    last = Qt.point(e.x, e.y);
                }
            }
            onClicked: e => { if (win.tool === "zoom") canvas.zoomAt(e.modifiers & Qt.AltModifier ? 1 / 1.5 : 1.5, e.x, e.y); }
            onDoubleClicked: if (win.tool === "hand") canvas.zoomFit()
            onWheel: e => canvas.zoomAt(Math.pow(1.0015, e.angleDelta.y), e.x, e.y)
        }
        // The outline of the selection (dashed, over the image) and of the rectangle being dragged
        Rectangle {
            readonly property var r: { canvas.viewKey; return win.drag ? Qt.rect(Math.min(win.drag.x, win.drag.x + win.drag.width), Math.min(win.drag.y, win.drag.y + win.drag.height), Math.abs(win.drag.width), Math.abs(win.drag.height)) : win.marquee ? win.itemRect(win.marquee) : null; }
            visible: r !== null
            x: r ? r.x : 0; y: r ? r.y : 0; width: r ? r.width : 0; height: r ? r.height : 0
            color: "transparent"
            border { width: 1; color: FiliTheme.accentColor }
        }
        FiliTextField {
            id: textInput
            visible: win.textAt !== null
            x: win.textAt ? win.textAt.x : 0
            y: win.textAt ? win.textAt.y : 0
            width: 240
            placeholder: Fili.tr("Type, then press Enter")
            Keys.onEscapePressed: win.textAt = null
            onAccepted: {
                if (text !== "" && win.textAt)
                    canvas.run("type.create", JSON.stringify({ x: Math.round(win.textAt.doc[0]), y: Math.round(win.textAt.doc[1]), text: text, size: win.textSize, color: win.brushColor }));
                win.textAt = null;
            }
        }
        Canvas {
            id: lassoPath
            anchors.fill: parent
            visible: win.lasso.length > 0
            onVisibleChanged: requestPaint()
            Connections { target: win; function onLassoChanged() { lassoPath.requestPaint(); } }
            onPaint: {
                const c = getContext("2d");
                c.reset();
                if (win.lasso.length < 2) return;
                c.strokeStyle = FiliTheme.accentColor.toString();
                c.lineWidth = 1;
                c.beginPath();
                c.moveTo(win.lasso[0].x, win.lasso[0].y);
                for (let i = 1; i < win.lasso.length; i++) c.lineTo(win.lasso[i].x, win.lasso[i].y);
                c.stroke();
            }
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
