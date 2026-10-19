# -*- coding: utf-8 -*-
# 新图完整识别：红斜线（答案镜）+ 黑斜线（固定镜）+ 端口，输出标注图
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from collections import deque

im = Image.open('_maze_src2.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]

# 网格定标（从投影峰得到）
x0, y0, cw, ch = 280.0, 76.0, 67.0, 66.0


def cell_center(c, rw):
    return x0 + c * cw + cw / 2, y0 + rw * ch + ch / 2


def clusters_from(mask, min_size=15):
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


# ---------- 红斜线：红色掩膜，只取网格内部、斜向（bbox 近方）的簇 ----------
redm = (r > 130) & (r - g > 50) & (r - b > 50)
redcs = clusters_from(redm)
reds = []
for pts in redcs:
    ys = [p[0] for p in pts]
    xs = [p[1] for p in pts]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    if not (x0 - 10 < cx < x0 + 10 * cw + 10 and y0 - 10 < cy < y0 + 10 * ch + 10):
        continue
    wd, ht = max(xs) - min(xs), max(ys) - min(ys)
    if wd < 8 or ht < 8:
        continue
    if not (0.4 < wd / ht < 2.5):
        continue
    reds.append((cx, cy, wd, ht))
reds.sort(key=lambda t: (t[1], t[0]))
print('红斜线簇 %d 个：' % len(reds))
for cx, cy, wd, ht in reds:
    c = int(round((cx - x0) / cw - 0.5))
    rr = int(round((cy - y0) / ch - 0.5))
    print('  (%4d,%4d) w%d h%d -> c%d r%d' % (cx, cy, wd, ht, c, rr))

# ---------- 黑斜线：暗像素掩膜 - 网格线，取内部斜向簇 ----------
darkm = (r < 140) & (g < 140) & (b < 140)
# 去掉网格线（横向/纵向长条）：线宽约2px，位置在网格边界
lines = np.zeros((H, W), bool)
for k in range(11):
    yy = int(y0 + k * ch)
    lines[max(0, yy - 2):yy + 3, :] = True
    xx = int(x0 + k * cw)
    lines[:, max(0, xx - 2):xx + 3] = True
body = darkm & ~lines
# 去掉很靠近边缘的文字区：只在网格内部
body[:int(y0) - 6, :] = False
body[int(y0 + 10 * ch) + 6:, :] = False
body[:, :int(x0) - 6] = False
body[:, int(x0 + 10 * cw) + 6:] = False
blackcs = clusters_from(body, min_size=20)
blacks = []
for pts in blackcs:
    ys = [p[0] for p in pts]
    xs = [p[1] for p in pts]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    wd, ht = max(xs) - min(xs), max(ys) - min(ys)
    if wd < 9 or ht < 9:
        continue
    # 主轴斜率：比较对角线方向密度
    d1 = d2 = 0
    for yy, xx in pts:
        dxv, dyv = xx - cx, yy - cy
        d1 += abs(dxv - dyv)   # 沿 \ 方向（主对角线）
        d2 += abs(dxv + dyv)   # 沿 / 方向
    if d1 < d2:
        ori = '\\'
    else:
        ori = '/'
    blacks.append((cx, cy, wd, ht, ori))
blacks.sort(key=lambda t: (t[1], t[0]))
print('黑斜线簇 %d 个：' % len(blacks))
for cx, cy, wd, ht, ori in blacks:
    c = int(round((cx - x0) / cw - 0.5))
    rr = int(round((cy - y0) / ch - 0.5))
    print('  (%4d,%4d) w%d h%d %s -> c%d r%d' % (cx, cy, wd, ht, ori, c, rr))
