# -*- coding: utf-8 -*-
# 干净版：黑框墙检测 + BFS 分区 + 斜线/端口检测
import numpy as np
from PIL import Image, ImageDraw

im = Image.open('_maze_src4.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 80) & (g < 80) & (b < 80)
red = (r > 180) & (g < 90) & (b < 90)
x0, cw, y0, ch = 208.0, 90.2, 113.0, 90.1


def vwall(k, j):
    """竖段 c{k-1}|c{k} r{j}：沿中心线 ±4 统计黑色列覆盖"""
    xx = int(round(x0 + k * cw))
    y1 = int(round(y0 + j * ch)) + 6
    y2 = int(round(y0 + (j + 1) * ch)) - 6
    # 该段任意一列黑像素占比 > 0.72 视为墙
    best = 0.0
    for x in range(xx - 4, xx + 5):
        col = black[y1:y2, x]
        frac = col.mean()
        best = max(best, frac)
    return best


def hwall(k, i):
    yy = int(round(y0 + k * ch))
    x1 = int(round(x0 + i * cw)) + 6
    x2 = int(round(x0 + (i + 1) * cw)) - 6
    best = 0.0
    for y in range(yy - 4, yy + 5):
        row = black[y, x1:x2]
        frac = row.mean()
        best = max(best, frac)
    return best


V = [[False] * 10 for _ in range(11)]
HH = [[False] * 10 for _ in range(11)]
for k in range(1, 10):
    for j in range(10):
        V[k][j] = vwall(k, j) > 0.72
for k in range(1, 10):
    for i in range(10):
        HH[k][i] = hwall(k, i) > 0.72

print('竖墙:')
for k in range(1, 10):
    s = ' '.join('r%d' % j for j in range(10) if V[k][j])
    if s:
        print('  c%d|c%d: %s' % (k - 1, k, s))
print('横墙:')
for k in range(1, 10):
    s = ' '.join('c%d' % i for i in range(10) if HH[k][i])
    if s:
        print('  r%d|r%d: %s' % (k - 1, k, s))

parent = list(range(100))


def find(z):
    while parent[z] != z:
        parent[z] = parent[parent[z]]
        z = parent[z]
    return z


def union(p, q):
    rp, rq = find(p), find(q)
    if rp != rq:
        parent[rp] = rq


def idx(c, rr):
    return rr * 10 + c


for i in range(10):
    for j in range(10):
        if i < 9 and not V[i + 1][j]:
            union(idx(i, j), idx(i + 1, j))
        if j < 9 and not HH[j + 1][i]:
            union(idx(i, j), idx(i, j + 1))
regions = {}
for z in range(100):
    regions.setdefault(find(z), []).append((z % 10, z // 10))
print('\n连通区域数:', len(regions))
for n, cells in enumerate(sorted(regions.values(), key=lambda cs: -len(cs))):
    cells.sort(key=lambda c: (c[1], c[0]))
    print('  区%d (%d格): %s' % (n, len(cells), ' '.join('%d,%d' % c for c in cells)))
