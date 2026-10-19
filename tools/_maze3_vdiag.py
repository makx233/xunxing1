# -*- coding: utf-8 -*-
# 竖墙水平厚度：在真实竖线 x 附近，连续多少列在该段内有>=70暗像素
import numpy as np
from PIL import Image

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 110) & (g < 110) & (b < 110)
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3


def hthickness(k, j, xc):
    y1, y2 = int(y0 + j * ch) + 12, int(y0 + (j + 1) * ch) - 12
    lf = 0
    for x in range(xc, xc - 20, -1):
        if int(black[y1:y2, x].sum()) >= 70:
            lf += 1
        else:
            break
    rt = 0
    for x in range(xc + 1, xc + 20):
        if int(black[y1:y2, x].sum()) >= 70:
            rt += 1
        else:
            break
    return lf + rt


print('竖墙水平厚度（>=5 粗墙）:')
for k in range(1, 10):
    xt = int(x0 + k * cw)
    row = []
    for j in range(10):
        y1, y2 = int(y0 + j * ch) + 12, int(y0 + (j + 1) * ch) - 12
        bestx, bestc = xt, -1
        for x in range(xt - 18, xt + 18):
            c = int(black[y1:y2, x].sum())
            if c > bestc:
                bestc, bestx = c, x
        t = hthickness(k, j, bestx)
        row.append('r%d:%d' % (j, t))
    print('  c%d|c%d: %s' % (k - 1, k, ' '.join(row)))
