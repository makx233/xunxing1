# -*- coding: utf-8 -*-
# 唯一性穷举（与 solve_maze.gd 同口径）：每框 0 或 1 面镜，全亮 = 解。
# 剪枝：任一色"已确定失败"即剪；光路过未定格 = pending。
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
COLORS = list(ANSWERS.keys())

SOL_MIRRORS = {(7, 0): '\\', (2, 1): '/', (7, 3): '\\', (6, 3): '\\',
               (2, 5): '\\', (6, 8): '/', (1, 9): '/',
               (8, 5): '/', (6, 5): '\\', (7, 9): '\\'}
PRESETS = [(8, 5), (6, 5), (7, 9)]
# 高清画稿照排 10 框（每框恰好 1 镜，100 格铺满；walls3 自动分割）
FRAMES = [
    # R5 (2,5)\
    [(0, 3), (1, 3), (2, 3), (0, 4), (1, 4), (2, 4), (0, 5), (1, 5), (2, 5), (0, 6), (1, 6), (2, 6)],
    # R2 (2,1)/
    [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)],
    # R1 (7,0)\
    [(4, 0), (5, 0), (6, 0), (7, 0), (3, 1), (4, 1), (3, 2), (4, 2), (5, 2), (6, 2)],
    # B2 (8,5)/ 预设
    [(8, 2), (9, 2), (8, 3), (9, 3), (8, 4), (9, 4), (8, 5), (9, 5), (8, 6), (9, 6)],
    # R4 (6,3)\
    [(3, 3), (4, 3), (5, 3), (6, 3), (3, 4), (4, 4), (3, 5), (4, 5), (3, 6), (4, 6)],
    # B1 (6,5)\ 预设
    [(5, 4), (6, 4), (7, 4), (5, 5), (6, 5), (7, 5), (5, 6), (6, 6), (7, 6), (6, 7)],
    # R6 (6,8)/
    [(3, 7), (4, 7), (5, 7), (3, 8), (4, 8), (5, 8), (6, 8), (3, 9), (4, 9), (5, 9)],
    # B3 (7,9)\ 预设
    [(7, 7), (8, 7), (9, 7), (7, 8), (8, 8), (9, 8), (6, 9), (7, 9), (8, 9), (9, 9)],
    # R3 (7,3)\ （右上 L 形）
    [(8, 0), (9, 0), (5, 1), (6, 1), (7, 1), (8, 1), (9, 1), (7, 2), (7, 3)],
    # R7 (1,9)/
    [(0, 7), (1, 7), (2, 7), (0, 8), (1, 8), (2, 8), (0, 9), (1, 9), (2, 9)],
]

frame_of = {}
for fi, cells in enumerate(FRAMES):
    for c in cells:
        frame_of[c] = fi

# 每框候选：非预设格
frames = []
for cells in FRAMES:
    taken = any(c in PRESETS for c in cells)
    cand = [c for c in cells if c not in PRESETS]
    frames.append({'taken': taken, 'cand': cand})

# 按候选少排序
order = sorted(range(len(frames)), key=lambda i: len(frames[i]['cand']))

placed = {}
undecided = set()
for i in order:
    for c in frames[i]['cand']:
        undecided.add(c)

count = 0
pruned = 0
pending_hits = 0
shown = []


def status(c):
    global pending_hits
    a = ANSWERS[c]
    cur = (a['in'][0] + DIRS[a['in_dir']][0], a['in'][1] + DIRS[a['in_dir']][1])
    d = a['in_dir']
    seen = set()
    hit = set()
    while True:
        if not (0 <= cur[0] < COLS and 0 <= cur[1] < ROWS):
            if cur == a['out'] and d == a['out_dir']:
                return 'lit'
            return 'fail'
        if cur in undecided:
            pending_hits += 1
            return 'pending'
        key = (cur[0], cur[1], d)
        if key in seen:
            return 'fail'
        seen.add(key)
        s = placed.get(cur)
        if s is None and cur in SOL_MIRRORS and cur in PRESETS:
            s = SOL_MIRRORS[cur]
        if s is not None:
            if cur in hit:
                return 'fail'
            hit.add(cur)
            d = FLIP[s][d]
        cur = (cur[0] + DIRS[d][0], cur[1] + DIRS[d][1])
    return 'fail'


def prefix_ok():
    for c in COLORS:
        if status(c) == 'fail':
            return False
    return True


def all_lit():
    for c in COLORS:
        if status(c) != 'lit':
            return False
    return True


def dfs(depth):
    global count, pruned
    if depth == len(order):
        if all_lit():
            count += 1
            if len(shown) < 12:
                shown.append(dict(placed))
        return
    fi = order[depth]
    f = frames[fi]
    cells = f['cand']
    for c in cells:
        undecided.discard(c)
    # 空
    if prefix_ok():
        dfs(depth + 1)
    # 放镜
    if not f['taken']:
        for c in cells:
            for s in ['/', '\\']:
                placed[c] = s
                if prefix_ok():
                    dfs(depth + 1)
                placed.pop(c, None)
    for c in cells:
        undecided.add(c)


dfs(0)
print('解数 =', count)
for i, sol in enumerate(shown, 1):
    keys = sorted(sol.keys(), key=lambda k: (k[1], k[0]))
    print('  解%d: %s' % (i, ' '.join('%s%s' % (k, sol[k]) for k in keys)))
# 答案本身是解？
ans_key = {k: v for k, v in SOL_MIRRORS.items() if k not in PRESETS}
print('答案摆法在解中:', ans_key in shown)
