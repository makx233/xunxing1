# -*- coding: utf-8 -*-
# 用"格间墙检测 + 连通区域分割"照画稿重建黑框
# 1) 统计每条内边的暗度（不扣细格线，只数非常暗的像素）
# 2) 找暗度两档（细铅笔基线 vs 粗黑墙）
# 3) 墙两侧格子不连通 → 连通分量 = 框
import numpy as np
from PIL import Image, ImageDraw, ImageFont

im = Image.open('_maze_src2.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
x0, y0, cw, ch = 280.0, 76.0, 67.0, 66.0
verydark = (r < 160) & (g < 160) & (b < 160)


def seg_v(k, j, w=5):
    xx = int(x0 + k * cw)
    y1, y2 = int(y0 + j * ch) + 5, int(y0 + (j + 1) * ch) - 5
    xa, xb = max(0, xx - w), min(W, xx + w)
    return int(verydark[y1:y2, xa:xb].sum())


def seg_h(k, i, w=5):
    yy = int(y0 + k * ch)
    x1, x2 = int(x0 + i * cw) + 5, int(x0 + (i + 1) * cw) - 5
    ya, yb = max(0, yy - w), min(H, yy + w)
    return int(verydark[ya:yb, x1:x2].sum())


# 竖内边 V[k][j]：k=1..9（c{k-1}|c{k}）
V = [[0] * 10 for _ in range(11)]
HH = [[0] * 10 for _ in range(11)]
for k in range(1, 10):
    for j in range(10):
        V[k][j] = seg_v(k, j)
for k in range(1, 10):
    for i in range(10):
        HH[k][i] = seg_h(k, i)

vals = [V[k][j] for k in range(1, 10) for j in range(10)] + \
       [HH[k][i] for k in range(1, 10) for i in range(10)]
vals.sort()
print('内边暗度分位:', ' '.join('%d' % vals[q] for q in [0, 10, 25, 50, 75, 90, 100, 120, 140, 160, 179]))
# 简单两档阈值
import collections
hist = collections.Counter(v // 25 * 25 for v in vals)
for bucket in sorted(hist):
    print('  暗度 %d-%d: %d 段' % (bucket, bucket + 24, hist[bucket]))

print('\n竖边(>120):')
for k in range(1, 10):
    s = ' '.join('r%d' % j for j in range(10) if V[k][j] > 120)
    if s:
        print('  c%d|c%d: %s' % (k - 1, k, s))
print('横边(>120):')
for k in range(1, 10):
    s = ' '.join('c%d' % i for i in range(10) if HH[k][i] > 120)
    if s:
        print('  r%d|r%d: %s' % (k - 1, k, s))

TH = 120
# 连通区域
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

# 渲染
SCALE = 42
out = Image.new('RGB', (10 * SCALE + 60, 10 * SCALE + 60), (250, 248, 240))
dd = ImageDraw.Draw(out)
try:
    font = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 12)
except Exception:
    font = ImageFont.load_default()
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
# 墙
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
out.save('_maze_frames_div.png')
print('saved _maze_frames_div.png')
