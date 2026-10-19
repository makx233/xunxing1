# -*- coding: utf-8 -*-
# 诊断3：对每个红镜方向组合，统计可通色数与失败色
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


def exit_dir(p):
    return {'D': 'U', 'U': 'D', 'R': 'L', 'L': 'R'}[port_dir(p)]


def trace(allm, entry, d):
    cur = (entry[0] + DIRS[d][0], entry[1] + DIRS[d][1])
    seen = set()
    turns = []
    while True:
        if not (0 <= cur[0] < COLS and 0 <= cur[1] < ROWS):
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'looped': False}
        key = (cur[0], cur[1], d)
        if key in seen:
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'looped': True}
        seen.add(key)
        if cur in allm:
            nd = FLIP[allm[cur]][d]
            turns.append((cur, d, nd))
            d = nd
        cur = (cur[0] + DIRS[d][0], cur[1] + DIRS[d][1])


def lit(allm, c, pin, pout):
    r = trace(allm, pin, port_dir(pin))
    if r['looped']:
        return False
    if r['exit'] != pout or r['exit_dir'] != exit_dir(pout):
        return False
    ms = [t[0] for t in r['turns']]
    return len(ms) == len(set(ms))


import itertools

best = (0, None)
for red_dirs in itertools.product(['/', '\\'], repeat=7):
    allm = dict(PRESET_DIR)
    for pos, s in zip(RED_MIRRORS, red_dirs):
        allm[pos] = s
    fail = []
    for c, (p1, p2) in FIXED_PORTS.items():
        ok = lit(allm, c, p1, p2) or lit(allm, c, p2, p1)
        if not ok:
            fail.append(c)
    n_ok = 7 - len(fail)
    if n_ok > best[0]:
        best = (n_ok, dict(zip(RED_MIRRORS, red_dirs)), fail)
print('最多可通 %d/7 色，失败色 %s，红镜方向 %s' % (best[0], best[2], best[1]))
