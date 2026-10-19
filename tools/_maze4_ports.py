# -*- coding: utf-8 -*-
# 端口只扫棋盘外环带（排除红斜线），按色聚类
import numpy as np
from PIL import Image

im = Image.open('_maze_src4.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
x0, cw, y0, ch = 208.0, 90.2, 113.0, 90.1
H, W = r.shape

colmask = {
    'red': (r > 200) & (g < 110) & (b < 110),
    'orange': (r > 220) & (g > 110) & (g < 200) & (b < 100),
    'yellow': (r > 220) & (g > 210) & (b < 120),
    'green': (r < 120) & (g > 150) & (b < 120),
    'cyan': (r < 100) & (g > 150) & (b > 180),
    'blue': (r < 100) & (g > 100) & (g < 200) & (b > 200),
    'purple': (r > 140) & (r < 215) & (g < 115) & (b > 150),
}
# 环带：棋盘外
band = np.zeros((H, W), bool)
m = 70
band[:max(0, int(y0) - 8), :] = True
band[int(y0 + 10 * ch) + 8:, :] = True
band[:, :max(0, int(x0) - 8)] = True
band[:, int(x0 + 10 * cw) + 8:] = True

for name, msk in colmask.items():
    m2 = msk & band
    ys, xs = np.where(m2)
    if len(xs) < 30:
        print('%-7s 无圆圈' % name)
        continue
    # 聚类（简单：按近邻合并到最近格）
    pts = []
    for i in range(len(xs)):
        x, y = int(xs[i]), int(ys[i])
        if y < y0 - 8:
            k = int(round((x - x0) / cw)); tag = '顶 c%d' % k
        elif y > y0 + 10 * ch + 8:
            k = int(round((x - x0) / cw)); tag = '底 c%d' % k
        elif x < x0 - 8:
            k = int(round((y - y0) / ch)); tag = '左 r%d' % k
        else:
            k = int(round((y - y0) / ch)); tag = '右 r%d' % k
        pts.append(tag)
    from collections import Counter
    print('%-7s %s' % (name, dict(Counter(pts))))
