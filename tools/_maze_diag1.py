# -*- coding: utf-8 -*-
# 诊断1：红镜方向自由 + 青端口自由（其余6色端口按图固定），只求七色全亮
DIRS = {'R': (1, 0), 'L': (-1, 0), 'D': (0, 1), 'U': (0, -1)}
FLIP = {
    '/': {'R': 'U', 'L': 'D', 'U': 'R', 'D': 'L'},
    '\\': {'R': 'D', 'L': 'U', 'U': 'L', 'D': 'R'},
}
COLS = ROWS = 10
GESTURE = ['L>D', 'D>R', 'R>D', 'D>L']

FIXED_PORTS = {
    'red': [(1, 10), (7, 10)], 'orange': [(-1, 3), (8, -1)], 'yellow': [(-1, 5), (2, 10)],
    'green': [(-1, 0), (10, 3)], 'blue': [(10, 0), (-1, 7)],
    'purple': [(6, -1), (10, 9)],
}
RED_MIRRORS = [(6, 0), (2, 1), (5, 3), (6, 3), (2, 5), (5, 8), (1, 9)]
PRESET_DIR = {(4, 1): '\\', (7, 1): '\\', (6, 2): '/', (7, 5): '/', (6, 8): '\\'}

# 青端口候选：网格四边任意位置（不与其它端口重复）
EDGE = []
for x in range(10):
    EDGE.append((x, -1)); EDGE.append((x, 10))
for y in range(10):
    EDGE.append((-1, y)); EDGE.append((10, y))


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


import itertools

all_edges = [e for e in EDGE]
# 青两端口组合（有序对，可同边不同点）
cyan_pairs = [(a, b) for a in all_edges for b in all_edges if a != b]
print('青端口组合数:', len(cyan_pairs))

count = 0
for red_dirs in itertools.product(['/', '\\'], repeat=7):
    rm = dict(zip(RED_MIRRORS, red_dirs))
    allm = dict(PRESET_DIR)
    for pos in RED_MIRRORS:
        allm[pos] = rm[pos]
    for (cp1, cp2) in cyan_pairs:
        # 其它色固定端口+进出分配
        answers = {}
        ok = True
        for c, (p1, p2) in FIXED_PORTS.items():
            for (pin, pout) in [(p1, p2), (p2, p1)]:
                ans = {'in': pin, 'in_dir': port_dir(pin), 'out': pout, 'out_dir': port_dir(pout)}
                r = trace(allm, pin, port_dir(pin))
                if not r['looped'] and r['exit'] == pout and r['exit_dir'] == port_dir(pout):
                    ms = [t[0] for t in r['turns']]
                    if len(ms) == len(set(ms)):
                        answers[c] = ans
                        break
            if c not in answers:
                ok = False
                break
        if not ok:
            continue
        # 青
        for (pin, pout) in [(cp1, cp2), (cp2, cp1)]:
            ans = {'in': pin, 'in_dir': port_dir(pin), 'out': pout, 'out_dir': port_dir(pout)}
            r = trace(allm, pin, port_dir(pin))
            if not r['looped'] and r['exit'] == pout and r['exit_dir'] == port_dir(pout):
                ms = [t[0] for t in r['turns']]
                if len(ms) == len(set(ms)):
                    answers['cyan'] = ans
                    break
        if 'cyan' not in answers:
            continue
        # 蓝光 S？
        bt = trace(allm, answers['blue']['in'], answers['blue']['in_dir'])
        bturns = ['%s>%s' % (t[1], t[2]) for t in bt['turns']]
        s_ok = bturns == GESTURE
        count += 1
        print('!! 全亮解：红镜', {k: v for k, v in rm.items()}, '青', answers['cyan'],
              'S=%s' % s_ok, '蓝折向', bturns)
        if count >= 10:
            break
    if count >= 10:
        break
print('找到全亮解', count, '个（含S标记）')
