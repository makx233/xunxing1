# -*- coding: utf-8 -*-
# 精确裁 r5 行 c5-c9（两条黑斜线），r8-r9 行 c5-c8（R6红、B3黑），放大 4x
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

crop_cells(5, 9, 5, 5, '_maze3_r5.png')   # r5 行两条黑斜线
crop_cells(0, 3, 9, 9, '_maze3_r9l.png')  # r9 左 R7 红
crop_cells(5, 8, 8, 9, '_maze3_rbr.png')  # r8-r9 中下 R6、B3
