# -*- coding: utf-8 -*-
# 新图 _maze_src2.jpg（1276x805）网格定标：找 10x10 网格线
import numpy as np
from PIL import Image

im = Image.open('_maze_src2.jpg').convert('L')
a = np.asarray(im, dtype=np.float32)
H, W = a.shape
print('size', W, H)

# 找深色像素（线条/文字）
dark = a < 150
print('dark ratio', dark.mean().round(4))

# 行投影（dark 像素按行求和），列投影
rowsum = dark.sum(axis=1)
colsum = dark.sum(axis=0)

# 网格区域应该在画面中部。先看投影分布找网格 bounding box
import json
# 打印投影的非零范围
rows_nz = np.nonzero(rowsum > 5)[0]
cols_nz = np.nonzero(colsum > 5)[0]
print('rows nz', rows_nz[0] if len(rows_nz) else None, rows_nz[-1] if len(rows_nz) else None)
print('cols nz', cols_nz[0] if len(cols_nz) else None, cols_nz[-1] if len(cols_nz) else None)

# 保存投影数据用于后续脚本
np.save('_proj_rows.npy', rowsum)
np.save('_proj_cols.npy', colsum)
