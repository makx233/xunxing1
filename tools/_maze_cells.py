# -*- coding: utf-8 -*-
# 逐格分析：红斜线/黑斜线/空，输出 10x10 地图
import numpy as np
from PIL import Image

im = Image.open('_maze_src.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
lum = (r * 0.3 + g * 0.59 + b * 0.11)
red = (r > 140) & (r - g > 50) & (r - b > 50)
blueline = (b - np.maximum(r, g)) > 30  # 纸面蓝色横线
dark = (lum < 150) & ~blueline

x0, y0, cw, ch = 90, 280, 80.0, 73.0


def cell_analysis(c, rr):
    # 格子内部 70% 区域（避开网格线）
    xa = int(x0 + c * cw + cw * 0.15)
    xb = int(x0 + c * cw + cw * 0.85)
    ya = int(y0 + rr * ch + ch * 0.15)
    yb = int(y0 + rr * ch + ch * 0.85)
    if xb <= xa or yb <= ya:
        return None
    rd = red[ya:yb, xa:xb].sum()
    dk = dark[ya:yb, xa:xb].sum()
    total = (xb - xa) * (yb - ya)
    # 方向：暗/红像素沿主对角线(n1)还是反对角线(n2)
    def diag_dist(mask):
        ys, xs = np.where(mask)
        if len(ys) < 8:
            return (0, 0)
        # 格内归一化
        nx = (xs + 0.5) / (xb - xa)
        ny = (ys + 0.5) / (yb - ya)
        d1 = np.abs(nx - ny)  # 主对角线
        d2 = np.abs(nx + ny - 1)  # 反对角线
        n1 = (d1 < 0.22).sum()
        n2 = (d2 < 0.22).sum()
        return (n1, n2)
    n1d, n2d = diag_dist(dark[ya:yb, xa:xb])
    n1r, n2r = diag_dist(red[ya:yb, xa:xb])
    return (rd, dk, total, n1d, n2d, n1r, n2r)


print('每格: 红px/暗px | 黑斜线方向 | 红斜线方向')
for rr in range(10):
    line = []
    for c in range(10):
        ca = cell_analysis(c, rr)
        if ca is None:
            line.append('  ?  ')
            continue
        rd, dk, total, n1d, n2d, n1r, n2r = ca
        tag = '·'
        if rd > 25:
            tag = 'R' + ('\\' if n1r > n2r else '/')
        elif dk > 30:
            tag = 'K' + ('\\' if n1d > n2d else '/')
        else:
            tag = '空'
        line.append('%s(%d,%d)' % (tag, rd, dk))
    print('r%d: %s' % (rr, ' '.join(line)))
