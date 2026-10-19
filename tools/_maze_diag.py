# -*- coding: utf-8 -*-
# 斜线检测：不依赖格子边界，用 45°/135° 游程找斜线段，区分红/黑
import numpy as np
from PIL import Image
from collections import deque

im = Image.open('_maze_src.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
lum = (r * 0.3 + g * 0.59 + b * 0.11)
red = (r > 140) & (r - g > 50) & (r - b > 50)
dark = lum < 150

# 只处理网格区，减少噪声
mask = np.zeros((H, W), bool)
mask[270:1030, 80:900] = dark[270:1030, 80:900]

# 45° 游程（方向 dy=dx）：对每条主对角线扫描
minlen = 7


def diag_runs(arr, anti):
    # anti=False: 主对角线方向(右上->左下, dy=-1,dx=+1 等价 dy=+1,dx=-1 同一线)
    # anti=True: 反对角线方向 (dy=+1,dx=+1)
    out = np.zeros_like(arr, dtype=np.int16)
    h, w = arr.shape
    if not anti:
        # 沿 dx=+1, dy=+1 扫（反对角线组）
        for s in range(-(h - 1), w):
            y0 = max(0, -s)
            x0 = max(0, s)
            run = 0
            y, x = y0, x0
            while y < h and x < w:
                if arr[y, x]:
                    run += 1
                else:
                    run = 0
                if run >= minlen:
                    out[y, x] = run
                y += 1
                x += 1
    else:
        # 沿 dx=-1, dy=+1 扫（主对角线组）: 从每行第一列或每列最后一行开始
        # 简化为按反对角线: 起始 (y,0) 和 (0,x)
        for s in range(0, w + h - 1):
            y0 = max(0, s - (w - 1))
            x0 = min(s, w - 1)
            run = 0
            y, x = y0, x0
            while y < h and x >= 0:
                if arr[y, x]:
                    run += 1
                else:
                    run = 0
                if run >= minlen:
                    out[y, x] = run
                y += 1
                x -= 1
    return out


r45 = diag_runs(mask, anti=True)  # 反对角线带(像 '/')
r135 = diag_runs(mask, anti=False)  # 主对角线带(像 '\')
is_slash = r45 >= minlen  # '/'
is_back = r135 >= minlen  # '\'
both = is_slash & is_back
is_slash = is_slash & ~both
is_back = is_back & ~both


def clusters_idx(idx_mask, min_size=25):
    vis = np.zeros((H, W), bool)
    out = []
    ys, xs = np.where(idx_mask)
    for (y, x) in zip(ys, xs):
        if not vis[y, x]:
            q = deque([(y, x)])
            vis[y, x] = True
            pts = []
            while q:
                yy, xx = q.popleft()
                pts.append((yy, xx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = yy + dy, xx + dx
                        if 0 <= ny < H and 0 <= nx < W and idx_mask[ny, nx] and not vis[ny, nx]:
                            vis[ny, nx] = True
                            q.append((ny, nx))
            if len(pts) >= min_size:
                out.append(pts)
    return out


def summarize(pts, color_mask):
    ys = np.array([p[0] for p in pts], float)
    xs = np.array([p[1] for p in pts], float)
    cy, cx = ys.mean(), xs.mean()
    red_cnt = sum(1 for (yy, xx) in pts if red[yy, xx])
    return int(cx), int(cy), red_cnt, len(pts)


print('=== 反斜线 \\（主对角线，暗色）===')
for i, pts in enumerate(sorted(clusters_idx(is_back), key=lambda p: p[0][0])):
    cx, cy, rc, n = summarize(pts, red)
    tag = '红' if rc > n * 0.5 else '黑'
    print('%s%d: 中心(%d,%d) 红像素%d/%d' % (tag, i, cx, cy, rc, n))

print('=== 斜线 /（反对角线，暗色）===')
for i, pts in enumerate(sorted(clusters_idx(is_slash), key=lambda p: p[0][0])):
    cx, cy, rc, n = summarize(pts, red)
    tag = '红' if rc > n * 0.5 else '黑'
    print('%s%d: 中心(%d,%d) 红像素%d/%d' % (tag, i, cx, cy, rc, n))
