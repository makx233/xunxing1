# -*- coding: utf-8 -*-
import numpy as np
from PIL import Image
from collections import deque

im = Image.open('_maze_src.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
lum = (r * 0.3 + g * 0.59 + b * 0.11)
red = (r > 140) & (r - g > 50) & (r - b > 50)
dark = (lum < 165)
v = 8
colcum = np.cumsum(dark.astype(np.int16), axis=0)
rows = np.arange(H)
top = np.clip(rows[:, None] - v, 0, H - 1)
bot = np.clip(rows[:, None] + v + 1, 1, H)
vline = (colcum[bot[:, 0] - 1] - colcum[top[:, 0]]) > 2 * v * 0.42
rowcum = np.cumsum(dark.astype(np.int16), axis=1)
cols = np.arange(W)
lf = np.clip(cols[None, :] - v, 0, W - 1)
rt = np.clip(cols[None, :] + v + 1, 1, W)
hline = (rowcum[:, rt[0, :] - 1] - rowcum[:, lf[0, :]]) > 2 * v * 0.42
gridlines = vline | hline
black = dark & ~gridlines & ~red


def clusters(mask, min_size=15):
    vis = np.zeros((H, W), bool)
    out = []
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not vis[y, x]:
                q = deque([(y, x)])
                vis[y, x] = True
                pts = []
                while q:
                    yy, xx = q.popleft()
                    pts.append((yy, xx))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = yy + dy, xx + dx
                            if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not vis[ny, nx]:
                                vis[ny, nx] = True
                                q.append((ny, nx))
                if len(pts) >= min_size:
                    out.append(pts)
    return out


def orient(pts):
    ys = np.array([p[0] for p in pts], float)
    xs = np.array([p[1] for p in pts], float)
    cy, cx = ys.mean(), xs.mean()
    syy = ((ys - cy) ** 2).sum()
    sxx = ((xs - cx) ** 2).sum()
    sxy = ((xs - cx) * (ys - cy)).sum()
    ang = 0.5 * np.arctan2(2 * sxy, sxx - syy)
    return cx, cy, np.degrees(ang)


print('=== 网格内黑色斜线（dark<165）===')
n = 0
for i, pts in enumerate(sorted(clusters(black), key=lambda p: p[0][0])):
    cx, cy, ang = orient(pts)
    in_grid = 100 < cx < 880 and 275 < cy < 1010
    tag = '[网格内]' if in_grid else ''
    print('黑%d: 中心(%d,%d) 主轴%.0f 大小%d %s' % (i, int(cx), int(cy), ang, len(pts), tag))
    if in_grid:
        n += 1
print('网格内黑斜线簇数:', n)
