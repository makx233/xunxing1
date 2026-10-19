# -*- coding: utf-8 -*-
# 干净版 _maze_src4.png 定标与颜色普查
import numpy as np
from PIL import Image

im = Image.open('_maze_src4.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
print('size', W, H)
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]

# 黑色像素（黑框/黑斜线）
black = (r < 70) & (g < 70) & (b < 70)
# 灰色格线
gray = (abs(r - g) < 12) & (abs(g - b) < 12) & (r >= 150) & (r <= 210)
# 红斜线
red = (r > 180) & (g < 90) & (b < 90)

ys, xs = np.where(black)
print('黑像素 x 范围', xs.min(), xs.max(), ' y 范围', ys.min(), ys.max())

# 行/列黑像素计数，找外框和粗线
rowsum = black.sum(axis=1)
colsum = black.sum(axis=0)
print('黑像素最多的行(横墙候选):')
for y in np.argsort(rowsum)[-12:][::-1]:
    print('  y=%d cnt=%d' % (y, rowsum[y]))
print('黑像素最多的列(竖墙候选):')
for x in np.argsort(colsum)[-12:][::-1]:
    print('  x=%d cnt=%d' % (x, colsum[x]))

# 红斜线位置
rys, rxs = np.where(red)
print('红像素 x 范围', rxs.min(), rxs.max(), ' y 范围', rys.min(), rys.max(), ' 数', len(rys))
