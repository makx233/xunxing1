# -*- coding: utf-8 -*-
# 高清图：精确网格定标 + 笔画宽度法识别黑框
import numpy as np
from PIL import Image, ImageDraw, ImageFont

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 110) & (g < 110) & (b < 110)

x0, cw = 586.0, 140.5
y0, ch = 155.0, 140.3


def widths_v(k, j):
    xx = int(x0 + k * cw)
    y1, y2 = int(y0 + j * ch) + 8, int(y0 + (j + 1) * ch) - 8
    ws = []
    for y in range(y1, y2, 4):
        L = 0
        for x in range(xx, max(xx - 12, 0) - 1, -1):
            if black[y, x]:
                L += 1
            else:
                break
        R = 0
        for x in range(xx + 1, min(xx + 12, W)):
            if black[y, x]:
                R += 1
            else:
                break
        ws.append(L + R)
    return ws


def widths_h(k, i):
    yy = int(y0 + k * ch)
    x1, x2 = int(x0 + i * cw) + 8, int(x0 + (i + 1) * cw) - 8
    ws = []
    for x in range(x1, x2, 4):
        U = 0
        for y in range(yy, max(yy - 12, 0) - 1, -1):
            if black[y, x]:
                U += 1
            else:
                break
        D = 0
        for y in range(yy + 1, min(yy + 12, H)):
            if black[y, x]:
                D += 1
            else:
                break
        ws.append(U + D)
    return ws


def med(vals):
    s = sorted(vals)
    return s[len(s) // 2]


def cover(vals, t):
    return sum(1 for v in vals if v >= t) / max(1, len(vals))


V = [[None] * 10 for _ in range(11)]
HH = [[None] * 10 for _ in range(11)]
for k in range(1, 10):
    for j in range(10):
        V[k][j] = widths_v(k, j)
for k in range(1, 10):
    for i in range(10):
        HH[k][i] = widths_h(k, i)

# 输出每段“宽度中位数>=5 的覆盖率”
print('=== 竖边（c{k-1}|c{k} 各 r 段）：宽度中位数>=5 的覆盖比例 ===')
for k in range(1, 10):
    cells = []
    for j in range(10):
        c = cover(V[k][j], 5)
        cells.append(c)
    print('k=%d: ' % k + ' '.join('%.2f' % c for c in cells))
print('=== 横边（r{k-1}|r{k} 各 c 段）===')
for k in range(1, 10):
    cells = []
    for i in range(10):
        c = cover(HH[k][i], 5)
        cells.append(c)
    print('k=%d: ' % k + ' '.join('%.2f' % c for c in cells))
