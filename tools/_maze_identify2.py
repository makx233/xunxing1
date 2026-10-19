# -*- coding: utf-8 -*-
# 生成新图标注图：网格 + 红斜线（答案镜）+ 黑斜线（固定镜候选）+ 端口
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from collections import deque

im = Image.open('_maze_src2.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
draw = ImageDraw.Draw(im)

x0, y0, cw, ch = 280.0, 76.0, 67.0, 66.0

try:
    f = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 15)
    fb = ImageFont.truetype(r'C:\Windows\Fonts\msyhbd.ttc', 15)
except Exception:
    f = ImageFont.load_default()
    fb = f


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


def ori_of(pts, cx, cy):
    d1 = d2 = 0
    for yy, xx in pts:
        dxv, dyv = xx - cx, yy - cy
        d1 += abs(dxv - dyv)
        d2 += abs(dxv + dyv)
    return '\\' if d1 < d2 else '/'


def cell_of(cx, cy):
    return int(round((cx - x0) / cw - 0.5)), int(round((cy - y0) / ch - 0.5))


# ---- 画网格 ----
for k in range(11):
    x = int(x0 + k * cw)
    draw.line([(x, int(y0)), (x, int(y0 + 10 * ch))], fill=(60, 160, 255), width=1)
    if k < 10:
        draw.text((x + 24, int(y0) - 18), 'c%d' % k, fill=(60, 160, 255), font=f)
for k in range(11):
    y = int(y0 + k * ch)
    draw.line([(int(x0), y), (int(x0 + 10 * cw), y)], fill=(60, 160, 255), width=1)
    if k < 10:
        draw.text((int(x0) - 30, y + 22), 'r%d' % k, fill=(60, 160, 255), font=f)

# ---- 红斜线（答案镜） ----
redm = (r > 130) & (r - g > 50) & (r - b > 50)
redcs = clusters_from(redm)
reds = []
for pts in redcs:
    ys = [p[0] for p in pts]
    xs = [p[1] for p in pts]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    if not (x0 - 12 < cx < x0 + 10 * cw + 12 and y0 - 12 < cy < y0 + 10 * ch + 12):
        continue
    wd, ht = max(xs) - min(xs), max(ys) - min(ys)
    if wd < 12 or ht < 12:
        continue
    if not (0.4 < wd / ht < 2.5):
        continue
    reds.append((cx, cy, wd, ht, ori_of(pts, cx, cy)))
reds.sort(key=lambda t: (t[1], t[0]))
# 合并同格簇（保留大的）；R4 这类小残片若与同格大簇合并则自然消失
merged = {}
for cx, cy, wd, ht, o in reds:
    key = cell_of(cx, cy)
    if key not in merged or wd * ht > merged[key][2] * merged[key][3]:
        merged[key] = (cx, cy, wd, ht, o)
reds = sorted(merged.values(), key=lambda t: (t[1], t[0]))
print('红斜线（答案镜）最终 %d 处：' % len(reds))
for i, (cx, cy, wd, ht, o) in enumerate(reds, 1):
    c, rr = cell_of(cx, cy)
    print('  R%d (%4d,%4d) w%d h%d %s -> c%d r%d' % (i, cx, cy, wd, ht, o, c, rr))
    draw.ellipse([cx - 15, cy - 15, cx + 15, cy + 15], outline=(0, 180, 80), width=3)
    draw.text((cx + 9, cy - 22), 'R%d %s' % (i, o), fill=(0, 180, 80), font=fb)

# ---- 黑斜线（固定镜候选） ----
darkm = (r < 140) & (g < 140) & (b < 140)
lines = np.zeros((H, W), bool)
for k in range(11):
    yy = int(y0 + k * ch)
    lines[max(0, yy - 3):yy + 4, :] = True
    xx = int(x0 + k * cw)
    lines[:, max(0, xx - 3):xx + 4] = True
body = darkm & ~lines
body[:int(y0) - 8, :] = False
body[int(y0 + 10 * ch) + 8:, :] = False
body[:, :int(x0) - 8] = False
body[:, int(x0 + 10 * cw) + 8:] = False
blackcs = clusters_from(body, min_size=30)
bm = {}
for pts in blackcs:
    ys = [p[0] for p in pts]
    xs = [p[1] for p in pts]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    wd, ht = max(xs) - min(xs), max(ys) - min(ys)
    # 只要完整的 45° 斜线：宽高都接近一格、比例接近 1
    if wd < 38 or ht < 38:
        continue
    if not (0.65 < wd / ht < 1.55):
        continue
    o = ori_of(pts, cx, cy)
    key = cell_of(cx, cy)
    if key not in bm or wd * ht > bm[key][2] * bm[key][3]:
        bm[key] = (cx, cy, wd, ht, o)
blacks = sorted(bm.values(), key=lambda t: (t[1], t[0]))
# 用户修正：r1/r4/r7 无黑斜线；r9 只有红字(c7)上方一处；c6r8/c1r9 的黑检是红斜线误检
KEEP_B = {(8, 5), (6, 5), (7, 9)}
print('黑斜线（固定镜候选）最终 %d 处：' % len(blacks))
shown = 0
for i, (cx, cy, wd, ht, o) in enumerate(blacks, 1):
    c, rr = cell_of(cx, cy)
    if (c, rr) not in KEEP_B:
        print('  B%d (%4d,%4d) w%d h%d %s -> c%d r%d（已按用户修正剔除）' % (i, cx, cy, wd, ht, o, c, rr))
        continue
    shown += 1
    print('  B%d (%4d,%4d) w%d h%d %s -> c%d r%d ✓' % (i, cx, cy, wd, ht, o, c, rr))
    draw.ellipse([cx - 13, cy - 13, cx + 13, cy + 13], outline=(30, 60, 220), width=3)
    draw.text((cx + 9, cy - 20), 'B%d %s' % (i, o), fill=(30, 60, 220), font=fb)
print('保留固定镜 %d 处' % shown)

# ---- 端口（边缘色字） ----
def mask_of(color):
    if color == 'red':
        return (r > 120) & (r - g > 40) & (r - b > 40)
    if color == 'orange':
        return (r > 130) & (g > 70) & (b < 110) & (r - b > 60) & (r - g > 30)
    if color == 'yellow':
        return (r > 140) & (g > 120) & (b < 120) & (r - b > 40) & (g - b > 30)
    if color == 'green':
        return (g > 120) & (g - r > 40) & (g - b > 40)
    if color == 'blue':
        return (b > 120) & (b - r > 50) & (b - g > 30)
    if color == 'purple':
        return (r > 110) & (b > 110) & (g < 110) & (r - g > 40) & (b - g > 40)
    raise ValueError(color)

for col in ['red', 'orange', 'yellow', 'green', 'blue', 'purple']:
    m = mask_of(col)
    cs = clusters_from(m, min_size=12)
    for pts in cs:
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
        side = '?'
        if cy < y0 - 12:
            side = '顶'
        elif cy > y0 + 10 * ch + 12:
            side = '底'
        elif cx < x0 - 12:
            side = '左'
        elif cx > x0 + 10 * cw + 12:
            side = '右'
        else:
            continue
        pos = ''
        if side in ('顶', '底'):
            pos = 'c%d' % int(round((cx - x0) / cw - 0.5))
        else:
            pos = 'r%d' % int(round((cy - y0) / ch - 0.5))
        draw.rectangle([min(xs) - 6, min(ys) - 6, max(xs) + 6, max(ys) + 6],
                       outline=(200, 120, 0), width=3)
        draw.text((min(xs) - 4, min(ys) - 22), '%s %s %s' % (col, side, pos),
                  fill=(200, 120, 0), font=fb)
        print('%s %s %s (%d,%d)' % (col, side, pos, cx, cy))

im.save('_maze_identify3.png')
print('saved _maze_identify3.png')
