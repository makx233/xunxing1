# -*- coding: utf-8 -*-
# 核对 R2 (2,1)/ 和 R5 (2,5)\
from PIL import Image
im = Image.open('_maze_src3.jpg').convert('RGB')
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3


def crop_cells(c1, c2, r1, r2, name, scale=4):
    xa = int(x0 + c1 * cw)
    xb = int(x0 + (c2 + 1) * cw)
    ya = int(y0 + r1 * ch)
    yb = int(y0 + (r2 + 1) * ch)
    im2 = im.crop((xa, ya, xb, yb))
    im2 = im2.resize((int((xb - xa) * scale), int((yb - ya) * scale)), Image.LANCZOS)
    im2.save(name)
    print(name, im2.size)


crop_cells(1, 3, 1, 1, '_maze3_r2.png')   # R2
crop_cells(1, 3, 5, 5, '_maze3_r5l.png')  # R5
