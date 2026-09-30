#!/usr/bin/env python3
"""Writes the app's Lottie animations to Sources/AppUI/Resources/Animations."""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "AppUI", "Resources", "Animations")

ACCENT = [0x5A / 255, 0xC8 / 255, 0xD6 / 255, 1]
OK = [0x4C / 255, 0xC3 / 255, 0x8A / 255, 1]
BAD = [0xF0 / 255, 0x71 / 255, 0x6B / 255, 1]
LINE = [0x3A / 255, 0x3E / 255, 0x47 / 255, 1]
FAINT = [0x7C / 255, 0x81 / 255, 0x8C / 255, 1]

EASE_OUT = {"o": {"x": [0.33], "y": [0]}, "i": {"x": [0.2], "y": [1]}}
EASE_IO = {"o": {"x": [0.45], "y": [0]}, "i": {"x": [0.55], "y": [1]}}


def static(v):
    return {"a": 0, "k": v}


def keys(frames, ease=EASE_IO):
    out = []
    for i, (t, v) in enumerate(frames):
        k = {"t": t, "s": v if isinstance(v, list) else [v]}
        if i < len(frames) - 1:
            k = {**k, **ease}
        out.append(k)
    return {"a": 1, "k": out}


def transform(p=(0, 0), s=100, r=0, o=100, anchor=(0, 0)):
    return {
        "o": o if isinstance(o, dict) else static(o),
        "r": r if isinstance(r, dict) else static(r),
        "p": p if isinstance(p, dict) else static([p[0], p[1], 0]),
        "a": static([anchor[0], anchor[1], 0]),
        "s": s if isinstance(s, dict) else static([s, s, 100]),
    }


def group_tr(p=(0, 0), s=100, o=100):
    return {"ty": "tr", "p": p if isinstance(p, dict) else static(list(p)), "a": static([0, 0]),
            "s": s if isinstance(s, dict) else static([s, s]), "r": static(0),
            "o": o if isinstance(o, dict) else static(o), "sk": static(0), "sa": static(0)}


def stroke(color, width):
    return {"ty": "st", "c": static(color), "o": static(100), "w": static(width), "lc": 2, "lj": 2, "ml": 4}


def fill(color):
    return {"ty": "fl", "c": static(color), "o": static(100), "r": 1}


def ellipse(size):
    return {"ty": "el", "p": static([0, 0]), "s": static([size, size]), "d": 1}


def rect(w, h, r):
    return {"ty": "rc", "p": static([0, 0]), "s": static([w, h]), "r": static(r), "d": 1}


def path(points):
    n = len(points)
    return {"ty": "sh", "ks": static({"i": [[0, 0]] * n, "o": [[0, 0]] * n, "v": points, "c": False})}


def trim(start, end):
    return {"ty": "tm", "s": start if isinstance(start, dict) else static(start),
            "e": end if isinstance(end, dict) else static(end), "o": static(0), "m": 1}


def layer(ind, name, shapes, op, ks=None):
    return {"ddd": 0, "ind": ind, "ty": 4, "nm": name, "sr": 1, "ks": ks or transform(), "ao": 0,
            "shapes": shapes, "ip": 0, "op": op, "st": 0, "bm": 0}


def animation(name, w, h, op, layers):
    return {"v": "5.7.4", "fr": 60, "ip": 0, "op": op, "w": w, "h": h, "nm": name, "ddd": 0, "assets": [], "layers": layers}


def connecting():
    op = 90
    ring = {"ty": "gr", "it": [ellipse(84), stroke(ACCENT, 6),
                                trim(keys([(0, 0), (45, 20), (90, 0)]), keys([(0, 25), (45, 75), (90, 25)])),
                                group_tr()]}
    track = {"ty": "gr", "it": [ellipse(84), stroke(LINE, 6), group_tr()]}
    dot = {"ty": "gr", "it": [ellipse(14), fill(ACCENT), group_tr(s=keys([(0, [70, 70]), (45, [115, 115]), (90, [70, 70])]))]}
    return animation("connecting", 120, 120, op, [
        layer(1, "dot", [dot], op, transform(p=(60, 60))),
        layer(2, "ring", [ring], op, transform(p=(60, 60), r=keys([(0, 0), (90, 360)], {"o": {"x": [0], "y": [0]}, "i": {"x": [1], "y": [1]}}))),
        layer(3, "track", [track], op, transform(p=(60, 60))),
    ])


def working():
    op = 72
    layers = []
    for i in range(3):
        delay = i * 10
        y = keys([(0 + delay, [0, 0]), (18 + delay, [0, -9]), (36 + delay, [0, 0]), (op, [0, 0])], EASE_IO)
        o = keys([(0 + delay, 45), (18 + delay, 100), (36 + delay, 45), (op, 45)])
        dot = {"ty": "gr", "it": [ellipse(10), fill(ACCENT), group_tr(p=y, o=o)]}
        layers.append(layer(i + 1, f"dot{i}", [dot], op, transform(p=(18 + i * 18, 20))))
    return animation("working", 72, 40, op, layers)


def verdict(name, color, marks):
    op = 60
    circle = {"ty": "gr", "it": [ellipse(84), stroke(color, 6), trim(0, keys([(0, 0), (24, 100)], EASE_OUT)), group_tr()]}
    mark_groups = []
    for i, pts in enumerate(marks):
        start = 18 + i * 8
        mark_groups.append({"ty": "gr", "it": [path(pts), stroke(color, 7),
                                               trim(0, keys([(start, 0), (start + 16, 100)], EASE_OUT)), group_tr()]})
    pop = keys([(0, [85, 85, 100]), (26, [104, 104, 100]), (40, [100, 100, 100])], EASE_OUT)
    return animation(name, 120, 120, op, [
        layer(1, "mark", mark_groups, op, transform(p=(60, 60))),
        layer(2, "circle", [circle], op, transform(p=(60, 60), s=pop)),
    ])


def empty():
    op = 180
    float_y = keys([(0, [80, 84, 0]), (90, [80, 76, 0]), (op, [80, 84, 0])])
    top = {"ty": "gr", "it": [rect(88, 30, 9), stroke(FAINT, 4), group_tr(p=(0, -18))]}
    bottom = {"ty": "gr", "it": [rect(88, 30, 9), stroke(FAINT, 4), group_tr(p=(0, 18))]}
    blink = keys([(0, 100), (40, 100), (50, 20), (60, 100), (op, 100)])
    led1 = {"ty": "gr", "it": [ellipse(8), fill(ACCENT), group_tr(p=(-28, -18), o=blink)]}
    led2 = {"ty": "gr", "it": [ellipse(8), fill(FAINT), group_tr(p=(-28, 18))]}
    shadow = {"ty": "gr", "it": [rect(70, 6, 3), fill(LINE),
                                 group_tr(p=(0, 0), s=keys([(0, [100, 100]), (90, [80, 100]), (op, [100, 100])]))]}
    return animation("empty", 160, 160, op, [
        layer(1, "server", [led1, led2, top, bottom], op, transform(p=float_y)),
        layer(2, "shadow", [shadow], op, transform(p=(80, 136))),
    ])


ANIMATIONS = {
    "connecting": connecting(),
    "working": working(),
    "pass": verdict("pass", OK, [[[-20, 2], [-6, 16], [22, -14]]]),
    "fail": verdict("fail", BAD, [[[-16, -16], [16, 16]], [[16, -16], [-16, 16]]]),
    "empty": empty(),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, anim in ANIMATIONS.items():
        with open(os.path.join(OUT, f"{name}.json"), "w") as f:
            json.dump(anim, f, separators=(",", ":"))
    print(", ".join(sorted(ANIMATIONS)))
