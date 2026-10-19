# -*- coding: utf-8 -*-
# 逐段诊断 r1|r2、r2|r3、r3|r4 在 c5-c8 的最厚暗段
import numpy as np
from PIL import Image

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 110) & (g < 110) & (b < 110)
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3


def thick_h_band(k, i):
    yy = int(y0 + k * ch)
    x1, x2 = int(x0 + i * cw) + 10, int(x0 + (i + 1) * cw) - 10
    ya, yb = max(0, yy - 18), min(H, yy + 18)
    # 逐 y 行统计该段暗像素，找最厚的连续水平线段所在 y
    best = 0
    best_y = -1
    for y in range(ya, yb):
        line = black[y, x1:x2]
        run = cur = 0
        for v in line:
            if v:
                cur += 1
                run = max(run, cur)
            else:
                cur = 0
        if run > best:
            best = run
            best_y = y
    return best, best_y


for k in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
    for i in range(10):
        thick, by = thick_h_band(k, i)
        if thick >= 40:
            print('r%d|r%d c%d: 最厚水平暗段=%dpx (y=%d)' % (k - 1, k, i, thick, by))
