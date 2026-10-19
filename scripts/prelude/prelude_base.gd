extends Control
## ============================================================================
##  《寻星》前日谈 —— 场景部分基类
## ============================================================================
##  子类（week1_1 / week2_1）只需要提供：
##    · data_path()        脚本数据路径
##    · chapter_id()       章节 id
##    · chapter_sequences()本次要播的序列列表
##    · 需要时覆盖 _on_chapter_end() 做幕间转场
##
##  运行时会自己搭好 UI 与背景，所以 .tscn 里只要挂这个脚本即可，
##  这样也就从根本上不存在"节点找不到"的问题。
## ============================================================================

const RUNTIME_SCRIPT := "res://scripts/ui/dialogue_runtime.gd"

## 幕间黑屏的时长（秒）
const INTERMISSION_WAIT := 2.4

var runtime: Control = null
var _curtain: ColorRect = null
var _label: Label = null
var _advanced := false
var _intermission := false
var _intermission_cb: Callable = Callable()


func _ready() -> void:
	# 本节点已在树内，父级尺寸有效，所以可以直接铺满。
	# 注意用 set_anchors_and_offsets_preset()：set_anchors_preset() 只改 anchor 不动
	# offset，节点会保持 0×0，整个前日谈就什么都看不到、也点不到。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_curtain()

	runtime = Control.new()
	runtime.name = "Runtime"
	runtime.set_script(load(RUNTIME_SCRIPT))
	if runtime.get_script() == null:
		push_error("[Prelude] 无法加载运行时脚本：%s" % RUNTIME_SCRIPT)
		return
	# 关键：必须在 add_child 之前把章节信息交给运行时。
	# add_child 会立刻触发运行时的 _ready，而那一刻本脚本的子类覆盖还没绑定好，
	# 运行时要是在 _ready 里去问父节点要序列，只会拿到自己的默认空数组。
	runtime.call("configure", chapter_id(), data_path(), chapter_sequences())
	add_child(runtime)
	# 【坑·已修】运行时在"序列播完"时会 emit sequence_finished，但以前没人接这个信号，
	# 于是子类覆盖的 _on_chapter_end()（幕间转场 / 结局按钮）永远跑不到，
	# 玩家按到最后只会看到对话框里一句「（本章已结束。）」就卡住。
	# 信号带一个 sequence_id 参数，这里接一个不收参数的 Callable，多余的实参会被忽略。
	runtime.connect("sequence_finished", Callable(self, "_on_sequence_finished"))


## 幕间黑屏（默认全透明，只有转场时才拉出来）
func _make_curtain() -> void:
	_curtain = ColorRect.new()
	_curtain.name = "Intermission"
	# 幕间要在所有东西之上（说话人立绘是 z_index 1、对话框 5、标题卡 9，见坑 41）
	_curtain.z_index = 12
	_curtain.color = Color(0.01, 0.01, 0.015, 0.0)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_curtain)
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_label = Label.new()
	_label.name = "IntermissionLabel"
	_label.z_index = 13
	_label.text = "点击 / 空格  继续"
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.74, 0.72, 0.68))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_label.offset_left = -200.0
	_label.offset_right = 200.0
	_label.offset_top = 90.0
	_label.offset_bottom = 120.0
	_label.modulate.a = 0.0


# ---------------------------------------------------------------- 子类覆盖点
## 默认指向一周目数据（子类 week1_1 / week2_1 各自覆盖为自己的数据文件）
func data_path() -> String:
	return "res://data/week1_dialogue.json"


func chapter_id() -> String:
	return "week1"


func chapter_sequences() -> Array:
	return []


## 快捷进入（标题页"章节选择"）：若 PreludeState 立了 quick_start 标记、且它在本次
## 序列里，就只播"从那段往后的部分"，并清掉标记；否则原样返回全部序列。
## 用"截断序列"而不是"跳索引"，因为走位续行/存档都以 sequence_order 为准，
## 截断后播完会自动走本幕的正常收尾（幕间/转场），整条链能自洽地接下去。
## 【坑·已修】走位返回时宿主场景会重建、_quick_trim 会再跑一遍——如果只认 quick_start，
## 第二次进来时标记已被清空，会退回"完整序列"，而走位恢复点存的 _seq_index 是按截断
## 序列算的，套在完整序列上就错位（快捷进第 2 天 → 走位后跳回第一天开头）。
## 所以截断时把"截断起始下标 + 章节 id"存下来，同一章节重建场景时沿用同一次截断。
func _quick_trim(seqs: Array) -> Array:
	var qs := str(PreludeState.get_flag("quick_start", ""))
	if qs != "" and seqs.has(qs):
		var at := seqs.find(qs)
		PreludeState.set_flag("quick_start", "")
		PreludeState.set_flag("quick_trim_at", at)
		PreludeState.set_flag("quick_trim_chapter", chapter_id())
		return seqs.slice(at)
	# 同一次快捷进入的后续重建（走位返回 / 面板返回）：沿用截断点，保持索引对齐
	var cid := str(PreludeState.get_flag("quick_trim_chapter", ""))
	if cid == chapter_id():
		var at2 := int(PreludeState.get_flag("quick_trim_at", -1))
		if at2 >= 0 and at2 < seqs.size():
			return seqs.slice(at2)
	# 本幕正常播完 / 从第一段开始 / 已切到别的幕：不再截断
	PreludeState.set_flag("quick_trim_at", "")
	PreludeState.set_flag("quick_trim_chapter", "")
	return seqs


func _on_chapter_end() -> void:
	pass


## 【坑·已修】runtime.sequence_finished 带一个 sequence_id 实参，
## 而子类覆盖的 _on_chapter_end() 不收参数 —— 直接 connect("sequence_finished", Callable(self, "_on_chapter_end"))
## 运行时会报 "Method expected 0 argument(s), but called with 1."，
## 于是幕间 / 结局永远不会触发。这里用一层转发把实参吃掉。
func _on_sequence_finished(_sequence_id: String) -> void:
	_on_chapter_end()


## 走位结束后要切回哪一幕。runtime 拿不到 current_scene（探针环境）时
## 会回来问宿主，子类用自己的场景路径覆盖即可。
func return_scene() -> String:
	return ""


# ---------------------------------------------------------------- 幕间转场
## 拉黑幕；玩家点击 / 空格（或超时）后执行 on_continue
func _show_intermission(hint: String, on_continue: Callable) -> void:
	_advanced = false
	_intermission = true
	_intermission_cb = on_continue
	_label.text = hint
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_curtain, "color:a", 1.0, 0.9)
	tw.tween_property(_label, "modulate:a", 1.0, 1.6)

	# 超时自动继续（防止玩家不知道该点哪里）
	var timer := get_tree().create_timer(INTERMISSION_WAIT)
	timer.timeout.connect(func(): _gate_continue(on_continue))
	# 点击 / 空格也能继续：交给 _unhandled_input


## 幕间等待期间，点击或空格可以提前继续
func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	# 【测试专用 · 项目收尾时删除】P 键跳过解密直接进宿舍走位。
	# 注意：不能用 F8/F9 等 F 键——F8 是 Godot 编辑器"停止运行"的默认快捷键，
	# 从编辑器跑测试时会被编辑器截走，导致一按就退出整个测试。
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_P:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		PreludeState.test_skip_to_dorm_walk()
		return
	if _intermission and event.is_action_pressed("prelude_advance"):
		# 【坑 59】先取 viewport、判空，再切场景。
		# _gate_continue() 里会 change_scene_to_file()，这一下就把本节点摘出了场景树
		# （实测 Godot 4.7：切完之后 get_viewport() 已经是 null），
		# 原来的写法紧接着调 get_viewport().set_input_as_handled() 就会报
		# "Cannot call method 'set_input_as_handled' on a null value."
		# 玩家（2026-10-14 Kerry）正是在「第一幕结束 → 点进第二幕」这一下踩到的。
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		_gate_continue(_intermission_cb)


func _gate_continue(on_continue: Callable) -> void:
	if _advanced or not _intermission:
		return
	_advanced = true
	_intermission = false
	if on_continue.is_valid():
		on_continue.call()
