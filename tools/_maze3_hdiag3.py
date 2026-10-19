# -*- coding: utf-8 -*-
# 横墙垂直厚度：在真实横线 y 附近，数连续多少行在该段内有>=80个暗像素
import numpy as np
from PIL import Image

im = Image.open('_maze_src3.jpg').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
black = (r < 110) & (g < 110) & (b < 110)
x0, cw, y0, ch = 586.0, 140.5, 155.0, 140.3


def vthickness(k, i, yc):
    """横线垂直厚度：在 yc 附近连续行，每行暗像素>=70 视为墙行"""
    x1, x2 = int(x0 + i * cw) + 12, int(x0 + (i + 1) * cw) - 12
    # 从 yc 向上
    up = 0
    for y in range(yc, yc - 20, -1):
        if int(black[y, x1:x2].sum()) >= 70:
            up += 1
        else:
            break
    dn = 0
    for y in range(yc + 1, yc + 20):
        if int(black[y, x1:x2].sum()) >= 70:
            dn += 1
        else:
            break
    return up + dn


# 用每段的真实 y（前面诊断的 by）
print('横边垂直厚度（>=5 粗墙）:')
for k in range(1, 10):
    yt = int(y0 + k * ch)
    row = []
    for i in range(10):
        # 在 yt±18 找暗像素最多的行作为 yc
        besty, bestc = yt, -1
        for y in range(yt - 18, yt + 18):
            c = int(black[y, int(x0 + i * cw) + 12:int(x0 + (i + 1) * cw) - 12].sum())
            if c > bestc:
                bestc, besty = c, y
        t = vthickness(k, i, besty)
        row.append('c%d:%d' % (i, t))
    print('  r%d|r%d: %s' % (k - 1, k, ' '.join(row)))
