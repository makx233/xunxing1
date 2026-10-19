# -*- coding: utf-8 -*-
# 裁出原图网格区并放大，便于人工看黑框
from PIL import Image
im = Image.open('_maze_src2.jpg').convert('RGB')
x0, y0, cw, ch = 280, 76, 67, 66
x1, y1 = x0 + 10 * cw, y0 + 10 * ch
grid = im.crop((x0 - 10, y0 - 10, x1 + 10, y1 + 10))
grid = grid.resize((grid.width * 2, grid.height * 2), Image.LANCZOS)
grid.save('_maze_grid_zoom.png')
print(grid.size)
