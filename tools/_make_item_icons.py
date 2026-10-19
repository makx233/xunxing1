# -*- coding: utf-8 -*-
"""重新生成物件图标：三张参考图本就是透明背景 PNG，只需裁切 + 缩放"""
import os
from PIL import Image

SRC = r"D:\62503\桌面\寻星_2026-10-16_10-38-27\-2026gamejam--main\tools\_tmp_refs"
DST = r"D:\62503\桌面\寻星_2026-10-16_10-38-27\-2026gamejam--main\assets\props"

TASKS = [
    ("star.png", "paper_star.png"),
    ("phone.png", "phone.png"),
    ("box.png", "black_box.png"),
]


def crop_and_fit(img, long_side=300, pad_ratio=0.02):
    img = img.convert("RGBA")
    a = img.split()[3]
    bbox = a.point(lambda v: 255 if v > 12 else 0).getbbox()
    if bbox is None:
        return img
    pad = max(2, int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * pad_ratio))
    l, t, r, b = bbox
    img = img.crop((max(0, l - pad), max(0, t - pad), r + pad, b + pad))
    w, h = img.size
    k = long_side / max(w, h)
    if k < 1.0:
        img = img.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
    return img


for src, dst in TASKS:
    img = Image.open(os.path.join(SRC, src))
    print("== %s 原始 %s" % (src, img.size))
    out = crop_and_fit(img)
    a = out.split()[3]
    nz = sum(1 for v in a.getdata() if v > 16)
    total = a.width * a.height
    out.save(os.path.join(DST, dst))
    print("   -> %s %s 主体占比 %.1f%%" % (dst, out.size, 100.0 * nz / total))
print("done")
