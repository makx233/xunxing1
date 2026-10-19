# -*- coding: utf-8 -*-
# 斜线（红答案/黑预设）+ 七色端口检测
import numpy as np
from PIL import Image

im = Image.open('_maze_src4.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
red = (r > 180) & (g < 90) & (b < 90)
black = (r < 80) & (g < 80) & (b < 80)
x0, cw, y0, ch = 208.0, 90.2, 113.0, 90.1


def cell_bbox(c, rr, inset=0):
    x1 = int(round(x0 + c * cw)) + inset
    y1 = int(round(y0 + rr * ch)) + inset
    x2 = int(round(x0 + (c + 1) * cw)) - inset
    y2 = int(round(y0 + (rr + 1) * ch)) - inset
    return x1, y1, x2, y2


def orient(mask, c, rr):
    """返回 ('/' 或 '\\') 及像素数：沿两对角线判朝向"""
    x1, y1, x2, y2 = cell_bbox(c, rr, 8)
    ys, xs = np.where(mask[y1:y2, x1:x2])
    if len(xs) < 10:
        return None, 0
    dx = xs - (x2 - x1) / 2
    dy = ys - (y2 - y1) / 2
    # '\\' : dy≈dx (dy-dx≈0)；'/' : dy≈-dx (dy+dx≈0)
    d_back = np.abs(dy - dx)
    d_slash = np.abs(dy + dx)
    return ('\\' if d_back.mean() < d_slash.mean() else '/'), len(xs)


print('=== 红斜线（答案镜）===')
red_mirrors = {}
for rr in range(10):
    for c in range(10):
        x1, y1, x2, y2 = cell_bbox(c, rr, 8)
        n = red[y1:y2, x1:x2].sum()
        if n > 20:
            o, nn = orient(red, c, rr)
            red_mirrors[(c, rr)] = o
            print('  (%d,%d) %s  红像素=%d' % (c, rr, o, n))

print('=== 黑斜线（预设镜）===  内缩 22 排除框边')
for rr in range(10):
    for c in range(10):
        x1, y1, x2, y2 = cell_bbox(c, rr, 22)
        n = black[y1:y2, x1:x2].sum()
        if n > 30:
            o, nn = orient(black, c, rr)
            # 仅当沿某条对角线明显集中才算斜线
            print('  (%d,%d) %s  黑像素=%d' % (c, rr, o, n))

# 端口：棋盘外一圈的彩色像素
print('=== 彩色端口（圆圈）===')
colmask = {
    'red': (r > 200) & (g < 110) & (b < 110),
    'orange': (r > 220) & (g > 120) & (g < 190) & (b < 90),
    'yellow': (r > 220) & (g > 210) & (b < 110),
    'green': (r < 110) & (g > 160) & (b < 110),
    'cyan': (r < 90) & (g > 160) & (b > 180),
    'blue': (r < 90) & (g > 110) & (g < 190) & (b > 200),
    'purple': (r > 140) & (r < 210) & (g < 110) & (b > 160),
}
for name, m in colmask.items():
    ys, xs = np.where(m)
    if len(xs) == 0:
        print('  %s: 未找到' % name)
        continue
    cx, cy = xs.mean(), ys.mean()
    # 判定在棋盘哪一侧、对应哪个格
    if cy < y0 - 12:
        gc = int(round((cx - x0) / cw))
        print('  %-7s 顶 c%d (x=%.0f y=%.0f n=%d)' % (name, gc, cx, cy, len(xs)))
    elif cy > y0 + 10 * ch + 12:
        gc = int(round((cx - x0) / cw))
        print('  %-7s 底 c%d (x=%.0f y=%.0f n=%d)' % (name, gc, cx, cy, len(xs)))
    elif cx < x0 - 12:
        gr = int(round((cy - y0) / ch))
        print('  %-7s 左 r%d (x=%.0f y=%.0f n=%d)' % (name, gr, cx, cy, len(xs)))
    elif cx > x0 + 10 * cw + 12:
        gr = int(round((cy - y0) / ch))
        print('  %-7s 右 r%d (x=%.0f y=%.0f n=%d)' % (name, gr, cx, cy, len(xs)))
    else:
        print('  %-7s 内部? (x=%.0f y=%.0f n=%d)' % (name, cx, cy, len(xs)))
