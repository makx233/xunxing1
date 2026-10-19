# -*- coding: utf-8 -*-
# 网格定标校验图：画估算格线 + 红斜线簇标记，目测对齐
from PIL import Image, ImageDraw

im = Image.open('_maze_src.png').convert('RGB')
d = ImageDraw.Draw(im)

# 估算网格：x0=90, y0=280, 10格宽80, 10格高73
x0, y0, cw, ch = 90, 280, 80.0, 73.0
for k in range(11):
    x = int(x0 + k * cw)
    d.line([(x, y0 - 20), (x, y0 + 10 * ch + 20)], fill=(255, 0, 0), width=2)
for k in range(11):
    y = int(y0 + k * ch)
    d.line([(x0 - 20, y), (x0 + 10 * cw + 20, y)], fill=(255, 0, 0), width=2)

# 红斜线簇中心（网格内）
reds = [(615, 298), (650, 332), (275, 390), (623, 520), (540, 518),
        (656, 557), (576, 548), (251, 660), (256, 661), (280, 687), (301, 709)]
for cx, cy in reds:
    d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], outline=(0, 255, 0), width=2)

# 四边颜色字位置（OCR 归一化 -> 原图像素）
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
    d.rectangle([bx1, by1, bx2, by2], outline=(0, 0, 255), width=2)
    d.text((bx1, by1 - 8), txt, fill=(0, 0, 255))

im.save('_grid_check.png')
print('saved')
