# -*- coding: utf-8 -*-
# 高清图：定位棋盘外框 + 网格定标
import numpy as np
from PIL import Image

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 100) & (g < 100) & (b < 100)

# 列暗像素数、行暗像素数
col = black.sum(axis=0)
row = black.sum(axis=1)

# 棋盘外框：连续暗像素数接近边长的列/行
# 找最长的连续暗线段
def longest_runs(proj, thresh):
    runs = []
    i = 0
    n = len(proj)
    while i < n:
        if proj[i] >= thresh:
            j = i
            while j < n and proj[j] >= thresh:
                j += 1
            runs.append((i, j - 1, j - i))
            i = j
        else:
            i += 1
    return runs

# 外框竖线：暗像素高度大（>800 像素）
vruns = longest_runs(col, 800)
print('候选竖外框线（暗高>=800）:', vruns)
hruns = longest_runs(row, 1000)
print('候选横外框线（暗宽>=1000）:', hruns)

# 用最外侧的两条长竖线、两条长横线
vlines = [p[0] for p in vruns]
hlines = [p[0] for p in hruns]
print('竖线 x:', vlines)
print('横线 y:', hlines)
