extends CanvasLayer
## ============================================================================
##  《寻星》—— 暂停菜单（全局，autoload 名 PauseMenu）
## ============================================================================
##  来源（Kerry 2026-10-14）：
##    「封面界面加功能…必要的如退出游戏，读取存档，设置（音量等）」
##    「在游玩过程中缺少暂停，存档，退出/回到主菜单（封面），设置的选项」
##
##  为什么做成 autoload 而不是某个场景的子节点：
##    · 暂停要在"对话里"和"走位里"都好使，两套运行时各挂一份容易漏；
##    · 读档 / 回主菜单要自己切场景，切完新场景也得还有它。
##
##  【坑】Esc 同时是"合上回看 / 笔记面板"的键。这里的规矩是：
##  当前场景的运行时若正开着某个覆盖层（小游戏面板 / 回看 / 笔记 / 选项 / 记录卡 / 物件弹窗），
##  Esc 让给运行时去关那一层，不弹暂停菜单 —— 运行时用 blocks_pause() 回答这件事。
##
##  【坑】挂 autoload 的这个节点要 `process_mode = PROCESS_MODE_WHEN_PAUSED`，
##  否则 get_tree().paused = true 之后连"继续游戏"都点不动。
## ============================================================================

## preload 而不是直接用全局类名 PreludeUI：见 HANDOFF 坑（class_name 在 --script 模式下不注册）
const UI := preload("res://scripts/ui/prelude_ui.gd")

const TITLE_SCENE := "res://scenes/title/title.tscn"

var _root: Control = null
var _panel: PanelContainer = null
var _main_box: VBoxContainer = null
var _set_box: VBoxContainer = null
var _msg: Label = null
var _volume_slider: HSlider = null
var _auto_check: CheckButton = null

## 按键重绑状态
var _rebinding_action: String = ""      ## 正在等待按键输入的 action 名
var _rebind_buttons: Dictionary = {}    ## action 名 → 对应的按钮（用于刷新文字）


func _ready() -> void:
	# 【坑】这里必须是 ALWAYS，不能写 PROCESS_MODE_WHEN_PAUSED：
	# WHEN_PAUSED 的意思是"只有游戏已经暂停时才处理"，于是游戏正常跑的时候
	# 这个节点的 _input 根本不触发 —— Esc 永远打不开暂停菜单（实机踩过）。
	# ALWAYS = 暂停前后都收输入，按钮在暂停中才点得动。
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128          # 盖在所有东西上面（幕间层是 12 / 13，小游戏面板是 7）


# ============================================================================
#  开关
# ============================================================================

func is_open() -> bool:
	return _root != null and _root.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	_ensure_built()
	if _root == null:
		return
	_root.visible = true
	_show_main()
	_set_msg("")
	get_tree().paused = true


## 标题页的「设置」按钮走这里：直接开在设置页（Kerry：封面也该能调音量）。
func open_settings() -> void:
	open()
	_show_settings()


func close() -> void:
	if _root != null:
		_root.visible = false
	get_tree().paused = false


## 问当前场景的运行时："现在有覆盖层开着吗？"
func _blocks_pause() -> bool:
	var rt := _runtime()
	if rt != null and rt.has_method("blocks_pause"):
		return bool(rt.call("blocks_pause"))
	return false


## 宿主场景（prelude_base / prelude_walk）把运行时节点存在 `runtime` 属性里
func _runtime() -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	var rt = cs.get("runtime")
	if rt is Node:
		return rt as Node
	return null


# ============================================================================
#  界面
# ============================================================================

func _ensure_built() -> void:
	if _root != null:
		return

	_root = Control.new()
	_root.name = "PauseRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# 【坑】先给全屏锚点再设 offset（见 progress.md 第 26 条），否则容器会被压成一条
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "PausePanel"
	_panel.add_theme_stylebox_override("panel", UI.panel_skin(UI.C_PANEL_HI, UI.C_LINE, 8))
	_root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -220.0
	_panel.offset_right = 220.0
	_panel.offset_top = -220.0
	_panel.offset_bottom = 220.0

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	var head := Label.new()
	head.text = "暂停"
	head.add_theme_font_size_override("font_size", UI.FS_NAME)
	head.add_theme_color_override("font_color", UI.C_INK)
	col.add_child(head)

	var hr := UI.hline(360.0)
	col.add_child(hr)

	# ---- 主菜单列
	_main_box = VBoxContainer.new()
	_main_box.name = "PauseMain"
	_main_box.add_theme_constant_override("separation", 8)
	col.add_child(_main_box)
	_main_box.add_child(_button("继续游戏", close))
	_main_box.add_child(_button("保存进度", _on_save_pressed))
	_main_box.add_child(_button("读取存档", _on_load_pressed))
	_main_box.add_child(_button("设置", _show_settings))
	_main_box.add_child(_button("回到主菜单", _on_title_pressed))
	_main_box.add_child(_button("退出游戏", _on_quit_pressed))

	# ---- 设置列
	_set_box = VBoxContainer.new()
	_set_box.name = "PauseSettings"
	_set_box.add_theme_constant_override("separation", 10)
	col.add_child(_set_box)

	var vlabel := Label.new()
	vlabel.text = "主音量"
	vlabel.add_theme_font_size_override("font_size", UI.FS_TEXT)
	vlabel.add_theme_color_override("font_color", UI.C_INK)
	_set_box.add_child(vlabel)

	_volume_slider = HSlider.new()
	_volume_slider.name = "VolumeSlider"
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.custom_minimum_size = Vector2(340, 26)
	var gs := _settings()
	_volume_slider.value = gs.volume if gs != null else 0.8
	_volume_slider.value_changed.connect(_on_volume_changed)
	_set_box.add_child(_volume_slider)

	_auto_check = CheckButton.new()
	_auto_check.name = "AutoplayCheck"
	_auto_check.text = "自动播放剧情（每句自动往下）"
	_auto_check.add_theme_font_size_override("font_size", UI.FS_TIP)
	_auto_check.button_pressed = gs.autoplay if gs != null else false
	_auto_check.toggled.connect(_on_autoplay_toggled)
	_set_box.add_child(_auto_check)

	# ---- 按键设置区域
	var key_hr := UI.hline(360.0)
	_set_box.add_child(key_hr)

	var key_title := Label.new()
	key_title.text = "按键设置"
	key_title.add_theme_font_size_override("font_size", UI.FS_TEXT)
	key_title.add_theme_color_override("font_color", UI.C_INK)
	_set_box.add_child(key_title)

	# 5 个可自定义按键
	if gs != null:
		for entry in gs.BINDABLE_ACTIONS:
			var display_name: String = entry[0]
			var action: String = entry[1]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			_set_box.add_child(row)

			var lbl := Label.new()
			lbl.text = display_name
			lbl.custom_minimum_size = Vector2(120, 0)
			lbl.add_theme_font_size_override("font_size", UI.FS_TIP)
			lbl.add_theme_color_override("font_color", UI.C_INK)
			row.add_child(lbl)

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(100, 28)
			btn.text = gs.keycode_to_name(gs.get_key_for_action(action))
			btn.add_theme_font_size_override("font_size", UI.FS_TIP)
			UI.apply_button_skin(btn)
			btn.pressed.connect(_on_rebind_pressed.bind(action))
			row.add_child(btn)

			_rebind_buttons[action] = btn

		# 恢复默认按键按钮
		var reset_btn := Button.new()
		reset_btn.text = "恢复默认按键"
		reset_btn.add_theme_font_size_override("font_size", UI.FS_TIP)
		UI.apply_button_skin(reset_btn)
		reset_btn.pressed.connect(_on_reset_keys_pressed)
		_set_box.add_child(reset_btn)

	_set_box.add_child(_button("返回", _show_main))

	# ---- 提示行
	_msg = Label.new()
	_msg.name = "PauseMsg"
	_msg.add_theme_font_size_override("font_size", UI.FS_TIP)
	_msg.add_theme_color_override("font_color", UI.C_INK_DIM)
	_msg.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(_msg)

	var hint := Label.new()
	hint.text = "Esc 继续游戏"
	hint.add_theme_font_size_override("font_size", UI.FS_TIP)
	hint.add_theme_color_override("font_color", UI.C_INK_DIM)
	col.add_child(hint)

	_show_main()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UI.FS_TEXT)
	UI.apply_button_skin(b)
	b.pressed.connect(cb)
	return b


func _show_main() -> void:
	if _main_box == null:
		return
	_main_box.visible = true
	_set_box.visible = false


func _show_settings() -> void:
	if _main_box == null:
		return
	_main_box.visible = false
	_set_box.visible = true
	_set_msg("")


func _set_msg(text: String) -> void:
	if _msg != null:
		_msg.text = text


func _settings() -> Node:
	return get_node_or_null("/root/GameSettings")


# ============================================================================
#  按钮行为
# ============================================================================

func _on_save_pressed() -> void:
	var rt := _runtime()
	var sg := get_node_or_null("/root/SaveGame")
	if sg == null:
		_set_msg("存档服务没起来。")
		return
	# 走位场景没有 save_now：那里不落盘，等回到对话时会自动存（见 SaveGame 的说明）。
	if rt == null or not rt.has_method("save_now"):
		_set_msg("现在没有正在进行的对话，先不存。")
		return
	rt.call("save_now")
	if bool(sg.call("has_save")):
		_set_msg("已保存：%s" % str(sg.call("label")))
	else:
		_set_msg("这里没有可以保存的进度。")


func _on_load_pressed() -> void:
	var sg := get_node_or_null("/root/SaveGame")
	if sg == null:
		_set_msg("存档服务没起来。")
		return
	if not bool(sg.call("has_save")):
		_set_msg("还没有存档。")
		return
	var path := str(sg.call("request_resume"))
	if path == "":
		_set_msg("存档读不出来。")
		return
	close()
	get_tree().change_scene_to_file(path)


func _on_title_pressed() -> void:
	close()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_volume_changed(v: float) -> void:
	var gs := _settings()
	if gs != null:
		gs.call("set_volume", v)


func _on_autoplay_toggled(on: bool) -> void:
	var gs := _settings()
	if gs != null:
		gs.call("set_autoplay", on)


# ============================================================================
#  按键重绑
# ============================================================================

## 点了某个按键的"更改"按钮：进入等待输入状态
func _on_rebind_pressed(action: String) -> void:
	_rebinding_action = action
	var gs := _settings()
	if gs == null:
		return
	# 把按钮文字改成"按任意键..."
	var btn: Button = _rebind_buttons.get(action)
	if btn != null:
		btn.text = "按任意键..."
	_set_msg("按下你想设的按键（Esc 取消）")


## 恢复默认按键
func _on_reset_keys_pressed() -> void:
	var gs := _settings()
	if gs == null:
		return
	gs.key_bindings.clear()
	gs.apply_key_bindings()
	gs.save_settings()
	_refresh_rebind_buttons()
	_set_msg("已恢复默认按键（WASD + 空格）")


## 刷新所有按键按钮的文字
func _refresh_rebind_buttons() -> void:
	var gs := _settings()
	if gs == null:
		return
	for action in _rebind_buttons:
		var btn: Button = _rebind_buttons[action]
		btn.text = gs.keycode_to_name(gs.get_key_for_action(action))


## 重写 _input，加上按键捕获（原来的 _input 处理 Esc 开关暂停菜单）
func _input(event: InputEvent) -> void:
	# 如果正在等待按键输入，优先处理这个
	if _rebinding_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			var ev := event as InputEventKey
			var gs := _settings()
			if gs != null:
				if ev.keycode == KEY_ESCAPE:
					# Esc 取消
					_set_msg("已取消按键修改")
				else:
					# 设置新按键
					gs.set_key_for_action(_rebinding_action, ev.keycode)
					_set_msg("已设置：%s" % gs.keycode_to_name(ev.keycode))
			_rebinding_action = ""
			_refresh_rebind_buttons()
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			return
		# 鼠标点击也可以作为按键？不，只接受键盘
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	# 覆盖层开着（回看 / 笔记 / 小游戏面板 / 记录卡 …）：这一下 Esc 归运行时，让它关那一层
	if not is_open() and _blocks_pause():
		return
	toggle()
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
