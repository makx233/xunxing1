extends RefCounted
## 《寻星》前日谈 · 俯视角房间绘制。
##
## 这一版是照着参考图重做的：场景必须有"实体感"——
##   1. 墙不是框，是一面有正面的墙：墙顶受光、墙面中间调、墙脚压暗；
##   2. 地面是网格瓷砖，逐格灰度有细微变化，并且从墙脚往近端逐渐变暗（光衰减）；
##   3. 陈设（门 / 窗 / 柜 / 栏杆 / 桌）都是有厚度、有受光面、有投影的方块，不是空心线框；
##   4. 人物放大到约 2 格高，每个人有能一眼分开的剪影（发型 / 轮廓 / 明度对比）；
##   5. 统一用黑白灰 + 一点冷色/暖色的光，跟李星.png / 刘忆.png 的灰白手绘对齐。
##
## 坐标体系：逻辑单位。房间宽度固定 2400，格子边长 96（GLYPH 是"格"的谐音写法）。
## 绘制流程一律"先铺底 → 再画墙 → 再画地面 → 按 y 从远到近画家具 → 最后画人物"，
## 这样人物走到桌子后面会被桌子挡住，符合俯视角的直觉。
##
## 【踩过的坑，别改回去】
##   · CanvasItem 自己的 size 为 0 时画的内容会被裁掉，所以调用方必须先
##     set_anchors_and_offsets_preset(PRESET_FULL_RECT)；
##   · 缩放/平移只能用 draw_set_transform_matrix，且坐标要逐个手算（不要用 draw_set_transform
##     做缩放，Godot 4.7 / GL Compatibility 下它对 draw_polyline / draw_colored_polygon 会失效）；
##   · 三角形永远能三角化成功，凹四边形会让 draw_colored_polygon 报
##     "Invalid polygon data, triangulation failed" 并刷屏——几何一律优先用三角形。

const GLYPH := 96.0          # 格子边长（逻辑单位）
const ROOM_W := 2400.0       # 房间固定宽度

## 寝室贴图底（用户指定）：把俯视角程序化房间底换成这张漫画插画。
## 原图 2736x1536。顶部 y0..400 是空白天花板（纯白留白，已实测无内容），按用户
## 「最多截掉上下白色部分」的要求裁掉；主画面 1136px 高 → 宽高比 ≈2.41。
## 主画面铺满视带高度（724 逻辑 px，垂直零裁切）后宽约 1744 逻辑 px，比视带
## （约 1288）宽出约 456——镜头横向跟随时整幅图左右平移，走到图两端镜头夹死
## （背景停住、人物继续走向屏幕边缘）。
const DORM_BACKDROP := "res://assets/rooms/dorm_room.png"
const DORM_IMG_W := 2736.0
const DORM_IMG_H := 1536.0
const DORM_TRIM_TOP := 400.0          # 顶部白色留白（图像像素）
const DORM_W := 1744.0                # 图上屏宽度（逻辑 px）＝房间数据 floor_w
const DORM_H := 724.0                 # 图上屏高度（逻辑 px）＝视带高度

# ── 黑白灰基调 ────────────────────────────────────────────────────────────
const G_BG := Color(0.028, 0.028, 0.034)
const G_FLOOR_HI := Color(0.330, 0.330, 0.345)   # 靠墙（受光）
const G_FLOOR_LO := Color(0.175, 0.177, 0.190)   # 近端（背光）
const G_WALL_FACE := Color(0.215, 0.215, 0.228)
const G_WALL_TOP := Color(0.300, 0.300, 0.315)
const G_WALL_FOOT := Color(0.090, 0.090, 0.100)
const G_SEAM := Color(0.0, 0.0, 0.0, 0.30)
const G_EDGE := Color(0.74, 0.74, 0.78, 0.34)
const G_EDGE_HI := Color(0.90, 0.90, 0.94, 0.60)
const G_FURN_TOP := Color(0.360, 0.360, 0.380)
const G_FURN_FACE := Color(0.215, 0.215, 0.232)
const G_SHADOW := Color(0.0, 0.0, 0.0, 0.34)
const G_WARM := Color(0.98, 0.83, 0.58)
const G_COOL := Color(0.62, 0.72, 0.88)

var _room: Dictionary = {}
var _room_on := false
var _player := Vector2.ZERO
var _near: Dictionary = {}
var _items: Array = []
var _props: Array = []
var _popup := false
var _scale := 1.0
var _t := 0.0
## 每间房的"地砖灰度噪声"缓存，避免每帧重算；换房间时清空。
var _tile_seed := 0
## 寝室贴图底（懒加载缓存）
var _backdrop_tex: Texture2D = null
## 布置模式（F12）：隐形物品画幽灵框、选中物品画右下角改大小把手
var _edit_on := false
var _edit_sel := -1
## 玩家（李星）四方向贴图缓存与当前朝向
var _player_tex: Dictionary = {}
var _facing := Vector2(0, 1)


## 由 room_runtime 每帧调用：布置模式的开关与选中项
func set_edit(on: bool, sel: int) -> void:
	_edit_on = on
	_edit_sel = sel


## 由 room_runtime 每帧调用：玩家当前朝向（决定用哪个方向的贴图）
func set_facing(dir: Vector2) -> void:
	_facing = dir


## 由 prelude_backdrop 每帧调用。room 传空字典 = 退出俯视角模式。
func set_room(room: Dictionary, player: Vector2, near: Dictionary,
		items: Array, props: Array, popup: bool, scale: float, t: float) -> void:
	if room.is_empty():
		_room_on = false
		return
	if _room.get("title", "") != room.get("title", ""):
		_tile_seed = 0
	_room = room
	_player = player
	_near = near
	_items = items
	_props = props
	_popup = popup
	_scale = scale
	_t = t
	_room_on = true


func is_on() -> bool:
	return _room_on


# ── 坐标变换 ──────────────────────────────────────────────────────────────
## 取景：把「墙 + 地面」这块内容按高度装进视口（留一点上下边距），
## 这样地板能占满屏幕的大部分，而不是像第一版那样在画面中间挤成一条带。
## 房间比屏幕宽时镜头跟着玩家横向走；camera_follow=false 就固定居中。
const VIEW_MARGIN := 26.0

func xform(win: Vector2) -> Transform2D:
	var s := _view_scale(win)
	var view_w := win.x / s
	# 【坑】镜头夹取的范围用"房间真正的横向范围"（_cam_rect，0..ROOM_W），
	# 不能用 _geom_rect——后者为了铺底色故意向左右各外扩了 2400，
	# 拿它做 clamp 会让镜头停在 -1200 附近，画面左边露出一条底色黑带。
	# 【关键·已修】在 _cam_rect 之上再向外放宽 view_w/2：
	# 这样镜头跟到房间两端也不会被夹住，人物**永远**留在画面正中，
	# 人物与场景严格 1:1 移动。旧版把 clamp 卡死在房间边界上，
	# 人物一走到两端镜头就停住，于是"人物独自滑过静止的画面"
	# （用户反馈：「人物移动到场景边缘后人物移动速度远大于场景移动速度」）。
	# 越界那一小段由 _draw_end_fade 渐隐到黑、地面多铺 _lateral_extend 兜住，
	# 画面里不会露底色。
	var cam := _cam_rect()
	var off_x := 0.0
	if bool(_room.get("camera_follow", true)) and view_w < cam.size.x:
		if _backdrop_active():
			# 贴图底（寝室）：镜头夹在图幅 [0, DORM_W] 内，经典横版卷轴。
			# 人物走到图两端时镜头停住、人物继续走向屏幕边缘（背景不动人物动）。
			off_x = clampf(_player.x - view_w * 0.5, 0.0, cam.size.x - view_w)
		else:
			var pad := view_w * 0.5
			off_x = clampf(_player.x - view_w * 0.5,
					cam.position.x - pad, cam.end.x + pad - view_w)
	else:
		off_x = cam.position.x + (cam.size.x - view_w) * 0.5
	var off_y := (win.y - _room_height() * s) * 0.5
	return Transform2D(0.0, Vector2(s, s), 0.0, Vector2(-off_x * s, off_y))


## 取景缩放：先按"内容高度装得下"定一个上限，再夹到 room.scale。
## xform 与 draw_room 都走这一支，免得两处各算一遍算岔。
func _view_scale(win: Vector2) -> float:
	var s := _scale
	if s <= 0.0:
		s = 1.0
	var fit := (win.y - VIEW_MARGIN * 2.0) / maxf(1.0, _room_height())
	s = minf(s, fit)
	if s <= 0.05:
		s = 0.05
	return s


## 横向要多铺几格地面：镜头允许越过房间两端 view_w/2，
## 所以地面至少要比房间多铺这么宽，否则画面左右会露出底色。
## 取整到整格，地砖接缝才和房间里原有的那套对得上。
func _lateral_extend(view_w: float) -> float:
	var need := view_w * 0.5 + GLYPH * 2.0
	return ceilf(need / GLYPH) * GLYPH


## 房间真正的横向范围（寝室贴图底＝图幅宽 DORM_W，其余＝房间宽）
func _cam_rect() -> Rect2:
	if _backdrop_active():
		return Rect2(0.0, 0.0, DORM_W, _room_height())
	return Rect2(0.0, 0.0, maxf(ROOM_W, _floor_rect().end.x), _room_height())


func _room_height() -> float:
	var rows := int(_room.get("wall_rows", 3)) + int(_room.get("floor_rows", 5))
	return float(rows) * GLYPH


func _wall_h() -> float:
	return float(int(_room.get("wall_rows", 3))) * GLYPH


func _floor_rect() -> Rect2:
	var x := float(_room.get("floor_x", 120.0))
	var w := float(_room.get("floor_w", ROOM_W - 240.0))
	var y := _wall_h()
	var h := float(int(_room.get("floor_rows", 5))) * GLYPH
	return Rect2(x, y, w, h)


func _col(v: Variant, fallback: Color) -> Color:
	if v is Array:
		var a: Array = v
		if a.size() >= 4:
			return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
		if a.size() >= 3:
			return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## 轴对齐的椭圆（影子 / 光斑）。
## 【坑·已修】以前这两处是「draw_set_transform_matrix(压扁) + draw_circle + 复位成 IDENTITY」，
## 而 draw_room 是靠**一次**变换矩阵把整个房间从逻辑坐标画到屏幕的——那两处一复位，
## 后面所有绘制（人物、近端压暗、两端渐隐、四角压暗）就全跑到"屏幕坐标"里去了：
## 镜头跟随时场景在动、人物却按逻辑坐标原地画 → 人物相对场景约 2 倍速乱飘
## （用户反馈：「人物移动到场景边缘后人物移动速度远大于场景移动速度」）。
## 所以：不要在任何绘制函数里碰 draw_set_transform_matrix，椭圆就用多边形画。
func _draw_ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float,
		col: Color, segs := 32) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


# ── 主入口 ────────────────────────────────────────────────────────────────
func draw_room(ci: CanvasItem) -> void:
	var wall_h := _wall_h()
	var floor_r := _floor_rect()
	var th: Dictionary = _room.get("theme", {}) as Dictionary
	var light_c := _col(th.get("light", [0.96, 0.86, 0.66]), G_WARM)

	# 0. 取景：**整张房间都用 Room 逻辑坐标画**，最后靠一次变换矩阵缩放到屏幕。
	#    【坑】这个矩阵必须在最前面设一次——之前忘了设，房间就按 1:1 画，
	#    2400 宽的走廊只有屏幕左边四分之一可见，看起来像"左边一条黑带"。
	var win := ci.get_viewport_rect().size
	ci.draw_set_transform_matrix(xform(win))
	# 镜头两端会越过房间边界，地面要横向多铺 ext 格；越界那头靠渐隐到黑收边
	var ext := _lateral_extend(win.x / _view_scale(win))

	# 【寝室贴图底】标题为「寝室」的房间（dorm_room / dorm_after）不再画程序化的
	# 墙 / 地面，改用整幅插画当背景；镜头照旧横向跟着玩家走，于是人物走动时
	# 背景图左右移动。前景只保留交互热区 / 标签 / 人物，灰色实心块不画。
	if _backdrop_active():
		_draw_image_backdrop(ci, win)
		_draw_image_room_overlays(ci, light_c)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return

	# 1. 底色：铺得比房间宽得多，镜头跟着玩家走时两侧不会露出黑边
	ci.draw_rect(Rect2(-6000, -600, ROOM_W + 12000, _room_height() + 1400), G_BG)

	# 2. 墙：正面 → 墙面上的陈设（门窗）→ 墙顶压条 → 墙脚
	#    墙面用"横向色带"做出上暗下亮的环境光，比 GradientTexture2D 可控：
	#    贴图会被拉伸到 2400 宽，第一版这么做时整面墙发白。
	var wall_base := _col(th.get("wall", [0.215, 0.215, 0.228]), G_WALL_FACE)
	var bands := 22
	for i in bands:
		var k := float(i) / float(bands - 1)
		var c := wall_base.darkened(0.30 - 0.30 * k)
		c = c.lerp(wall_base.lerp(light_c, 0.05), k * 0.55)
		ci.draw_rect(Rect2(-6000, wall_h * k, ROOM_W + 12000, wall_h / float(bands) + 1.0), c)
	for p in _props:
		var d: Dictionary = p
		if not bool(d.get("on_wall", false)):
			continue
		_draw_wall_prop(ci, d, wall_h, light_c)
	ci.draw_rect(Rect2(-6000, 0.0, ROOM_W + 12000, 5.0), G_WALL_TOP)
	ci.draw_rect(Rect2(-6000, wall_h - 12.0, ROOM_W + 12000, 12.0), G_WALL_FOOT.lerp(wall_base, 0.25))

	# 3. 地面：网格瓷砖 + 光衰减（横向多铺 ext 格，兜住越界的镜头）
	_draw_floor(ci, Rect2(floor_r.position.x - ext, floor_r.position.y,
			floor_r.size.x + ext * 2.0, floor_r.size.y), light_c)

	# 4. 地面上的陈设与可交互物件，按 y 从远到近（谁靠前谁后画）
	var ground: Array = []
	for p in _props:
		var d: Dictionary = p
		if bool(d.get("on_wall", false)):
			continue
		ground.append(d)
	for p in _items:
		ground.append(p)
	ground.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))
	for d in ground:
		if d.has("name"):
			var vis := int(d.get("vis", 1))
			var is_nr: bool = d == _near
			if vis == 0:
				# 隐形：平时不画；靠近（或编辑选中）时亮边缘+名称，编辑时画幽灵框
				if _edit_on and not is_nr:
					_draw_item_ghost(ci, d)
				elif _edit_on or is_nr:
					_draw_item_near_only(ci, d, is_nr, light_c)
				else:
					continue
			elif vis == 2:
				# 靠近时显示：平时隐形，靠近（或编辑时）亮边缘 + 名称
				if not _edit_on and not is_nr:
					continue
				_draw_item_near_only(ci, d, is_nr, light_c)
			else:
				_draw_item(ci, d, is_nr, light_c)
			if _edit_on and is_nr:
				_draw_edit_handle(ci, d)
		else:
			_draw_block(ci, d, light_c)

	# 6. 人物（按 y 排序，谁靠前谁后画）
	_draw_actors(ci, floor_r)
	# 人物之后再描一遍靠近物件的名称标签，人物不会把字挡住（同贴图底模式）
	if not _near.is_empty():
		_draw_item_tag(ci, _near, true)

	# 7. 近端压暗 + 两端渐隐 + 四角压暗，把视线收到房间中间
	ci.draw_rect(Rect2(-6000, floor_r.end.y, ROOM_W + 12000, 600.0), G_BG)
	_draw_end_fade(ci, floor_r, ext)
	_draw_vignette(ci)
	# 8. 走廊尽头那扇窗投在地上的光斑（参考图里房间也是有一处主光的）
	_draw_light_pool(ci, floor_r, light_c)
	# 9. 收尾：复位变换矩阵，别把别的绘制（比如标题条）也缩了
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# ── 寝室贴图底 ────────────────────────────────────────────────────────────
## 懒加载贴图：优先走 Godot 导入（ResourceLoader）；编辑器还没生成 .import 时
## 直接读文件兜底，保证把图拷进工程即可看到效果。
func _load_backdrop() -> Texture2D:
	if _backdrop_tex != null:
		return _backdrop_tex
	if ResourceLoader.exists(DORM_BACKDROP):
		var r: Variant = load(DORM_BACKDROP)
		if r is Texture2D:
			_backdrop_tex = r
			return _backdrop_tex
	if FileAccess.file_exists(DORM_BACKDROP):
		var fs := ProjectSettings.globalize_path(DORM_BACKDROP)
		if fs != "":
			var img := Image.load_from_file(fs)
			if img != null:
				_backdrop_tex = ImageTexture.create_from_image(img)
				return _backdrop_tex
	return null


## 房间数据里写了 bg_image 字段，或者是标题为「寝室」的房间，都用贴图底
func _backdrop_active() -> bool:
	var bg_path := String(_room.get("bg_image", ""))
	if bg_path != "":
		return _load_custom_backdrop(bg_path) != null
	return String(_room.get("title", "")) == "寝室" and _load_backdrop() != null


## 加载房间数据里指定的自定义背景图
func _load_custom_backdrop(path: String) -> Texture2D:
	var key := "custom:" + path
	if _backdrop_tex != null and _backdrop_tex.get_meta("path", "") == path:
		return _backdrop_tex
	if ResourceLoader.exists(path):
		var r: Variant = load(path)
		if r is Texture2D:
			_backdrop_tex = r
			_backdrop_tex.set_meta("path", path)
			return _backdrop_tex
	if FileAccess.file_exists(path):
		var fs := ProjectSettings.globalize_path(path)
		var img := Image.new()
		var err := img.load(fs)
		if err == OK:
			_backdrop_tex = ImageTexture.create_from_image(img)
			_backdrop_tex.set_meta("path", path)
			return _backdrop_tex
	return null


## 把背景图铺进房间逻辑坐标：整幅图高＝视带高，垂直零裁切；宽度按比例缩放，
## 镜头跟随时左右平移。寝室图保持原有裁切逻辑，自定义图直接整幅画。
func _draw_image_backdrop(ci: CanvasItem, win: Vector2) -> void:
	var s := _view_scale(win)
	var band_h := win.y / s
	var off_y := (win.y - _room_height() * s) * 0.5
	# 兜底暗色：极端情况下（贴图加载失败等）也不露底色
	ci.draw_rect(Rect2(-600, -1200, 3000, _room_height() + 2600), G_BG)

	var bg_path := String(_room.get("bg_image", ""))
	if bg_path != "":
		# 自定义背景图：整幅拉伸铺满视带高度
		var tex := _load_custom_backdrop(bg_path)
		if tex != null:
			var img_w := tex.get_width()
			var img_h := tex.get_height()
			# 按视带高度等比缩放
			var draw_h := band_h
			var draw_w := float(img_w) / float(img_h) * draw_h
			var top := (band_h - draw_h) * 0.5
			ci.draw_texture_rect(tex,
					Rect2(0.0, off_y + top, draw_w, draw_h),
					false, Color.WHITE)
		return

	# 寝室贴图底（原有逻辑）
	var tex := _load_backdrop()
	if tex != null:
		var top := (band_h - DORM_H) * 0.5
		ci.draw_texture_rect_region(tex,
				Rect2(0.0, off_y + top, DORM_W, DORM_H),
				Rect2(0.0, DORM_TRIM_TOP, DORM_IMG_W, DORM_IMG_H - DORM_TRIM_TOP),
				Color.WHITE)


## 贴图底模式的前景：墙面 / 地面陈设只画标签（图里已有家具，不叠灰色实心块），
## 可交互物件保留热区框 / 呼吸高亮 / 勾选 / 标签，最后画人物与四角压暗。
func _draw_image_room_overlays(ci: CanvasItem, light_c: Color) -> void:
	# 与可交互物件同名的陈设标签跳过（物件标签已含，避免"室友的书桌/衣柜"出现两行）
	var item_names := {}
	for d in _items:
		item_names[String(d.get("name", ""))] = true
	# 墙面陈设标签（门窗 / 洞洞板…）
	for p in _props:
		var d: Dictionary = p
		if not bool(d.get("on_wall", false)):
			continue
		if item_names.has(String(d.get("label", ""))):
			continue
		_draw_prop_label(ci, d)
	# 地面陈设标签（衣柜 / 书桌 / 椅子 / 床…）
	for p in _props:
		var d: Dictionary = p
		if bool(d.get("on_wall", false)):
			continue
		if item_names.has(String(d.get("label", ""))):
			continue
		_draw_prop_label(ci, d)
	# 可交互物件：热区框 + 高亮 + 勾选 + 标签（隐形/靠近时显示按 vis 分支；靠近一律亮边缘+名称）
	for d in _items:
		var vis := int(d.get("vis", 1))
		var is_nr: bool = d == _near
		if vis == 0:
			if _edit_on and not is_nr:
				_draw_item_ghost(ci, d)
			elif _edit_on or is_nr:
				_draw_item_near_only(ci, d, is_nr, light_c)
			else:
				continue
		elif vis == 2:
			if not _edit_on and not is_nr:
				continue
			_draw_item_near_only(ci, d, is_nr, light_c)
		else:
			_draw_item(ci, d, is_nr, light_c)
		if _edit_on and is_nr:
			_draw_edit_handle(ci, d)
	# 人物（玩家 + 第二个人）
	_draw_actors(ci, _floor_rect())
	# 人物之后再描一遍当前靠近物件的名称标签：人物贴图很高，站在桌前
	# 会把物件上方的字挡住（用户要求：人物不能遮挡靠近时的字样）
	if not _near.is_empty():
		_draw_item_tag(ci, _near, true)
	# 四角轻压暗，保证标题 / 提示 / 按钮文字读得清
	_draw_vignette(ci)


## 贴图底模式下只画陈设标签；数据里的 y 已按图上家具位置标定（见
## data/prelude_rooms.json 的 dorm_room / dorm_after），标签取 (x+6, y-10)
func _draw_prop_label(ci: CanvasItem, d: Dictionary) -> void:
	var label := String(d.get("label", ""))
	if label == "":
		return
	var x := float(d["x"])
	var ly := float(d.get("y", 0.0)) - 10.0
	_draw_label(ci, label, Vector2(x + 6.0, ly), 16, Color(0.86, 0.86, 0.90, 0.72))


# ── 地面 ──────────────────────────────────────────────────────────────────
func _draw_floor(ci: CanvasItem, r: Rect2, light_c: Color) -> void:
	ci.draw_rect(r, G_FLOOR_LO)
	var cols := int(ceil(r.size.x / GLYPH))
	var rows := int(round(r.size.y / GLYPH))
	for iy in rows:
		var y := r.position.y + float(iy) * GLYPH
		# 距墙越远越暗：把"光照衰减"做在灰度上，而不是叠一层半透明黑，
		# 这样瓷砖之间的接缝不会被蒙掉。
		var k := 1.0 - float(iy) / maxf(1.0, float(rows - 1))
		var base := G_FLOOR_LO.lerp(G_FLOOR_HI, k * k)
		for ix in cols:
			var x := r.position.x + float(ix) * GLYPH
			var w := minf(GLYPH, r.end.x - x)
			if w <= 0.0:
				continue
			var h := minf(GLYPH, r.end.y - y)
			var n := _tile_noise(ix, iy)
			var c := base.lightened(n * 0.055)
			# 靠墙的两行接一点窗外光，偏暖
			if k > 0.62:
				c = c.lerp(light_c, 0.05 * k)
			ci.draw_rect(Rect2(x, y, w + 0.6, h + 0.6), c)
			ci.draw_line(Vector2(x, y + 0.5), Vector2(x + w, y + 0.5), G_SEAM, 1.0)
			ci.draw_line(Vector2(x + 0.5, y), Vector2(x + 0.5, y + h), G_SEAM, 1.0)


## 四角压暗：让画面中心成为视觉焦点（参考图里房间四周也是暗下去的）
func _draw_vignette(ci: CanvasItem) -> void:
	for i in 3:
		var k := float(i) / 3.0
		var inset := 46.0 * (1.0 - k)
		# 上边两条斜带
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(-400.0 + inset, -10.0 - inset), Vector2(1200.0, -10.0 - inset),
			Vector2(1200.0, 90.0 + inset), Vector2(-400.0, 90.0 + inset),
		]), Color(0.0, 0.0, 0.0, 0.10 + 0.06 * k))
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(1200.0, -10.0 - inset), Vector2(2800.0 + inset, -10.0 - inset),
			Vector2(2800.0 + inset, 90.0 + inset), Vector2(1200.0, 90.0 + inset),
		]), Color(0.0, 0.0, 0.0, 0.10 + 0.06 * k))
	# 左右两端不再用等宽的暗带（见 _draw_end_fade）


## 左右两端：从地面边缘向外**渐次加深**，让走廊在两端"没入黑暗"。
## 镜头现在允许越过房间两端（xform 里的 pad），越界的那段就靠这条渐变兜住；
## 同时也让玩家一眼看出"走到头了"，而不是撞上一堵看不见的墙。
func _draw_end_fade(ci: CanvasItem, fr: Rect2, ext: float) -> void:
	var steps := 12
	var h := _room_height()
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var a := 0.88 * pow(t1, 1.7)
		var d0 := ext * t0
		var d1 := ext * t1
		ci.draw_rect(Rect2(fr.position.x - d1, 0.0, d1 - d0, h), Color(0, 0, 0, a))
		ci.draw_rect(Rect2(fr.end.x + d0, 0.0, d1 - d0, h), Color(0, 0, 0, a))


## 主光落在店里地上的光斑：一圈由亮到无的暖色，位置取房间里的灯/窗
func _draw_light_pool(ci: CanvasItem, floor_r: Rect2, light_c: Color) -> void:
	var cx := ROOM_W * 0.5
	var cy := floor_r.position.y + floor_r.size.y * 0.34
	if not _props.is_empty():
		# 有灯就用灯的位置，没灯就落在房间中段
		for p in _props:
			var d: Dictionary = p
			if String(d.get("kind", "")) == "window":
				cx = float(d.get("x", cx)) + float(d.get("w", 0.0)) * 0.5
				break
	for i in 7:
		var t := float(i) / 6.0
		var r := 640.0 * (1.0 - t * 0.78)
		var a := 0.032 * (1.0 - t) * (1.0 - t)
		_draw_ellipse(ci, Vector2(cx, cy), r, r * 0.52,
				Color(light_c.r, light_c.g, light_c.b, a), 48)


func _tile_noise(ix: int, iy: int) -> float:	# 便宜的确定性噪声：同一格每帧都一样，不会闪
	var n := (ix * 73856093) ^ (iy * 19349663) ^ (_tile_seed * 83492791)
	n = (n ^ (n >> 13)) & 0x7fffffff
	return float(n % 1000) / 1000.0


# ── 墙面陈设：门 / 窗 ─────────────────────────────────────────────────────
func _draw_wall_prop(ci: CanvasItem, d: Dictionary, wall_h: float, light_c: Color) -> void:
	var kind := String(d.get("kind", "rect"))
	var x := float(d["x"])
	var w := float(d["w"])
	var label := String(d.get("label", ""))
	match kind:
		"window":
			var y := float(d["y"])
			var h := float(d["h"])
			# 窗：外框 + 玻璃 + 十字窗棂 + 透出来的光
			ci.draw_rect(Rect2(x, y, w, h), Color(0.62, 0.62, 0.68).lerp(light_c, 0.18))
			ci.draw_rect(Rect2(x + 5, y + 5, w - 10, h - 10), light_c.lerp(Color(0.92, 0.93, 0.98), 0.55))
			ci.draw_line(Vector2(x + w * 0.5, y + 5), Vector2(x + w * 0.5, y + h - 5), G_WALL_FACE, 6.0)
			ci.draw_line(Vector2(x + 5, y + h * 0.5), Vector2(x + w - 5, y + h * 0.5), G_WALL_FACE, 6.0)
			ci.draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0), false, 5.0)
			_draw_label(ci, label, Vector2(x + 6, y - 8), 15)
		"door":
			# 教室 / 寝室的门：门框比墙略深，门板比墙略浅，中间一竖条门缝
			var y2 := wall_h - float(d.get("h", 150.0))
			var h2 := float(d.get("h", 150.0))
			ci.draw_rect(Rect2(x - 8, y2 - 6, w + 16, h2 + 6), G_WALL_FACE.darkened(0.34))
			ci.draw_rect(Rect2(x, y2, w, h2), G_WALL_FACE.lightened(0.10))
			ci.draw_line(Vector2(x + w * 0.5, y2), Vector2(x + w * 0.5, y2 + h2), G_SEAM, 2.0)
			# 门上观察窗
			ci.draw_rect(Rect2(x + w * 0.22, y2 + 20, w * 0.56, 34), Color(0.70, 0.74, 0.80, 0.72))
			# 门把手
			ci.draw_circle(Vector2(x + w - 16, y2 + h2 * 0.52), 5.0, G_EDGE_HI)
			_draw_label(ci, label, Vector2(x + 6, y2 - 12), 15)
		"locker":
			# 书架 / 柜子：一排格
			var y3 := wall_h - float(d.get("h", 150.0))
			var h3 := float(d.get("h", 150.0))
			ci.draw_rect(Rect2(x - 6, y3 - 6, w + 12, h3 + 6), G_WALL_FACE.darkened(0.36))
			ci.draw_rect(Rect2(x, y3, w, h3), G_FURN_FACE)
			var bays := maxi(1, int(w / 110.0))
			for i in bays:
				var bx := x + float(i) * w / float(bays)
				ci.draw_line(Vector2(bx, y3), Vector2(bx, y3 + h3), G_EDGE, 2.0)
				# 每格里几条"书脊"
				var n := int(_tile_noise(i, 3) * 3.0) + 2
				for j in n:
					var sx := bx + 12.0 + float(j) * 14.0
					if sx > bx + w / float(bays) - 14.0:
						break
					var hh := 34.0 + _tile_noise(i, j) * 52.0
					ci.draw_rect(Rect2(sx, y3 + h3 - hh - 8, 9.0, hh),
							G_FURN_TOP.darkened(0.10 + _tile_noise(j, i) * 0.30))
			_draw_label(ci, label, Vector2(x + 6, y3 - 12), 15)
		"board":
			# 洞洞板：整块挂在墙上的多孔板，上面插着可左右挪的隔板（第 4 关的线索就在这上面）
			var y4 := wall_h - float(d.get("h", 120.0))
			var h4 := float(d.get("h", 120.0))
			ci.draw_rect(Rect2(x - 6, y4 - 6, w + 12, h4 + 6), G_WALL_FACE.darkened(0.30))
			ci.draw_rect(Rect2(x, y4, w, h4), Color(0.315, 0.310, 0.335))
			# 孔：小圆点网格（判据只看数据，别在这里藏谜底）
			var cols := maxi(1, int(w / 20.0))
			var rows := maxi(1, int(h4 / 20.0))
			for i in cols:
				for j in rows:
					var px := x + 10.0 + float(i) * w / float(cols)
					var py := y4 + 10.0 + float(j) * h4 / float(rows)
					ci.draw_circle(Vector2(px, py), 2.0, Color(0, 0, 0, 0.42))
			# 两块插板：横向长条，插在孔里，位置由数据里的 board_shelves 决定（没有就用默认）
			var shelves: Array = d.get("shelves", [0.16, 0.66])
			for i in shelves.size():
				var f := float(shelves[i])
				ci.draw_rect(Rect2(x + w * f, y4 + h4 * 0.30, w * 0.20, 13.0),
						G_FURN_TOP.darkened(0.12))
				ci.draw_rect(Rect2(x + w * f, y4 + h4 * 0.30, w * 0.20, 13.0),
						G_SEAM, false, 1.4)
			_draw_label(ci, label, Vector2(x + 6, y4 - 12), 15)
		_:
			_draw_block(ci, d, light_c)


# ── 陈设方块（有厚度、有投影） ────────────────────────────────────────────
func _draw_block(ci: CanvasItem, d: Dictionary, light_c: Color) -> void:
	var r := Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))
	var lift := float(d.get("lift", minf(r.size.y * 0.34, 34.0)))
	_soft_shadow(ci, r, lift)
	var face := Rect2(r.position.x, r.position.y + lift, r.size.x, r.size.y)
	ci.draw_rect(face, G_FURN_FACE)
	# 顶面：往上抬 lift，比正面亮，做出俯视角里"看到一点台面"的感觉
	var top := PackedVector2Array([
		Vector2(r.position.x, r.position.y + lift),
		Vector2(r.position.x + r.size.x, r.position.y + lift),
		Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x, r.position.y),
	])
	ci.draw_colored_polygon(top, G_FURN_TOP)
	# 受光边（光从左上打）
	ci.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x + r.size.x, r.position.y),
			G_EDGE_HI, 2.0)
	ci.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.position.y + r.size.y),
			G_EDGE, 1.6)
	ci.draw_rect(face, G_SEAM, false, 1.6)
	var label := String(d.get("label", ""))
	if label != "":
		_draw_label(ci, label, Vector2(r.position.x + 6, r.position.y - 10), 15)


func _soft_shadow(ci: CanvasItem, r: Rect2, lift: float) -> void:
	# 三段式投影：不是一块死黑的矩形，边缘一层比一层浅
	var off := lift * 0.55
	for i in 3:
		var g := float(i)
		var rr := Rect2(r.position.x - g * 5.0 + 4.0, r.position.y + off - g * 3.0,
				r.size.x + g * 10.0, r.size.y + g * 6.0)
		ci.draw_rect(rr, Color(0, 0, 0, 0.13 - g * 0.035))


# ── 可交互物件 ────────────────────────────────────────────────────────────

## 有贴图的物件（用户提供的生活照，已去白底）：房间里直接画图片替代灰色占位块，
## 位置/大小仍取房间数据里物件自己的热区矩形，交互判定不变。
const ITEM_TEX := {
	"一些小纸片": "res://assets/props/paper_scraps.png",
	"jajo可乐": "res://assets/props/cola_can.png",
	# 第一天桌面三样新物件（用户给的微信参考图裁出，透明底小图标）
	"手机": "res://assets/props/phone.png",
	"黑箱": "res://assets/props/black_box.png",
	"折纸星星": "res://assets/props/paper_star.png",
	# 杯垫（用户提供的 XSer 杯垫图，透明底）
	"一个杯垫": "res://assets/props/coaster.png",
	"书后的折纸星星": "res://assets/props/paper_star.png",
}
## 这几件贴图物件不画脚下椭圆影子（用户要求：小纸片不要影子）
const ITEM_NO_SHADOW := {
	"一些小纸片": true,
}
var _item_tex: Dictionary = {}


## 懒加载物件贴图：优先走 Godot 导入，编辑器没生成 .import 时直接读文件兜底
func _load_item_tex(nm: String) -> Texture2D:
	if _item_tex.has(nm):
		return _item_tex[nm]
	if not ITEM_TEX.has(nm):
		return null
	var pth: String = ITEM_TEX[nm]
	if ResourceLoader.exists(pth):
		var r: Variant = load(pth)
		if r is Texture2D:
			_item_tex[nm] = r
			return r
	if FileAccess.file_exists(pth):
		var fs := ProjectSettings.globalize_path(pth)
		if fs != "":
			var img := Image.load_from_file(fs)
			if img != null:
				var tex := ImageTexture.create_from_image(img)
				_item_tex[nm] = tex
				return tex
	return null


## 贴图版物件：小椭圆投影 + 等比缩放进热区矩形（贴住底边、水平居中），
## 靠近高亮 / 看过的勾 / 名称标签与黑框版保持一致
func _draw_item_sprite(ci: CanvasItem, d: Dictionary, r: Rect2, tex: Texture2D,
		is_near: bool, light_c: Color) -> void:
	var asp := float(tex.get_width()) / float(tex.get_height())
	var h := r.size.y
	var w := h * asp
	if w > r.size.x:
		w = r.size.x
		h = w / asp
	var pos := Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + r.size.y - h)
	if not ITEM_NO_SHADOW.has(String(d.get("name", ""))):
		_draw_ellipse(ci, Vector2(pos.x + w * 0.5, pos.y + h), w * 0.5, w * 0.20,
				Color(0, 0, 0, 0.30))
	ci.draw_texture_rect(tex, Rect2(pos, Vector2(w, h)), false)
	if is_near:
		var pulse: float = 0.42 + 0.30 * abs(sin(_t * 3.0))
		ci.draw_rect(Rect2(pos.x - 5.0, pos.y - 5.0, w + 10.0, h + 10.0),
				Color(light_c.r, light_c.g, light_c.b, pulse * 0.5), false, 3.0)
		var ax: float = pos.x + w * 0.5
		var ay: float = pos.y - 16.0 - abs(sin(_t * 3.0)) * 5.0
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(ax, ay + 12.0), Vector2(ax - 8.0, ay), Vector2(ax + 8.0, ay),
		]), Color(light_c.r, light_c.g, light_c.b, 0.92))
	if bool(d.get("seen", false)):
		var cx: float = pos.x + w - 12.0
		var cy: float = pos.y + h - 4.0
		ci.draw_line(Vector2(cx - 9, cy - 5), Vector2(cx - 3, cy + 1), G_EDGE_HI, 3.0)
		ci.draw_line(Vector2(cx - 3, cy + 1), Vector2(cx + 8, cy - 11), G_EDGE_HI, 3.0)
	_draw_item_tag(ci, d, is_near)


## 物件名称标签：浅米色圆角底板 + 深色字（用户反馈：以前的裸字和背景混在一起看不清）。
## 物件的三条绘制路径（贴图版 / 黑框版 / 靠近时显示版）都走这里；
## is_near 时底板更实、字更黑，平时半透明、字稍浅。
func _draw_item_tag(ci: CanvasItem, d: Dictionary, is_near: bool) -> void:
	var nm := String(d.get("name", ""))
	if nm == "":
		return
	var f := ThemeDB.fallback_font
	if f == null:
		return
	var size := 16
	var pos := Vector2(float(d["x"]) + 6.0, float(d["y"]) - 12.0)
	var ts := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var plate := Rect2(pos.x - 5.0, pos.y - f.get_ascent(size) - 3.0,
			ts.x + 10.0, f.get_height(size) + 6.0)
	var sb := _tag_style()
	sb.bg_color = Color(0.99, 0.97, 0.90, 0.95) if is_near else Color(0.98, 0.96, 0.89, 0.78)
	ci.draw_style_box(sb, plate)
	ci.draw_string(f, pos, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			Color(0.14, 0.11, 0.09) if is_near else Color(0.30, 0.25, 0.20, 0.95))


## 标签底板样式缓存：每帧都要画，避免反复 new StyleBoxFlat
var _tag_sb: StyleBoxFlat = null

func _tag_style() -> StyleBoxFlat:
	if _tag_sb == null:
		_tag_sb = StyleBoxFlat.new()
		_tag_sb.set_border_width_all(1)
		_tag_sb.border_color = Color(0.22, 0.18, 0.14, 0.50)
		_tag_sb.set_corner_radius_all(4)
	return _tag_sb


## 布置模式：隐形物品的幽灵框（正常游玩不画，编辑时画出来方便找到）
func _draw_item_ghost(ci: CanvasItem, d: Dictionary) -> void:
	var r := Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))
	ci.draw_rect(r, Color(0.10, 0.10, 0.13, 0.16))
	ci.draw_rect(r, Color(0.40, 0.40, 0.48, 0.30), false, 1.4)
	var nm := String(d.get("name", ""))
	if nm != "":
		_draw_label(ci, nm, Vector2(r.position.x + 6, r.position.y - 10), 14,
				Color(0.58, 0.58, 0.62, 0.45))


## 靠近时显示：平时完全隐形，靠近（或布置模式）时亮起暖色边缘 + 名称
func _draw_item_near_only(ci: CanvasItem, d: Dictionary, is_near: bool, light_c: Color) -> void:
	var r := Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))
	# 半透明底面：让图上家具透出来，不挡画面
	ci.draw_rect(Rect2(r.position.x, r.position.y + 14.0, r.size.x, r.size.y),
			Color(G_FURN_FACE.r, G_FURN_FACE.g, G_FURN_FACE.b, 0.30))
	var pulse: float = 0.45 + 0.30 * abs(sin(_t * 3.0)) if is_near else 0.32
	ci.draw_rect(r, Color(light_c.r, light_c.g, light_c.b, pulse), false, 2.5)
	_draw_item_tag(ci, d, is_near)
	if is_near:
		var ax: float = r.position.x + r.size.x * 0.5
		var ay: float = r.position.y - 16.0 - abs(sin(_t * 3.0)) * 5.0
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(ax, ay + 12.0), Vector2(ax - 8.0, ay), Vector2(ax + 8.0, ay),
		]), Color(light_c.r, light_c.g, light_c.b, 0.92))


## 布置模式：选中物品右下角的改大小把手
func _draw_edit_handle(ci: CanvasItem, d: Dictionary) -> void:
	var r := Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))
	var c := Vector2(r.end.x, r.end.y)
	var hs := 16.0
	ci.draw_rect(Rect2(c.x - hs, c.y - hs, hs, hs), Color(0.98, 0.72, 0.35, 0.95))
	ci.draw_rect(Rect2(c.x - hs, c.y - hs, hs, hs), Color(1.0, 1.0, 1.0, 0.90), false, 2.0)
	ci.draw_line(Vector2(c.x - hs + 4.0, c.y - 4.0), Vector2(c.x - 4.0, c.y - hs + 4.0),
			Color(0.35, 0.22, 0.08, 0.90), 2.0)


func _draw_item(ci: CanvasItem, d: Dictionary, is_near: bool, light_c: Color) -> void:
	var r := Rect2(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))
	var tex := _load_item_tex(String(d.get("name", "")))
	if tex != null:
		_draw_item_sprite(ci, d, r, tex, is_near, light_c)
		return
	_soft_shadow(ci, r, 16.0)
	var face_c := G_FURN_FACE.lightened(0.06) if is_near else G_FURN_FACE
	ci.draw_rect(Rect2(r.position.x, r.position.y + 14.0, r.size.x, r.size.y), face_c)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x, r.position.y + 14.0),
		Vector2(r.position.x + r.size.x, r.position.y + 14.0),
		Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x, r.position.y),
	]), G_FURN_TOP.lightened(0.06) if is_near else G_FURN_TOP)
	if is_near:
		# 呼吸高亮：外圈暖色 + 头顶一个小箭头（比小圆点更容易看见）
		var pulse: float = 0.42 + 0.30 * abs(sin(_t * 3.0))
		ci.draw_rect(Rect2(r.position.x - 5.0, r.position.y - 5.0, r.size.x + 10.0, r.size.y + 24.0),
				Color(light_c.r, light_c.g, light_c.b, pulse * 0.5), false, 3.0)
		var ax: float = r.position.x + r.size.x * 0.5
		var ay: float = r.position.y - 16.0 - abs(sin(_t * 3.0)) * 5.0
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(ax, ay + 12.0), Vector2(ax - 8.0, ay), Vector2(ax + 8.0, ay),
		]), Color(light_c.r, light_c.g, light_c.b, 0.92))
	else:
		ci.draw_rect(Rect2(r.position.x, r.position.y + 14.0, r.size.x, r.size.y),
				G_EDGE, false, 1.6)
	if bool(d.get("seen", false)):
		# 看过的打一个勾（右下角）
		var cx: float = r.position.x + r.size.x - 20.0
		var cy: float = r.position.y + r.size.y - 4.0
		ci.draw_line(Vector2(cx - 9, cy - 5), Vector2(cx - 3, cy + 1), G_EDGE_HI, 3.0)
		ci.draw_line(Vector2(cx - 3, cy + 1), Vector2(cx + 8, cy - 11), G_EDGE_HI, 3.0)
	_draw_item_tag(ci, d, is_near)


# ── 人物 ──────────────────────────────────────────────────────────────────

## 玩家四方向贴图（assets/sprites/lixing_down/up/left/right.png）
const PLAYER_TEX := {
	"down": "res://assets/sprites/lixing_down.png",
	"up": "res://assets/sprites/lixing_up.png",
	"left": "res://assets/sprites/lixing_left.png",
	"right": "res://assets/sprites/lixing_right.png",
}
const PLAYER_H := 352.0   # 贴图人物目标全身高（逻辑px，与程序化画法一致）


func _draw_actors(ci: CanvasItem, floor_r: Rect2) -> void:
	var list: Array = []
	list.append({"p": _player, "liu": false, "walk": true})
	var a: Array = _room.get("actor_a", []) as Array
	if a.size() >= 2:
		list.append({
			"p": Vector2(float(a[0]), float(a[1])),
			"liu": true,
			"walk": false,
			"s": float(a[2]) if a.size() >= 3 else 1.0,
		})
	list.sort_custom(func(x, y): return float((x["p"] as Vector2).y) < float((y["p"] as Vector2).y))
	for e in list:
		var p: Vector2 = e["p"]
		var is_liu := bool(e["liu"])
		var s := float(e.get("s", 1.0)) * float(_room.get("actor_scale", 1.0))
		var bob: float = sin(_t * 8.0) * 2.0 if bool(e["walk"]) else sin(_t * 1.6) * 1.0
		_draw_person(ci, p + Vector2(0, bob), s, is_liu, bool(e["walk"]))


## 懒加载玩家贴图：优先走 Godot 导入，编辑器没生成 .import 时直接读文件兜底
func _load_player_tex(key: String) -> Texture2D:
	if _player_tex.has(key):
		return _player_tex[key]
	if not PLAYER_TEX.has(key):
		return null
	var pth: String = PLAYER_TEX[key]
	if ResourceLoader.exists(pth):
		var r: Variant = load(pth)
		if r is Texture2D:
			_player_tex[key] = r
			return r
	if FileAccess.file_exists(pth):
		var fs := ProjectSettings.globalize_path(pth)
		if fs != "":
			var img := Image.load_from_file(fs)
			if img != null:
				var tex := ImageTexture.create_from_image(img)
				_player_tex[key] = tex
				return tex
	return null


## 按当前朝向选贴图：横移看左右，纵向看上下，静止默认朝下
func _player_sprite_tex() -> Texture2D:
	var k := "down"
	if absf(_facing.x) > absf(_facing.y):
		k = "left" if _facing.x < 0.0 else "right"
	elif _facing.y < 0.0:
		k = "up"
	return _load_player_tex(k)


## 用贴图画玩家：脚点对准贴图底部中心，影子与程序化画法一致
func _draw_player_sprite(ci: CanvasItem, foot: Vector2, s: float, tex: Texture2D) -> void:
	var hgt := PLAYER_H * s
	var asp := float(tex.get_width()) / float(tex.get_height())
	var w := hgt * asp
	var sw := w * 0.5
	_draw_ellipse(ci, foot, sw, sw * 0.40, Color(0, 0, 0, 0.40))
	_draw_ellipse(ci, foot, sw * 0.66, sw * 0.66 * 0.40, Color(0, 0, 0, 0.28))
	var pos := Vector2(foot.x - w * 0.5, foot.y - hgt)
	ci.draw_texture_rect(tex, Rect2(pos, Vector2(w, hgt)), false)


## 人物总入口：玩家（李星）有贴图就用四方向贴图，否则回退程序化画法；刘忆固定程序化
func _draw_person(ci: CanvasItem, foot: Vector2, s: float, is_liu: bool, walking: bool) -> void:
	if not is_liu:
		var tex := _player_sprite_tex()
		if tex != null:
			_draw_player_sprite(ci, foot, s, tex)
			return
	_draw_person_procedural(ci, foot, s, is_liu, walking)


## 俯视角 3/4 视的人物：脚下椭圆影 + 两条腿 + 躯干 + 手臂 + 头 + 发型 + 细节。
## 李星与刘忆的剪影特意做得不一样：李星高、深色长外套 + 围巾 + 眼镜；
## 刘忆矮一点、亮色外套 + 深色侧条 + 齐肩发、发尾在右侧。
func _draw_person_procedural(ci: CanvasItem, foot: Vector2, s: float, is_liu: bool, walking: bool) -> void:
	# 人物按"两个半格子高"来画（参考图里角色与地砖 1:2 左右），
	# 头略小于肩宽才不会显得像大头娃娃。u 是整身的统一缩放单位。
	# 【尺寸】H 从 190 提到 235：190 时人物在 1280x720 里只有一百来像素高，
	# 认不出谁是谁（用户原话"你人物也太小了…分不清谁是谁"）。235 大约两格半，
	# 与参考图里角色占房间的比例接近，同时仍能看清地面上的走位格子。
	var H := 235.0 * s            # 全身高
	var u := H / 150.0
	var sw := 34.0 * u            # 半肩宽（头直径 ≈ 32*u，比肩窄一点）
	var hd := 16.0 * u            # 头半径

	# 影子：压扁的椭圆（照常按逻辑坐标画，draw_room 设的房间变换照旧生效）
	_draw_ellipse(ci, foot, sw * 1.05, sw * 1.05 * 0.40, Color(0, 0, 0, 0.40))
	_draw_ellipse(ci, foot, sw * 0.66, sw * 0.66 * 0.40, Color(0, 0, 0, 0.28))

	# 腿：走动时前后错开，两腿之间留一条缝，不然像一根柱子
	var swing := sin(_t * 9.0) * 7.0 * u if walking else 0.0
	var leg_c := Color(0.150, 0.150, 0.165) if is_liu else Color(0.115, 0.115, 0.130)
	for i in 2:
		var dx := (-8.0 + 16.0 * float(i)) * u
		var dz := swing * (1.0 if i == 0 else -1.0)
		ci.draw_line(foot + Vector2(dx, -H * 0.46 + dz * 0.18),
				foot + Vector2(dx + dz * 0.22, -3.0 * u), leg_c, 11.0 * u)
		# 鞋
		ci.draw_circle(foot + Vector2(dx + dz * 0.22, -3.0 * u),
			6.5 * u, Color(0.80, 0.80, 0.83) if is_liu else Color(0.22, 0.22, 0.24))

	# 躯干：外套。左半受光（光从左上来），中间一条收腰的暗缝
	var body_top := foot + Vector2(0, -H * 0.95)
	var body_mid := foot + Vector2(0, -H * 0.48)
	var coat := Color(0.610, 0.605, 0.590) if is_liu else Color(0.205, 0.205, 0.225)
	var body_pts := PackedVector2Array([
		body_top + Vector2(-sw, 0), body_top + Vector2(sw, 0),
		body_mid + Vector2(sw * 1.04, 0), body_mid + Vector2(-sw * 1.04, 0),
	])
	ci.draw_colored_polygon(body_pts, coat)
	ci.draw_colored_polygon(PackedVector2Array([
		body_top + Vector2(-sw, 0), body_top + Vector2(0, 0),
		body_mid + Vector2(0, 0), body_mid + Vector2(-sw * 1.04, 0),
	]), coat.lightened(0.14))
	# 收腰暗缝
	ci.draw_line(body_top + Vector2(0, 6.0 * u), body_mid + Vector2(0, 0),
			coat.darkened(0.34), 2.0 * u)

	if is_liu:
		# 校服外套：两条深色侧条 + 白色衣领（一眼认出的标志）
		for sx in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([
				body_top + Vector2(sx * sw * 0.58, 0), body_top + Vector2(sx * sw, 0),
				body_mid + Vector2(sx * sw * 1.04, 0), body_mid + Vector2(sx * sw * 0.62, 0),
			]), Color(0.190, 0.190, 0.205))
		ci.draw_colored_polygon(PackedVector2Array([
			body_top + Vector2(-sw * 0.52, -3.0 * u), body_top + Vector2(sw * 0.52, -3.0 * u),
			body_top + Vector2(sw * 0.30, 5.0 * u), body_top + Vector2(-sw * 0.30, 5.0 * u),
		]), Color(0.760, 0.755, 0.740))
	else:
		# 李星：黑色高领 + 围巾 + 耳机线
		ci.draw_colored_polygon(PackedVector2Array([
			body_top + Vector2(-sw * 0.80, -3.0 * u), body_top + Vector2(sw * 0.80, -3.0 * u),
			body_top + Vector2(sw * 1.00, 10.0 * u), body_top + Vector2(-sw * 1.00, 10.0 * u),
		]), Color(0.100, 0.100, 0.115))
		ci.draw_line(body_top + Vector2(-sw * 0.30, 10.0 * u),
				body_mid + Vector2(-sw * 0.44, 4.0 * u), Color(0.545, 0.545, 0.570), 1.6 * u)
		ci.draw_line(body_top + Vector2(sw * 0.34, 9.0 * u),
				body_mid + Vector2(sw * 0.50, 2.0 * u), Color(0.545, 0.545, 0.570), 1.6 * u)

	# 手臂
	for sx in [-1.0, 1.0]:
		var ax: float = body_top.x + sx * sw * 0.98
		ci.draw_line(Vector2(ax, body_top.y + 6.0 * u),
				Vector2(ax + sx * 5.0 * u, body_mid.y + 6.0 * u), coat.darkened(0.16), 10.0 * u)

	# 脖子 + 头
	ci.draw_line(body_top + Vector2(0, -2.0 * u), body_top + Vector2(0, -9.0 * u),
			Color(0.66, 0.66, 0.70), 8.0 * u)
	var head := body_top + Vector2(0, -hd - 5.0 * u)
	ci.draw_circle(head, hd, Color(0.855, 0.855, 0.875))
	# 脸的暗部（右下）
	ci.draw_circle(head + Vector2(hd * 0.16, hd * 0.20), hd * 0.86, Color(0.755, 0.755, 0.780))

	if is_liu:
		# 刘忆：齐肩发，深色发块盖住头顶两侧，右鬓留一缕到肩
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-hd * 1.06, -hd * 0.20), head + Vector2(hd * 1.06, -hd * 0.20),
			head + Vector2(hd * 0.98, hd * 1.60), head + Vector2(-hd * 0.98, hd * 1.60),
		]), Color(0.135, 0.135, 0.150))
		ci.draw_circle(head + Vector2(0, -hd * 0.26), hd * 1.02, Color(0.185, 0.185, 0.200))
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(hd * 0.66, hd * 0.16), head + Vector2(hd * 1.20, hd * 0.34),
			head + Vector2(hd * 1.06, hd * 2.10), head + Vector2(hd * 0.58, hd * 1.90),
		]), Color(0.115, 0.115, 0.130))
		# 五官：两条短眉毛 + 一个很浅的笑（她是个爱笑的人）
		for sx3 in [-1.0, 1.0]:
			var bx: float = head.x + sx3 * hd * 0.44
			ci.draw_line(Vector2(bx - hd * 0.24, head.y - hd * 0.34),
					Vector2(bx + hd * 0.24, head.y - hd * 0.30), Color(0.20, 0.20, 0.22), 1.6 * u)
		ci.draw_line(head + Vector2(-hd * 0.30, hd * 0.46), head + Vector2(0, hd * 0.58),
				Color(0.34, 0.34, 0.37), 1.4 * u)
		ci.draw_line(head + Vector2(0, hd * 0.58), head + Vector2(hd * 0.30, hd * 0.44),
				Color(0.34, 0.34, 0.37), 1.4 * u)
	else:
		# 李星：长直发，盖过肩，两侧垂到胸口
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-hd * 1.12, -hd * 0.24), head + Vector2(hd * 1.12, -hd * 0.24),
			head + Vector2(hd * 1.24, hd * 2.80), head + Vector2(-hd * 1.24, hd * 2.80),
		]), Color(0.085, 0.085, 0.098))
		ci.draw_circle(head + Vector2(0, -hd * 0.28), hd * 1.06, Color(0.110, 0.110, 0.125))
		# 眼镜：两条短横线 + 鼻梁（正面看是深色镜框，这是最好认的标志）
		var gy := head.y + 2.0 * u
		for sx2 in [-1.0, 1.0]:
			var cx: float = head.x + sx2 * hd * 0.50
			ci.draw_line(Vector2(cx - hd * 0.34, gy), Vector2(cx + hd * 0.34, gy),
					Color(0.92, 0.92, 0.95, 0.90), 1.8)
		ci.draw_line(Vector2(head.x - hd * 0.16, gy), Vector2(head.x + hd * 0.16, gy),
				Color(0.92, 0.92, 0.95, 0.90), 1.8)
		# 眼镜片：淡淡的镜片反光，比"两根线"更像眼镜
		for sx4 in [-1.0, 1.0]:
			ci.draw_circle(head + Vector2(sx4 * hd * 0.50, gy),
					hd * 0.36, Color(0.86, 0.90, 0.96, 0.16))
		# 嘴角是平的：她不太会用表情表达
		ci.draw_line(head + Vector2(-hd * 0.26, hd * 0.54), head + Vector2(hd * 0.26, hd * 0.54),
				Color(0.36, 0.36, 0.39), 1.4 * u)
	# 头顶高光（统一打光方向：左上）
	ci.draw_circle(head + Vector2(-hd * 0.38, -hd * 0.48), hd * 0.26, Color(1, 1, 1, 0.16))


# ── 文字 ──────────────────────────────────────────────────────────────────
func _draw_label(ci: CanvasItem, text: String, pos: Vector2, size: int, c := Color(0, 0, 0, 0)) -> void:
	if text == "":
		return
	var col := c if c.a > 0.0 else Color(0.84, 0.84, 0.88, 0.66)
	var f := ThemeDB.fallback_font
	if f == null:
		return
	# 先画一层描边，保证在亮地面上也读得清
	ci.draw_string(f, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.55))
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

