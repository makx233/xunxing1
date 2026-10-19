extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— 刘忆的书桌（俯视图）
## ============================================================================
##  一个偏俯视图的木质桌面，上面摆着手机、黑箱、折纸星星三样东西。
##  【调试模式】按 F1 开启/关闭调试模式：
##    · Tab 切换选中的物品（手机/黑箱/星星）
##    · 方向键 上下左右 移动选中的物品
##    · +/- 键 调整选中物品的大小
##    · 调整好之后按 P 键打印当前的位置和大小参数
## ============================================================================

const DESK_W := 600.0
const DESK_H := 400.0

## 物品纹理（和走位房间里的是同一套）
const TEX_PHONE := "res://assets/props/phone.png"
const TEX_BLACK_BOX := "res://assets/props/black_box.png"
const TEX_STAR := "res://assets/props/paper_star.png"

## 物品的位置和大小（可以在调试模式下调整）
var _item_positions := {
	"phone": {"x": 120.0, "y": 220.0, "w": 80.0, "h": 120.0},
	"box": {"x": 280.0, "y": 180.0, "w": 120.0, "h": 100.0},
	"star": {"x": 450.0, "y": 250.0, "w": 60.0, "h": 60.0},
}

var _tex_phone: Texture2D = null
var _tex_box: Texture2D = null
var _tex_star: Texture2D = null
var _canvas: Control = null
var _star_collected := false

# 调试模式相关
var _debug_mode := false
var _selected_item := "phone"
var _debug_label: Label = null


# ---------------------------------------------------------------- 子类覆盖点
func wants_exit() -> bool:
	return true


func panel_title() -> String:
	return "刘忆的书桌"


func panel_hint() -> String:
	if _debug_mode:
		return "调试模式：Tab 切换物品，方向键移动，+/- 调整大小，P 打印参数"
	else:
		return "点击右上角退出按钮关闭窗口"


func build_body(body: VBoxContainer) -> void:
	# 加载物品纹理
	_tex_phone = PreludeUI.load_texture(TEX_PHONE)
	_tex_box = PreludeUI.load_texture(TEX_BLACK_BOX)
	_tex_star = PreludeUI.load_texture(TEX_STAR)

	# 创建画布
	_canvas = Control.new()
	_canvas.name = "DesktopCanvas"
	_canvas.custom_minimum_size = Vector2(DESK_W, DESK_H)
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_canvas)

	# 调试模式的提示文字
	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	_debug_label.position = Vector2(10, 10)
	_debug_label.visible = false
	_canvas.add_child(_debug_label)

	_paint_desk()
	_paint_items()


# ---------------------------------------------------------------- 布景
func _paint_desk() -> void:
	# 木质桌面背景（用代码生成木纹效果）
	var desk := ColorRect.new()
	desk.color = Color(0.45, 0.32, 0.20)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(desk)
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 画木纹（横向的条纹）
	for i in range(20):
		var y = float(i) * (DESK_H / 20.0)
		var stripe := ColorRect.new()
		# 随机深浅的木纹
		var shade = 0.05 * sin(i * 0.5)
		stripe.color = Color(
			0.45 + shade,
			0.32 + shade * 0.7,
			0.20 + shade * 0.5
		)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(stripe)
		stripe.set_anchors_preset(Control.PRESET_TOP_LEFT)
		stripe.offset_left = 0
		stripe.offset_top = y
		stripe.offset_right = DESK_W
		stripe.offset_bottom = y + (DESK_H / 20.0) * 0.8

	# 桌沿高光（顶部）
	var edge_top := ColorRect.new()
	edge_top.color = Color(0.55, 0.40, 0.27)
	edge_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(edge_top)
	edge_top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	edge_top.offset_left = 0
	edge_top.offset_top = 0
	edge_top.offset_right = DESK_W
	edge_top.offset_bottom = 8

	# 桌沿阴影（底部）
	var edge_bottom := ColorRect.new()
	edge_bottom.color = Color(0.30, 0.20, 0.12)
	edge_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(edge_bottom)
	edge_bottom.set_anchors_preset(Control.PRESET_TOP_LEFT)
	edge_bottom.offset_left = 0
	edge_bottom.offset_top = DESK_H - 8
	edge_bottom.offset_right = DESK_W
	edge_bottom.offset_bottom = DESK_H

	# 桌沿阴影（左侧）
	var edge_left := ColorRect.new()
	edge_left.color = Color(0.35, 0.24, 0.15)
	edge_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(edge_left)
	edge_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	edge_left.offset_left = 0
	edge_left.offset_top = 0
	edge_left.offset_right = 8
	edge_left.offset_bottom = DESK_H

	# 桌沿高光（右侧）
	var edge_right := ColorRect.new()
	edge_right.color = Color(0.50, 0.36, 0.24)
	edge_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(edge_right)
	edge_right.set_anchors_preset(Control.PRESET_TOP_LEFT)
	edge_right.offset_left = DESK_W - 8
	edge_right.offset_top = 0
	edge_right.offset_right = DESK_W
	edge_right.offset_bottom = DESK_H


func _paint_items() -> void:
	# 手机位置
	if _tex_phone != null:
		var p = _item_positions["phone"]
		_sprite(_canvas, Rect2(p["x"], p["y"], p["w"], p["h"]), _tex_phone)
	
	# 黑箱位置
	if _tex_box != null:
		var p = _item_positions["box"]
		_sprite(_canvas, Rect2(p["x"], p["y"], p["w"], p["h"]), _tex_box)
	
	# 星星位置
	if _tex_star != null and not _star_collected:
		var p = _item_positions["star"]
		_sprite(_canvas, Rect2(p["x"], p["y"], p["w"], p["h"]), _tex_star)

	# 调试模式下画选中框
	if _debug_mode:
		_draw_debug_selection()


func _draw_debug_selection() -> void:
	# 清除旧的选中框（简单起见，全部重画）
	# 先画物品
	_paint_items()
	
	# 画选中框
	var p = _item_positions[_selected_item]
	var selection := ColorRect.new()
	selection.color = Color(1, 0, 0, 0.3)
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(selection)
	selection.set_anchors_preset(Control.PRESET_TOP_LEFT)
	selection.offset_left = p["x"] - 2
	selection.offset_top = p["y"] - 2
	selection.offset_right = p["x"] + p["w"] + 2
	selection.offset_bottom = p["y"] + p["h"] + 2


# ---------------------------------------------------------------- 输入处理（调试模式）
func handle_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event = event as InputEventKey
		if key_event.pressed:
			# F1 开启/关闭调试模式
			if key_event.keycode == KEY_F1:
				_debug_mode = not _debug_mode
				_debug_label.visible = _debug_mode
				if _debug_label != null:
					_debug_label.text = "调试模式已开启"
				_paint_items()
				return
	
	if not _debug_mode:
		return
	
	if event is InputEventKey:
		var key_event = event as InputEventKey
		if key_event.pressed:
			match key_event.keycode:
				KEY_TAB:
					# 切换选中的物品
					match _selected_item:
						"phone":
							_selected_item = "box"
						"box":
							_selected_item = "star"
						"star":
							_selected_item = "phone"
					_paint_items()
				
				KEY_UP:
					_item_positions[_selected_item]["y"] -= 5
					_paint_items()
				KEY_DOWN:
					_item_positions[_selected_item]["y"] += 5
					_paint_items()
				KEY_LEFT:
					_item_positions[_selected_item]["x"] -= 5
					_paint_items()
				KEY_RIGHT:
					_item_positions[_selected_item]["x"] += 5
					_paint_items()
				
				KEY_EQUAL:
					# 放大
					_item_positions[_selected_item]["w"] *= 1.1
					_item_positions[_selected_item]["h"] *= 1.1
					_paint_items()
				KEY_MINUS:
					# 缩小
					_item_positions[_selected_item]["w"] *= 0.9
					_item_positions[_selected_item]["h"] *= 0.9
					_paint_items()
				
				KEY_P:
					# 打印当前参数
					print("=== 桌面物品参数 ===")
					for key in _item_positions:
						var p = _item_positions[key]
						print("%s: x=%.1f, y=%.1f, w=%.1f, h=%.1f" % [key, p["x"], p["y"], p["w"], p["h"]])


func wants_input() -> bool:
	return _debug_mode


# ---------------------------------------------------------------- 工具函数
func _sprite(parent: Control, r: Rect2, tex: Texture2D) -> TextureRect:
	if tex == null:
		return null
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	t.set_anchors_preset(Control.PRESET_TOP_LEFT)
	t.offset_left = r.position.x
	t.offset_top = r.position.y
	t.offset_right = r.position.x + r.size.x
	t.offset_bottom = r.position.y + r.size.y
	return t
