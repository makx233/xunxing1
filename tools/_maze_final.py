# -*- coding: utf-8 -*-
# 定稿数据验证：红7+黑3镜位方向按图，6色端口按图，青端口自由——能否全亮+蓝光S？
DIRS = {'R': (1, 0), 'L': (-1, 0), 'D': (0, 1), 'U': (0, -1)}
FLIP = {
    '/': {'R': 'U', 'L': 'D', 'U': 'R', 'D': 'L'},
    '\\': {'R': 'D', 'L': 'U', 'U': 'L', 'D': 'R'},
}
COLS = ROWS = 10
GESTURE = ['L>D', 'D>R', 'R>D', 'D>L']

# 镜位（红=答案，黑=固定）
RED_MIRRORS = [(7, 0), (2, 1), (7, 3), (6, 3), (2, 5), (6, 8), (1, 9)]
RED_DIR = {'\\': [(7, 0), (7, 3), (6, 3), (2, 5)], '/': [(2, 1), (6, 8), (1, 9)]}
PRESET_DIR = {(8, 5): '/', (6, 5): '\\', (7, 9): '\\'}

FIXED_PORTS = {
    'red': [(1, 10), (7, 10)], 'orange': [(-1, 3), (8, -1)], 'yellow': [(-1, 5), (2, 10)],
    'green': [(-1, 0), (10, 3)], 'blue': [(10, 1), (-1, 8)],
    'purple': [(6, -1), (10, 9)],
}
EDGE = []
for x in range(10):
    EDGE.append((x, -1)); EDGE.append((x, 10))
for y in range(10):
    EDGE.append((-1, y)); EDGE.append((10, y))
# 青不能占已有端口位置
taken = set()
for p1, p2 in FIXED_PORTS.values():
    taken.add(p1); taken.add(p2)
EDGE = [e for e in EDGE if e not in taken]


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


def lit(allm, c, ans):
    r = trace(allm, ans['in'], ans['in_dir'])
    if r['looped']:
        return False
    if r['exit'] != ans['out'] or r['exit_dir'] != ans['out_dir']:
        return False
    ms = [t[0] for t in r['turns']]
    return len(ms) == len(set(ms))


import itertools

allm = dict(PRESET_DIR)
for pos, s in RED_DIR.items():
    for p in s:
        allm[p] = pos

colors = list(FIXED_PORTS.keys()) + ['cyan']
found = 0
for bits in itertools.product([0, 1], repeat=6):
    in_choice = dict(zip(list(FIXED_PORTS.keys()), bits))
    answers = {}
    for c, (p1, p2) in FIXED_PORTS.items():
        if in_choice[c] == 0:
            answers[c] = {'in': p1, 'in_dir': port_dir(p1), 'out': p2, 'out_dir': exit_dir(p2)}
        else:
            answers[c] = {'in': p2, 'in_dir': port_dir(p2), 'out': p1, 'out_dir': exit_dir(p1)}
    # 青端口位置自由
    for (cp1, cp2) in [(a, b) for a in EDGE for b in EDGE if a != b]:
        for (pin, pout) in [(cp1, cp2), (cp2, cp1)]:
            ans = {'in': pin, 'in_dir': port_dir(pin), 'out': pout, 'out_dir': exit_dir(pout)}
            if lit(allm, 'cyan', ans):
                answers['cyan'] = ans
                break
        if 'cyan' in answers:
            break
    if 'cyan' not in answers:
        continue
    ok = all(lit(allm, c, a) for c, a in answers.items())
    if not ok:
        continue
    bt = trace(allm, answers['blue']['in'], answers['blue']['in_dir'])
    bturns = ['%s>%s' % (t[1], t[2]) for t in bt['turns']]
    found += 1
    print('!! 全亮解：端口分配', in_choice, '青', answers['cyan'])
    print('   S=%s 蓝折向 %s' % (bturns == GESTURE, bturns))
print('共 %d 个全亮解' % found)
