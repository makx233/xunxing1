# -*- coding: utf-8 -*-
# 设计搜索：固定 12 镜位（7红+5黑），搜端口 in/out 分配 + 红镜方向，
# 使七色全亮且蓝光折向 == S 同向（L>D,D>R,R>D,D>L）
DIRS = {'R': (1, 0), 'L': (-1, 0), 'D': (0, 1), 'U': (0, -1)}
FLIP = {
    '/': {'R': 'U', 'L': 'D', 'U': 'R', 'D': 'L'},
    '\\': {'R': 'D', 'L': 'U', 'U': 'L', 'D': 'R'},
}
COLS = ROWS = 10
GESTURE = ['L>D', 'D>R', 'R>D', 'D>L']

# 镜位：red_answers = 7 红（方向可变），presets = 5 黑（方向固定）
ANSWERS_POS = {
    'red': [(1, 10), (7, 10)], 'orange': [(-1, 3), (8, -1)], 'yellow': [(-1, 5), (2, 10)],
    'green': [(-1, 0), (10, 3)], 'cyan': [(10, 2), (6, 10)], 'blue': [(10, 0), (-1, 7)],
    'purple': [(6, -1), (10, 9)],
}
# 每色两个口的固定方向：in 用进入方向；out 用离开方向（= 进入方向的反向）
def port_dir(p):
    x, y = p
    if y == -1: return 'D'
    if y == 10: return 'U'
    if x == -1: return 'R'
    if x == 10: return 'L'
    raise ValueError(p)

INV = {'D': 'U', 'U': 'D', 'R': 'L', 'L': 'R'}


def exit_dir(p):
    return INV[port_dir(p)]

RED_MIRRORS = [(6, 0), (2, 1), (5, 3), (6, 3), (2, 5), (5, 8), (1, 9)]
PRESET_DIR = {(4, 1): '\\', (7, 1): '\\', (6, 2): '/', (7, 5): '/', (6, 8): '\\'}


def trace(allm, entry, d):
    cur = (entry[0] + DIRS[d][0], entry[1] + DIRS[d][1])
    seen = set()
    path = []
    mirrors = []
    turns = []
    while True:
        if not (0 <= cur[0] < COLS and 0 <= cur[1] < ROWS):
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'path': path, 'looped': False}
        key = (cur[0], cur[1], d)
        if key in seen:
            return {'exit': cur, 'exit_dir': d, 'turns': turns, 'path': path, 'looped': True}
        seen.add(key)
        path.append(cur)
        if cur in allm:
            nd = FLIP[allm[cur]][d]
            mirrors.append(cur)
            turns.append((cur, d, nd))
            d = nd
        cur = (cur[0] + DIRS[d][0], cur[1] + DIRS[d][1])


def evaluate(red_dir_map, in_choice):
    allm = dict(PRESET_DIR)
    for pos in RED_MIRRORS:
        allm[pos] = red_dir_map[pos]
    answers = {}
    for c, (p1, p2) in ANSWERS_POS.items():
        if in_choice[c] == 0:
            answers[c] = {'in': p1, 'in_dir': port_dir(p1), 'out': p2, 'out_dir': exit_dir(p2)}
        else:
            answers[c] = {'in': p2, 'in_dir': port_dir(p2), 'out': p1, 'out_dir': exit_dir(p1)}
    ok = True
    for c in ANSWERS_POS:
        a = answers[c]
        r = trace(allm, a['in'], a['in_dir'])
        if r['looped']:
            ok = False
            break
        if r['exit'] != a['out'] or r['exit_dir'] != a['out_dir']:
            ok = False
            break
        ms = r['turns']
        if len([m[0] for m in ms]) != len(set(m[0] for m in ms)):
            ok = False
            break
    if not ok:
        return None
    bt = trace(allm, answers['blue']['in'], answers['blue']['in_dir'])
    bturns = ['%s>%s' % (t[1], t[2]) for t in bt['turns']]
    if bturns == GESTURE:
        return answers
    return None


import itertools

# 先固定红镜方向按图，只搜端口分配
RED_DIR_FIG = {(6, 0): '\\', (2, 1): '/', (5, 3): '/', (6, 3): '\\', (2, 5): '\\', (5, 8): '/', (1, 9): '/'}
colors = list(ANSWERS_POS.keys())
found = []
for bits in itertools.product([0, 1], repeat=7):
    in_choice = dict(zip(colors, bits))
    ans = evaluate(RED_DIR_FIG, in_choice)
    if ans:
        found.append(ans)
        print('!! 按图红镜方向 + 端口分配', in_choice, '全亮且蓝光S')

if not found:
    print('按图红镜方向无解，放开红镜方向全搜……')
    for red_dirs in itertools.product(['/', '\\'], repeat=7):
        rm = dict(zip(RED_MIRRORS, red_dirs))
        for bits in itertools.product([0, 1], repeat=7):
            in_choice = dict(zip(colors, bits))
            ans = evaluate(rm, in_choice)
            if ans:
                found.append(ans)
                print('!! 解：红镜', rm, '端口', in_choice)
                if len(found) > 20:
                    break
        if len(found) > 20:
            break
    print('共找到', len(found), '个解')
