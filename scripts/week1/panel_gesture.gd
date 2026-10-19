extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 · 第 2 关 —— 九宫格手势密码
## ============================================================================
##  玩法：3×3 九个点，按顺序点亮。正确顺序就是上一关那句话里的那个形状「S」，
##  **从上往下画**：右上 → 上中 → 左上 → 左中 → 正中 → 右中 → 右下 → 下中 → 左下
##  也就是 (2,0)(1,0)(0,0)(0,1)(1,1)(2,1)(2,2)(1,2)(0,2)——
##  在九宫格上连出来正是一个「S」（顺手把上一关的谜底再用一遍）。
##  【方向千万别搞反】起笔在**右上角**：S 的上排接的是左边那根竖线、下排接的是右边那根。
##  反过来（上排接右边、下排接左边）画出来是「2」——设计师文档里那条
##  「手势密码是s 不是2 反了」说的就是上一版画成了 2，所以这里必须保持现在这个方向。
##
##  点错 = 不是下一个该点的点：整条线清空、错误次数 +1，
##  错到 3 次就把提示升级成"S 有五笔。这个数字等下还有用。"
##
##  背景那层暗蓝是「手机壁纸」，只给气氛，**不画任何图形**。
##  【不要】再把正解描在壁纸上：这里原来按 PATTERN 铺过一层 0.30 透明度的淡蓝线，
##  等于把九个点的正确顺序直接摆在玩家眼前。玩家反馈「不要有底层淡淡的痕迹提示」，
##  正解得让玩家自己从上一关的线索（上一关的 S 有五笔）推出来。
## ============================================================================

const DOTS := 3                     # 3×3
const GAP_X := 66.0                 # 点之间横向间距
const GAP_Y := 80.0                 # 点之间纵向间距
const DOT := 40.0                   # 点直径 40px
const BOARD_W := 260.0              # 画板宽度（手机宽度）
const BOARD_H := 520.0              # 画板高度（手机高度）

const C_DOT := Color(0.85, 0.92, 0.95, 0.55)          # 未点亮的点（半透明浅蓝白）
const C_DOT_ON := Color(1.0, 0.95, 0.60, 1.0)         # 已点亮的点，暖黄
const C_LINE_SKIN := Color(1.0, 0.90, 0.50, 0.85)
const C_BUMP := Color(0.95, 0.40, 0.40)               # 点错时的提示色

## 手机图片路径
const PHONE_TEX := "res://assets/props/phone_gesture.png"

## 「S」形手势，从上往下画：上排从右上起笔往左 → 左竖下来 → 中排往右 → 右竖下来 → 下排往左。
##
##   ●───●───●      上排：3 ← 2 ← 1（起笔在右上角）
##   │
##   ●───●───●      中排：4 → 5 → 6
##           │
##   ●───●───●      下排：7 ← 8 ← 9
##
## 上面的编号是"九宫格通用编号"（1=(0,0) 行优先）。上排连左竖、下排连右竖 = S；
## 反过来就是「2」。Kerry 的截图（已点亮 8/9）里画的正是那个 2，别再改回去。
const PATTERN: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	Vector2i(2, 2), Vector2i(1, 2), Vector2i(0, 2),
]

var _board: Control = null
var _line_holder: Control = null
var _step_label: Label = null
var _dots: Array[Button] = []
var _lines: Array[ColorRect] = []
var _step := 0
var _errors := 0
var _won := false

## 调试模式：按 D 开关，开了可以拖点，按 P 打印数值
var _debug_mode := false
var _dragging_dot: Button = null
var _drag_offset := Vector2.ZERO
# 【坑】基类自己有一个 _closing，子类不要再声明同名变量，
# 否则解析期直接报 "already exists in parent class"，整份脚本作废。


# ---------------------------------------------------------------- 基类覆盖点
func panel_title() -> String:
	return "手势密码"


func panel_hint() -> String:
	return "按顺序点亮九个点"


func build_body(body: VBoxContainer) -> void:
	# —— 状态行：报"点到第几个 / 点错了 / 解锁了"
	_step_label = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	_step_label.name = "GestureStep"
	_step_label.custom_minimum_size = Vector2(0, 26)
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_step_label)

	var center := CenterContainer.new()
	center.name = "GestureCenter"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	_board = Control.new()
	_board.name = "GestureBoard"
	_board.custom_minimum_size = Vector2(BOARD_W, BOARD_H)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_board)

	# —— 手机背景图片（最底层）
	var phone_bg := TextureRect.new()
	phone_bg.name = "PhoneBg"
	phone_bg.texture = load(PHONE_TEX)
	phone_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	phone_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	phone_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phone_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(phone_bg)

	# 连线层放在点下面
	_line_holder = Control.new()
	_line_holder.name = "GestureLines"
	_line_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(_line_holder)

	for y in DOTS:
		for x in DOTS:
			var b := Button.new()
			b.name = "Dot_%d_%d" % [x, y]
			b.custom_minimum_size = Vector2(DOT, DOT)
			b.offset_left = DOT_ORIGIN.x + float(x) * GAP_X - DOT * 0.5
			b.offset_top = DOT_ORIGIN.y + float(y) * GAP_Y - DOT * 0.5
			b.offset_right = b.offset_left + DOT
			b.offset_bottom = b.offset_top + DOT
			# 纯圆点：圆角半径给到直径的一半
			var sb := StyleBoxFlat.new()
			sb.bg_color = C_DOT
			sb.set_corner_radius_all(int(DOT * 0.5))
			b.add_theme_stylebox_override("normal", sb)
			var sb_hover := sb.duplicate() as StyleBoxFlat
			sb_hover.bg_color = Color(0.95, 0.98, 1.0, 0.8)
			b.add_theme_stylebox_override("hover", sb_hover)
			b.add_theme_stylebox_override("focus", sb_hover)
			b.add_theme_stylebox_override("pressed", sb_hover)
			b.pressed.connect(_on_dot_pressed.bind(Vector2i(x, y)))
			# 调试模式：鼠标按下可以拖动
			b.gui_input.connect(_on_dot_gui_input.bind(b))
			_board.add_child(b)
			_dots.append(b)

	_refresh()


# ---------------------------------------------------------------- 点击
func _on_dot_pressed(c: Vector2i) -> void:
	if _won:
		return
	# 点错：不是下一个该点的点 → 整条清空
	if c != PATTERN[_step]:
		_errors += 1
		_reset_chain()
		if _errors >= 3:
			_set_step_text("S 有五笔。这个数字等下还有用。", PreludeUI.C_NAME)
		else:
			_set_step_text("不对。从右上角重新开始，从上往下画。", C_BUMP)
		return

	# 点对：续上，并把这一点和前一点连起来
	var seg: ColorRect = null
	if _step > 0:
		seg = _make_line(PATTERN[_step - 1], c)
	_step += 1
	_refresh()

	if _step >= PATTERN.size():
		_win()
		return
	if seg != null:
		_pop(seg)
	if _step <= 1:
		_set_step_text("", PreludeUI.C_INK_DIM)
	else:
		_set_step_text("已点亮 %d / %d" % [_step, PATTERN.size()], PreludeUI.C_INK_DIM)


func _reset_chain() -> void:
	_step = 0
	for l in _lines:
		if is_instance_valid(l):
			l.queue_free()
	_lines.clear()
	_refresh()


# ---------------------------------------------------------------- 视觉
func _refresh() -> void:
	for i in _dots.size():
		if not is_instance_valid(_dots[i]):
			continue
		var lit := false
		for k in _step:
			if PATTERN[k] == _cell_of(i):
				lit = true
				break
		var sb := _dots[i].get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).bg_color = C_DOT_ON if lit else C_DOT


func _cell_of(i: int) -> Vector2i:
	return Vector2i(i % DOTS, i / DOTS)


## 屏幕区域里 9 个点的起始位置（手机图片里屏幕左上角的点）
const DOT_ORIGIN := Vector2(70, 187)

## 在两点之间摆一个细长的 ColorRect。只支持横 / 竖（本关的手势正好只有这两向），
## 而且因为 [S] 每一笔都穿过中间那个点，所以虚线中间绕个弯也不用管。
func _make_line(a: Vector2i, b: Vector2i) -> ColorRect:
	var r := ColorRect.new()
	r.color = C_LINE_SKIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thickness := 4.0
	if a.y == b.y:
		var y := DOT_ORIGIN.y + float(a.y) * GAP_Y
		r.offset_left = DOT_ORIGIN.x + minf(float(a.x), float(b.x)) * GAP_X
		r.offset_right = DOT_ORIGIN.x + maxf(float(a.x), float(b.x)) * GAP_X
		r.offset_top = y - thickness * 0.5
		r.offset_bottom = y + thickness * 0.5
	else:
		var x := DOT_ORIGIN.x + float(a.x) * GAP_X
		r.offset_left = x - thickness * 0.5
		r.offset_right = x + thickness * 0.5
		r.offset_top = DOT_ORIGIN.y + minf(float(a.y), float(b.y)) * GAP_Y
		r.offset_bottom = DOT_ORIGIN.y + maxf(float(a.y), float(b.y)) * GAP_Y
	_line_holder.add_child(r)
	_lines.append(r)
	return r


## 新画出来的一笔"长出来"：从中心拉长到整段
func _pop(r: ColorRect) -> void:
	var full := r.size
	if full.x <= 0.0 or full.y <= 0.0:
		return
	var mid := r.position + full * 0.5
	r.pivot_offset = full * 0.5
	r.position = mid - full * 0.5
	r.scale = Vector2(0.08, 0.08)
	var t := create_tween()
	t.tween_property(r, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_step_text(text: String, col: Color) -> void:
	if not is_instance_valid(_step_label):
		return
	_step_label.text = text
	_step_label.add_theme_color_override("font_color", col)


# ---------------------------------------------------------------- 通关
func _win() -> void:
	_won = true
	_set_step_text("手机解锁了。", PreludeUI.C_NAME)
	# 停 0.6 秒让玩家看清那句话，再交还控制权
	await get_tree().create_timer(0.6).timeout
	PreludeState.set_flag("week1_gesture_pattern", "S")
	close_panel({"ok": true, "pattern": "S"})


# ============================================================================
#  调试模式（按 D 开关，开了可以拖点对齐手机图片，按 P 打印数值）
# ============================================================================

## 点的鼠标输入：调试模式下按下开始拖动
func _on_dot_gui_input(event: InputEvent, dot: Button) -> void:
	if not _debug_mode:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_dragging_dot = dot
			_drag_offset = dot.get_global_rect().position - get_global_mouse_position()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging_dot = null


func _input(event: InputEvent) -> void:
	# 按 D 切换调试模式
	if event is InputEventKey and event.pressed and not event.echo:
		var ev := event as InputEventKey
		if ev.keycode == KEY_D:
			_debug_mode = not _debug_mode
			if _debug_mode:
				_set_step_text("调试模式开了：拖点对齐，按 P 打印数值", Color(0.5, 1.0, 0.5))
			else:
				_set_step_text("调试模式关了", C_DOT_ON)
			return
		# 按 P 打印当前数值
		if ev.keycode == KEY_P:
			_print_debug_values()
			return

	# 调试模式下拖动点
	if _debug_mode and _dragging_dot != null:
		if event is InputEventMouseMotion:
			var mp := get_global_mouse_position() + _drag_offset
			# 把全局坐标转成 board 局部坐标
			var local_pos := _board.get_global_transform_with_canvas().affine_inverse() * mp
			_dragging_dot.offset_left = local_pos.x
			_dragging_dot.offset_top = local_pos.y
			_dragging_dot.offset_right = local_pos.x + DOT
			_dragging_dot.offset_bottom = local_pos.y + DOT
			accept_event()


## 打印当前九个点的位置，方便写死到代码里
func _print_debug_values() -> void:
	print("===== 手势面板调试数值 =====")
	# 左上点 = (0,0) 的位置
	var dot00 := _dots[0]  # (0,0)
	var dot10 := _dots[1]  # (1,0)
	var dot01 := _dots[3]  # (0,1)
	var ox := dot00.offset_left + DOT * 0.5
	var oy := dot00.offset_top + DOT * 0.5
	var gx := (dot10.offset_left + DOT * 0.5) - ox
	var gy := (dot01.offset_top + DOT * 0.5) - oy
	print("DOT_ORIGIN = Vector2(%.1f, %.1f)" % [ox, oy])
	print("GAP_X = %.1f" % gx)
	print("GAP_Y = %.1f" % gy)
	print("DOT = %.1f" % DOT)
	print("BOARD_W = %.1f" % BOARD_W)
	print("BOARD_H = %.1f" % BOARD_H)
	print("===== 九个点的中心坐标 =====")
	for i in _dots.size():
		var d := _dots[i]
		var cx := d.offset_left + DOT * 0.5
		var cy := d.offset_top + DOT * 0.5
		print("  dot[%d] = (%.1f, %.1f)" % [i, cx, cy])
	print("=============================")
	_set_step_text("数值已打印到控制台（按 F8 看）", Color(0.5, 1.0, 0.5))
