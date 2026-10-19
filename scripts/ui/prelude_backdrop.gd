extends Control
## ============================================================================
##  《寻星》前日谈 —— 手绘风场景底（纯代码绘制，零素材依赖）
## ============================================================================
##  设计目标：和 assets 里那两张灰白手绘立绘「同一种笔」，而不是照片或纯色板。
##  所以整张底只有三样东西：
##    · 一层暗色基调（分场景换色）
##    · 铅笔感的线与面（半透明白色描边、切角、排线阴影）
##    · 少量暖色强调（高窗的光、顶灯、十月末的余晖）
##  对话那套全部按 1280x720 的设计坐标画，再按窗口等比放大，因此任意分辨率都不糊。
##  俯视角走位那套是另一套坐标（房间 2400 宽 + 96 的格子），绘制逻辑放在
##  scripts/ui/prelude_room_draw.gd 里，本文件只负责转发。
##
##  【踩过的坑，别改回去】
##    · 必须用 set_anchors_and_offsets_preset：只设 anchor 不改 offset 会让画布
##      保持 0×0，而 CanvasItem 尺寸为 0 时画的东西会被自己的矩形裁掉，整屏空白。
##    · 缩放/平移只能用 draw_set_transform_matrix，不要用 draw_set_transform 做缩放：
##      Godot 4.7 / GL Compatibility 下它对 draw_polyline / draw_colored_polygon 会失效。
##    · 三角形永远能三角化成功；凹四边形会让 draw_colored_polygon 报
##      "Invalid polygon data, triangulation failed" 并刷屏。几何一律优先用三角形。
##    · 几何体一律优先用三角形。
## ============================================================================

# ---------------------------------------------------------------- 调色
# 【与立绘同一种笔】：两张立绘的线稿是明确的深色中粗线 + 灰调块面，所以场景底
# 不能只用细淡线。第一版把 C_LINE 压到 0.22 透明度，结果场景像「没画完的草稿」，
# 立绘贴上去像贴纸。这里把主线提到 0.46，并保留一条更淡的辅助线做层次。
const C_DEEP := Color(0.075, 0.078, 0.095)          # 最暗
const C_MID := Color(0.135, 0.138, 0.158)           # 中间调
const C_LIGHT := Color(0.26, 0.27, 0.30)            # 受光面
const C_LINE := Color(0.88, 0.87, 0.84, 0.46)       # 铅笔画线（主线）
const C_LINE_SOFT := Color(0.86, 0.85, 0.82, 0.16)  # 更轻的线（辅助）
const C_HATCH := Color(0.0, 0.0, 0.0, 0.26)         # 排线阴影
const C_WARM := Color(0.98, 0.82, 0.55)             # 暖光
const C_WARM_DIM := Color(0.80, 0.62, 0.42)         # 弱暖光
const C_COOL := Color(0.60, 0.70, 0.85)             # 冷光（走廊灯 / 夜色）
const C_DUSK := Color(0.85, 0.55, 0.36)             # 十月末余晖

const ROOM_DRAW_SCRIPT := "res://scripts/ui/prelude_room_draw.gd"

var _t := 0.0
var _scene := "hallway"
## 阳台门是否开着 —— 第二幕的关键伏笔（二周目第 6 关回收）
var balcony_open := true

# ---------------------------------------------------------------- 贴图背景（用户替换）
var _tex_hallway: Texture2D = null
var _tex_dorm: Texture2D = null
var _tex_classroom: Texture2D = null
var _tex_classroom_week2: Texture2D = null
var _tex_clubroom_door: Texture2D = null
var _tex_activity: Texture2D = null   # 推理社活动空间（周末初遇刘忆那段的阅览室）
var _tex_night: Texture2D = null      # 二周目结尾 CG：夜空大星星小星星（用户提供的星云图）
var _tex_balcony: Texture2D = null    # 二周目阳台：金属栏杆+城市楼群（用户提供的阳台照片）
var _tex_star_jar: Texture2D = null   # 一周目结尾：盒子里空空落落……出自一人之手（星形罐子）
var _tex_star_hand: Texture2D = null  # 一周目结尾：我摊开掌心……恰停在瓶颈（掌心星星）
var _tex_star_rise: Texture2D = null  # 一周目结尾：然后这缤纷的水面上攀……停在了瓶颈（星星上飘）
var _tex_star_riddle: Texture2D = null  # 一周目结尾：这是你送给我的谜底吗？（李星肖像）
var _tex_star_sorrow: Texture2D = null  # 一周目结尾：我或许会看见……行星（刘忆带泪微笑）
var _tex_star_burst1: Texture2D = null  # 一周目结尾：星星漫过胸口·帧1：罐口星光上飘
var _tex_star_burst2: Texture2D = null  # 一周目结尾：星星漫过胸口·帧2：星光迸发
var _tex_star_burst3: Texture2D = null  # 一周目结尾：星星漫过胸口·帧3：星光弥漫
var _tex_star_burst4: Texture2D = null  # 一周目结尾：星星漫过胸口·帧4：白色光晕弥散
var _tex_star_burst5: Texture2D = null  # 一周目结尾：星星漫过胸口·帧5：全白
var _tex_trans_toilet: Texture2D = null  # 衔接段：教学楼卫生间隔间
var _tex_trans_paper: Texture2D = null  # 衔接段：桌面上的空白试卷（含拉远版）
var _tex_trans_backdoor: Texture2D = null  # 衔接段：教室后门
var _tex_trans_corridor: Texture2D = null  # 衔接段：走廊
var _tex_trans_stairs: Texture2D = null  # 衔接段：楼梯（离开教学楼）
var _tex_trans_road1: Texture2D = null  # 衔接段·路面1（砖块落叶）
var _tex_trans_road2: Texture2D = null  # 衔接段·路面2（人字形砖块）
var _tex_trans_road3: Texture2D = null  # 衔接段·路面3（人字形砖块）
var _tex_trans_road4: Texture2D = null  # 衔接段·路面4（带绿篱的步道）
var _tex_trans_small_gate: Texture2D = null  # 衔接段·寝室楼后的小门
var _tex_trans_stairs_dark: Texture2D = null  # 衔接段·昏暗楼梯（仰视台阶）
var _tex_trans_stairs_2: Texture2D = null  # 衔接段·楼梯（水泥台阶）
var _tex_trans_floor3: Texture2D = null  # 衔接段·3F 楼层标志
var _tex_trans_stairs_3: Texture2D = null  # 衔接段·楼梯（转角）
var _tex_trans_door_closed: Texture2D = null  # 衔接段·6F 门紧闭
var _tex_trans_door_open: Texture2D = null  # 衔接段·门打开（全白）

# ---------------------------------------------------------------- 俯视角走位模式
# 对话那套用 _scene 切场景；走位那套用下面这些字段，两套互不干扰。
# 真正的绘制在 prelude_room_draw.gd，这里只保留状态并转发。
## 非空即表示「当前在画俯视角房间」
var _room: Dictionary = {}
var _r_player := Vector2(600, 520)
var _r_near: Dictionary = {}
var _r_items: Array = []
var _r_props: Array = []
var _r_popup := false
var _r_scale := 0.92
var _room_on := false
var _room_draw: RefCounted = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 必须是 *_and_offsets_* 版本：只设 anchor 不改 offset 会让画布保持 0×0，
	# 整个手绘场景就一片空白。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	set_process(true)
	# 加载用户替换的背景图
	_tex_hallway = load("res://assets/rooms/hallway_new.jpg")
	_tex_dorm = load("res://assets/rooms/dorm_new.jpg")
	_tex_classroom = load("res://assets/rooms/classroom_new.jpg")
	_tex_classroom_week2 = load("res://assets/rooms/classroom_week2.jpg")
	_tex_clubroom_door = load("res://assets/rooms/clubroom_door.png")
	_tex_activity = load("res://assets/rooms/activity.jpg")
	_tex_night = load("res://assets/rooms/w2_night.jpg")
	_tex_balcony = load("res://assets/rooms/w2_balcony.jpg")
	_tex_star_jar = load("res://assets/rooms/star_jar.png")
	_tex_star_hand = load("res://assets/rooms/star_hand.png")
	_tex_star_rise = load("res://assets/rooms/star_rise.png")
	_tex_star_riddle = load("res://assets/rooms/star_riddle.png")
	_tex_star_sorrow = load("res://assets/rooms/star_sorrow.png")
	_tex_star_burst1 = load("res://assets/rooms/star_burst1.png")
	_tex_star_burst2 = load("res://assets/rooms/star_burst2.png")
	_tex_star_burst3 = load("res://assets/rooms/star_burst3.png")
	_tex_star_burst4 = load("res://assets/rooms/star_burst4.png")
	_tex_star_burst5 = load("res://assets/rooms/star_burst5.png")
	_tex_trans_toilet = load("res://assets/rooms/trans_toilet.png")
	_tex_trans_paper = load("res://assets/rooms/trans_paper.png")
	_tex_trans_backdoor = load("res://assets/rooms/trans_backdoor.png")
	_tex_trans_corridor = load("res://assets/rooms/trans_corridor.png")
	_tex_trans_stairs = load("res://assets/rooms/trans_stairs.png")
	_tex_trans_road1 = load("res://assets/rooms/trans_road1.png")
	_tex_trans_road2 = load("res://assets/rooms/trans_road2.png")
	_tex_trans_road3 = load("res://assets/rooms/trans_road3.png")
	_tex_trans_road4 = load("res://assets/rooms/trans_road4.png")
	_tex_trans_small_gate = load("res://assets/rooms/trans_small_gate.png")
	_tex_trans_stairs_dark = load("res://assets/rooms/trans_stairs_dark.png")
	_tex_trans_stairs_2 = load("res://assets/rooms/trans_stairs_2.png")
	_tex_trans_floor3 = load("res://assets/rooms/trans_floor3.png")
	_tex_trans_stairs_3 = load("res://assets/rooms/trans_stairs_3.png")
	_tex_trans_door_closed = load("res://assets/rooms/trans_door_closed.png")
	_tex_trans_door_open = load("res://assets/rooms/trans_door_open.png")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func set_scene(key: String) -> void:
	if _scene == key:
		return
	_scene = key
	queue_redraw()


# ---------------------------------------------------------------- 俯视角房间接口
## 由 scripts/ui/room_runtime.gd 每帧调用。room 为空字典 = 退出走位模式。
func set_room(room: Dictionary, player: Vector2, near: Dictionary,
		items: Array, props: Array, popup: bool) -> void:
	_room = room
	_r_player = player
	_r_near = near
	_r_items = items
	_r_props = props
	_r_popup = popup
	_room_on = not room.is_empty()
	_r_scale = float(room.get("scale", 1.0))
	if _room_draw == null and ResourceLoader.exists(ROOM_DRAW_SCRIPT):
		_room_draw = load(ROOM_DRAW_SCRIPT).new()
	if _room_draw != null:
		_room_draw.call("set_room", room, player, near, items, props, popup, _r_scale, _t)
	queue_redraw()


## 布置模式用的坐标换算：转发给房间绘制层，保证和画出来的是同一套变换
func room_xform(win: Vector2) -> Transform2D:
	if _room_draw != null and _room_on:
		return _room_draw.call("xform", win) as Transform2D
	return Transform2D.IDENTITY


## 布置模式状态（隐形幽灵框 / 选中把手）：转发给房间绘制层
func set_edit(on: bool, sel: int) -> void:
	if _room_draw != null:
		_room_draw.call("set_edit", on, sel)


## 玩家朝向（四方向贴图选择）：转发给房间绘制层
func set_facing(dir: Vector2) -> void:
	if _room_draw != null:
		_room_draw.call("set_facing", dir)


# ---------------------------------------------------------------- 画布坐标换算
## 以 1280x720 为设计尺寸，等比铺满窗口（居中裁切）
func _xform() -> Transform2D:
	var win := get_viewport_rect().size
	if win.x <= 0.0 or win.y <= 0.0:
		win = size
	if win.x <= 0.0 or win.y <= 0.0:
		win = Vector2(1280, 720)
	var s := maxf(win.x / 1280.0, win.y / 720.0)
	var off := (win - Vector2(1280, 720) * s) * 0.5
	return Transform2D(0.0, Vector2(s, s), 0.0, off)


func _draw() -> void:
	# 走位模式：整张画面交给房间绘制（它是自己的一套坐标，不走 1280x720 的设计框）
	if _room_on and _room_draw != null:
		_room_draw.set("_t", _t)
		_room_draw.call("draw_room", self)
		return

	draw_set_transform_matrix(_xform())

	# 基调
	draw_rect(Rect2(0, 0, 1280, 720), _base_color())

	match _scene:
		"hallway":
			_hallway()
		"classroom":
			_classroom()
		"classroom_week2":
			_classroom_week2()
		"clubroom_door":
			_clubroom_door()
		"activity":
			_activity()
		"star_jar":
			_star_jar()
		"star_hand":
			_star_hand()
		"star_rise":
			_star_rise()
		"star_riddle":
			_star_riddle()
		"star_sorrow":
			_star_sorrow()
		"star_burst1":
			_star_burst1()
		"star_burst2":
			_star_burst2()
		"star_burst3":
			_star_burst3()
		"star_burst4":
			_star_burst4()
		"star_burst5":
			_star_burst5()
		"trans_toilet":
			_trans_toilet()
		"trans_paper":
			_trans_paper()
		"trans_backdoor":
			_trans_backdoor()
		"trans_corridor":
			_trans_corridor()
		"trans_stairs":
			_trans_stairs()
		"trans_road1":
			_trans_road1()
		"trans_road2":
			_trans_road2()
		"trans_road3":
			_trans_road3()
		"trans_road4":
			_trans_road4()
		"trans_small_gate":
			_trans_small_gate()
		"trans_stairs_dark":
			_trans_stairs_dark()
		"trans_stairs_2":
			_trans_stairs_2()
		"trans_floor3":
			_trans_floor3()
		"trans_stairs_3":
			_trans_stairs_3()
		"trans_door_closed":
			_trans_door_closed()
		"trans_door_open":
			_trans_door_open()
		"trans_white":
			_trans_white()
		"montage":
			_montage()
		"roofline":
			_roofline()
		"dorm_corridor":
			_dorm_corridor()
		"dorm_room":
			_dorm_room()
		"balcony":
			_balcony()
		"night":
			_night()
		"black":
			pass
		_:
			_hallway()

	# 压角暗影：让画面中心更聚焦，也帮 UI 上的文字读得清
	_vignette()


func _base_color() -> Color:
	match _scene:
		"hallway":
			return Color(0.105, 0.108, 0.130)
		"classroom":
			return Color(0.086, 0.090, 0.108)
		"activity":
			return Color(0.086, 0.090, 0.108)
		"star_jar":
			return Color(0.086, 0.090, 0.108)
		"star_hand":
			return Color(0.086, 0.090, 0.108)
		"star_rise":
			return Color(0.086, 0.090, 0.108)
		"star_riddle":
			return Color(0.086, 0.090, 0.108)
		"star_sorrow":
			return Color(0.086, 0.090, 0.108)
		"star_burst1":
			return Color(0.086, 0.090, 0.108)
		"star_burst2":
			return Color(0.086, 0.090, 0.108)
		"star_burst3":
			return Color(0.086, 0.090, 0.108)
		"star_burst4":
			return Color(0.086, 0.090, 0.108)
		"star_burst5":
			return Color(0.086, 0.090, 0.108)
		"trans_toilet":
			return Color(0.086, 0.090, 0.108)
		"trans_paper":
			return Color(0.086, 0.090, 0.108)
		"trans_backdoor":
			return Color(0.086, 0.090, 0.108)
		"trans_corridor":
			return Color(0.086, 0.090, 0.108)
		"trans_stairs":
			return Color(0.086, 0.090, 0.108)
		"trans_road1":
			return Color(0.086, 0.090, 0.108)
		"trans_road2":
			return Color(0.086, 0.090, 0.108)
		"trans_road3":
			return Color(0.086, 0.090, 0.108)
		"trans_road4":
			return Color(0.086, 0.090, 0.108)
		"trans_small_gate":
			return Color(0.086, 0.090, 0.108)
		"trans_stairs_dark":
			return Color(0.086, 0.090, 0.108)
		"trans_stairs_2":
			return Color(0.086, 0.090, 0.108)
		"trans_floor3":
			return Color(0.086, 0.090, 0.108)
		"trans_stairs_3":
			return Color(0.086, 0.090, 0.108)
		"trans_door_closed":
			return Color(0.086, 0.090, 0.108)
		"trans_door_open":
			return Color(0.086, 0.090, 0.108)
		"trans_white":
			return Color(1.0, 1.0, 1.0)
		"montage":
			return Color(0.095, 0.095, 0.115)
		"roofline":
			return Color(0.085, 0.092, 0.115)
		"dorm_corridor":
			return Color(0.150, 0.112, 0.092)
		"dorm_room":
			return Color(0.098, 0.094, 0.104)
		"balcony":
			return Color(0.09, 0.095, 0.13)
		"night":
			return Color(0.035, 0.04, 0.075)
		"black":
			return Color(0.012, 0.012, 0.016)
		_:
			return C_DEEP


# ============================================================================
#  通用零件
# ============================================================================

func _pencil(a: Vector2, b: Vector2, w := 1.4, c := C_LINE) -> void:
	draw_line(a, b, c, w, true)


func _pencil_rect(r: Rect2, w := 1.4, c := C_LINE) -> void:
	draw_rect(r, c, false, w)


func _fill_rect(r: Rect2, c: Color) -> void:
	draw_rect(r, c, true)


## 排线阴影：在矩形内画一组斜线（手绘排线的味道）
func _hatch(r: Rect2, spacing := 9.0, c := C_HATCH, w := 1.0, flip := false) -> void:
	var total := r.size.x + r.size.y
	var n := int(total / spacing)
	for i in n + 1:
		var t := float(i) * spacing
		var p1: Vector2
		var p2: Vector2
		if flip:
			p1 = Vector2(r.position.x, r.position.y + t)
			p2 = Vector2(r.position.x + t, r.position.y)
		else:
			p1 = Vector2(r.position.x + t, r.position.y)
			p2 = Vector2(r.position.x, r.position.y + t)
		# 裁到矩形内：手动夹一下，免得排线糊到画面外
		p1 = _clamp_in(p1, r)
		p2 = _clamp_in(p2, r)
		if p1.distance_to(p2) < 1.0:
			continue
		draw_line(p1, p2, c, w, true)


func _clamp_in(p: Vector2, r: Rect2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


## 一道「光柱」（高窗打进来的光）
func _light_shaft(pts: PackedVector2Array, c: Color) -> void:
	draw_colored_polygon(pts, c)


## 天空渐变（用几条横带模拟，省掉 shader）
func _sky_bands(r: Rect2, top: Color, bottom: Color, bands := 26) -> void:
	for i in bands:
		var t := float(i) / float(bands - 1)
		var c := top.lerp(bottom, t)
		var y := r.position.y + r.size.y * t
		draw_rect(Rect2(r.position.x, y, r.size.x, r.size.y / float(bands) + 1.5), c)


func _glow(center: Vector2, radius: float, c: Color, rings := 12) -> void:
	for i in rings:
		var t := float(i) / float(rings)
		var rr := radius * (1.0 - t)
		var a := c.a * (1.0 - t) * 0.5
		draw_circle(center, rr, Color(c.r, c.g, c.b, a))


func _vignette() -> void:
	# 四条边各一层渐变暗角
	var steps := 10
	for i in steps:
		var t := float(i) / float(steps)
		var a := 0.05 * (1.0 - t)
		var inset := t * 120.0
		var col := Color(0, 0, 0, a)
		draw_rect(Rect2(0, 0, 1280, 18.0 + inset), col)
		draw_rect(Rect2(0, 720 - 18.0 - inset, 1280, 18.0 + inset), col)
		draw_rect(Rect2(0, 0, 18.0 + inset, 720), col)
		draw_rect(Rect2(1280 - 18.0 - inset, 0, 18.0 + inset, 720), col)


# ============================================================================
#  场景 1 · 教学楼走廊尽头 / 推理社门口（保持原手绘）
# ============================================================================
func _hallway() -> void:
	# 透视：走廊往右后方收（尽头在 x≈980）
	var vanish := Vector2(980, 330)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-40, 720), Vector2(1320, 720), Vector2(vanish.x + 120, vanish.y), Vector2(vanish.x - 240, vanish.y)
	]), C_MID)
	_hatch(Rect2(0, 430, 560, 290), 11.0, Color(0, 0, 0, 0.14))
	draw_colored_polygon(PackedVector2Array([
		Vector2(1280, 60), Vector2(1280, 720), Vector2(vanish.x + 200, vanish.y + 40), Vector2(vanish.x + 60, vanish.y - 120)
	]), C_LIGHT)
	_dust(Vector2(430, 380), 26)


## 缓慢漂浮的浮尘（用时间做确定性的伪随机，不用随机数保持稳定）
func _dust(center: Vector2, count: int) -> void:
	for i in count:
		var seed_a := float(i) * 12.9898
		var seed_b := float(i) * 78.233
		var dx := (fmod(abs(sin(seed_a) * 43758.5453), 1.0) - 0.5) * 620.0
		var dy := (fmod(abs(sin(seed_b) * 43758.5453), 1.0) - 0.5) * 430.0
		var drift := sin(_t * 0.35 + float(i)) * 14.0
		var p := center + Vector2(dx + drift * 0.5, dy + drift)
		var a: float = 0.10 + 0.10 * abs(sin(_t * 0.8 + float(i) * 2.1))
		draw_circle(p, 1.5, Color(1.0, 0.94, 0.82, a))


# ============================================================================
#  场景 2 · 推理社活动教室（贴图版）
# ============================================================================
func _classroom() -> void:
	# 用用户提供的参考图替换手绘背景
	if _tex_classroom != null:
		draw_texture_rect(_tex_classroom, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		# 回退：原来的手绘代码（图片加载失败时用）
		_fill_rect(Rect2(0, 0, 1280, 520), Color(0.105, 0.108, 0.126))
		var board := Rect2(150, 120, 700, 260)
		_fill_rect(board, Color(0.075, 0.088, 0.082))
		_pencil_rect(board, 3.0, Color(0.80, 0.78, 0.74, 0.18))
		var screen := Rect2(880, 120, 360, 250)
		_fill_rect(screen, Color(0.30, 0.30, 0.32))
		_sky_bands(screen, Color(0.46, 0.46, 0.48), Color(0.20, 0.20, 0.22), 14)
		_dust(Vector2(760, 300), 18)


func _classroom_week2() -> void:
	# 二周目教室（走访同学C、D）用用户提供的第二张参考图
	if _tex_classroom_week2 != null:
		draw_texture_rect(_tex_classroom_week2, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		# 回退：和普通教室一样的手绘代码
		_fill_rect(Rect2(0, 0, 1280, 520), Color(0.105, 0.108, 0.126))
		var board := Rect2(150, 120, 700, 260)
		_fill_rect(board, Color(0.075, 0.088, 0.082))
		_pencil_rect(board, 3.0, Color(0.80, 0.78, 0.74, 0.18))
		var screen := Rect2(880, 120, 360, 250)
		_fill_rect(screen, Color(0.30, 0.30, 0.32))
		_sky_bands(screen, Color(0.46, 0.46, 0.48), Color(0.20, 0.20, 0.22), 14)
		_dust(Vector2(760, 300), 18)


func _clubroom_door() -> void:
	# 推理社教室门口（二周目走访同学E）用用户提供的参考图
	if _tex_clubroom_door != null:
		draw_texture_rect(_tex_clubroom_door, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		# 回退：和走廊一样的手绘代码
		_hallway()


## 推理社活动空间（阅览室）：一周目初遇刘忆那一段（"活动空间里已经坐了一个女生"
## 到"我叫刘忆"）用用户提供的参考图
func _activity() -> void:
	if _tex_activity != null:
		draw_texture_rect(_tex_activity, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		# 回退：图片没加载出来时和走廊一样的手绘
		_hallway()


## 一周目结尾：打开密码盒、星形罐子（"盒子里空空落落……出自一人之手"）
func _star_jar() -> void:
	if _tex_star_jar != null:
		draw_texture_rect(_tex_star_jar, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 一周目结尾：摊开的掌心与星星（"我摊开掌心……恰停在瓶颈"）
func _star_hand() -> void:
	if _tex_star_hand != null:
		draw_texture_rect(_tex_star_hand, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 一周目结尾：星形瓶装满星星、星星向上飘（"然后这缤纷的水面上攀……恰停在瓶颈"）
func _star_rise() -> void:
	if _tex_star_rise != null:
		draw_texture_rect(_tex_star_rise, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 一周目结尾：李星肖像（"这是你送给我的谜底吗？……但是我不会明白的。"）
func _star_riddle() -> void:
	if _tex_star_riddle != null:
		draw_texture_rect(_tex_star_riddle, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 一周目结尾：刘忆带泪微笑（"我或许会看见……但是我不会明白的。" / "行星"）
func _star_sorrow() -> void:
	if _tex_star_sorrow != null:
		draw_texture_rect(_tex_star_sorrow, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 一周目结尾：星星漫过胸口·帧1：罐口星光上飘
func _star_burst1() -> void:
	if _tex_star_burst1 != null:
		draw_texture_rect(_tex_star_burst1, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()

## 一周目结尾：星星漫过胸口·帧2：星光迸发
func _star_burst2() -> void:
	if _tex_star_burst2 != null:
		draw_texture_rect(_tex_star_burst2, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()

## 一周目结尾：星星漫过胸口·帧3：星光弥漫
func _star_burst3() -> void:
	if _tex_star_burst3 != null:
		draw_texture_rect(_tex_star_burst3, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()

## 一周目结尾：星星漫过胸口·帧4：白色光晕弥散
func _star_burst4() -> void:
	if _tex_star_burst4 != null:
		draw_texture_rect(_tex_star_burst4, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()

## 一周目结尾：星星漫过胸口·帧5：全白
func _star_burst5() -> void:
	if _tex_star_burst5 != null:
		draw_texture_rect(_tex_star_burst5, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段：教学楼卫生间隔间
func _trans_toilet() -> void:
	if _tex_trans_toilet != null:
		draw_texture_rect(_tex_trans_toilet, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段：桌面上的空白试卷
func _trans_paper() -> void:
	if _tex_trans_paper != null:
		draw_texture_rect(_tex_trans_paper, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段：教室后门
func _trans_backdoor() -> void:
	if _tex_trans_backdoor != null:
		draw_texture_rect(_tex_trans_backdoor, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段：走廊
func _trans_corridor() -> void:
	if _tex_trans_corridor != null:
		draw_texture_rect(_tex_trans_corridor, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段：楼梯（离开教学楼）
func _trans_stairs() -> void:
	if _tex_trans_stairs != null:
		draw_texture_rect(_tex_trans_stairs, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·路面1（砖块落叶）
func _trans_road1() -> void:
	if _tex_trans_road1 != null:
		draw_texture_rect(_tex_trans_road1, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·路面2（人字形砖块）
func _trans_road2() -> void:
	if _tex_trans_road2 != null:
		draw_texture_rect(_tex_trans_road2, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·路面3（人字形砖块）
func _trans_road3() -> void:
	if _tex_trans_road3 != null:
		draw_texture_rect(_tex_trans_road3, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·路面4（带绿篱的步道）
func _trans_road4() -> void:
	if _tex_trans_road4 != null:
		draw_texture_rect(_tex_trans_road4, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·寝室楼后的小门
func _trans_small_gate() -> void:
	if _tex_trans_small_gate != null:
		draw_texture_rect(_tex_trans_small_gate, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·昏暗楼梯（仰视台阶）
func _trans_stairs_dark() -> void:
	if _tex_trans_stairs_dark != null:
		draw_texture_rect(_tex_trans_stairs_dark, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·楼梯（水泥台阶）
func _trans_stairs_2() -> void:
	if _tex_trans_stairs_2 != null:
		draw_texture_rect(_tex_trans_stairs_2, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·3F 楼层标志
func _trans_floor3() -> void:
	if _tex_trans_floor3 != null:
		draw_texture_rect(_tex_trans_floor3, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·楼梯（转角）
func _trans_stairs_3() -> void:
	if _tex_trans_stairs_3 != null:
		draw_texture_rect(_tex_trans_stairs_3, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·6F 门紧闭
func _trans_door_closed() -> void:
	if _tex_trans_door_closed != null:
		draw_texture_rect(_tex_trans_door_closed, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段·门打开（全白）
func _trans_door_open() -> void:
	if _tex_trans_door_open != null:
		draw_texture_rect(_tex_trans_door_open, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		_hallway()


## 衔接段最后一张：门打开后整屏全白（然后进入二周目）
func _trans_white() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(1.0, 1.0, 1.0, 1.0))


func _person_silhouette(base: Vector2, h: float, a: float) -> void:
	var c := Color(0.10, 0.10, 0.12, a)
	draw_circle(base - Vector2(0, h * 0.78), h * 0.16, c)
	# 躯干用三角形，不要用四边形。四边形只要有一个角是凹的（叉积符号翻转），
	# Godot 的 ear-clipping 就会失败并刷屏：
	#   ERROR: Invalid polygon data, triangulation failed.
	# 三角形永远能三角化，所以这里固定三角形。
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(h * 0.24, 0),
		base - Vector2(h * 0.24, 0),
		base - Vector2(0, h * 0.70)
	]), c)


# ============================================================================
#  场景 3 · 蒙太奇（借还书 / 笔记本 / 空掉的课表）
# ============================================================================
func _montage() -> void:
	# 三块「漂浮的纸」：书页 / 笔记本 / 活动表，轻微浮动
	var bob := sin(_t * 0.6) * 5.0
	var bob2 := sin(_t * 0.5 + 1.4) * 6.0
	var bob3 := sin(_t * 0.7 + 2.2) * 4.0

	# 左：摊开的书
	_page(Rect2(120, 170 + bob, 300, 380), -0.06)
	# 中：笔记本（三栏）
	_page(Rect2(500, 130 + bob2, 320, 420), 0.02)
	_note_columns(Rect2(520, 160 + bob2, 280, 360))
	# 右：活动表（格子）
	_page(Rect2(880, 210 + bob3, 280, 320), 0.07)
	_schedule_grid(Rect2(900, 240 + bob3, 240, 260))

	_glow(Vector2(640, 360), 620.0, Color(0.9, 0.86, 0.72, 0.06))


## 一张浮在暗处的纸
func _page(r: Rect2, rot: float) -> void:
	var xf := _xform() * Transform2D(rot, Vector2(1, 1), 0.0, Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5))
	draw_set_transform_matrix(xf)
	var rr := Rect2(-r.size * 0.5, r.size)
	_fill_rect(rr, Color(0.85, 0.84, 0.80, 0.055))
	_pencil_rect(rr, 1.4, Color(0.90, 0.88, 0.82, 0.26))
	_hatch(rr, 14.0, Color(1.0, 1.0, 1.0, 0.014))
	draw_set_transform_matrix(_xform())


func _note_columns(r: Rect2) -> void:
	# 三栏：行为 → 情感 → 例证
	for i in 3:
		var x := r.position.x + r.size.x * (float(i) / 3.0)
		_pencil(Vector2(x, r.position.y), Vector2(x, r.end.y), 1.0, Color(0.90, 0.88, 0.82, 0.16))
	# 假字迹
	for row in 9:
		var y := r.position.y + 26.0 + float(row) * 34.0
		for i in 3:
			var x0 := r.position.x + r.size.x * (float(i) / 3.0) + 10.0
			var w := 20.0 + fmod(abs(sin(float(row * 3 + i) * 5.1) * 43758.5), 1.0) * 48.0
			_pencil(Vector2(x0, y), Vector2(x0 + w, y), 1.2, Color(0.92, 0.90, 0.84, 0.13))
	# 第三栏有几行被画了重点
	for row in [2, 5]:
		var y := r.position.y + 26.0 + float(row) * 34.0
		_pencil(Vector2(r.position.x + r.size.x * 0.68, y + 5),
				Vector2(r.position.x + r.size.x * 0.68 + 56, y + 5), 2.0, Color(0.80, 0.42, 0.38, 0.35))


func _schedule_grid(r: Rect2) -> void:
	var cols := 5
	var rows := 4
	for i in cols + 1:
		var x := r.position.x + r.size.x * (float(i) / float(cols))
		_pencil(Vector2(x, r.position.y), Vector2(x, r.end.y), 1.0, Color(0.90, 0.88, 0.82, 0.14))
	for j in rows + 1:
		var y := r.position.y + r.size.y * (float(j) / float(rows))
		_pencil(Vector2(r.position.x, y), Vector2(r.end.x, y), 1.0, Color(0.90, 0.88, 0.82, 0.14))
	# 空格子：越往后越空（呼应「空掉的课表」）
	var empties := [
		Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(4, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)
	]
	for e in empties:
		var cw := r.size.x / float(cols)
		var ch := r.size.y / float(rows)
		_pencil_rect(Rect2(r.position.x + cw * e.x + 4, r.position.y + ch * e.y + 4, cw - 8, ch - 8),
				1.0, Color(0.86, 0.60, 0.34, 0.22))


# ============================================================================
#  场景 4 · 裂缝（成绩条 / 电话 / 考试失利）
# ============================================================================
func _roofline() -> void:
	# 一扇朝天的窗，外面是灰白的天
	var win := Rect2(180, 40, 860, 300)
	_sky_bands(win, Color(0.30, 0.33, 0.38), Color(0.16, 0.17, 0.20), 20)
	# 云（几条横向的软线）
	for i in 9:
		var y := win.position.y + 30.0 + float(i) * 30.0
		var a: float = 0.05 + 0.04 * abs(sin(float(i) * 1.7))
		draw_rect(Rect2(win.position.x + 40, y, win.size.x - 80, 12), Color(0.85, 0.88, 0.94, a))
	# 雨丝（缓慢下落）
	for i in 90:
		var sx := win.position.x + fmod(float(i) * 137.0, win.size.x)
		var sy := win.position.y + fmod(float(i) * 61.0 + _t * 190.0, win.size.y)
		draw_line(Vector2(sx, sy), Vector2(sx - 5, sy + 22), Color(0.80, 0.85, 0.95, 0.16), 1.0, true)
	_pencil_rect(win, 3.0, Color(0.88, 0.86, 0.82, 0.22))
	# 窗棂
	_pencil(Vector2(610, win.position.y), Vector2(610, win.end.y), 3.0, Color(0.10, 0.10, 0.12, 0.75))
	_pencil(Vector2(win.position.x, 190), Vector2(win.end.x, 190), 3.0, Color(0.10, 0.10, 0.12, 0.75))

	# 窗台
	_fill_rect(Rect2(150, 340, 920, 22), Color(0.155, 0.155, 0.175))
	_pencil_rect(Rect2(150, 340, 920, 22), 1.6, C_LINE_SOFT)

	# 前景：一张被揉过又展平的纸（成绩条）
	var paper := Rect2(230, 430, 250, 130)
	_fill_rect(paper, Color(0.82, 0.81, 0.78, 0.10))
	_pencil_rect(paper, 1.6, Color(0.90, 0.88, 0.82, 0.30))
	# 折痕
	for i in 5:
		var x := paper.position.x + 30.0 + float(i) * 44.0
		_pencil(Vector2(x, paper.position.y + 6), Vector2(x + 12, paper.end.y - 6), 1.0, Color(0.95, 0.93, 0.88, 0.09))
	# 上面的数字（假字迹）
	_pencil(Vector2(paper.position.x + 26, paper.position.y + 40),
			Vector2(paper.position.x + 96, paper.position.y + 40), 2.4, Color(0.90, 0.55, 0.45, 0.30))
	_pencil(Vector2(paper.position.x + 26, paper.position.y + 76),
			Vector2(paper.position.x + 150, paper.position.y + 76), 1.6, Color(0.92, 0.90, 0.84, 0.16))

	# 远景：窗边一个背对的人影（很小，只是「她在打电话」的信号）
	_person_silhouette(Vector2(860, 350), 150.0, 0.55)

	# 下方暗部
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 720), Vector2(1280, 720), Vector2(1280, 600), Vector2(0, 640)
	]), Color(0.055, 0.058, 0.070, 0.85))


# ============================================================================
#  第二幕 · 6F 寝室走廊（贴图版 · 十月底的余晖）
# ============================================================================
func _dorm_corridor() -> void:
	# 用用户提供的参考图替换手绘背景
	if _tex_hallway != null:
		draw_texture_rect(_tex_hallway, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		# 回退：原来的手绘代码（图片加载失败时用）
		_fill_rect(Rect2(0, 0, 1280, 150), Color(0.095, 0.082, 0.084))
		_fill_rect(Rect2(0, 150, 1280, 330), Color(0.185, 0.140, 0.112))
		_fill_rect(Rect2(0, 480, 1280, 240), Color(0.135, 0.108, 0.092))
		var endwin := Rect2(1040, 200, 200, 250)
		_fill_rect(endwin, Color(0.20, 0.16, 0.14))
		_sky_bands(endwin, Color(0.95, 0.72, 0.46), Color(0.55, 0.34, 0.26), 22)
		_glow(Vector2(1140, 320), 900.0, Color(1.0, 0.70, 0.40, 0.16))
		_dust(Vector2(880, 400), 30)


# ============================================================================
#  第二幕 · 刘忆的寝室（贴图版）
# ============================================================================
func _dorm_room() -> void:
	# 用用户提供的参考图替换手绘背景
	if _tex_dorm != null:
		draw_texture_rect(_tex_dorm, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
	else:
		# 回退：原来的手绘代码（图片加载失败时用）
		_fill_rect(Rect2(0, 0, 1280, 500), Color(0.115, 0.112, 0.124))
		_fill_rect(Rect2(0, 500, 1280, 220), Color(0.088, 0.086, 0.096))
		var bd := Rect2(720, 150, 260, 350)
		_fill_rect(Rect2(bd.position.x - 6, bd.position.y - 6, bd.size.x + 12, bd.size.y + 12), Color(0.075, 0.073, 0.082))
		_sky_bands(bd, Color(0.20, 0.22, 0.27), Color(0.10, 0.11, 0.14), 18)
		_glow(Vector2(850, 400), 520.0, Color(0.70, 0.78, 1.0, 0.06))
		_dust(Vector2(700, 380), 16)


# ============================================================================
#  二周目 · 阳台（刘忆坠楼处：栏杆缺了一个口子、一把横倒的扫帚）
# ============================================================================
func _balcony() -> void:
	# 优先使用用户提供的阳台照片（手绘阳台留作图片加载失败时的回退）
	if _tex_balcony != null:
		draw_texture_rect(_tex_balcony, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
		return
	# 暮色夜空
	_sky_bands(Rect2(0, 0, 1280, 420), Color(0.20, 0.22, 0.30), Color(0.08, 0.09, 0.13), 22)
	# 远方的楼群剪影
	_fill_rect(Rect2(0, 300, 1280, 120), Color(0.10, 0.105, 0.14))
	for i in 7:
		var w := 90.0 + float(i % 3) * 60.0
		var x := 60.0 + float(i) * 190.0
		var h := 60.0 + float(i % 4) * 40.0
		_fill_rect(Rect2(x, 300.0 + 120.0 - h, w, h), Color(0.085, 0.09, 0.12))
		_hatch(Rect2(x, 300.0 + 120.0 - h, w, h), 14.0, Color(0.0, 0.0, 0.0, 0.18))
	# 阳台地面
	_fill_rect(Rect2(0, 420, 1280, 300), Color(0.13, 0.12, 0.14))
	_hatch(Rect2(0, 560, 1280, 160), 16.0, Color(0.0, 0.0, 0.0, 0.20))
	# 护栏：横杆 + 竖杆（铁艺，铅笔画）
	var rail_y := 330.0
	_pencil(Vector2(0, rail_y), Vector2(1280, rail_y), 5.0, Color(0.72, 0.72, 0.76, 0.85))
	_pencil(Vector2(0, rail_y + 60), Vector2(1280, rail_y + 60), 4.0, Color(0.72, 0.72, 0.76, 0.70))
	for i in 42:
		var x := 20.0 + float(i) * 30.0
		_pencil(Vector2(x, rail_y), Vector2(x, rail_y + 60), 3.0, Color(0.72, 0.72, 0.76, 0.62))
	# 【缺了一个口子的栏杆】第 17-22 根竖杆之间断掉，横杆也断成两截
	var gap_x := 500.0
	_pencil(Vector2(gap_x, rail_y), Vector2(gap_x + 200, rail_y), 5.0, Color(0.12, 0.12, 0.14, 0.94))
	_pencil(Vector2(gap_x, rail_y + 60), Vector2(gap_x + 210, rail_y + 60), 4.0, Color(0.12, 0.12, 0.14, 0.94))
	# 断口处的碎茬（几根歪斜短线段）
	for i in 5:
		var x := gap_x + 10.0 + float(i) * 40.0
		_pencil(Vector2(x, rail_y), Vector2(x + 18, rail_y - 26), 2.0, Color(0.60, 0.60, 0.66, 0.80))
		_pencil(Vector2(x + 6, rail_y + 60), Vector2(x + 24, rail_y + 82), 2.0, Color(0.60, 0.60, 0.66, 0.70))
	# 横倒的扫帚（杆斜躺在地上，帚头朝右）
	var broom := Vector2(900, 640)
	_pencil(broom + Vector2(0, -8), broom + Vector2(-190, 6), 5.0, Color(0.52, 0.42, 0.32, 0.92))
	for i in 8:
		var a := float(i) * 0.35
		var bx := broom.x + 10.0 + float(i) * 9.0
		_pencil(broom + Vector2(0, -6) + Vector2(bx - broom.x, 0), broom + Vector2(bx - broom.x, 34), 3.0, Color(0.66, 0.60, 0.50, 0.85))
	# 角落一只倒扣的小药瓶（呼应药片线索）
	_pencil_rect(Rect2(180, 590, 26, 44), 2.0, Color(0.80, 0.80, 0.84, 0.55))
	_pencil(Vector2(180, 620), Vector2(206, 620), 2.0, Color(0.80, 0.80, 0.84, 0.55))
	_glow(Vector2(640, 300), 700.0, Color(0.55, 0.62, 0.95, 0.07))
	_dust(Vector2(400, 480), 22)


# ============================================================================
#  二周目结尾 CG · 夜空（弄一点夜空里的大星星小星星）
# ============================================================================
func _night() -> void:
	# 用用户提供的星云 CG 做结尾背景（手绘星空留作图片加载失败时的回退）
	if _tex_night != null:
		draw_texture_rect(_tex_night, Rect2(0, 0, 1280, 720), false, Color(1, 1, 1, 1.0))
		return
	_sky_bands(Rect2(0, 0, 1280, 720), Color(0.055, 0.06, 0.11), Color(0.02, 0.025, 0.05), 30)
	# 星群：大小不一的十字光点，亮暗错落
	var seed_i := 0
	for i in 150:
		var x := fmod(float(i) * 137.0 + 41.0, 1280.0)
		var y := fmod(float(i) * 71.0 + 19.0, 560.0)
		var big := (i % 11 == 0)
		var r := 2.4 if big else 1.1
		var a: float = 0.35 + 0.30 * abs(sin(float(i) * 1.37))
		var c := Color(0.98, 0.97, 0.92, a)
		draw_circle(Vector2(x, y), r, c)
		if big:
			_pencil(Vector2(x - 10, y), Vector2(x + 10, y), 1.0, Color(0.98, 0.96, 0.88, a * 0.7))
			_pencil(Vector2(x, y - 10), Vector2(x, y + 10), 1.0, Color(0.98, 0.96, 0.88, a * 0.7))
		seed_i += 1
	# 几颗亮的大星星（故意做得醒目）
	for i in 6:
		var x := 180.0 + float(i) * 200.0
		var y := 90.0 + float(i % 2) * 160.0
		for arm in 4:
			var ang := deg_to_rad(float(arm) * 90.0 + float(i) * 11.0)
			var dir := Vector2(cos(ang), sin(ang)) * 26.0
			_pencil(Vector2(x, y), Vector2(x, y) + dir, 2.2, Color(0.98, 0.95, 0.86, 0.55))
		draw_circle(Vector2(x, y), 3.6, Color(0.99, 0.97, 0.90, 0.9))
	# 下方一层深色地平线
	_fill_rect(Rect2(0, 640, 1280, 80), Color(0.015, 0.018, 0.03))
	# 远景楼影
	for i in 9:
		var w := 70.0 + float(i % 3) * 50.0
		var x := 40.0 + float(i) * 145.0
		var h := 40.0 + float(i % 4) * 30.0
		_fill_rect(Rect2(x, 640.0 - h, w, h), Color(0.03, 0.035, 0.055))
	_glow(Vector2(640, 300), 900.0, Color(0.40, 0.55, 1.0, 0.05))
	_dust(Vector2(300, 500), 18)
