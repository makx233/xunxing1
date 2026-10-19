# -*- coding: utf-8 -*-
# 裁高清图右上 r0-r3 c5-c9 和 r1-r6 c6-c9 放大
from PIL import Image
im = Image.open('_maze_src3.jpg').convert('RGB')
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3

def crop_cells(c1, c2, r1, r2, name, scale=3):
    xa = int(x0 + c1 * cw)
    xb = int(x0 + (c2 + 1) * cw)
    ya = int(y0 + r1 * ch)
    yb = int(y0 + (r2 + 1) * ch)
    im2 = im.crop((xa, ya, xb, yb))
    im2 = im2.resize((int((xb - xa) * scale), int((yb - ya) * scale)), Image.LANCZOS)
    im2.save(name)
    print(name, im2.size)

crop_cells(4, 9, 0, 2, '_maze3_rt_top.png')   # 右上 r0-r2
crop_cells(6, 9, 1, 6, '_maze3_rt_mid.png')   # 右侧 r1-r6
