# -*- coding: utf-8 -*-
# 每格内容缩略图：10x10 拼图，每格内部内容缩成图标
import numpy as np
from PIL import Image

im = Image.open('_maze_src.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
lum = (r * 0.3 + g * 0.59 + b * 0.11)
red = (r > 140) & (r - g > 50) & (r - b > 50)
dark = lum < 150

x0, y0, cw, ch = 90, 280, 80.0, 73.0
CELL = 36  # 每格图标显示尺寸
out = Image.new('RGB', (10 * CELL, 10 * CELL), (250, 248, 240))
d = out.load()
for rr in range(10):
    for c in range(10):
        xa = int(x0 + c * cw + cw * 0.18)
        xb = int(x0 + c * cw + cw * 0.82)
        ya = int(y0 + rr * ch + ch * 0.18)
        yb = int(y0 + rr * ch + ch * 0.82)
        ic = 12  # 内部采样 12x12
        for iy in range(ic):
            for ix in range(ic):
                px = xa + (xb - xa) * ix // ic
                py = ya + (yb - ya) * iy // ic
                is_red = red[py, px]
                is_dark = dark[py, px]
                # 填充到 3x3 显示块
                for dy in range(3):
                    for dx in range(3):
                        ox = c * CELL + ix * 3 + dx
                        oy = rr * CELL + iy * 3 + dy
                        if is_red:
                            d[ox, oy] = (225, 60, 55)
                        elif is_dark:
                            d[ox, oy] = (40, 40, 45)
                        # 默认留纸面
out.save('_maze_cells_map.png')
print('saved')
