#!/usr/bin/env python3
"""Drives the tools of the window without a mouse: starts fili-photocraft off screen on a generated image and sends each tool a
press / move / release through `ctl action pointer-*`, then reads `ctl state` (the last step of the history, the layers, the
selection). Usage: scripts/test-tools.py [BINARY]   (default: target/fast/fili-photocraft, with the QML read from the sources)"""
import json, os, pathlib, struct, subprocess, sys, tempfile, time, zlib

root = pathlib.Path(__file__).resolve().parents[1]
binary = sys.argv[1] if len(sys.argv) > 1 else str(root / "target/fast/fili-photocraft")
tmp = pathlib.Path(tempfile.mkdtemp(prefix="fili-photocraft-tools-"))

def png(path, w=600, h=400):
    rows = b"".join(b"\x00" + b"".join(bytes([x * 255 // w, y * 255 // h, 128]) for x in range(w)) for y in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))

image = tmp / "test.png"
png(image)
env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(tmp / "config"),
           FILI_QML_DIR=str(root / "qml"), FILI_UI_QML=str((root / "../fili-ui/qml").resolve()))
app = subprocess.Popen([binary, str(image)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

def ctl(*args):
    out = subprocess.run([binary, "ctl", "--pid", str(app.pid), *args], env=env, capture_output=True, text=True, timeout=15).stdout
    try: return json.loads(out)
    except Exception: return {"ok": False, "error": out}

failures = []
def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + str(detail)))
    if not ok: failures.append(name)

for _ in range(60):
    st = ctl("state")
    if st.get("loaded"): break
    time.sleep(0.5)
else:
    print("FAIL the window never loaded the image"); app.kill(); sys.exit(1)
time.sleep(1)
st = ctl("state")
W, H = st["view"]["w"], st["view"]["h"]
cx, cy = W / 2, H / 2

def act(name, arg=""): return ctl("action", name, *([arg] if arg else []))
def drag(points, mod=""):
    first = points[0]
    act("pointer-press", f"{first[0]:.0f},{first[1]:.0f}" + (f",{mod}" if mod else ""))
    for p in points[1:]:
        act("pointer-move", f"{p[0]:.0f},{p[1]:.0f}")
    last = points[-1]
    act("pointer-release", f"{last[0]:.0f},{last[1]:.0f}")
    time.sleep(0.3)
    return ctl("state")
def line(n=6, dx=40, dy=25): return [(cx - dx + i * 2 * dx / (n - 1), cy - dy + i * 2 * dy / (n - 1)) for i in range(n)]
box = [(cx - 60, cy - 40), (cx, cy), (cx + 60, cy + 40)]

for tool, step in [("brush", "Brush"), ("pencil", "Pencil"), ("blur", "Blur"), ("sharpen", "Sharpen"), ("smudge", "Smudge"), ("dodge", "Dodge"), ("burn", "Burn"), ("sponge", "Sponge"), ("eraser", "Eraser")]:
    act("tool-" + tool)
    s = drag(line())
    check(f"{tool}: a stroke adds a history step ({step})", step.lower() in s["lastStep"].lower(), s["lastStep"])

act("tool-history"); s = drag(line()); check("history brush: a stroke", "history" in s["lastStep"].lower(), s["lastStep"])
act("tool-heal"); s = drag(line()); check("spot healing: a stroke", "heal" in s["lastStep"].lower(), s["lastStep"])
act("tool-stamp"); drag([(cx - 80, cy)], "alt"); s = drag([(cx, cy + 20), (cx + 30, cy + 30), (cx + 50, cy + 30)]); check("clone stamp: alt+click then a stroke", "clone" in s["lastStep"].lower(), s["lastStep"])

act("tool-remove"); s = drag(line()); check("remove: a stroke is accepted", s["error"] == "", s["error"])
for tool in ("marquee", "ellipse", "object"):
    act("deselect"); act("tool-" + tool); s = drag(box)
    check(f"{tool}: a drag makes a selection", s["selection"] != "", s)
act("deselect"); act("tool-lasso"); s = drag([(cx - 50, cy - 30), (cx + 50, cy - 30), (cx + 50, cy + 30), (cx - 50, cy + 30), (cx - 49, cy - 29)]); check("lasso: a loop makes a selection", s["selection"] != "", s)
act("deselect"); act("tool-wand"); s = drag([(cx, cy)]); check("magic wand: a click makes a selection", s["selection"] != "", s)
act("deselect"); act("tool-quick"); s = drag(line()); check("quick selection: a stroke makes a selection", s["selection"] != "", s)
act("deselect")

act("tool-gradient"); s = drag([(cx - 80, cy), (cx + 80, cy)]); check("gradient: a drag", "gradient" in s["lastStep"].lower(), s["lastStep"])
act("tool-bucket"); s = drag([(cx, cy)]); check("paint bucket: a click", "bucket" in s["lastStep"].lower(), s["lastStep"])
before = s["layers"]
for tool in ("rect", "rounded", "shapeellipse", "triangle", "star", "polygon"):
    act("tool-" + tool); n = ctl("state")["layers"]; s = drag(box); check(f"{tool}: a drag adds a shape layer", s["layers"] == n + 1, s["layers"])
act("tool-line"); n = ctl("state")["layers"]; s = drag([(cx - 60, cy), (cx + 60, cy + 20)]); check("line: a drag adds a shape layer", s["layers"] == n + 1, s["layers"])
act("tool-pen"); n = ctl("state")["layers"]
for p in [(cx - 50, cy - 40), (cx + 50, cy - 40), (cx + 50, cy + 40), (cx - 49, cy - 39)]:
    act("pointer-press", f"{p[0]:.0f},{p[1]:.0f}"); act("pointer-release", f"{p[0]:.0f},{p[1]:.0f}")
time.sleep(0.3); s = ctl("state"); check("pen: closing the path adds a shape layer", s["layers"] == n + 1, s["layers"])
act("tool-direct"); s = drag([(cx - 50, cy - 40), (cx - 30, cy - 20)]); check("direct selection: dragging an anchor", "path" in s["lastStep"].lower() or "anchor" in s["lastStep"].lower() or "transform" in s["lastStep"].lower(), s["lastStep"])
act("tool-move"); s = drag([(cx, cy), (cx + 20, cy + 10)]); check("move: a drag", "move" in s["lastStep"].lower(), s["lastStep"])
act("tool-crop"); w0 = ctl("state")["info"]; s = drag(box); check("crop: a drag changes the size", s["info"] != w0, s["info"])
act("undo"); act("undo")

app.terminate()
print("\n%d failure(s)" % len(failures) if failures else "\nall tools answer")
sys.exit(1 if failures else 0)
