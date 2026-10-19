# -*- coding: utf-8 -*-
# 用颜色掩膜直接定位四边颜色字（比 OCR 准），换算端口行列
import numpy as np
from PIL import Image
from collections import deque

im = Image.open('_maze_src.png').convert('RGB')
a = np.asarray(im, dtype=np.int32)
H, W, _ = a.shape
r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]

# 网格（估算）：
x0, y0, cw, ch = 90.0, 280.0, 80.0, 73.0


def mask_of(color):
    if color == 'red':
        return (r > 120) & (r - g > 40) & (r - b > 40)
    if color == 'orange':
        return (r > 130) & (g > 70) & (b < 110) & (r - b > 60) & (r - g > 30)
    if color == 'yellow':
        return (r > 140) & (g > 120) & (b < 120) & (r - b > 40) & (g - b > 30)
    if color == 'green':
        return (g > 120) & (g - r > 40) & (g - b > 40)
    if color == 'blue':
        return (b > 120) & (b - r > 50) & (b - g > 30)
    if color == 'purple':
        return (r > 110) & (b > 110) & (g < 110) & (r - g > 40) & (b - g > 40)
    raise ValueError(color)


def clusters(mask, min_size=20):
    vis = np.zeros((H, W), bool)
    out = []
    for y in range(H):
        for x in range(W):
            if mask[y, x] and not vis[y, x]:
                q = deque([(y, x)])
                vis[y, x] = True
                pts = []
                while q:
                    yy, xx = q.popleft()
                    pts.append((yy, xx))
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            ny, nx = yy + dy, xx + dx
                            if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not vis[ny, nx]:
                                vis[ny, nx] = True
                                q.append((ny, nx))
                if len(pts) >= min_size:
                    out.append(pts)
    return out


for col in ['red', 'orange', 'yellow', 'green', 'blue', 'purple']:
    m = mask_of(col)
    cs = clusters(m)
    cs.sort(key=lambda p: (p[0][0], p[0][1]))
    parts = []
    for pts in cs:
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
        # 判断在网格哪侧
        side = '?'
        if cy < y0 - 15:
            side = '顶'
        elif cy > y0 + 10 * ch + 15:
            side = '底'
        elif cx < x0 - 15:
            side = '左'
        elif cx > x0 + 10 * cw + 15:
            side = '右'
        else:
            side = '内部'
        # 行列换算（只对边缘字）
        pos = '-'
        if side == '顶':
            pos = 'c%d' % int(round((cx - x0) / cw))
        elif side == '底':
            pos = 'c%d' % int(round((cx - x0) / cw))
        elif side == '左':
            pos = 'r%d' % int(round((cy - y0) / ch))
        elif side == '右':
            pos = 'r%d' % int(round((cy - y0) / ch))
        parts.append('%s(%d,%d)->%s' % (side, int(cx), int(cy), pos))
    print('%s: %s' % (col, ' | '.join(parts)))
