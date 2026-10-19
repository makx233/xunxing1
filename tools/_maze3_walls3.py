# -*- coding: utf-8 -*-
# v3：统一厚度判据（横=垂直厚度，竖=水平厚度），窗口±26 容差，BFS 分区
import numpy as np
from PIL import Image, ImageDraw

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 110) & (g < 110) & (b < 110)
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3
TOL = 26
DARK = 70
THICK = 5


def h_thick(k, i):
    """横边 r{k-1}|r{k} 的 c{i} 段：垂直厚度"""
    yt = int(y0 + k * ch)
    x1, x2 = int(x0 + i * cw) + 12, int(x0 + (i + 1) * cw) - 12
    besty, bestc = yt, -1
    for y in range(yt - TOL, yt + TOL):
        if y < 0 or y >= H:
            continue
        c = int(black[y, x1:x2].sum())
        if c > bestc:
            bestc, besty = c, y
    if bestc < DARK:
        return 0
    up = 0
    for y in range(besty, besty - TOL - 1, -1):
        if y >= 0 and int(black[y, x1:x2].sum()) >= DARK:
            up += 1
        else:
            break
    dn = 0
    for y in range(besty + 1, besty + TOL + 1):
        if y < H and int(black[y, x1:x2].sum()) >= DARK:
            dn += 1
        else:
            break
    return up + dn


def v_thick(k, j):
    """竖边 c{k-1}|c{k} 的 r{j} 段：水平厚度"""
    xt = int(x0 + k * cw)
    y1, y2 = int(y0 + j * ch) + 12, int(y0 + (j + 1) * ch) - 12
    bestx, bestc = xt, -1
    for x in range(xt - TOL, xt + TOL):
        if x < 0 or x >= W:
            continue
        c = int(black[y1:y2, x].sum())
        if c > bestc:
            bestc, bestx = c, x
    if bestc < DARK:
        return 0
    lf = 0
    for x in range(bestx, bestx - TOL - 1, -1):
        if x >= 0 and int(black[y1:y2, x].sum()) >= DARK:
            lf += 1
        else:
            break
    rt = 0
    for x in range(bestx + 1, bestx + TOL + 1):
        if x < W and int(black[y1:y2, x].sum()) >= DARK:
            rt += 1
        else:
            break
    return lf + rt


V = [[False] * 10 for _ in range(11)]
HH = [[False] * 10 for _ in range(11)]
for k in range(1, 10):
    for j in range(10):
        V[k][j] = v_thick(k, j) >= THICK
for k in range(1, 10):
    for i in range(10):
        HH[k][i] = h_thick(k, i) >= THICK

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

mirrors = {(7, 0): 'R1', (2, 1): 'R2', (7, 3): 'R3', (6, 3): 'R4', (2, 5): 'R5',
           (6, 8): 'R6', (1, 9): 'R7', (8, 5): 'B2', (6, 5): 'B1', (7, 9): 'B3'}
print('\n连通区域数:', len(regions))
multi = 0
frames_out = []
for n, cells in enumerate(sorted(regions.values(), key=lambda cs: -len(cs))):
    cells.sort(key=lambda c: (c[1], c[0]))
    ms = [mirrors[c] for c in cells if c in mirrors]
    flag = '  <<< 多镜!' if len(ms) > 1 else ('  (无镜)' if not ms else '')
    if len(ms) > 1:
        multi += 1
    print('  区%d (%d格): 镜%s%s' % (n, len(cells), ','.join(ms) if ms else '-', flag))
    print('      %s' % ' '.join('%d,%d' % c for c in cells))
    frames_out.append((ms[0] if ms else '-', cells))

# 可视化
SCALE = 46
out = Image.new('RGB', (10 * SCALE + 60, 10 * SCALE + 60), (250, 248, 240))
dd = ImageDraw.Draw(out)
colors = [(255, 230, 200), (200, 230, 255), (220, 255, 220), (255, 220, 230),
          (240, 225, 255), (255, 245, 200), (205, 245, 240), (240, 240, 200),
          (230, 215, 245), (215, 235, 255), (255, 225, 215), (220, 250, 225)]
for n, cells in enumerate(sorted(regions.values(), key=lambda cs: -len(cs))):
    col = colors[n % len(colors)]
    for (i, j) in cells:
        dd.rectangle([30 + i * SCALE, 30 + j * SCALE, 30 + (i + 1) * SCALE, 30 + (j + 1) * SCALE], fill=col)
for i in range(10):
    for j in range(10):
        dd.rectangle([30 + i * SCALE, 30 + j * SCALE, 30 + (i + 1) * SCALE, 30 + (j + 1) * SCALE], outline=(200, 198, 190), width=1)
for k in range(1, 10):
    for j in range(10):
        if V[k][j]:
            dd.line([(30 + k * SCALE, 30 + j * SCALE), (30 + k * SCALE, 30 + (j + 1) * SCALE)], fill=(0, 0, 0), width=6)
for k in range(1, 10):
    for i in range(10):
        if HH[k][i]:
            dd.line([(30 + i * SCALE, 30 + k * SCALE), (30 + (i + 1) * SCALE, 30 + k * SCALE)], fill=(0, 0, 0), width=6)
dd.rectangle([30, 30, 30 + 10 * SCALE, 30 + 10 * SCALE], outline=(0, 0, 0), width=3)
for (c, rr), name in mirrors.items():
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    col = (0, 150, 60) if name.startswith('R') else (20, 50, 220)
    dd.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], outline=col, width=2)
out.save('_maze3_frames.png')
print('多镜区域数:', multi)
