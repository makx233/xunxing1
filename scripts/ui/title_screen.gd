extends Control
## ============================================================================
##  开场画面：封面
## ============================================================================
##  为什么单独做一个场景：Kerry 给的封面本来就是 16:9（换成了最新那版 3447x1944），
##  铺满 1280x720 不会变形；开场先看它一眼，再进一周目。
##
##  【坑 29】封面是从外面拷进来的图，**没有 .import**，ResourceLoader 看不见它，
##  必须走 PreludeUI.load_texture()（它内部会退回 Image.load_from_file）。
##
##  输入：点一下 / 空格 / 回车 都开始；开始后本节点不再吃输入。
##  读不出封面也不能卡住——退回一行"寻星"，照样能开始。
##  有存档时底部多一行「继续上次（第 N 章 · …）」，点它直接从存档处接着走。
## ============================================================================

const COVER := "res://assets/cover/chase_the_star.png"
const NEXT_SCENE := "res://scenes/week1/week1_1.tscn"

## 标题页"快捷进入 · 章节选择"：按 部分/天 列出的入口。
## 每项 = [按钮文字, 场景, 起始段 key, 附加要立的 flag]。
## 附加 flag 例子：二周目直入时立 prelude_done，播完才会"回到标题"而不是跳前日谈。
const QUICK_ENTRIES := [
	["一周目 · 第 1 天（星期三）", "res://scenes/week1/week1_1.tscn", "s0_maze", []],
	["一周目 · 第 2 天（早上）", "res://scenes/week1/week1_1.tscn", "s1_phone", []],
	["一周目 · 第 3 天（找不同）", "res://scenes/week1/week1_1.tscn", "s3_desk", []],
	["一周目 · 第 4 天（海龟汤）", "res://scenes/week1/week1_1.tscn", "s4_soup", []],
	["二周目 · 第 2 天（案发之后）", "res://scenes/week2/week2_1.tscn", "s0_scene", ["prelude_done"]],
]

var _started := false
var _has_save := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var cover := PreludeUI.load_texture(COVER)
	if cover != null:
		var tex := TextureRect.new()
		tex.name = "Cover"
		tex.texture = cover
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 封面原图就是 16:9，直接铺满，不用 KEEP_ASPECT（会留黑边）
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
	else:
		var fallback := Label.new()
		fallback.text = "寻　星"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 72)
		fallback.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)

	# 底部压一层暗色，保证提示文字在亮色封面上也读得清
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.42)
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_top = -132.0
	shade.offset_bottom = 0.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "点击 / 空格　开始"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
	prompt.anchor_left = 0.0
	prompt.anchor_right = 1.0
	prompt.anchor_top = 1.0
	prompt.anchor_bottom = 1.0
	prompt.offset_top = -92.0
	prompt.offset_bottom = -48.0
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)

	# 有存档的时候：给两个按钮，并且【关掉"点一下就开始"】——
	# 不然玩家想看封面随手一点，一周目的进度就没了。
	_has_save = SaveGame.has_save()
	if _has_save:
		var resume := Button.new()
		resume.name = "ResumeButton"
		resume.text = "继续上次　%s" % SaveGame.label()
		PreludeUI.apply_button_skin(resume)
		resume.anchor_left = 0.5
		resume.anchor_right = 0.5
		resume.anchor_top = 1.0
		resume.anchor_bottom = 1.0
		resume.offset_left = -230.0
		resume.offset_right = 230.0
		resume.offset_top = -196.0
		resume.offset_bottom = -144.0
		resume.pressed.connect(_resume)
		add_child(resume)

		var fresh := Button.new()
		fresh.name = "NewGameButton"
		fresh.text = "从头开始（会清掉现在的进度）"
		PreludeUI.apply_button_skin(fresh)
		fresh.anchor_left = 0.5
		fresh.anchor_right = 0.5
		fresh.anchor_top = 1.0
		fresh.anchor_bottom = 1.0
		fresh.offset_left = -230.0
		fresh.offset_right = 230.0
		fresh.offset_top = -136.0
		fresh.offset_bottom = -96.0
		fresh.pressed.connect(_start_fresh)
		add_child(fresh)

		prompt.text = "点上面的按钮继续　（存档时间 %s）" % SaveGame.saved_at()
		prompt.add_theme_font_size_override("font_size", 20)

	# 封面自己的「设置 / 退出」（Kerry 第 1 条：封面也应有退出、读档、设置）。
	# 读档＝上面那颗「继续上次」；体积小的设置与退出摆右上角，按 Esc 也能叫出完整暂停菜单。
	_build_corner_button("设置", _on_settings_pressed, -22.0, 96.0)
	_build_corner_button("退出游戏", _on_quit_pressed, -126.0, 96.0)

	# 快捷进入 · 章节选择（按"第几周目 / 前日谈第几幕"直接进对应段落，播完按正常链接续）
	_build_quick_entries()

	# 呼吸闪烁：不引入新资源，只用 Tween 改 alpha
	var tw := create_tween().set_loops()
	tw.tween_property(prompt, "modulate:a", 0.35, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(prompt, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)


## 章节选择：竖排在画面中部（底部留给"开始/继续/存档"那组按钮）。
func _build_quick_entries() -> void:
	var vb := VBoxContainer.new()
	vb.name = "QuickEntry"
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.0
	vb.anchor_bottom = 0.0
	vb.offset_left = -230.0
	vb.offset_right = 230.0
	vb.offset_top = 148.0
	vb.offset_bottom = 560.0
	add_child(vb)

	var cap := Label.new()
	cap.text = "快捷进入 · 章节选择"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", Color(0.90, 0.88, 0.82))
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(cap)

	for opt: Array in QUICK_ENTRIES:
		var b := Button.new()
		b.name = "Quick_" + str(opt[0])
		b.text = str(opt[0])
		PreludeUI.apply_button_skin(b, false)
		b.custom_minimum_size = Vector2(460, 40)
		b.pressed.connect(_quick_enter.bind(opt))
		vb.add_child(b)


## 快捷进入：清掉旧剧情状态 → 立 quick_start（+附加 flag）→ 切到对应场景。
## 不动存档文件；播完按该幕的正常收尾继续整条链。
func _quick_enter(opt: Array) -> void:
	if _started:
		return
	_started = true
	PreludeState.reset()
	PreludeState.set_flag("quick_start", str(opt[2]))
	for k: Variant in (opt[3] as Array):
		PreludeState.set_flag(str(k), true)
	get_tree().change_scene_to_file(str(opt[1]))


## 右上角两颗小按钮（设置 / 退出）：锚在右上，offset 用负数表示"离右边多远"。
func _build_corner_button(text: String, cb: Callable, right_offset: float, btn_width: float) -> void:
	var b := Button.new()
	b.name = "Corner_" + text
	b.text = text
	PreludeUI.apply_button_skin(b)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.0
	b.anchor_bottom = 0.0
	b.offset_left = right_offset - btn_width
	b.offset_right = right_offset
	b.offset_top = 22.0
	b.offset_bottom = 62.0
	b.pressed.connect(cb)
	add_child(b)


func _on_settings_pressed() -> void:
	var pm := get_node_or_null("/root/PauseMenu")
	if pm != null and pm.has_method("open_settings"):
		pm.call("open_settings")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	# 【测试专用 · 项目收尾时删除】P 键直接进宿舍走位（不动存档）。
	# 不用 F8：它是 Godot 编辑器"停止运行"的默认快捷键，编辑器会先截走。
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_P:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		PreludeState.test_skip_to_dorm_walk()
		return
	if _started:
		return
	# 有存档时只有空格/回车算"开始"（还要再确认一次），鼠标点击一律不算
	if _has_save and event is InputEventMouseButton:
		return
	var go := false
	if event is InputEventMouseButton:
		go = (event as InputEventMouseButton).pressed
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		go = true
	if go:
		if _has_save:
			_resume()
		else:
			_start_fresh()


## 从头开始：清掉存档与上一轮的资料，别把旧笔记/旧旗标带进新档
func _start_fresh() -> void:
	if _started:
		return
	_started = true
	SaveGame.clear()
	PreludeState.reset()
	get_tree().change_scene_to_file(NEXT_SCENE)


## 继续上次：存档系统把资料灌回 PreludeState，然后去存档那一幕
func _resume() -> void:
	if _started:
		return
	var scene := SaveGame.request_resume()
	if scene == "":
		# 存档坏了/文件被删了：退回"从头开始"，别把玩家卡在标题页
		_started = false
		_has_save = false
		_start_fresh()
		return
	_started = true
	get_tree().change_scene_to_file(scene)
