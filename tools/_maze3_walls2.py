# -*- coding: utf-8 -*-
# 高清图框墙 v2：容差窗口内找最厚暗段（不要求与理论格线对齐），再看沿线覆盖率
import numpy as np
from PIL import Image, ImageDraw, ImageFont

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 110) & (g < 110) & (b < 110)
x0, cw = 586.0, 140.5
y0, ch = 155.0, 140.3


def thick_v(k, j):
    """竖段：沿 y 采样，每个 y 在 xx±16 窗口内找最厚水平连续暗段；返回(t>=5 的覆盖率)"""
    xx = int(x0 + k * cw)
    y1, y2 = int(y0 + j * ch) + 10, int(y0 + (j + 1) * ch) - 10
    xa, xb = max(0, xx - 16), min(W, xx + 16)
    hit = 0
    tot = 0
    for y in range(y1, y2, 4):
        line = black[y, xa:xb]
        best = cur = 0
        for v in line:
            if v:
                cur += 1
                best = max(best, cur)
            else:
                cur = 0
        tot += 1
        if best >= 5:
            hit += 1
    return hit / max(1, tot)


def thick_h(k, i):
    yy = int(y0 + k * ch)
    x1, x2 = int(x0 + i * cw) + 10, int(x0 + (i + 1) * cw) - 10
    ya, yb = max(0, yy - 16), min(H, yy + 16)
    hit = 0
    tot = 0
    for x in range(x1, x2, 4):
        line = black[ya:yb, x]
        best = cur = 0
        for v in line:
            if v:
                cur += 1
                best = max(best, cur)
            else:
                cur = 0
        tot += 1
        if best >= 5:
            hit += 1
    return hit / max(1, tot)


V = [[0.0] * 10 for _ in range(11)]
HH = [[0.0] * 10 for _ in range(11)]
for k in range(1, 10):
    for j in range(10):
        V[k][j] = thick_v(k, j)
for k in range(1, 10):
    for i in range(10):
        HH[k][i] = thick_h(k, i)

TH = 0.55
print('竖墙:')
for k in range(1, 10):
    s = ' '.join('r%d' % j for j in range(10) if V[k][j] > TH)
    if s:
        print('  c%d|c%d: %s' % (k - 1, k, s))
print('横墙:')
for k in range(1, 10):
    s = ' '.join('c%d' % i for i in range(10) if HH[k][i] > TH)
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
        if i < 9 and V[i + 1][j] <= TH:
            union(idx(i, j), idx(i + 1, j))
        if j < 9 and HH[j + 1][i] <= TH:
            union(idx(i, j), idx(i, j + 1))
regions = {}
for z in range(100):
    regions.setdefault(find(z), []).append((z % 10, z // 10))
print('\n连通区域数:', len(regions))
for n, cells in enumerate(sorted(regions.values(), key=lambda cs: -len(cs))):
    cells.sort(key=lambda c: (c[1], c[0]))
    print('  区%d (%d格): %s' % (n, len(cells), ' '.join('%d,%d' % c for c in cells)))

SCALE = 44
out = Image.new('RGB', (10 * SCALE + 60, 10 * SCALE + 60), (250, 248, 240))
dd = ImageDraw.Draw(out)
colors = [(255, 230, 200), (200, 230, 255), (220, 255, 220), (255, 220, 230),
          (240, 225, 255), (255, 245, 200), (205, 245, 240), (240, 240, 200),
          (230, 215, 245), (215, 235, 255), (255, 225, 215), (220, 250, 225)]
for n, cells in enumerate(sorted(regions.values(), key=lambda cs: -len(cs))):
    col = colors[n % len(colors)]
    for (i, j) in cells:
        x, y = 30 + i * SCALE, 30 + j * SCALE
        dd.rectangle([x, y, x + SCALE, y + SCALE], fill=col)
for i in range(10):
    for j in range(10):
        x, y = 30 + i * SCALE, 30 + j * SCALE
        dd.rectangle([x, y, x + SCALE, y + SCALE], outline=(190, 188, 180), width=1)
for k in range(1, 10):
    for j in range(10):
        if V[k][j] > TH:
            px = 30 + k * SCALE
            dd.line([(px, 30 + j * SCALE), (px, 30 + (j + 1) * SCALE)], fill=(0, 0, 0), width=6)
for k in range(1, 10):
    for i in range(10):
        if HH[k][i] > TH:
            py = 30 + k * SCALE
            dd.line([(30 + i * SCALE, py), (30 + (i + 1) * SCALE, py)], fill=(0, 0, 0), width=6)
dd.rectangle([30, 30, 30 + 10 * SCALE, 30 + 10 * SCALE], outline=(0, 0, 0), width=3)
reds = [(7, 0), (2, 1), (7, 3), (6, 3), (2, 5), (6, 8), (1, 9)]
blacks = [(8, 5), (6, 5), (7, 9)]
for (c, rr) in reds:
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    dd.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], outline=(0, 170, 70), width=2)
for (c, rr) in blacks:
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    dd.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], outline=(20, 50, 220), width=2)
out.save('_maze3_frames.png')
print('saved')
