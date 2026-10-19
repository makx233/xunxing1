# -*- coding: utf-8 -*-
# 识别标注图：估算格网 + 红斜线 + 黑斜线 + 四边颜色口，交付用户确认
from PIL import Image, ImageDraw, ImageFont

im = Image.open('_maze_src.png').convert('RGB')
d = ImageDraw.Draw(im)

x0, y0, cw, ch = 90.0, 280.0, 80.0, 73.0
# 格网 + 坐标标签
try:
    f = ImageFont.truetype(r'C:\Windows\Fonts\msyh.ttc', 15)
    fb = ImageFont.truetype(r'C:\Windows\Fonts\msyhbd.ttc', 15)
except Exception:
    f = ImageFont.load_default()
    fb = f
for k in range(11):
    x = int(x0 + k * cw)
    d.line([(x, int(y0)), (x, int(y0 + 10 * ch))], fill=(190, 188, 175), width=1)
    if k < 10:
        d.text((x + 30, int(y0) - 16), 'c%d' % k, fill=(160, 158, 148), font=f)
for k in range(11):
    y = int(y0 + k * ch)
    d.line([(int(x0), y), (int(x0 + 10 * cw), y)], fill=(190, 188, 175), width=1)
    if k < 10:
        d.text((int(x0) - 26, y + 26), 'r%d' % k, fill=(160, 158, 148), font=f)

# 红斜线（答案镜）簇中心
reds = [(637, 320, 'R1'), (274, 392, 'R2'), (563, 538, 'R3'), (627, 516, 'R4'),
        (272, 680, 'R5'), (561, 899, 'R6'), (199, 972, 'R7')]
for cx, cy, tag in reds:
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], outline=(0, 180, 80), width=3)
    d.text((cx + 8, cy - 18), tag, fill=(0, 180, 80), font=fb)

# 黑斜线候选（网格内、方向接近45的暗簇）
blacks = [(385, 332), (675, 338), (378, 328), (669, 326), (666, 359), (595, 442),
          (673, 507), (678, 578), (671, 681), (714, 675), (602, 896), (639, 962)]
for cx, cy in blacks:
    d.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], outline=(30, 60, 220), width=3)

# 四边颜色口（OCR 归一化 -> 原图）
def conv(nx, ny):
    return nx * 914 / 1000, ny * 1626 / 1000
labels = [('紫', (590, 130, 660, 168)), ('橙', (745, 132, 813, 170)),
          ('绿', (38, 182, 86, 220)), ('蓝', (900, 208, 968, 246)),
          ('橙', (38, 310, 86, 348)), ('绿', (900, 312, 968, 350)),
          ('黄', (38, 400, 86, 438)), ('蓝', (38, 528, 86, 566)),
          ('紫', (900, 578, 968, 616)), ('红', (186, 622, 254, 660)),
          ('黄', (265, 622, 313, 660)), ('红', (654, 624, 702, 662))]
for txt, (x1, y1, x2, y2) in labels:
    bx1, by1 = conv(x1, y1)
    bx2, by2 = conv(x2, y2)
    d.rectangle([bx1, by1, bx2, by2], outline=(200, 120, 0), width=3)
    d.text((bx1, by1 - 6), txt, fill=(200, 120, 0), font=fb)

im.save('_maze_identify.png')
print('saved')
