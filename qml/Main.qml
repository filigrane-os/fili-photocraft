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
    property string tool: "move"
    property int propertiesTab: 0
    property int layersTab: 0
    property int topTab: 0
    // The footer follows Settings > Appearance (fili-theme footer, --no-footer) live; it comes back for an error
    property bool showFooter: Fili.footer()
    property bool errorShown: false
    readonly property bool footerShown: showFooter || errorShown
    Connections { target: Fili; function onThemeChanged() { win.showFooter = Fili.footer(); } }
    Connections { target: canvas; function onChanged() { Qt.callLater(() => { win.errorShown = canvas.error !== ""; }); } }
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
        pen: { icon: "pen-tool", tip: "Pen", hint: "P" },
        direct: { icon: "pointer", tip: "Direct Selection", hint: "A" },
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
        ["move"], ["marquee", "ellipse"], ["lasso"], ["wand"], ["crop"], ["eyedropper"], ["brush", "pencil"], ["stamp", "history", "heal"], ["gradient", "bucket"], ["pen"], ["direct"], ["text"], ["rect", "rounded", "shapeellipse", "triangle", "star", "polygon", "line"], ["eraser"], ["blur", "sharpen", "smudge"], ["dodge", "burn", "sponge"], ["hand"], ["zoom"]
    ]
    property var groupPick: ({})
    readonly property var toolModel: {
        const out = [];
        toolGroups.forEach((g, i) => {
            const id = g.indexOf(tool) >= 0 ? tool : (groupPick[i] ?? g[0]);
            const t = toolInfo[id];
            if (i === 1 || i === 6 || i === 16) out.push({ sep: true });
            out.push({ id: id, icon: t.icon, tip: Fili.tr(t.tip), hint: t.hint, variants: g.length > 1 });
        });
        return out;
    }
    // Pen: clicks add the corners of a path, Enter or a double click (or a click on the first point) closes it into a shape layer
    function finishPen() {
        const pts = penPoints.filter((p, i, a) => i === 0 || Math.hypot(p[0] - a[i - 1][0], p[1] - a[i - 1][1]) > 1);
        penPoints = [];
        if (pts.length >= 3)
            canvas.run("shape.create", JSON.stringify({ kind: "path", fill: brushColor, path: { subpaths: [{ closed: true, knots: pts }] } }));
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
    readonly property bool usesColor: shapeTool || tool === "pen" || tool === "text" || tool === "brush" || tool === "pencil" || tool === "bucket" || tool === "gradient"
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
    readonly property var swatchGroups: { canvas.layers; try { return JSON.parse(canvas.ask("swatches.list", "{}")).groups; } catch (e) { return []; } }
    // The sliders of each adjustment (the parameters of layer.setAdjustment); `index` picks one value of a list
    readonly property var adjSchema: ({
        levels: [{ key: "inBlack", label: "Input black", min: 0, max: 253 }, { key: "gamma", label: "Gamma", min: 0.1, max: 9.99, decimals: 2 }, { key: "inWhite", label: "Input white", min: 2, max: 255 },
            { key: "outBlack", label: "Output black", min: 0, max: 255 }, { key: "outWhite", label: "Output white", min: 0, max: 255 }],
        hueSaturation: [{ key: "hue", label: "Hue", min: -180, max: 180 }, { key: "saturation", label: "Saturation", min: -100, max: 100 }, { key: "lightness", label: "Lightness", min: -100, max: 100 }],
        brightnessContrast: [{ key: "brightness", label: "Brightness", min: -150, max: 150 }, { key: "contrast", label: "Contrast", min: -50, max: 100 }],
        vibrance: [{ key: "vibrance", label: "Vibrance", min: -100, max: 100 }, { key: "saturation", label: "Saturation", min: -100, max: 100 }],
        exposure: [{ key: "exposure", label: "Exposure", min: -20, max: 20, decimals: 2 }, { key: "offset", label: "Offset", min: -0.5, max: 0.5, decimals: 3 }, { key: "gamma", label: "Gamma", min: 0.01, max: 9.99, decimals: 2 }],
        threshold: [{ key: "level", label: "Threshold level", min: 1, max: 255 }],
        posterize: [{ key: "levels", label: "Levels", min: 2, max: 255 }],
        photoFilter: [{ key: "density", label: "Density", min: 1, max: 100 }],
        blackWhite: [{ key: "reds", label: "Reds", min: -200, max: 300 }, { key: "yellows", label: "Yellows", min: -200, max: 300 }, { key: "greens", label: "Greens", min: -200, max: 300 },
            { key: "cyans", label: "Cyans", min: -200, max: 300 }, { key: "blues", label: "Blues", min: -200, max: 300 }, { key: "magentas", label: "Magentas", min: -200, max: 300 }],
        colorBalance: ["shadows", "midtones", "highlights"].reduce((a, k) => a.concat(["Cyan - Red", "Magenta - Green", "Yellow - Blue"].map((l, i) => ({ key: k, index: i, label: Fili.tr(k[0].toUpperCase() + k.slice(1)) + " · " + l, min: -100, max: 100 }))), [])
    })
    readonly property var adjustmentSliders: adjustment && !curvesShown ? (adjSchema[adjustment.kind] ?? []) : []
    function adjustmentParams(row, v) {
        const p = { layer: activeLayer.id };
        if (row.index !== undefined) { const a = adjustment.params[row.key].slice(); a[row.index] = v; p[row.key] = a; } else p[row.key] = v;
        return JSON.stringify(p);
    }
    // Size of the document in pixels, from its info line "W × H · n layers"
    readonly property var docSize: { const m = /^(\d+) × (\d+)/.exec(canvas.info); return m ? { w: Number(m[1]), h: Number(m[2]) } : { w: 0, h: 0 }; }
    // Direct Selection: the anchor points of the shape layer in hand, and the one being dragged ({sp, k, from} in document pixels)
    readonly property var shapeAnchors: {
        canvas.layers;
        if (tool !== "direct" || !activeLayer) return [];
        try {
            const info = JSON.parse(canvas.ask("shape.info", JSON.stringify({ layer: activeLayer.id })));
            const out = [];
            info.path.subpaths.forEach((sp, i) => sp.knots.forEach((k, j) => { const a = Array.isArray(k) ? k : k.anchor; out.push({ sp: i, k: j, x: a[0], y: a[1] }); }));
            return out;
        } catch (e) { return []; }
    }
    property var anchorDrag: null
    function anchorParams(move) { return JSON.stringify({ name: "layer", layer: activeLayer.id, anchors: [[anchorDrag.sp, anchorDrag.k]], move: move }); }
    property var penPoints: []
    property string tipText: ""
    function showTip(item, text) { tipText = text; }
    function hideTip(item) { tipText = ""; }
    // The blend modes of the layer menu, in Photoshop order (the engine reads the labels)
    readonly property var blendModes: ["Normal", "Dissolve", "Darken", "Multiply", "Color Burn", "Linear Burn", "Darker Color", "Lighten", "Screen", "Color Dodge", "Linear Dodge (Add)", "Lighter Color", "Overlay", "Soft Light", "Hard Light", "Vivid Light", "Linear Light", "Pin Light", "Hard Mix", "Difference", "Exclusion", "Subtract", "Divide", "Hue", "Saturation", "Color", "Luminosity"].map(n => ({ label: Fili.tr(n), value: n }))
    // BEGIN generated dialogs
    readonly property var dialogSpecs: {"file-new": {"cmd": "file.new", "title": "New Document", "fields": [{"key": "width", "label": "Width (px)", "value": 1920}, {"key": "height", "label": "Height (px)", "value": 1080}], "extra": {}}, "edit-stroke": {"cmd": "edit.stroke", "title": "Stroke the selection", "fields": [{"key": "width", "label": "Width (px)", "value": 3}], "extra": {"color": "$fg"}}, "image-size": {"cmd": "image.imageSize", "title": "Image Size", "fields": [{"key": "width", "label": "Width (px)", "value": "@w"}, {"key": "height", "label": "Height (px)", "value": "@h"}], "extra": {}}, "image-canvas-size": {"cmd": "image.canvasSize", "title": "Canvas Size", "fields": [{"key": "width", "label": "Width (px)", "value": "@w"}, {"key": "height", "label": "Height (px)", "value": "@h"}], "extra": {}}, "filter-gaussian-blur": {"cmd": "filter.blur.gaussianBlur", "title": "Gaussian Blur", "fields": [{"key": "radius", "label": "Radius (px)", "value": 5}], "extra": {}}, "filter-box-blur": {"cmd": "filter.blur.boxBlur", "title": "Box Blur", "fields": [{"key": "radius", "label": "Radius (px)", "value": 5}], "extra": {}}, "filter-motion-blur": {"cmd": "filter.blur.motionBlur", "title": "Motion Blur", "fields": [{"key": "angle", "label": "Angle (°)", "value": 0}, {"key": "distance", "label": "Distance (px)", "value": 20}], "extra": {}}, "filter-surface-blur": {"cmd": "filter.blur.surfaceBlur", "title": "Surface Blur", "fields": [{"key": "radius", "label": "Radius (px)", "value": 5}, {"key": "threshold", "label": "Threshold", "value": 15}], "extra": {}}, "filter-unsharp-mask": {"cmd": "filter.sharpen.unsharpMask", "title": "Unsharp Mask", "fields": [{"key": "amount", "label": "Amount (%)", "value": 80}, {"key": "radius", "label": "Radius (px)", "value": 1}, {"key": "threshold", "label": "Threshold", "value": 0}], "extra": {}}, "filter-smart-sharpen": {"cmd": "filter.sharpen.smartSharpen", "title": "Smart Sharpen", "fields": [{"key": "amount", "label": "Amount (%)", "value": 100}, {"key": "radius", "label": "Radius (px)", "value": 1}, {"key": "reduceNoise", "label": "Reduce noise (%)", "value": 10}], "extra": {}}, "filter-add-noise": {"cmd": "filter.noise.addNoise", "title": "Add Noise", "fields": [{"key": "amount", "label": "Amount (%)", "value": 12.5}], "extra": {}}, "filter-median": {"cmd": "filter.noise.median", "title": "Median", "fields": [{"key": "radius", "label": "Radius (px)", "value": 2}], "extra": {}}, "filter-emboss": {"cmd": "filter.stylize.emboss", "title": "Emboss", "fields": [{"key": "angle", "label": "Angle (°)", "value": 135}, {"key": "height", "label": "Height (px)", "value": 3}, {"key": "amount", "label": "Amount (%)", "value": 100}], "extra": {}}, "filter-high-pass": {"cmd": "filter.other.highPass", "title": "High Pass", "fields": [{"key": "radius", "label": "Radius (px)", "value": 10}], "extra": {}}, "filter-offset": {"cmd": "filter.other.offset", "title": "Offset", "fields": [{"key": "horizontal", "label": "Horizontal (px)", "value": 0}, {"key": "vertical", "label": "Vertical (px)", "value": 0}], "extra": {"undefinedAreas": "wrap"}}}
    // END generated dialogs
    function runCommand(cmd, params) { canvas.run(cmd, JSON.stringify(params)); }
    // A command with a few numbers to ask for: the dialog is filled from the spec, "@w" and "@h" are the size of the image
    property var paramSpec: null
    property var paramValues: []
    function openParams(action) {
        const spec = dialogSpecs[action];
        paramSpec = spec;
        paramValues = spec.fields.map(f => String(f.value === "@w" ? docSize.w : f.value === "@h" ? docSize.h : f.value));
        paramDialog.open();
    }
    function applyParams() {
        const p = Object.assign({}, paramSpec.extra);
        paramSpec.fields.forEach((f, i) => { const v = Number(paramValues[i].replace(",", ".")); if (!isNaN(v)) p[f.key] = v; });
        if (p.color === "$fg") p.color = brushColor;
        runCommand(paramSpec.cmd, p);
    }
    function setLayer(id, props) { canvas.run("layer.setProps", JSON.stringify(Object.assign({ layer: id }, props))); }
    function zoomStep(factor) { canvas.zoomAt(factor, canvas.width / 2, canvas.height / 2); }

    FileDialog {
        id: saveDialog
        title: Fili.tr("Save a Copy")
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG (*.png)", "JPEG (*.jpg *.jpeg)", "WebP (*.webp)", "TIFF (*.tif *.tiff)", "PhotoCraft/Photoshop (*.psd)"]
        onAccepted: { let p = selectedFile.toString().replace("file://", ""); if (!/\.[A-Za-z0-9]+$/.test(p)) p += ".png"; win.runCommand("file.saveACopy", { path: decodeURIComponent(p) }); }
    }
    FiliDialog {
        id: paramDialog
        title: win.paramSpec ? Fili.tr(win.paramSpec.title) : ""
        confirmLabel: Fili.tr("OK")
        cardWidth: 340
        onAccepted: win.applyParams()
        Column {
            spacing: FiliTheme.space2
            width: parent ? parent.width : 300
            Repeater {
                model: win.paramSpec ? win.paramSpec.fields : []
                Row {
                    required property var modelData
                    required property int index
                    spacing: FiliTheme.space3
                    Text { width: 130; anchors.verticalCenter: parent.verticalCenter; text: Fili.tr(modelData.label); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text; elide: Text.ElideRight }
                    FiliTextField {
                        width: 120
                        text: win.paramValues[index] ?? ""
                        onTextChanged: { const v = win.paramValues.slice(); v[index] = text; win.paramValues = v; }
                        onAccepted: paramDialog.accept()
                    }
                }
            }
        }
    }
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
        "tool-pen": { on: () => true, run: () => win.selectTool("pen") },
        "debug": { on: () => true, run: () => debug.open = !debug.open },
        "tool-direct": { on: () => true, run: () => win.selectTool("direct") },
        // BEGIN generated commands (scripts of the menus: File, Edit, Image, Layer, Filter)
        "save-copy": { on: () => canvas.loaded, run: () => saveDialog.open() },
        "edit-cut": { on: () => canvas.loaded, run: () => win.runCommand("edit.cut", {}) },
        "edit-copy": { on: () => canvas.loaded, run: () => win.runCommand("edit.copy", {}) },
        "edit-copy-merged": { on: () => canvas.loaded, run: () => win.runCommand("edit.copyMerged", {}) },
        "edit-paste": { on: () => canvas.loaded, run: () => win.runCommand("edit.paste", {}) },
        "edit-paste-in-place": { on: () => canvas.loaded, run: () => win.runCommand("edit.pasteSpecial.pasteInPlace", {}) },
        "edit-clear": { on: () => canvas.loaded, run: () => win.runCommand("edit.clear", {}) },
        "edit-fill-foreground": { on: () => canvas.loaded, run: () => win.runCommand("edit.fill", { contents: "color", color: win.brushColor }) },
        "edit-fill-background": { on: () => canvas.loaded, run: () => win.runCommand("edit.fill", { contents: "color", color: win.bgColor }) },
        "image-rotate-cw": { on: () => canvas.loaded, run: () => win.runCommand("image.imageRotation.90cw", {}) },
        "image-rotate-ccw": { on: () => canvas.loaded, run: () => win.runCommand("image.imageRotation.90ccw", {}) },
        "image-rotate-half-turn": { on: () => canvas.loaded, run: () => win.runCommand("image.imageRotation.180", {}) },
        "image-flip-horizontal": { on: () => canvas.loaded, run: () => win.runCommand("image.imageRotation.flipCanvasHorizontal", {}) },
        "image-flip-vertical": { on: () => canvas.loaded, run: () => win.runCommand("image.imageRotation.flipCanvasVertical", {}) },
        "image-crop-selection": { on: () => canvas.loaded, run: () => win.runCommand("image.crop", {}) },
        "image-trim": { on: () => canvas.loaded, run: () => win.runCommand("image.trim", {}) },
        "image-reveal-all": { on: () => canvas.loaded, run: () => win.runCommand("image.revealAll", {}) },
        "image-auto-tone": { on: () => canvas.loaded, run: () => win.runCommand("image.autoTone", {}) },
        "image-auto-contrast": { on: () => canvas.loaded, run: () => win.runCommand("image.autoContrast", {}) },
        "image-auto-color": { on: () => canvas.loaded, run: () => win.runCommand("image.autoColor", {}) },
        "image-mode-rgb": { on: () => canvas.loaded, run: () => win.runCommand("image.mode.rgb", {}) },
        "image-mode-grayscale": { on: () => canvas.loaded, run: () => win.runCommand("image.mode.grayscale", {}) },
        "image-mode-cmyk": { on: () => canvas.loaded, run: () => win.runCommand("image.mode.cmyk", {}) },
        "image-mode-lab": { on: () => canvas.loaded, run: () => win.runCommand("image.mode.lab", {}) },
        "image-bits-eight": { on: () => canvas.loaded, run: () => win.runCommand("image.mode.bits8", {}) },
        "image-bits-sixteen": { on: () => canvas.loaded, run: () => win.runCommand("image.mode.bits16", {}) },
        "layer-new": { on: () => canvas.loaded, run: () => win.runCommand("layer.new.layer", {}) },
        "layer-duplicate": { on: () => canvas.loaded, run: () => win.runCommand("layer.duplicate", {}) },
        "layer-delete": { on: () => canvas.loaded, run: () => win.runCommand("layer.delete", {}) },
        "layer-group": { on: () => canvas.loaded, run: () => win.runCommand("layer.groupLayers", {}) },
        "layer-merge-down": { on: () => canvas.loaded, run: () => win.runCommand("layer.mergeDown", {}) },
        "layer-merge-visible": { on: () => canvas.loaded, run: () => win.runCommand("layer.mergeVisible", {}) },
        "layer-flatten": { on: () => canvas.loaded, run: () => win.runCommand("layer.flattenImage", {}) },
        "layer-bring-forward": { on: () => canvas.loaded, run: () => win.runCommand("layer.arrange.bringForward", {}) },
        "layer-send-backward": { on: () => canvas.loaded, run: () => win.runCommand("layer.arrange.sendBackward", {}) },
        "layer-bring-to-front": { on: () => canvas.loaded, run: () => win.runCommand("layer.arrange.bringToFront", {}) },
        "layer-send-to-back": { on: () => canvas.loaded, run: () => win.runCommand("layer.arrange.sendToBack", {}) },
        "layer-rasterize": { on: () => canvas.loaded, run: () => win.runCommand("layer.rasterize.layer", {}) },
        "filter-blur": { on: () => canvas.loaded, run: () => win.runCommand("filter.blur.blur", {}) },
        "filter-blur-more": { on: () => canvas.loaded, run: () => win.runCommand("filter.blur.blurMore", {}) },
        "filter-sharpen": { on: () => canvas.loaded, run: () => win.runCommand("filter.sharpen.sharpen", {}) },
        "filter-sharpen-more": { on: () => canvas.loaded, run: () => win.runCommand("filter.sharpen.sharpenMore", {}) },
        "filter-sharpen-edges": { on: () => canvas.loaded, run: () => win.runCommand("filter.sharpen.sharpenEdges", {}) },
        "filter-despeckle": { on: () => canvas.loaded, run: () => win.runCommand("filter.noise.despeckle", {}) },
        "filter-find-edges": { on: () => canvas.loaded, run: () => win.runCommand("filter.stylize.findEdges", {}) },
        "filter-solarize": { on: () => canvas.loaded, run: () => win.runCommand("filter.stylize.solarize", {}) },
        "filter-oil-paint": { on: () => canvas.loaded, run: () => win.runCommand("filter.stylize.oilPaint", {}) },
        "file-new": { on: () => true, run: () => win.openParams("file-new") },
        "edit-stroke": { on: () => canvas.loaded, run: () => win.openParams("edit-stroke") },
        "image-size": { on: () => canvas.loaded, run: () => win.openParams("image-size") },
        "image-canvas-size": { on: () => canvas.loaded, run: () => win.openParams("image-canvas-size") },
        "filter-gaussian-blur": { on: () => canvas.loaded, run: () => win.openParams("filter-gaussian-blur") },
        "filter-box-blur": { on: () => canvas.loaded, run: () => win.openParams("filter-box-blur") },
        "filter-motion-blur": { on: () => canvas.loaded, run: () => win.openParams("filter-motion-blur") },
        "filter-surface-blur": { on: () => canvas.loaded, run: () => win.openParams("filter-surface-blur") },
        "filter-unsharp-mask": { on: () => canvas.loaded, run: () => win.openParams("filter-unsharp-mask") },
        "filter-smart-sharpen": { on: () => canvas.loaded, run: () => win.openParams("filter-smart-sharpen") },
        "filter-add-noise": { on: () => canvas.loaded, run: () => win.openParams("filter-add-noise") },
        "filter-median": { on: () => canvas.loaded, run: () => win.openParams("filter-median") },
        "filter-emboss": { on: () => canvas.loaded, run: () => win.openParams("filter-emboss") },
        "filter-high-pass": { on: () => canvas.loaded, run: () => win.openParams("filter-high-pass") },
        "filter-offset": { on: () => canvas.loaded, run: () => win.openParams("filter-offset") },
        // END generated commands
        "select-all": { on: () => canvas.loaded, run: () => { canvas.run("select.all", "{}")} },
        "select-inverse": { on: () => canvas.loaded, run: () => canvas.run("select.inverse", "{}") },
        "select-sky": { on: () => canvas.loaded, run: () => canvas.run("select.sky", "{}") },
        "deselect": { on: () => canvas.loaded, run: () => { canvas.run("select.deselect", "{}")} },
        "zoom-in": { on: () => canvas.loaded, run: () => win.zoomStep(1.25) },
        "zoom-out": { on: () => canvas.loaded, run: () => win.zoomStep(0.8) },
        "zoom-fit": { on: () => canvas.loaded, run: () => canvas.zoomFit() },
        "zoom-actual": { on: () => canvas.loaded, run: () => canvas.zoomActual() },
        "toggle-layer": { on: () => win.activeLayer !== null, run: () => win.setLayer(win.activeLayer.id, { visible: !win.activeLayer.visible }) },
        "adjust-curves": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.curves", '{"points":[[0,0],[64,40],[192,216],[255,255]]}') },
        "adjust-levels": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.levels", "{}") },
        "adjust-hue-saturation": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.hueSaturation", "{}") },
        "adjust-brightness-contrast": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.brightnessContrast", "{}") },
        "adjust-vibrance": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.vibrance", "{}") },
        "adjust-exposure": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.exposure", "{}") },
        "adjust-color-balance": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.colorBalance", "{}") },
        "adjust-black-white": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.blackWhite", "{}") },
        "adjust-threshold": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.threshold", "{}") },
        "adjust-posterize": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.posterize", "{}") },
        "adjust-photo-filter": { on: () => canvas.loaded, run: () => canvas.run("layer.newAdjustmentLayer.photoFilter", "{}") },
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
    Shortcut { sequence: "Return"; enabled: win.penPoints.length > 0; onActivated: win.finishPen() }
    Shortcut { sequence: "Escape"; enabled: win.penPoints.length > 0; onActivated: win.penPoints = [] }
    Shortcut { sequence: "P"; onActivated: win.keyTool("P") }
    Shortcut { sequence: "A"; onActivated: win.keyTool("A") }
    Shortcut { sequence: "Ctrl+Shift+L"; onActivated: win.runAction("debug") }
    Shortcut { sequence: "Ctrl+Shift+I"; onActivated: win.runAction("select-inverse") }
    // BEGIN generated shortcuts
    Shortcut { sequence: "Ctrl+X"; onActivated: win.runAction("edit-cut") }
    Shortcut { sequence: "Ctrl+C"; onActivated: win.runAction("edit-copy") }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: win.runAction("edit-copy-merged") }
    Shortcut { sequence: "Ctrl+V"; onActivated: win.runAction("edit-paste") }
    Shortcut { sequence: "Ctrl+Shift+V"; onActivated: win.runAction("edit-paste-in-place") }
    Shortcut { sequence: "Ctrl+N"; onActivated: win.runAction("file-new") }
    Shortcut { sequence: "Ctrl+Alt+I"; onActivated: win.runAction("image-size") }
    Shortcut { sequence: "Ctrl+Alt+C"; onActivated: win.runAction("image-canvas-size") }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: win.runAction("save-copy") }
    // END generated shortcuts
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
            visible: !win.painting && !win.shapeTool && win.tool !== "text" && win.tool !== "pen" && win.tool !== "direct" && !win.dragTools[win.tool] && win.tool !== "lasso" && win.tool !== "wand"
            text: win.tool === "zoom" ? Fili.tr("Click to zoom in, Alt+click to zoom out") : win.tool === "move" ? Fili.tr("Drag to move the selected layer") : Fili.tr("Drag to move the image")
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
            visible: win.shapeTool || win.tool === "pen"
            spacing: FiliTheme.space3
            Text { anchors.verticalCenter: parent.verticalCenter; text: Fili.tr("Drag to draw a shape in the colour of") ; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
            Repeater {
                model: win.shapeTool || win.tool === "pen" ? ["#000000", "#ffffff", "#e0605a", "#5cc06a", "#5a8fe0", "#e8c547"] : []
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
            visible: win.tool === "marquee" || win.tool === "ellipse" || win.tool === "lasso" || win.tool === "crop" || win.tool === "pen" || win.tool === "direct"
            text: win.tool === "direct" ? Fili.tr("Drag an anchor point of the selected shape") : win.tool === "pen" ? Fili.tr("Click to add points, Enter or double-click to close the shape, Esc to cancel") : win.tool === "crop" ? Fili.tr("Drag the area to keep") : Fili.tr("Drag to select, click to deselect")
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
        anchors { left: parent.left; top: optionsBar.bottom; bottom: debug.top }
        current: win.tool
        onPicked: id => win.pickTool(id)
        swatches: false
        model: win.toolModel
    }

    // The strip of panel icons (PhotoCraft): a click shows the panel, a click on the one in view hides the dock
    readonly property int rulerSize: 18
    property bool dockOpen: true
    function showPanel(group, index) {
        const now = group === 0 ? propertiesTab : group === 1 ? layersTab : topTab;
        if (dockOpen && now === index) { dockOpen = false; return; }
        dockOpen = true;
        if (group === 0) propertiesTab = index; else if (group === 1) layersTab = index; else topTab = index;
    }
    Rectangle {
        id: panelBar
        anchors { right: win.dockOpen ? dock.left : parent.right; top: optionsBar.bottom; bottom: debug.top }
        width: 36
        color: FiliTheme.background
        Rectangle { anchors { top: parent.top; bottom: parent.bottom; left: parent.left } width: FiliTheme.borderWidth; color: FiliTheme.border }
        Column {
            anchors { top: parent.top; topMargin: FiliTheme.space2; horizontalCenter: parent.horizontalCenter }
            spacing: 2
            Repeater {
                model: [
                    { glyph: "sliders-horizontal", tip: "Properties", group: 0, index: 0 }, { glyph: "compass", tip: "Navigator", group: 2, index: 2 },
                    { glyph: "palette", tip: "Color", group: 2, index: 0 }, { glyph: "layers", tip: "Layers", group: 1, index: 0 }, { glyph: "history", tip: "History", group: 1, index: 3 }
                ]
                Rectangle {
                    id: panelButton
                    required property var modelData
                    readonly property bool on: win.dockOpen && (modelData.group === 0 ? win.propertiesTab : modelData.group === 1 ? win.layersTab : win.topTab) === modelData.index
                    width: 30; height: 30; radius: FiliTheme.radiusControl
                    color: on ? FiliTheme.surfaceActive : area.containsMouse ? FiliTheme.surfaceHover : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: Fili.tr(modelData.tip)
                    FiliIcon { anchors.centerIn: parent; size: 16; name: panelButton.modelData.glyph; color: panelButton.on ? FiliTheme.accentColor : FiliTheme.textSecondary }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.showPanel(panelButton.modelData.group, panelButton.modelData.index)
                        onEntered: win.showTip(panelButton, Fili.tr(panelButton.modelData.tip))
                        onExited: win.hideTip(panelButton)
                    }
                }
            }
        }
    }

    FiliDock {
        id: dock
        visible: win.dockOpen
        anchors { right: parent.right; top: optionsBar.bottom; bottom: debug.top }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            tabs: [Fili.tr("Color"), Fili.tr("Swatches"), Fili.tr("Navigator")]
            currentIndex: win.topTab
            onTabClicked: i => win.topTab = i
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
                    Item {
                        id: picker
                        // The colour picker of PhotoCraft: saturation and value in the square, the hue on the strip
                        width: parent.width
                        height: 110
                        property real h: 0
                        property real sat: 0
                        property real val: 0
                        property bool dragging: false
                        function fromColor(c) { const q = Qt.color(c); if (q.hsvHue >= 0) h = q.hsvHue; sat = q.hsvSaturation; val = q.hsvValue; }
                        function apply() { win.brushColor = Qt.hsva(h, sat, val, 1).toString(); }
                        Component.onCompleted: fromColor(win.brushColor)
                        Connections { target: win; function onBrushColorChanged() { if (!picker.dragging) picker.fromColor(win.brushColor); } }
                        Rectangle {
                            id: svSquare
                            width: parent.width - 30; height: parent.height
                            radius: 3
                            color: Qt.hsva(picker.h, 1, 1, 1)
                            clip: true
                            Rectangle { anchors.fill: parent; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#ffffff" } GradientStop { position: 1; color: "#00ffffff" } } }
                            Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "#000000" } } }
                            Rectangle { x: picker.sat * parent.width - 5; y: (1 - picker.val) * parent.height - 5; width: 10; height: 10; radius: 5; color: "transparent"; border { width: 2; color: "#ffffff" } }
                            MouseArea {
                                anchors.fill: parent
                                function pick(e) { picker.dragging = true; picker.sat = Math.max(0, Math.min(1, e.x / width)); picker.val = 1 - Math.max(0, Math.min(1, e.y / height)); picker.apply(); }
                                onPressed: e => pick(e)
                                onPositionChanged: e => pick(e)
                                onReleased: picker.dragging = false
                            }
                        }
                        Rectangle {
                            x: parent.width - 20; width: 20; height: parent.height
                            radius: 3
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.hsva(0, 1, 1, 1) } GradientStop { position: 1 / 6; color: Qt.hsva(1 / 6, 1, 1, 1) } GradientStop { position: 2 / 6; color: Qt.hsva(2 / 6, 1, 1, 1) }
                                GradientStop { position: 3 / 6; color: Qt.hsva(3 / 6, 1, 1, 1) } GradientStop { position: 4 / 6; color: Qt.hsva(4 / 6, 1, 1, 1) } GradientStop { position: 5 / 6; color: Qt.hsva(5 / 6, 1, 1, 1) } GradientStop { position: 1; color: Qt.hsva(0.999, 1, 1, 1) }
                            }
                            Rectangle { x: -2; y: picker.h * parent.height - 2; width: parent.width + 4; height: 4; radius: 2; color: "transparent"; border { width: 2; color: "#ffffff" } }
                            MouseArea {
                                anchors.fill: parent
                                function pick(e) { picker.dragging = true; picker.h = Math.max(0, Math.min(0.999, e.y / height)); picker.apply(); }
                                onPressed: e => pick(e)
                                onPositionChanged: e => pick(e)
                                onReleased: picker.dragging = false
                            }
                        }
                    }
                    Row {
                        spacing: FiliTheme.space3
                        Rectangle { width: 28; height: 28; radius: 3; color: win.brushColor; border { width: 1; color: FiliTheme.border } }
                        Rectangle { width: 28; height: 28; radius: 3; color: win.bgColor; border { width: 1; color: FiliTheme.border } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.brushColor; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                        FiliButton { anchors.verticalCenter: parent.verticalCenter; label: Fili.tr("Swap"); onClicked: { const c = win.brushColor; win.brushColor = win.bgColor; win.bgColor = c; } }
                    }
                }
                FiliScrollBar { flick: colorView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }
            Flickable {
                id: swatchView
                clip: true
                contentHeight: swatchColumn.height + FiliTheme.space3
                KineticScroll {}
                Column {
                    id: swatchColumn
                    x: FiliTheme.space3
                    y: FiliTheme.space3
                    width: swatchView.width - 2 * FiliTheme.space3
                    spacing: FiliTheme.space2
                    Repeater {
                        model: win.swatchGroups
                        Column {
                            required property var modelData
                            width: swatchColumn.width
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
                FiliScrollBar { flick: swatchView; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }
            Item {
                id: navigatorView
                // The picture of the document and the part the canvas shows (a frame), a click or a drag moves the view
                readonly property real ratio: nav.implicitWidth > 0 ? nav.implicitWidth / nav.implicitHeight : 1
                Image {
                    id: nav
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 2 * FiliTheme.space3, (parent.height - 2 * FiliTheme.space3) * navigatorView.ratio)
                    height: width / navigatorView.ratio
                    source: canvas.navigator
                    cache: false
                    fillMode: Image.Stretch
                    Rectangle {
                        readonly property var rect: {
                            canvas.viewKey;
                            if (!canvas.loaded || canvasArea.width <= 0) return null;
                            const a = JSON.parse(canvas.toDoc(0, 0)), b = JSON.parse(canvas.toDoc(canvasArea.width, canvasArea.height));
                            const dw = win.docSize.w, dh = win.docSize.h;
                            if (dw <= 0 || dh <= 0) return null;
                            const x0 = Math.max(0, a[0]) / dw, y0 = Math.max(0, a[1]) / dh, x1 = Math.min(dw, b[0]) / dw, y1 = Math.min(dh, b[1]) / dh;
                            return Qt.rect(x0 * nav.width, y0 * nav.height, Math.max(2, (x1 - x0) * nav.width), Math.max(2, (y1 - y0) * nav.height));
                        }
                        visible: rect !== null
                        x: rect ? rect.x : 0; y: rect ? rect.y : 0; width: rect ? rect.width : 0; height: rect ? rect.height : 0
                        color: "transparent"
                        border { width: 2; color: FiliTheme.accentColor }
                    }
                    MouseArea {
                        anchors.fill: parent
                        function go(e) { canvas.centerOn(Math.max(0, Math.min(1, e.x / nav.width)) * win.docSize.w, Math.max(0, Math.min(1, e.y / nav.height)) * win.docSize.h); }
                        onPressed: e => go(e)
                        onPositionChanged: e => { if (pressed) go(e); }
                    }
                }
                Text { anchors.centerIn: parent; visible: !canvas.loaded; text: Fili.tr("No image"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
            }
        }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.preferredHeight: win.curvesShown || win.adjustmentSliders.length > 3 ? 440 : win.adjustmentSliders.length > 0 ? 320 : 225
            tabs: [Fili.tr("Properties"), Fili.tr("Adjustments")]
            currentIndex: win.propertiesTab
            onTabClicked: i => win.propertiesTab = i
            Item {
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space3 }
                    spacing: FiliTheme.space3
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
                            histogram: { canvas.layers; return win.curvesShown ? JSON.parse(canvas.histogram(win.curveChannel)) : []; }
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
                        visible: win.adjustmentSliders.length > 0
                        width: parent.width
                        spacing: FiliTheme.space2
                        Repeater {
                            model: win.adjustmentSliders
                            Item {
                                id: adjRow
                                required property var modelData
                                readonly property real current: { const v = win.adjustment.params[modelData.key]; return modelData.index !== undefined ? v[modelData.index] : v; }
                                width: parent.width
                                height: 30
                                Text { id: adjLabel; anchors { left: parent.left; verticalCenter: parent.verticalCenter } width: 96; elide: Text.ElideRight; text: Fili.tr(modelData.label); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
                                Text { id: adjValue; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 48; horizontalAlignment: Text.AlignRight; text: Number(adjSlider.dragging ? adjSlider.shown : adjRow.current).toFixed(modelData.decimals ?? 0); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                                FiliSlider {
                                    id: adjSlider
                                    property real shown: adjRow.current
                                    anchors { left: adjLabel.right; right: adjValue.left; leftMargin: FiliTheme.space2; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                    Binding on value { when: !adjSlider.dragging; value: (adjRow.current - adjRow.modelData.min) / (adjRow.modelData.max - adjRow.modelData.min) }
                                    onMoved: v => {
                                        value = v;
                                        const x = adjRow.modelData.min + v * (adjRow.modelData.max - adjRow.modelData.min);
                                        shown = adjRow.modelData.decimals ? x : Math.round(x);
                                        canvas.preview("layer.setAdjustment", win.adjustmentParams(adjRow.modelData, shown));
                                    }
                                    onReleased: { canvas.endPreview(); canvas.run("layer.setAdjustment", win.adjustmentParams(adjRow.modelData, shown)); }
                                }
                            }
                        }
                    }
                    Column {
                        visible: win.activeLayer !== null && !win.curvesShown && win.adjustmentSliders.length === 0
                        width: parent.width
                        spacing: FiliTheme.space3
                        Row {
                            spacing: FiliTheme.space2
                            FiliIcon { anchors.verticalCenter: parent.verticalCenter; size: 18; name: win.activeLayer && win.activeLayer.kind === "Type" ? "type" : win.activeLayer && win.activeLayer.kind === "Shape" ? "square" : "image"; color: FiliTheme.textSecondary }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: win.activeLayer ? win.activeLayer.name : ""; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeList; font.weight: Font.DemiBold; color: FiliTheme.text }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: win.activeLayer ? win.activeLayer.kind : ""; font.family: FiliTheme.font; font.pixelSize: FiliTheme.sizeSmall; color: FiliTheme.muted }
                        }
                        Grid {
                            columns: 4
                            columnSpacing: FiliTheme.space3
                            rowSpacing: FiliTheme.space2
                            Repeater {
                                model: [["X", 0], ["Y", 1], ["W", 2], ["H", 3]]
                                Row {
                                    required property var modelData
                                    spacing: FiliTheme.space2
                                    Text { text: modelData[0]; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.muted }
                                    Text { text: (win.activeLayer && win.activeLayer.bounds ? win.activeLayer.bounds[modelData[1]] : "") + " px"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
                                }
                            }
                        }
                        Item {
                            width: parent.width
                            height: 26
                            Text { id: fillLabel; anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: Fili.tr("Fill"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.text }
                            Text { id: fillValue; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 48; horizontalAlignment: Text.AlignRight; text: Math.round((fillSlider.dragging ? fillSlider.value : fillSlider.shown) * 100) + " %"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                            FiliSlider {
                                id: fillSlider
                                readonly property real shown: win.activeLayer && win.activeLayer.fill !== undefined ? win.activeLayer.fill : 1
                                anchors { left: fillLabel.right; right: fillValue.left; leftMargin: FiliTheme.space3; rightMargin: FiliTheme.space3; verticalCenter: parent.verticalCenter }
                                Binding on value { when: !fillSlider.dragging; value: fillSlider.shown }
                                onMoved: v => value = v
                                onReleased: if (win.activeLayer) win.setLayer(win.activeLayer.id, { fill: value })
                            }
                        }
                        Rectangle { width: parent.width; height: 1; color: FiliTheme.border }
                        Text { text: Fili.tr("Document"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; font.weight: Font.DemiBold; color: FiliTheme.text }
                        Text { width: parent.width; elide: Text.ElideRight; text: Fili.tr("Canvas") + "   " + win.docSize.w + " × " + win.docSize.h + " px   ·   RGB Color 8 bit"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                    }
                }
            }
            Column {
                FiliSidebarRow { label: Fili.tr("Curves"); enabled: canvas.loaded; onClicked: win.runAction("adjust-curves") }
                FiliSidebarRow { label: Fili.tr("Invert"); enabled: canvas.loaded; onClicked: win.runAction("adjust-invert") }
                FiliSidebarRow { label: Fili.tr("Levels"); enabled: canvas.loaded; onClicked: win.runAction("adjust-levels") }
                FiliSidebarRow { label: Fili.tr("Hue/Saturation"); enabled: canvas.loaded; onClicked: win.runAction("adjust-hue-saturation") }
                FiliSidebarRow { label: Fili.tr("Brightness/Contrast"); enabled: canvas.loaded; onClicked: win.runAction("adjust-brightness-contrast") }
                FiliSidebarRow { label: Fili.tr("Vibrance"); enabled: canvas.loaded; onClicked: win.runAction("adjust-vibrance") }
                FiliSidebarRow { label: Fili.tr("Exposure"); enabled: canvas.loaded; onClicked: win.runAction("adjust-exposure") }
                FiliSidebarRow { label: Fili.tr("Color Balance"); enabled: canvas.loaded; onClicked: win.runAction("adjust-color-balance") }
                FiliSidebarRow { label: Fili.tr("Black & White"); enabled: canvas.loaded; onClicked: win.runAction("adjust-black-white") }
                FiliSidebarRow { label: Fili.tr("Threshold"); enabled: canvas.loaded; onClicked: win.runAction("adjust-threshold") }
                FiliSidebarRow { label: Fili.tr("Posterize"); enabled: canvas.loaded; onClicked: win.runAction("adjust-posterize") }
                FiliSidebarRow { label: Fili.tr("Photo Filter"); enabled: canvas.loaded; onClicked: win.runAction("adjust-photo-filter") }
            }
        }
        FiliDockGroup {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tabs: [Fili.tr("Layers"), Fili.tr("Channels"), Fili.tr("Paths"), Fili.tr("History")]
            currentIndex: win.layersTab
            onTabClicked: i => win.layersTab = i
            Item {
                Column {
                    id: layerHeader
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: FiliTheme.space2 }
                    spacing: FiliTheme.space2
                    enabled: win.activeLayer !== null
                    opacity: enabled ? 1 : 0.5
                    Row {
                        width: parent.width
                        spacing: FiliTheme.space2
                        FiliSelect {
                            width: parent.width - opacityBox.width - parent.spacing
                            model: win.blendModes
                            current: win.activeLayer ? win.activeLayer.blend : "Normal"
                            onPicked: v => win.activeLayer && win.setLayer(win.activeLayer.id, { blend: v })
                        }
                        Item {
                            id: opacityBox
                            width: 120
                            height: 28
                            Text { id: opacityValue; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 44; horizontalAlignment: Text.AlignRight; text: Math.round(opacity.value * 100) + " %"; font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                            FiliSlider {
                                id: opacity
                                anchors { left: parent.left; right: opacityValue.left; rightMargin: FiliTheme.space2; verticalCenter: parent.verticalCenter }
                                // Follows the layer, except while the thumb is held
                                Binding on value { when: !opacity.dragging; value: win.activeLayer ? win.activeLayer.opacity : 1 }
                                onMoved: v => value = v
                                onReleased: if (win.activeLayer) win.setLayer(win.activeLayer.id, { opacity: value })
                            }
                        }
                    }
                    Row {
                        spacing: 2
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 40; text: Fili.tr("Lock"); font.family: FiliTheme.font; font.pixelSize: FiliTheme.size; color: FiliTheme.textSecondary }
                        Repeater {
                            model: [{ key: "transparency", icon: "image", tip: "Lock transparent pixels" }, { key: "pixels", icon: "brush", tip: "Lock image pixels" }, { key: "position", icon: "move", tip: "Lock position" }, { key: "all", icon: "lock", tip: "Lock all" }]
                            Rectangle {
                                id: lockButton
                                required property var modelData
                                readonly property bool on: win.activeLayer && win.activeLayer.locks ? win.activeLayer.locks[modelData.key] === true : false
                                width: 28; height: 28; radius: FiliTheme.radiusControl
                                color: on ? FiliTheme.surfaceActive : lockArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: Fili.tr(modelData.tip)
                                Accessible.checked: on
                                FiliIcon { anchors.centerIn: parent; size: 14; name: lockButton.modelData.icon; color: lockButton.on ? FiliTheme.accentColor : FiliTheme.textSecondary }
                                MouseArea {
                                    id: lockArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: win.setLayer(win.activeLayer.id, { locks: { [lockButton.modelData.key]: !lockButton.on } })
                                    onEntered: win.showTip(lockButton, Fili.tr(lockButton.modelData.tip))
                                    onExited: win.hideTip(lockButton)
                                }
                            }
                        }
                    }
                }
                ListView {
                    id: layersView
                    anchors { left: parent.left; right: parent.right; top: layerHeader.bottom; bottom: parent.bottom; bottomMargin: layerButtons.height }
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
                Row {
                    id: layerButtons
                    anchors { right: parent.right; bottom: parent.bottom; margins: FiliTheme.space2 }
                    spacing: 2
                    Repeater {
                        model: [{ icon: "plus", tip: "New Layer", cmd: "layer.new.layer" }, { icon: "copy", tip: "Duplicate Layer", cmd: "layer.duplicate" },
                            { icon: "folder-plus", tip: "Group Layers", cmd: "layer.groupLayers" }, { icon: "trash", tip: "Delete Layer", cmd: "layer.delete" }]
                        Rectangle {
                            id: layerButton
                            required property var modelData
                            width: 28; height: 28; radius: FiliTheme.radiusControl
                            color: lbArea.containsMouse ? FiliTheme.surfaceHover : "transparent"
                            opacity: canvas.loaded ? 1 : 0.4
                            Accessible.role: Accessible.Button
                            Accessible.name: Fili.tr(modelData.tip)
                            FiliIcon { anchors.centerIn: parent; size: 15; name: layerButton.modelData.icon; color: FiliTheme.textSecondary }
                            MouseArea {
                                id: lbArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: canvas.loaded
                                onClicked: canvas.run(layerButton.modelData.cmd, "{}")
                                onEntered: win.showTip(layerButton, Fili.tr(layerButton.modelData.tip))
                                onExited: win.hideTip(layerButton)
                            }
                        }
                    }
                }
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
        anchors { left: toolStrip.right; right: panelBar.left; top: optionsBar.bottom }
        height: implicitHeight
        closable: false
        detachable: false
        model: canvas.loaded ? [canvas.title + " @ " + Math.round(canvas.zoom * 100) + "%"] : []
    }
    // Rulers in document pixels along the top and the left of the canvas: a tick every step chosen to be at least 70 px apart
    Repeater {
        model: [true, false]
        Canvas {
            id: ruler
            required property bool modelData
            x: modelData ? canvasArea.x : canvasArea.x - win.rulerSize
            y: modelData ? canvasArea.y - win.rulerSize : canvasArea.y
            width: modelData ? canvasArea.width : win.rulerSize
            height: modelData ? win.rulerSize : canvasArea.height
            visible: canvas.loaded
            Connections { target: canvas; function onViewKeyChanged() { ruler.requestPaint(); } }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.fillStyle = FiliTheme.background.toString();
                c.fillRect(0, 0, width, height);
                const horizontal = modelData, zoom = canvas.zoom;
                if (!canvas.loaded || zoom <= 0) return;
                const origin = JSON.parse(canvas.toDoc(0, 0))[horizontal ? 0 : 1];
                const length = horizontal ? width : height;
                const steps = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000];
                const step = steps.find(v => v * zoom >= 70) ?? 10000;
                const minor = step / 5;
                c.strokeStyle = FiliTheme.muted.toString();
                c.fillStyle = FiliTheme.textSecondary.toString();
                c.font = "9px sans-serif";
                c.lineWidth = 1;
                c.beginPath();
                for (let d = Math.floor(origin / minor) * minor; (d - origin) * zoom < length; d += minor) {
                    const p = Math.round((d - origin) * zoom) + 0.5;
                    if (p < 0) continue;
                    const major = Math.abs(d / step - Math.round(d / step)) < 1e-6;
                    const len = major ? win.rulerSize : 5;
                    if (horizontal) { c.moveTo(p, win.rulerSize - len); c.lineTo(p, win.rulerSize); } else { c.moveTo(win.rulerSize - len, p); c.lineTo(win.rulerSize, p); }
                }
                c.stroke();
                for (let d = Math.ceil(origin / step) * step; (d - origin) * zoom < length; d += step) {
                    const p = (d - origin) * zoom;
                    if (p < 0) continue;
                    if (horizontal) c.fillText(String(Math.round(d)), p + 3, 9);
                    else { c.save(); c.translate(9, p + 3); c.rotate(-Math.PI / 2); c.textAlign = "right"; c.fillText(String(Math.round(d)), 0, 0); c.restore(); }
                }
            }
        }
    }

    Rectangle {
        anchors { left: toolStrip.right; leftMargin: win.rulerSize; right: panelBar.left; top: documentTab.bottom; topMargin: win.rulerSize; bottom: debug.top }
        id: canvasArea
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
            cursorShape: win.tool === "direct" ? Qt.ArrowCursor : win.tool === "text" ? Qt.IBeamCursor : win.shapeTool ? Qt.CrossCursor : win.tool === "move" ? Qt.SizeAllCursor : win.painting || win.tool === "bucket" || win.tool === "gradient" || win.tool === "eyedropper" || win.tool === "zoom" || win.dragTools[win.tool] || win.tool === "lasso" || win.tool === "wand" ? Qt.CrossCursor : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point last
            function addPoint(e) {
                win.stroke = win.stroke.concat([JSON.parse(canvas.toDoc(e.x, e.y))]);
                canvas.preview(win.strokeTools[win.tool], win.strokeParams());
            }
            onPressed: e => {
                last = Qt.point(e.x, e.y);
                if (win.dragTools[win.tool] && e.button === Qt.LeftButton) win.drag = Qt.rect(e.x, e.y, 0, 0);
                if ((win.tool === "lasso" || win.tool === "gradient" || win.tool === "line") && e.button === Qt.LeftButton) win.lasso = [Qt.point(e.x, e.y)];
                if (win.tool === "direct" && e.button === Qt.LeftButton) {
                    let best = null, bestD = 10;
                    win.shapeAnchors.forEach(a => { const p = JSON.parse(canvas.toItem(a.x, a.y)), d = Math.hypot(p[0] - e.x, p[1] - e.y); if (d < bestD) { bestD = d; best = a; } });
                    if (best) win.anchorDrag = { sp: best.sp, k: best.k, from: JSON.parse(canvas.toDoc(e.x, e.y)) };
                }
                if (win.tool === "pen" && e.button === Qt.LeftButton) {
                    const f = win.penPoints[0], first = f ? JSON.parse(canvas.toItem(f[0], f[1])) : null;
                    if (first && win.penPoints.length >= 3 && Math.hypot(e.x - first[0], e.y - first[1]) < 8) win.finishPen();
                    else win.penPoints = win.penPoints.concat([JSON.parse(canvas.toDoc(e.x, e.y))]);
                }
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
                if (win.anchorDrag) {
                    canvas.endPreview();
                    const p = JSON.parse(canvas.toDoc(e.x, e.y)), move = [p[0] - win.anchorDrag.from[0], p[1] - win.anchorDrag.from[1]];
                    if (Math.hypot(move[0], move[1]) > 0.5) canvas.run("path.moveAnchors", win.anchorParams(move));
                    win.anchorDrag = null;
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
                if (win.anchorDrag && pressedButtons & Qt.LeftButton) {
                    const p = JSON.parse(canvas.toDoc(e.x, e.y));
                    canvas.preview("path.moveAnchors", win.anchorParams([p[0] - win.anchorDrag.from[0], p[1] - win.anchorDrag.from[1]]));
                }
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
            onDoubleClicked: { if (win.tool === "hand") canvas.zoomFit(); else if (win.tool === "pen") win.finishPen(); }
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
        // Scroll bars of the view: the thumb is the part of the document shown, it appears once the image is larger than the canvas
        Repeater {
            model: [true, false]
            Rectangle {
                id: bar
                required property bool modelData
                readonly property var span: {
                    canvas.viewKey;
                    if (!canvas.loaded || win.docSize.w <= 0 || canvas.width <= 0) return null;
                    const a = JSON.parse(canvas.toDoc(0, 0)), b = JSON.parse(canvas.toDoc(canvas.width, canvas.height));
                    const d = modelData ? win.docSize.w : win.docSize.h;
                    const lo = Math.max(0, modelData ? a[0] : a[1]), hi = Math.min(d, modelData ? b[0] : b[1]);
                    return hi - lo >= d - 0.5 ? null : { lo: lo / d, hi: hi / d };
                }
                visible: span !== null
                color: "transparent"
                x: modelData ? 0 : parent.width - 10
                y: modelData ? parent.height - 10 : 0
                width: modelData ? parent.width - 10 : 10
                height: modelData ? 10 : parent.height - 10
                Rectangle {
                    readonly property real len: bar.modelData ? bar.width : bar.height
                    x: bar.modelData && bar.span ? bar.span.lo * len : 2
                    y: !bar.modelData && bar.span ? bar.span.lo * len : 2
                    width: bar.modelData ? (bar.span ? Math.max(24, (bar.span.hi - bar.span.lo) * len) : 0) : 6
                    height: bar.modelData ? 6 : (bar.span ? Math.max(24, (bar.span.hi - bar.span.lo) * len) : 0)
                    radius: 3
                    color: barArea.containsMouse || barArea.pressed ? FiliTheme.textSecondary : FiliTheme.muted
                    opacity: 0.7
                }
                MouseArea {
                    id: barArea
                    anchors.fill: parent
                    hoverEnabled: true
                    function go(e) {
                        const f = Math.max(0, Math.min(1, (bar.modelData ? e.x / width : e.y / height)));
                        const c = JSON.parse(canvas.toDoc(canvas.width / 2, canvas.height / 2));
                        if (bar.modelData) canvas.centerOn(f * win.docSize.w, c[1]); else canvas.centerOn(c[0], f * win.docSize.h);
                    }
                    onPressed: e => go(e)
                    onPositionChanged: e => { if (pressed) go(e); }
                }
            }
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
            id: anchorsView
            anchors.fill: parent
            visible: win.shapeAnchors.length > 0
            Connections { target: win; function onShapeAnchorsChanged() { anchorsView.requestPaint(); } }
            Connections { target: canvas; function onViewKeyChanged() { anchorsView.requestPaint(); } }
            onVisibleChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.strokeStyle = FiliTheme.accentColor.toString();
                c.fillStyle = "#ffffff";
                win.shapeAnchors.forEach(a => { const q = JSON.parse(canvas.toItem(a.x, a.y)); c.fillRect(q[0] - 3, q[1] - 3, 7, 7); c.strokeRect(q[0] - 3, q[1] - 3, 7, 7); });
            }
        }
        Canvas {
            id: penPath
            anchors.fill: parent
            visible: win.penPoints.length > 0
            Connections { target: win; function onPenPointsChanged() { penPath.requestPaint(); } }
            Connections { target: canvas; function onViewKeyChanged() { penPath.requestPaint(); } }
            onVisibleChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                if (win.penPoints.length === 0) return;
                c.strokeStyle = FiliTheme.accentColor.toString();
                c.fillStyle = FiliTheme.accentColor.toString();
                c.lineWidth = 1;
                c.beginPath();
                win.penPoints.forEach((p, i) => { const q = JSON.parse(canvas.toItem(p[0], p[1])); if (i === 0) c.moveTo(q[0], q[1]); else c.lineTo(q[0], q[1]); });
                c.stroke();
                win.penPoints.forEach(p => { const q = JSON.parse(canvas.toItem(p[0], p[1])); c.fillRect(q[0] - 2, q[1] - 2, 5, 5); });
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

    // Debug panel (View > Debug Logs, Ctrl+Shift+L): the log of the window above the footer
    FiliDebugPanel {
        id: debug
        anchors { bottom: footer.top; left: parent.left; right: parent.right }
    }

    // Status bar of PhotoCraft: zoom, size, layers on the left; the label of the hovered tool or the render time on the right
    FiliFooter {
        id: footer
        visible: win.footerShown
        height: win.footerShown ? implicitHeight : 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        error: canvas.error !== ""
        leftText: canvas.error !== "" ? canvas.error : (canvas.loaded ? Math.round(canvas.zoom * 100) + " %   ·   " + canvas.info : Fili.tr("No image"))
        rightText: win.tipText !== "" ? win.tipText : (canvas.loaded ? canvas.timing : "")
    }
}
