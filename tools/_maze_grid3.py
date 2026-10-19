# -*- coding: utf-8 -*-
# 找网格线：行/列 dark 比例高峰
import numpy as np
from PIL import Image

im = Image.open('_maze_src2.jpg').convert('L')
a = np.asarray(im, dtype=np.float32)
H, W = a.shape
dark = a < 150

# 只看画面中部区域（去掉边缘文字影响）：先粗看行分布
rowfrac = dark.mean(axis=1)
colfrac = dark.mean(axis=0)

def peaks(x, minfrac=0.15, gap=3):
    # 返回 x 中 >= minfrac 且为局部极大的位置（间隔至少 gap）
    out = []
    n = len(x)
    i = 0
    while i < n:
        if x[i] >= minfrac:
            j = i
            while j < n and x[j] >= minfrac:
                j += 1
            # 段 [i, j)，取中心
            out.append((i + j) // 2)
            i = j
        else:
            i += 1
    return out

rpeaks = peaks(rowfrac)
cpeaks = peaks(colfrac)
print('row peaks', rpeaks)
print('col peaks', cpeaks)

# 打印这些位置的具体比例，确认是网格线
for p in rpeaks:
    print('  row %d frac %.3f' % (p, rowfrac[p]))
for p in cpeaks:
    print('  col %d frac %.3f' % (p, colfrac[p]))
