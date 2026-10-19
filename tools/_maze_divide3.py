# -*- coding: utf-8 -*-
# 墙检测 v3：笔画宽度特征
# 沿边界方向逐采样点，量垂直于边界的暗像素连续宽度；粗墙=多数点宽度>=4 且连续
import numpy as np
from PIL import Image, ImageDraw, ImageFont

im = Image.open('_maze_src2.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
x0, y0, cw, ch = 280.0, 76.0, 67.0, 66.0
dark = (r < 140) & (g < 140) & (b < 140)


def widths_v(k, j):
    """竖段：沿 y 采样，每个 y 量 xx 附近暗像素的水平连续宽度（以 xx 为中心）"""
    xx = int(x0 + k * cw)
    y1, y2 = int(y0 + j * ch) + 6, int(y0 + (j + 1) * ch) - 6
    ws = []
    for y in range(y1, y2, 3):
        # 从 xx 向左右扩展连续暗像素
        L = 0
        for x in range(xx, max(xx - 10, 0) - 1, -1):
            if dark[y, x]:
                L += 1
            else:
                break
        R = 0
        for x in range(xx + 1, min(xx + 10, W)):
            if dark[y, x]:
                R += 1
            else:
                break
        ws.append(L + R)
    return ws


def widths_h(k, i):
    yy = int(y0 + k * ch)
    x1, x2 = int(x0 + i * cw) + 6, int(x0 + (i + 1) * cw) - 6
    ws = []
    for x in range(x1, x2, 3):
        U = 0
        for y in range(yy, max(yy - 10, 0) - 1, -1):
            if dark[y, x]:
                U += 1
            else:
                break
        D = 0
        for y in range(yy + 1, min(yy + 10, H)):
            if dark[y, x]:
                D += 1
            else:
                break
        ws.append(U + D)
    return ws


def wall_score(ws):
    if not ws:
        return 0.0
    thick = sum(1 for w in ws if w >= 4)
    return thick / len(ws)


V = [[0.0] * 10 for _ in range(11)]
HH = [[0.0] * 10 for _ in range(11)]
for k in range(1, 10):
    for j in range(10):
        V[k][j] = wall_score(widths_v(k, j))
for k in range(1, 10):
    for i in range(10):
        HH[k][i] = wall_score(widths_h(k, i))

vals = sorted([V[k][j] for k in range(1, 10) for j in range(10)] +
              [HH[k][i] for k in range(1, 10) for i in range(10)])
print('粗墙分位:', ' '.join('%.2f' % vals[q] for q in [0, 20, 40, 60, 80, 100, 120, 140, 160, 179]))

TH = 0.55
print('\n竖墙:')
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
    print('  区%d (%d格)' % (n, len(cells)))

SCALE = 42
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
            dd.line([(px, 30 + j * SCALE), (px, 30 + (j + 1) * SCALE)], fill=(0, 0, 0), width=5)
for k in range(1, 10):
    for i in range(10):
        if HH[k][i] > TH:
            py = 30 + k * SCALE
            dd.line([(30 + i * SCALE, py), (30 + (i + 1) * SCALE, py)], fill=(0, 0, 0), width=5)
dd.rectangle([30, 30, 30 + 10 * SCALE, 30 + 10 * SCALE], outline=(0, 0, 0), width=3)
reds = [(7, 0), (2, 1), (7, 3), (6, 3), (2, 5), (6, 8), (1, 9)]
blacks = [(8, 5), (6, 5), (7, 9)]
for (c, rr) in reds:
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    dd.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], outline=(0, 170, 70), width=2)
for (c, rr) in blacks:
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    dd.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], outline=(20, 50, 220), width=2)
out.save('_maze_frames_v3.png')
print('saved')
