# -*- coding: utf-8 -*-
# 裁出几个关键格子看细节：c6r8(R6/B7重叠)、c1r9(R7/B10重叠)、c2r1(R2/B2)
from PIL import Image
import numpy as np

im = Image.open('_maze_src2.jpg').convert('RGB')
a = np.asarray(im)
x0, y0, cw, ch = 280.0, 76.0, 67.0, 66.0


def crop(c, rw, zoom=4, pad=6):
    cx = int(x0 + c * cw + cw / 2)
    cy = int(y0 + rw * ch + ch / 2)
    x1, y1 = cx - int(cw / 2) - pad, cy - int(ch / 2) - pad
    x2, y2 = cx + int(cw / 2) + pad, cy + int(ch / 2) + pad
    sub = im.crop((x1, y1, x2, y2)).resize(((x2 - x1) * zoom, (y2 - y1) * zoom), Image.NEAREST)
    return sub


for c, rw, name in [(6, 8, 'c6r8'), (1, 9, 'c1r9'), (2, 1, 'c2r1'), (9, 1, 'c9r1'), (7, 4, 'c7r4'), (5, 7, 'c5r7'), (8, 5, 'c8r5'), (6, 5, 'c6r5'), (6, 9, 'c6r9'), (7, 9, 'c7r9'), (7, 0, 'c7r0'), (2, 5, 'c2r5'), (6, 3, 'c6r3'), (7, 3, 'c7r3')]:
    crop(c, rw).save('_cell_%s.png' % name)
print('done')
