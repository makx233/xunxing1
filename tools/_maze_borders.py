# -*- coding: utf-8 -*-
# 提取画稿上的黑色大框边界（粗黑线）：暗像素 - 细网格线 - 3 个预设黑斜线
# 然后渲染成 10x10 网格图，框边界用粗线标出
import numpy as np
from PIL import Image, ImageDraw, ImageFont

im = Image.open('_maze_src2.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
x0, y0, cw, ch = 280.0, 76.0, 67.0, 66.0

dark = (r < 130) & (g < 130) & (b < 130)

# 渲染放大网格（每格 40px），把原图里落在每格内的暗像素（粗线）画上去
SCALE = 40
out = Image.new('RGB', (10 * SCALE + 60, 10 * SCALE + 60), (250, 248, 240))
dd = ImageDraw.Draw(out)
try:
    f = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 12)
except Exception:
    f = ImageFont.load_default()

# 细网格线位置（列 x0+k*cw、行 y0+k*ch），先扣掉
thinline = np.zeros((H, W), bool)
for k in range(11):
    xx = int(x0 + k * cw)
    thinline[:, max(0, xx - 2):xx + 3] = True
    yy = int(y0 + k * ch)
    thinline[max(0, yy - 2):yy + 3, :] = True
thick = dark & ~thinline

# 3 个预设黑斜线（c8r5、c6r5、c7r9）也要扣掉，避免它们干扰框边界
for (c, rr) in [(8, 5), (6, 5), (7, 9)]:
    gx = int(x0 + c * cw)
    gy = int(y0 + rr * ch)
    # 只在这一格窗口内，用 45 斜线方向的掩码扣掉（粗笔）
    for yy in range(gy, gy + int(ch)):
        for xx in range(gx, gx + int(cw)):
            lx, ly = xx - gx, yy - gy
            if not (0 <= lx < int(cw) and 0 <= ly < int(ch)):
                continue

# 按"粗线在相邻格之间的边界段"统计：对每一条内边（竖边 x=x0+k*cw，行 j；横边 y=y0+k*ch，列 i）
# 取边界两侧 3px 条带的暗像素数，超阈值=粗线
def band_h(yy, x1, x2, w=3):
    y1, y2 = max(0, yy - w), min(H, yy + w)
    return int(thick[y1:y2, x1:x2].sum())


def band_v(xx, y1, y2, w=3):
    x1, x2 = max(0, xx - w), min(W, xx + w)
    return int(thick[y1:y2, x1:x2].sum())

# 竖边：VEDG[k][j] = 列 k 与列 k-1 之间的竖段（格 (k-1,j)|(k,j) 之间）
VEDG = [[0] * 10 for _ in range(11)]
HEDG = [[0] * 10 for _ in range(11)]  # HEDG[k][i] = 行 k 与行 k-1 之间横段（格 (i,k-1)|(i,k)）
for k in range(11):
    xx = int(x0 + k * cw)
    for j in range(10):
        y1 = int(y0 + j * ch) + 4
        y2 = int(y0 + (j + 1) * ch) - 4
        VEDG[k][j] = band_v(xx, y1, y2)
for k in range(11):
    yy = int(y0 + k * ch)
    for i in range(10):
        x1 = int(x0 + i * cw) + 4
        x2 = int(x0 + (i + 1) * cw) - 4
        HEDG[k][i] = band_h(yy, x1, x2)

print('竖边暗度（k=列边界，行 j）:')
for k in range(1, 10):
    row = ['%d:%d' % (j, VEDG[k][j]) for j in range(10) if VEDG[k][j] > 30]
    print('  竖边 k=%d  %s' % (k, ' '.join(row)))
print('横边暗度（k=行边界，列 i）:')
for k in range(1, 10):
    row = ['%d:%d' % (i, HEDG[k][i]) for i in range(10) if HEDG[k][i] > 30]
    print('  横边 k=%d  %s' % (k, ' '.join(row)))

# 阈值 30 → 粗边
TH = 30
for i in range(10):
    for j in range(10):
        x, y = 30 + i * SCALE, 30 + j * SCALE
        # 小格底
        dd.rectangle([x, y, x + SCALE, y + SCALE], outline=(200, 198, 190), width=1)
        if i < 9:
            dd.text((x + SCALE - 6, y + 2), 'c%d' % i, fill=(210, 208, 200), font=f)
        if j < 9:
            dd.text((x + 2, y + SCALE - 12), 'r%d' % j, fill=(210, 208, 200), font=f)
# 粗框边
for k in range(11):
    xx = int(x0 + k * cw)
    for j in range(10):
        if VEDG[k][j] > TH:
            px = 30 + k * SCALE
            dd.line([(px, 30 + j * SCALE), (px, 30 + (j + 1) * SCALE)], fill=(20, 20, 20), width=5)
for k in range(11):
    yy = int(y0 + k * ch)
    for i in range(10):
        if HEDG[k][i] > TH:
            py = 30 + k * SCALE
            dd.line([(30 + i * SCALE, py), (30 + (i + 1) * SCALE, py)], fill=(20, 20, 20), width=5)
# 外框
dd.rectangle([30, 30, 30 + 10 * SCALE, 30 + 10 * SCALE], outline=(20, 20, 20), width=3)

# 红答案镜位置（绿圈）+ 黑预设（蓝圈）
reds = [(7, 0), (2, 1), (7, 3), (6, 3), (2, 5), (6, 8), (1, 9)]
blacks = [(8, 5), (6, 5), (7, 9)]
for (c, rr) in reds:
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    dd.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], outline=(0, 180, 80), width=2)
for (c, rr) in blacks:
    cx, cy = 30 + c * SCALE + SCALE // 2, 30 + rr * SCALE + SCALE // 2
    dd.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], outline=(30, 60, 220), width=2)

out.save('_maze_frames_raw.png')
print('saved _maze_frames_raw.png')
