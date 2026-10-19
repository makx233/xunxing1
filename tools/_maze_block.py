# -*- coding: utf-8 -*-
# 网格切 4 块放大（2x 再放大），逐块读黑框
from PIL import Image
im = Image.open('_maze_grid_zoom.png').convert('RGB')
W, H = im.size
# 原图是 1380x1360（含 10px 边距再 2x）
# 切上下两半
top = im.crop((0, 0, W, H // 2))
bot = im.crop((0, H // 2, W, H))
top.save('_maze_block_top.png')
bot.save('_maze_block_bot.png')
# 再切左右，每块 5x5 区域
lt = im.crop((0, 0, W // 2, H // 2))
rt = im.crop((W // 2, 0, W, H // 2))
lb = im.crop((0, H // 2, W // 2, H))
rb = im.crop((W // 2, H // 2, W, H))
for nm, im2 in [('lt', lt), ('rt', rt), ('lb', lb), ('rb', rb)]:
    im2 = im2.resize((im2.width * 2, im2.height * 2), Image.LANCZOS)
    im2.save('_maze_block_%s.png' % nm)
print('done')
