# -*- coding: utf-8 -*-
# 精裁 r1-r2 c8-c9（右上框顶部封口），放大 6x
from PIL import Image
im = Image.open('_maze_src3.jpg').convert('RGB')
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3
# c8 到 c9，r1 到 r2
xa = int(x0 + 8 * cw) - 10
xb = int(x0 + 10 * cw) + 10
ya = int(y0 + 1 * ch) - 12
yb = int(y0 + 3 * ch) + 12
im2 = im.crop((xa, ya, xb, yb))
im2 = im2.resize((im2.width * 5, im2.height * 5), Image.LANCZOS)
im2.save('_maze3_seal.png')
print('_maze3_seal.png', im2.size)
