# -*- coding: utf-8 -*-
# 诊断：棋盘下半部横线的真实 y 位置
import numpy as np
from PIL import Image

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
x0, cw = 586.0, 140.5
y0, ch = 155.0, 140.3
black = (r < 110) & (g < 110) & (b < 110)

# 棋盘 x 范围
xa, xb = int(x0 + 5), int(x0 + 10 * cw - 5)
# 理论横线位置
for k in range(0, 11):
    yt = int(y0 + k * ch)
    print('理论 r%d 顶 y=%d' % (k, yt))

print('\n各 y 行在棋盘宽度内的暗像素数（找长横线，宽>=900）:')
for y in range(150, 1600):
    cnt = int(black[y, xa:xb].sum())
    if cnt >= 900:
        print('  y=%d 暗宽=%d' % (y, cnt))
