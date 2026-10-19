# -*- coding: utf-8 -*-
# 调试：构造答案摆法（placed=7红镜），undecided 空，逐色看 status
DIRS = {'R': (1, 0), 'L': (-1, 0), 'D': (0, 1), 'U': (0, -1)}
FLIP = {
    '/': {'R': 'U', 'L': 'D', 'U': 'R', 'D': 'L'},
    '\\': {'R': 'D', 'L': 'U', 'U': 'L', 'D': 'R'},
}
COLS = ROWS = 10
ANSWERS = {
    'red': {'in': (1, 10), 'in_dir': 'U', 'out': (7, 10), 'out_dir': 'D'},
    'orange': {'in': (-1, 3), 'in_dir': 'R', 'out': (8, -1), 'out_dir': 'U'},
    'yellow': {'in': (-1, 5), 'in_dir': 'R', 'out': (2, 10), 'out_dir': 'D'},
    'green': {'in': (-1, 0), 'in_dir': 'R', 'out': (10, 3), 'out_dir': 'R'},
    'cyan': {'in': (0, -1), 'in_dir': 'D', 'out': (0, 10), 'out_dir': 'D'},
    'blue': {'in': (10, 1), 'in_dir': 'L', 'out': (-1, 8), 'out_dir': 'L'},
    'purple': {'in': (6, -1), 'in_dir': 'D', 'out': (10, 9), 'out_dir': 'R'},
}
SOL_MIRRORS = {(7, 0): '\\', (2, 1): '/', (7, 3): '\\', (6, 3): '\\',
               (2, 5): '\\', (6, 8): '/', (1, 9): '/',
               (8, 5): '/', (6, 5): '\\', (7, 9): '\\'}
PRESETS = [(8, 5), (6, 5), (7, 9)]


def trace(placed, entry, d):
    cur = (entry[0] + DIRS[d][0], entry[1] + DIRS[d][1])
    seen = set()
    turns = []
    while True:
        if not (0 <= cur[0] < COLS and 0 <= cur[1] < ROWS):
            return {'exit': cur, 'exit_dir': d, 'turns': turns}
        key = (cur[0], cur[1], d)
        if key in seen:
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'looped': True}
        seen.add(key)
        s = placed.get(cur)
        if s is None and cur in SOL_MIRRORS and cur in PRESETS:
            s = SOL_MIRRORS[cur]
        if s is not None:
            nd = FLIP[s][d]
            turns.append((cur, d, nd))
            d = nd
        cur = (cur[0] + DIRS[d][0], cur[1] + DIRS[d][1])


placed = {k: v for k, v in SOL_MIRRORS.items() if k not in PRESETS}
for c, a in ANSWERS.items():
    r = trace(placed, a['in'], a['in_dir'])
    ok = (not r.get('looped', False) and r['exit'] == a['out'] and r['exit_dir'] == a['out_dir'])
    ms = [t[0] for t in r['turns']]
    dup = len(ms) != len(set(ms))
    print('%s: %s exit=%s%s turns=%s dup=%s' % (
        c, 'OK' if ok and not dup else 'FAIL', r['exit'], r['exit_dir'], ms, dup))
