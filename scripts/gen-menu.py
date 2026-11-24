#!/usr/bin/env python3
"""Regenerates the menus of the window from one table (the simple commands and the commands with a parameter dialog): the blocks
`BEGIN/END generated ...` of qml/Main.qml, the actions of shell/ctl/fili-photocraft.json and shell/appmenu/fili-photocraft.json.
Idempotent: edit the tables below (`simple`, `dialogs`) and the menu structure at the end, then run it, then `make test`.
The tools (tool-NAME actions) and the panels (panel-NAME) are not generated here: see docs/next.md."""
import json,re,sys
import pathlib
root=str(pathlib.Path(__file__).resolve().parents[1])+'/'
# (action, label, cmd, params-js, keys, dialog-key)
simple=[
 ("edit-cut","Cut","edit.cut","{}","Ctrl+X"),("edit-copy","Copy","edit.copy","{}","Ctrl+C"),("edit-copy-merged","Copy Merged","edit.copyMerged","{}","Ctrl+Shift+C"),
 ("edit-paste","Paste","edit.paste","{}","Ctrl+V"),("edit-paste-in-place","Paste in Place","edit.pasteSpecial.pasteInPlace","{}","Ctrl+Shift+V"),("edit-clear","Clear","edit.clear","{}",None),
 ("edit-fill-foreground","Fill with Foreground Color","edit.fill","{ contents: \"color\", color: win.brushColor }",None),
 ("edit-fill-background","Fill with Background Color","edit.fill","{ contents: \"color\", color: win.bgColor }",None),
 ("image-rotate-cw","Rotate 90° Clockwise","image.imageRotation.90cw","{}",None),("image-rotate-ccw","Rotate 90° Counter Clockwise","image.imageRotation.90ccw","{}",None),
 ("image-rotate-half-turn","Rotate 180°","image.imageRotation.180","{}",None),("image-flip-horizontal","Flip Canvas Horizontal","image.imageRotation.flipCanvasHorizontal","{}",None),
 ("image-flip-vertical","Flip Canvas Vertical","image.imageRotation.flipCanvasVertical","{}",None),
 ("image-crop-selection","Crop to Selection","image.crop","{}",None),("image-trim","Trim","image.trim","{}",None),("image-reveal-all","Reveal All","image.revealAll","{}",None),
 ("image-auto-tone","Auto Tone","image.autoTone","{}",None),("image-auto-contrast","Auto Contrast","image.autoContrast","{}",None),("image-auto-color","Auto Color","image.autoColor","{}",None),
 ("image-mode-rgb","RGB Color","image.mode.rgb","{}",None),("image-mode-grayscale","Grayscale","image.mode.grayscale","{}",None),("image-mode-cmyk","CMYK Color","image.mode.cmyk","{}",None),("image-mode-lab","Lab Color","image.mode.lab","{}",None),
 ("image-bits-eight","8 Bits/Channel","image.mode.bits8","{}",None),("image-bits-sixteen","16 Bits/Channel","image.mode.bits16","{}",None),
 ("layer-new","New Layer","layer.new.layer","{}",None),("layer-duplicate","Duplicate Layer","layer.duplicate","{}",None),("layer-delete","Delete Layer","layer.delete","{}",None),
 ("layer-group","Group Layers","layer.groupLayers","{}",None),("layer-merge-down","Merge Down","layer.mergeDown","{}",None),("layer-merge-visible","Merge Visible","layer.mergeVisible","{}",None),
 ("layer-flatten","Flatten Image","layer.flattenImage","{}",None),("layer-bring-forward","Bring Forward","layer.arrange.bringForward","{}",None),("layer-send-backward","Send Backward","layer.arrange.sendBackward","{}",None),
 ("layer-bring-to-front","Bring to Front","layer.arrange.bringToFront","{}",None),("layer-send-to-back","Send to Back","layer.arrange.sendToBack","{}",None),("layer-rasterize","Rasterize Layer","layer.rasterize.layer","{}",None),
 ("layer-mask-reveal-all","Reveal All","layer.layerMask.revealAll","{}",None),("layer-mask-hide-all","Hide All","layer.layerMask.hideAll","{}",None),
 ("layer-mask-reveal-selection","Reveal Selection","layer.layerMask.revealSelection","{}",None),("layer-mask-hide-selection","Hide Selection","layer.layerMask.hideSelection","{}",None),
 ("layer-mask-delete","Delete Layer Mask","layer.layerMask.delete","{}",None),("layer-mask-apply","Apply Layer Mask","layer.layerMask.apply","{}",None),
 ("layer-style-drop-shadow","Drop Shadow","layer.layerStyle.dropShadow","{}",None),("layer-style-inner-shadow","Inner Shadow","layer.layerStyle.innerShadow","{}",None),
 ("layer-style-outer-glow","Outer Glow","layer.layerStyle.outerGlow","{}",None),("layer-style-inner-glow","Inner Glow","layer.layerStyle.innerGlow","{}",None),
 ("layer-style-bevel-emboss","Bevel & Emboss","layer.layerStyle.bevelEmboss","{}",None),
 ("layer-style-color-overlay","Color Overlay","layer.layerStyle.colorOverlay","{ color: win.brushColor }",None),
 ("layer-style-gradient-overlay","Gradient Overlay","layer.layerStyle.gradientOverlay","{ from: win.brushColor, to: win.bgColor }",None),
 ("layer-style-clear","Clear Layer Style","layer.layerStyle.clear","{}",None),("layer-style-copy","Copy Layer Style","layer.layerStyle.copyLayerStyle","{}",None),("layer-style-paste","Paste Layer Style","layer.layerStyle.pasteLayerStyle","{}",None),
 ("layer-clipping-create","Create Clipping Mask","layer.createClippingMask","{}",None),("layer-clipping-release","Release Clipping Mask","layer.releaseClippingMask","{}",None),
 ("layer-link","Link Layers","layer.linkLayers","{}",None),
 ("select-subject","Subject","select.subject","{}",None),("select-grow","Grow","select.grow","{}",None),("select-similar","Similar","select.similar","{}",None),
 ("select-reselect","Reselect","select.reselect","{}",None),("select-focus-area","Focus Area","select.focusArea","{}",None),("select-to-work-path","Make Work Path","select.toWorkPath","{}",None),
 ("select-convert-to-shape","Convert to Shape","select.convertToShape","{}",None),("select-quick-mask","Edit in Quick Mask Mode","select.editInQuickMaskMode","{}",None),
 ("edit-content-aware-fill","Content-Aware Fill","edit.contentAwareFill","{}",None),
 ("history-new-snapshot","New Snapshot","history.newSnapshot","{}",None),("history-clear","Clear History","history.clear","{}",None),("history-step-forward","Step Forward","history.stepForward","{}",None),
 ("history-step-backward","Step Backward","history.stepBackward","{}","Ctrl+Alt+Z"),
 ("filter-blur","Blur","filter.blur.blur","{}",None),("filter-blur-more","Blur More","filter.blur.blurMore","{}",None),
 ("filter-sharpen","Sharpen","filter.sharpen.sharpen","{}",None),("filter-sharpen-more","Sharpen More","filter.sharpen.sharpenMore","{}",None),("filter-sharpen-edges","Sharpen Edges","filter.sharpen.sharpenEdges","{}",None),
 ("filter-despeckle","Despeckle","filter.noise.despeckle","{}",None),("filter-find-edges","Find Edges","filter.stylize.findEdges","{}",None),("filter-solarize","Solarize","filter.stylize.solarize","{}",None),
 ("filter-oil-paint","Oil Paint","filter.stylize.oilPaint","{}",None),
]
# dialogs: action -> (label, cmd, title, fields[{key,label,value,min,max}], extra, keys)
def f(key,label,value,**k): d={"key":key,"label":label,"value":value}; d.update(k); return d
dialogs=[
 ("file-new","New…","file.new","New Document",[f("width","Width (px)",1920),f("height","Height (px)",1080)],{},"Ctrl+N"),
 ("edit-stroke","Stroke…","edit.stroke","Stroke the selection",[f("width","Width (px)",3)],{"color":"$fg"},None),
 ("image-size","Image Size…","image.imageSize","Image Size",[f("width","Width (px)","@w"),f("height","Height (px)","@h")],{},"Ctrl+Alt+I"),
 ("image-canvas-size","Canvas Size…","image.canvasSize","Canvas Size",[f("width","Width (px)","@w"),f("height","Height (px)","@h")],{},"Ctrl+Alt+C"),
 ("layer-style-stroke","Stroke…","layer.layerStyle.stroke","Layer Style: Stroke",[f("size","Size (px)",3)],{"color":"$fg"},None),
 ("select-border","Border…","select.modify.border","Border Selection",[f("radius","Width (px)",5)],{},None),
 ("select-smooth","Smooth…","select.modify.smooth","Smooth Selection",[f("radius","Radius (px)",5)],{},None),
 ("select-expand","Expand…","select.modify.expand","Expand Selection",[f("radius","By (px)",5)],{},None),
 ("select-contract","Contract…","select.modify.contract","Contract Selection",[f("radius","By (px)",5)],{},None),
 ("select-feather","Feather…","select.modify.feather","Feather Selection",[f("radius","Radius (px)",5)],{},None),
 ("select-refine-edge","Refine Edge…","select.refineEdge","Refine Edge",[f("radius","Radius (px)",0),f("smooth","Smooth",0),f("feather","Feather (px)",0),f("contrast","Contrast (%)",0),f("shiftEdge","Shift edge (%)",0)],{},None),
 ("select-color-range","Color Range…","select.colorRange","Color Range",[f("fuzziness","Fuzziness",40)],{"select":"sampledColors","color":"$fg"},None),
 ("edit-free-transform","Free Transform…","edit.transform","Free Transform",[f("scaleX","Scale X (%)",100),f("scaleY","Scale Y (%)",100),f("rotate","Rotate (°)",0),f("dx","Move X (px)",0),f("dy","Move Y (px)",0)],{},"Ctrl+T"),
 ("filter-gaussian-blur","Gaussian Blur…","filter.blur.gaussianBlur","Gaussian Blur",[f("radius","Radius (px)",5)],{},None),
 ("filter-box-blur","Box Blur…","filter.blur.boxBlur","Box Blur",[f("radius","Radius (px)",5)],{},None),
 ("filter-motion-blur","Motion Blur…","filter.blur.motionBlur","Motion Blur",[f("angle","Angle (°)",0),f("distance","Distance (px)",20)],{},None),
 ("filter-surface-blur","Surface Blur…","filter.blur.surfaceBlur","Surface Blur",[f("radius","Radius (px)",5),f("threshold","Threshold",15)],{},None),
 ("filter-unsharp-mask","Unsharp Mask…","filter.sharpen.unsharpMask","Unsharp Mask",[f("amount","Amount (%)",80),f("radius","Radius (px)",1),f("threshold","Threshold",0)],{},None),
 ("filter-smart-sharpen","Smart Sharpen…","filter.sharpen.smartSharpen","Smart Sharpen",[f("amount","Amount (%)",100),f("radius","Radius (px)",1),f("reduceNoise","Reduce noise (%)",10)],{},None),
 ("filter-add-noise","Add Noise…","filter.noise.addNoise","Add Noise",[f("amount","Amount (%)",12.5)],{},None),
 ("filter-median","Median…","filter.noise.median","Median",[f("radius","Radius (px)",2)],{},None),
 ("filter-emboss","Emboss…","filter.stylize.emboss","Emboss",[f("angle","Angle (°)",135),f("height","Height (px)",3),f("amount","Amount (%)",100)],{},None),
 ("filter-high-pass","High Pass…","filter.other.highPass","High Pass",[f("radius","Radius (px)",10)],{},None),
 ("filter-offset","Offset…","filter.other.offset","Offset",[f("horizontal","Horizontal (px)",0),f("vertical","Vertical (px)",0)],{"undefinedAreas":"wrap"},None),
]
savekey="Ctrl+Shift+S"
# ---------- QML
q=open(root+'qml/Main.qml').read()
q=re.sub(r'        // BEGIN generated commands[^\n]*\n.*?        // END generated commands\n','',q,flags=re.S)
acts="        // BEGIN generated commands (scripts of the menus: File, Edit, Image, Layer, Filter)\n"
acts+='        "save-copy": { on: () => canvas.loaded, run: () => saveDialog.open() },\n'
acts+='        "export-layers": { on: () => canvas.loaded, run: () => exportLayersDialog.open() },\n'
for a,l,cmd,p,k in simple:
    acts+='        "%s": { on: () => canvas.loaded, run: () => win.runCommand("%s", %s) },\n'%(a,cmd,p)
for a,l,cmd,t,fl,ex,k in dialogs:
    on='true' if a=='file-new' else 'canvas.loaded'
    acts+='        "%s": { on: () => %s, run: () => win.openParams("%s") },\n'%(a,on,a)
acts+="        // END generated commands\n"
q=q.replace('        "select-all":',acts+'        "select-all":',1)
# dialog specs property
specs={}
for a,l,cmd,t,fl,ex,k in dialogs: specs[a]={"cmd":cmd,"title":t,"fields":fl,"extra":ex}
qml_specs="    // BEGIN generated dialogs\n    readonly property var dialogSpecs: "+json.dumps(specs,ensure_ascii=False)+"\n    // END generated dialogs\n"
q=re.sub(r'    // BEGIN generated dialogs\n.*?    // END generated dialogs\n','',q,flags=re.S)
HELPERS_OLD=r'    // BEGIN generated helpers\n.*?    // END generated helpers\n'
q=re.sub(HELPERS_OLD,'',q,flags=re.S)
q=q.replace('    function setLayer(',qml_specs+'''    // BEGIN generated helpers
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
    // END generated helpers
    function setLayer(''',1)
dlg='''    // BEGIN generated dialogs items
    FolderDialog {
        id: exportLayersDialog
        title: Fili.tr("Export Layers to Files")
        onAccepted: win.runCommand("file.export.layersToFiles", { dir: decodeURIComponent(selectedFolder.toString().replace("file://", "")), format: "png" })
    }
    FileDialog {
        id: saveDialog
        title: Fili.tr("Save a Copy")
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG (*.png)", "JPEG (*.jpg *.jpeg)", "WebP (*.webp)", "TIFF (*.tif *.tiff)", "PhotoCraft/Photoshop (*.psd)"]
        onAccepted: { let p = selectedFile.toString().replace("file://", ""); if (!/\\.[A-Za-z0-9]+$/.test(p)) p += ".png"; win.runCommand("file.saveACopy", { path: decodeURIComponent(p) }); }
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
    // END generated dialogs items
'''
q=re.sub(r'    // BEGIN generated dialogs items\n.*?    // END generated dialogs items\n','',q,flags=re.S)
q=q.replace('    FileDialog {\n        id: openDialog',dlg+'    FileDialog {\n        id: openDialog',1)
# shortcuts
q=re.sub(r'    // BEGIN generated shortcuts\n.*?    // END generated shortcuts\n','',q,flags=re.S)
sc="    // BEGIN generated shortcuts\n"
keys={}
for a,l,cmd,p,k in simple:
    if k: keys[k]=a
for a,l,cmd,t,fl,ex,k in dialogs:
    if k: keys[k]=a
keys[savekey]="save-copy"
for k,a in keys.items(): sc+='    Shortcut { sequence: "%s"; onActivated: win.runAction("%s") }\n'%(k,a)
sc+="    // END generated shortcuts\n"
q=q.replace('    Shortcut { sequence: "Ctrl+A";',sc+'    Shortcut { sequence: "Ctrl+A";',1)
open(root+'qml/Main.qml','w').write(q)
# ---------- ctl + menu
cp=root+'shell/ctl/fili-photocraft.json'
c=json.load(open(cp))
gen=set(["save-copy","export-layers"]+[a for a,*_ in simple]+[a for a,*_ in dialogs])
c['actions']=[a for a in c['actions'] if a['name'] not in gen]
new=[{"name":"save-copy","label":"Save a Copy…","keys":savekey,"args":"[PATH]"},{"name":"export-layers","label":"Export Layers to Files"}]
lab={}
for a,l,cmd,p,k in simple: new.append({k2:v for k2,v in {"name":a,"label":l,"keys":k}.items() if v}); lab[a]=(l,k)
for a,l,cmd,t,fl,ex,k in dialogs: new.append({k2:v for k2,v in {"name":a,"label":l.rstrip("…"),"keys":k}.items() if v}); lab[a]=(l,k)
lab["save-copy"]=("Save a Copy…",savekey)
lab["export-layers"]=("Export Layers to Files…",None)
i=[a['name'] for a in c['actions']].index('redo')+1
c['actions'][i:i]=new
json.dump(c,open(cp,'w'),indent=2,ensure_ascii=False); open(cp,'a').write("\n")
mp=root+'shell/appmenu/fili-photocraft.json'
m=json.load(open(mp))
def it(a): l,k=lab[a]; d={"label":l,"exec":"fili-photocraft ctl --pid %pid action "+a}; 
def mk(a):
    l,k=lab[a]; d={"label":l}
    if k: d["keys"]=k
    d["exec"]="fili-photocraft ctl --pid %pid action "+a; return d
SEP={"sep":True}
def sub(label,acts): return {"label":label,"children":[SEP if a is None else mk(a) for a in acts]}
menus={x['label']:x for x in m['menus']}
# File
open_e=[e for e in menus['File']['children'] if 'action open' in e.get('exec','')][0]
close_e=[e for e in menus['File']['children'] if 'action close' in e.get('exec','')][0]
menus['File']['children']=[mk("file-new"),open_e,mk("save-copy"),mk("export-layers"),SEP,close_e]
undo=[e for e in menus['Edit']['children'] if 'action undo' in e.get('exec','')][0]; redo=[e for e in menus['Edit']['children'] if 'action redo' in e.get('exec','')][0]
menus['Edit']['children']=[undo,redo,SEP]+[mk(a) for a in ["edit-cut","edit-copy","edit-copy-merged","edit-paste","edit-paste-in-place","edit-clear"]]+[SEP]+[mk(a) for a in ["edit-fill-foreground","edit-fill-background","edit-stroke","edit-content-aware-fill"]]+[SEP,mk("edit-free-transform"),SEP,sub("History",["history-step-backward","history-step-forward",None,"history-new-snapshot","history-clear"])]
image={"label":"Image","children":[sub("Mode",["image-mode-rgb","image-mode-grayscale","image-mode-cmyk","image-mode-lab",None,"image-bits-eight","image-bits-sixteen"]),SEP,
  mk("image-size"),mk("image-canvas-size"),sub("Image Rotation",["image-rotate-cw","image-rotate-ccw","image-rotate-half-turn",None,"image-flip-horizontal","image-flip-vertical"]),mk("image-crop-selection"),mk("image-trim"),mk("image-reveal-all"),SEP,
  mk("image-auto-tone"),mk("image-auto-contrast"),mk("image-auto-color")]}
# Layer: keep adjustments, prepend layer commands
lay=[e for e in menus['Layer']['children'] if e.get('exec') and e['exec'].rsplit(' ',1)[-1] not in gen]
lay_new=[mk(a) for a in ["layer-new","layer-duplicate","layer-delete","layer-group"]]+[SEP,
  sub("Layer Style",["layer-style-drop-shadow","layer-style-inner-shadow","layer-style-outer-glow","layer-style-inner-glow","layer-style-bevel-emboss",None,"layer-style-color-overlay","layer-style-gradient-overlay","layer-style-stroke",None,"layer-style-copy","layer-style-paste","layer-style-clear"]),
  sub("Layer Mask",["layer-mask-reveal-all","layer-mask-hide-all","layer-mask-reveal-selection","layer-mask-hide-selection",None,"layer-mask-apply","layer-mask-delete"]),
  mk("layer-clipping-create"),mk("layer-clipping-release"),mk("layer-link"),SEP,
  sub("Arrange",["layer-bring-to-front","layer-bring-forward","layer-send-backward","layer-send-to-back"]),SEP]+lay+[SEP]+[mk(a) for a in ["layer-rasterize","layer-merge-down","layer-merge-visible","layer-flatten"]]
menus['Layer']['children']=[e for e in lay_new if not (e.get("sep") and False)]
flt={"label":"Filter","children":[
 sub("Blur",["filter-blur","filter-blur-more",None,"filter-gaussian-blur","filter-box-blur","filter-motion-blur","filter-surface-blur"]),
 sub("Sharpen",["filter-sharpen","filter-sharpen-more","filter-sharpen-edges",None,"filter-unsharp-mask","filter-smart-sharpen"]),
 sub("Noise",["filter-add-noise","filter-median","filter-despeckle"]),
 sub("Stylize",["filter-emboss","filter-find-edges","filter-solarize","filter-oil-paint"]),
 sub("Other",["filter-high-pass","filter-offset"])]}
lab["select-all"]=("Select All","Ctrl+A"); lab["deselect"]=("Deselect","Ctrl+D"); lab["select-inverse"]=("Inverse","Ctrl+Shift+I"); lab["select-sky"]=("Sky",None)
menus['Select']['children']=[mk("select-all"),mk("deselect"),mk("select-reselect"),mk("select-inverse"),SEP,mk("select-subject"),mk("select-sky"),mk("select-focus-area"),mk("select-color-range"),SEP,
  sub("Modify",["select-border","select-smooth","select-expand","select-contract","select-feather"]),mk("select-grow"),mk("select-similar"),mk("select-refine-edge"),SEP,
  mk("select-to-work-path"),mk("select-convert-to-shape"),mk("select-quick-mask")]
order=[menus['File'],menus['Edit'],image,menus['Layer'],menus['Select'],flt,menus['View']]+([menus['Window']] if 'Window' in menus else [])+[menus['Tools']]
m['menus']=order
json.dump(m,open(mp,'w'),indent=2,ensure_ascii=False); open(mp,'a').write("\n")
print("ok")
