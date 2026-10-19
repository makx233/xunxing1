# -*- coding: utf-8 -*-
# 诊断2：逐色独立检查——给定全部12镜（方向自由），每色两个口之间是否有连通路径
DIRS = {'R': (1, 0), 'L': (-1, 0), 'D': (0, 1), 'U': (0, -1)}
FLIP = {
    '/': {'R': 'U', 'L': 'D', 'U': 'R', 'D': 'L'},
    '\\': {'R': 'D', 'L': 'U', 'U': 'L', 'D': 'R'},
}
COLS = ROWS = 10

FIXED_PORTS = {
    'red': [(1, 10), (7, 10)], 'orange': [(-1, 3), (8, -1)], 'yellow': [(-1, 5), (2, 10)],
    'green': [(-1, 0), (10, 3)], 'blue': [(10, 0), (-1, 7)],
    'purple': [(6, -1), (10, 9)], 'cyan': [(10, 2), (6, 10)],
}
RED_MIRRORS = [(6, 0), (2, 1), (5, 3), (6, 3), (2, 5), (5, 8), (1, 9)]
PRESET_DIR = {(4, 1): '\\', (7, 1): '\\', (6, 2): '/', (7, 5): '/', (6, 8): '\\'}


def port_dir(p):
    x, y = p
    if y == -1: return 'D'
    if y == 10: return 'U'
    if x == -1: return 'R'
    if x == 10: return 'L'


def trace(allm, entry, d):
    cur = (entry[0] + DIRS[d][0], entry[1] + DIRS[d][1])
    seen = set()
    turns = []
    while True:
        if not (0 <= cur[0] < COLS and 0 <= cur[1] < ROWS):
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'looped': True if cur in seen else False}
        key = (cur[0], cur[1], d)
        if key in seen:
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'looped': True}
        seen.add(key)
        if cur in allm:
            nd = FLIP[allm[cur]][d]
            turns.append((cur, d, nd))
            d = nd
        cur = (cur[0] + DIRS[d][0], cur[1] + DIRS[d][1])


import itertools

for c, (p1, p2) in FIXED_PORTS.items():
    best = None
    for red_dirs in itertools.product(['/', '\\'], repeat=7):
        allm = dict(PRESET_DIR)
        for pos, s in zip(RED_MIRRORS, red_dirs):
            allm[pos] = s
        # p1 -> p2
        r1 = trace(allm, p1, port_dir(p1))
        hit1 = (not r1['looped'] and r1['exit'] == p2 and r1['exit_dir'] == port_dir(p2))
        # p2 -> p1
        r2 = trace(allm, p2, port_dir(p2))
        hit2 = (not r2['looped'] and r2['exit'] == p1 and r2['exit_dir'] == port_dir(p1))
        if hit1 or hit2:
            best = (hit1, hit2, dict(zip(RED_MIRRORS, red_dirs)))
            break
    if best:
        print('%s: 可通 %s（红镜方向 %s）' % (c, 'p1→p2' if best[0] else 'p2→p1', best[2]))
    else:
        print('%s: 不可通（两个口之间无镜面路径）' % c)
