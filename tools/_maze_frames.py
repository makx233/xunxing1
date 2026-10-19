# -*- coding: utf-8 -*-
# 程序生成 10 框：以 10 个镜位为种子，BFS 生长铺满 100 格，每框连通且恰含 1 镜
from collections import deque

COLS = ROWS = 10
MIRRORS = [(7, 0), (2, 1), (7, 3), (6, 3), (2, 5), (6, 8), (1, 9),  # 红答案 7
           (8, 5), (6, 5), (7, 9)]                                     # 黑固定 3

# 种子的生长顺序：黑固定镜先长（其框 taken，玩家不能放镜，越固定越好）
ORDER = [(7, 0), (2, 1), (7, 3), (6, 3), (2, 5), (6, 8), (1, 9), (8, 5), (6, 5), (7, 9)]

areas = {m: [m] for m in ORDER}
owned = set(MIRRORS)
fringe = {m: deque([m]) for m in ORDER}


def neighbors(c):
    x, y = c
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < COLS and 0 <= ny < ROWS:
            yield (nx, ny)


# 交替生长：每次给区域最小的、且还有可生长空间的框加一格
remaining = set((x, y) for x in range(COLS) for y in range(ROWS)) - owned
while remaining:
    grown = False
    for m in sorted(ORDER, key=lambda mm: len(areas[mm])):
        cand = None
        for c in areas[m]:
            for nb in neighbors(c):
                if nb in remaining:
                    cand = nb
                    break
            if cand:
                break
        if cand:
            areas[m].append(cand)
            remaining.discard(cand)
            grown = True
            break
    if not grown:
        print('!! 卡死，剩余', len(remaining))
        break

# 校验
total = sum(len(v) for v in areas.values())
print('总格数', total, '(应为100)')
for m in ORDER:
    cells = areas[m]
    cnt = sum(1 for c in cells if c in MIRRORS)
    print('框@%s 格数%3d 含镜%d  %s' % (m, len(cells), cnt,
          'OK' if cnt == 1 else '!!问题!!'))

# 连通性检查
for m in ORDER:
    cells = set(areas[m])
    q = deque([areas[m][0]])
    vis = {areas[m][0]}
    while q:
        c = q.popleft()
        for nb in neighbors(c):
            if nb in cells and nb not in vis:
                vis.add(nb)
                q.append(nb)
    print('框@%s 连通性 %s' % (m, 'OK' if len(vis) == len(cells) else '!!断开!!'))

# 输出 GDScript 数组
import json
print('---')
for m in ORDER:
    cells = areas[m]
    cells_sorted = sorted(cells, key=lambda c: (c[1], c[0]))
    print('框@%s: %s' % (m, cells_sorted))
