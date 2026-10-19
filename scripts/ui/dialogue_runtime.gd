extends Control
## ============================================================================
##  《寻星》前日谈 —— 对话 / 演出运行时
## ============================================================================
##  职责：
##    · 按脚本数据（脚本行 + 演出标记）顺序推进对话
##    · 打字机 / 点击与空格推进 / 选项分支 / 记录卡 / 笔记页
##    · 场景搭建（背景、立绘、物品热区）
##
##  脚本行格式（数组，按顺序执行）：
##    ["n",  文本]                     旁白（无名字，斜体灰字）
##    ["d",  说话人, 文本]              对话
##    ["m",  文本]                     李星的内心独白
##    ["card", 文本]                    弹出一张记录卡；玩家点掉后继续
##    ["formula1089"]                   1089 魔术的算式卡（回忆段专用）：整屏居中，
##                                      算式按玩家在面板里报的那一位拼出 p9f ＋ f9p ＝ 1089，
##                                      文字由浅变深逐渐浮现，点击/空格收起后继续
##    ["title", 大标题, 副标题]         全屏标题卡，点击继续
##    ["space", 背景键, 立绘数组]       切换场景（清空热区与立绘）
##    ["who", 立绘键]                   切换当前说话人（另一人变暗）
##    ["show", 立绘键] / ["hide", 立绘键]
##    ["item", 名称, 详情, [x,y,w,h]]    放置一个可点击物品热区
##    ["room", 房间id]                  声明"这一段的可看物件摆在哪个俯视角场景"
##                                      （清单只在 data/prelude_rooms.json 里维护一份）
##    ["free"]                         自由调查；若上面声明过 room，则切到俯视角走位，
##                                      走完自动切回本场景并从下一行继续
##    ["choice", 提示语, [选项文本], [分支数组]]
## ============================================================================

signal sequence_finished(sequence_id: String)

## 手绘场景底的绘制脚本（纯代码绘制，无素材依赖）
const BACKDROP_SCRIPT := "res://scripts/ui/prelude_backdrop.gd"
## 俯视角走位场景（解谜 / 查看物件时用它）
const WALK_SCENE := "res://scenes/prelude/prelude_walk.tscn"
## 一周目小游戏面板登记表。
## 【坑】这里故意用 preload 而不是全局类名 Week1Panels：class_name 要等 Godot
## 重新扫描项目才会进 .godot/global_script_class_cache.cfg，而 headless 自检
## （--script）不会去扫，于是新加的类名会报 "Identifier not declared"。
const WEEK1_PANELS := preload("res://scripts/week1/week1_panels.gd")
const WEEK2_PANELS := preload("res://scripts/week2/week2_panels.gd")

# ---------------------------------------------------------------- 场景键
const SPACE_HALLWAY := "hallway"
const SPACE_CLASSROOM := "classroom"
const SPACE_MONTAGE := "montage"
const SPACE_ROOFLINE := "roofline"
const SPACE_DORM_CORRIDOR := "dorm_corridor"
const SPACE_DORM_ROOM := "dorm_room"
const SPACE_BLACK := "black"
const SPACE_BALCONY := "balcony"   # 二周目：刘忆坠楼的阳台（栏杆缺口 + 横倒扫帚）
const SPACE_NIGHT := "night"       # 二周目结尾 CG：夜空大星星小星星

# 立绘贴图：七张都在 assets/portraits/ 下，**都是带透明底的成品**（Kerry 自己抠的，
# 2026-01 换的），不需要再跑 tools/import_assets.gd 处理。
# 运行时 Portrait.setup() 只把 alpha 连通区当背景（build_bg_mask），绝不再按亮度抠。
# 【二周目走访人物命名】同学A=1床陈一、同学B=2床蒋佳怡、同学C=4床常颜（文档要求
# 用 A/B/C 系列立绘；文件仍是 student_c/d/e.png，只改显示名）。
const ART := {
	"李星": "res://assets/portraits/lixing.png",
	"刘忆": "res://assets/portraits/liuyi.png",
	"同学A": "res://assets/portraits/student_c.png",
	"同学B": "res://assets/portraits/student_d.png",
	"同学C": "res://assets/portraits/student_e.png",
	"班主任": "res://assets/portraits/teacher.png",
	"宿管阿姨": "res://assets/portraits/warden.png",
}

# 对话框上方的显示名：同学A/B/C → 陈一/蒋佳怡/常颜（立绘键不变）
const DISPLAY_NAME := {
	"同学A": "陈一",
	"同学B": "蒋佳怡",
	"同学C": "常颜",
}

# 还没自报姓名时的「？？？」实际是刘忆：说话时立绘按刘忆亮（名字仍显示？？？）
const SPEAKER_ART := {
	"？？？": "刘忆",
}

# 立绘站位：李星左，刘忆右（呼应"刘忆逆光探出门"的构图）。
# 二周目走访的几个被询问对象（同学A/B/C、班主任、宿管阿姨）统一站右，
# 保证"李星一直在左边、被问的人单个出现在右边"；切换对象时脚本里用 ["hide"] 收掉上一个。
const SIDE := {
	"李星": -1,
	"刘忆": 1,
	"同学A": 1,
	"同学B": 1,
	"同学C": 1,
	"班主任": 1,
	"宿管阿姨": 1,
}

# 心理独白（["m"] 行）默认是李星的内心。
# 画面上不给独白配标签（Kerry：把「旁白」「（心里）」都去掉，独白只靠立绘提示是谁），
# 回看流水里则记成这个名字，读起来才知道那句是她想的。
const MONOLOGUE_SPEAKER := "李星"

# 各场景的底色渐变（上、下）
const SPACE_TINT := {
	SPACE_HALLWAY: [Color(0.17, 0.16, 0.20), Color(0.05, 0.05, 0.07)],
	SPACE_CLASSROOM: [Color(0.13, 0.14, 0.18), Color(0.04, 0.045, 0.06)],
	SPACE_MONTAGE: [Color(0.12, 0.12, 0.15), Color(0.045, 0.045, 0.06)],
	SPACE_ROOFLINE: [Color(0.10, 0.11, 0.14), Color(0.03, 0.035, 0.05)],
	SPACE_DORM_CORRIDOR: [Color(0.20, 0.16, 0.13), Color(0.04, 0.035, 0.04)],
	SPACE_DORM_ROOM: [Color(0.12, 0.12, 0.14), Color(0.04, 0.04, 0.05)],
	SPACE_BLACK: [Color(0.02, 0.02, 0.025), Color(0.0, 0.0, 0.0)],
	SPACE_BALCONY: [Color(0.12, 0.13, 0.18), Color(0.04, 0.045, 0.07)],
	SPACE_NIGHT: [Color(0.055, 0.06, 0.11), Color(0.02, 0.025, 0.05)],
}

# ---------------------------------------------------------------- 数据
## 由宿主场景（prelude_base）在 add_child 之前填好。
## 为什么不让运行时自己去问父节点？—— add_child 会【立刻】触发本脚本的 _ready，
## 而那时父脚本的子类方法绑定还没就绪，call("chapter_sequences") 会掉回
## 运行时自己的默认实现（空数组），于是整幕一行都播不出来。传进来最稳。
var chapter_id: String = "week1"
var dialogue_path: String = "res://data/week1_dialogue.json"
var dialogue: Dictionary = {}
var sequence_order: Array = []
var _seq_index := -1

# ---------------------------------------------------------------- 状态
var _rows: Array = []
var _row_is_top: Array = []      # 与 _rows 平行：该行是不是序列自己的顶层行（choice 分支 / peek 追加是 false）
var _row_index := 0
var _active := false
var _line_ready := false
var _free_mode := false
var _free_remaining := 0
var _pending_branches: Array = []
var _peeks: Dictionary = {}            # 物品名 -> 首次查看后追加播放的行
var _peeks_pending: Array = []         # 待插入的追加段落

# ---------------------------------------------------------------- 节点引用
var _bg_rect: ColorRect = null
var _bg_grad: GradientTexture2D = null
var _bg_art: TextureRect = null
var _backdrop: Control = null
var _portrait_layer: Control = null
var _hotspot_layer: Control = null
var _portraits: Dictionary = {}
var _hotspots: Array = []
var _advance_btn: Button = null
var _dbox: PreludeUI.DialogueBox = null
var _flash_rect: ColorRect = null   # ["flash"] 闪白转场的白屏层
var _choice: PreludeUI.ChoiceMenu = null
var _card: PreludeUI.RecordCard = null
var _notes: PreludeUI.NotesPanel = null
var _history: PreludeUI.HistoryPanel = null
var _history_btn: Button = null
var _note_btn: Button = null
var _free_btn: Button = null
# 1089 揭晓的"同一页逐句展开"：你的过去/未来/现在是/也就是……四行，
# 点一下多出一行（_on_advance 里先喂完 _reveal_pending 再往下播）。
var _reveal_pending: Array = []
var _fade: ColorRect = null
var _toast: Label = null
var _toast_time := 0.0
var _current_bg := ""
var _title_layer: Control = null
var _formula_layer: Control = null      # ["formula1089"] 的算式卡全屏层
var _formula_text: Label = null         # 算式文字（做由浅变深渐现）
var _panel: Control = null             # 一周目小游戏面板（["panel", id]）
var _panel_pending := ""               # 玩家从谜题退出去看笔记时的待续谜题 id
var _mindread_input_layer: Control = null   # 1089 读心术的"对话框式"输入浮层
var _mindread_edit: LineEdit = null          # 浮层里的数字输入框
var _mindread_feedback: Label = null         # 浮层里的提示文字（输错时用）


# ============================================================================
#  初始化
# ============================================================================

func _ready() -> void:
	_fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	if dialogue.is_empty():
		_load_data()
	_begin()
	if _is_resuming_walk():
		_restore_after_walk()


## 把节点铺满父级。
## 为什么不用 set_anchors_preset()？——它【只改 anchor】，offset 原样保留；而且它在
## 节点还没有父级、没进树的时候调用，父级尺寸按 0 算，于是节点实际变成 0×0。
## 必须用 set_anchors_and_offsets_preset()（anchor 与 offset 一起算），并且在
## add_child() 之后调用。这个坑让全屏推进区、立绘层、对话框全部塌成 0 尺寸。
func _fill(c: Control, preset: int = Control.PRESET_FULL_RECT) -> void:
	if c == null:
		return
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 0.0)


## 宿主在 add_child 之前调用：把章节 id、脚本数据路径、要播的序列一次性交给运行时。
func configure(p_chapter_id: String, p_dialogue_path: String, p_sequences: Array) -> void:
	chapter_id = p_chapter_id
	if p_dialogue_path != "":
		dialogue_path = p_dialogue_path
	sequence_order = p_sequences.duplicate()
	_load_data()


func _build_ui() -> void:
	# 0. 背景层
	_bg_rect = ColorRect.new()
	_bg_rect.name = "Background"
	_bg_rect.color = Color(0.07, 0.075, 0.09, 1.0)
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)
	_fill(_bg_rect)

	_bg_grad = GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.10, 0.105, 0.13))
	grad.set_color(1, Color(0.035, 0.037, 0.05))
	_bg_grad.gradient = grad
	_bg_grad.fill_from = Vector2(0, 0)
	_bg_grad.fill_to = Vector2(0, 1)
	_bg_art = TextureRect.new()
	_bg_art.name = "BackgroundGradient"
	_bg_art.texture = _bg_grad
	_bg_art.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_art)
	_fill(_bg_art)

	# 0.5 手绘场景底：纯代码绘制，和灰白立绘同一种笔
	if ResourceLoader.exists(BACKDROP_SCRIPT):
		var bd := Control.new()
		bd.name = "Backdrop"
		bd.set_script(load(BACKDROP_SCRIPT))
		if bd.get_script() != null:
			add_child(bd)
			_fill(bd)
			_backdrop = bd

	# 1. 立绘层
	_portrait_layer = Control.new()
	_portrait_layer.name = "Portraits"
	_portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_layer)
	_fill(_portrait_layer)

	# 2. 热区层
	_hotspot_layer = Control.new()
	_hotspot_layer.name = "Hotspots"
	_hotspot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotspot_layer)
	_fill(_hotspot_layer)

	# 3. 全屏推进区（放在最底层：立绘与热区优先吃点击）
	_advance_btn = Button.new()
	_advance_btn.name = "AdvanceArea"
	_advance_btn.flat = true
	_advance_btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	_advance_btn.add_theme_stylebox_override("normal", empty)
	_advance_btn.add_theme_stylebox_override("hover", empty)
	_advance_btn.add_theme_stylebox_override("pressed", empty)
	_advance_btn.add_theme_stylebox_override("focus", empty)
	_advance_btn.pressed.connect(_on_advance)
	add_child(_advance_btn)
	_fill(_advance_btn)
	move_child(_advance_btn, 0)

	# 4. 对话框（DialogueBox 内部自己管底部锚点，这里只需它在树上）
	# 【坑 41】说话人立绘会把 z_index 提到 1（要盖住同侧的其他人），
	# 而对话框默认也是 0 -> 曾被立绘盖住台词。所以这里给 UI 各层一个明确的层级：
	#   立绘层 0（说话人 1） < 对话框 5 < 记录卡 6 < 标题卡/幕间 9
	_portrait_layer.z_index = 0
	_dbox = PreludeUI.DialogueBox.new()
	_dbox.z_index = 5
	add_child(_dbox)

	# 5. 记录卡
	_card = PreludeUI.RecordCard.new()
	_card.z_index = 6
	_card.closed.connect(_on_card_closed)
	add_child(_card)

	# 6. 选项菜单
	_choice = PreludeUI.ChoiceMenu.new()
	_choice.chosen.connect(_on_choice)
	add_child(_choice)

	# 7. 笔记
	_note_btn = Button.new()
	_note_btn.name = "NoteButton"
	_note_btn.text = "笔记  (Tab)"
	PreludeUI.apply_button_skin(_note_btn)
	_note_btn.pressed.connect(_toggle_notes)
	add_child(_note_btn)
	_fill(_note_btn, Control.PRESET_TOP_LEFT)
	# offset 必须在 _fill() 之后再设，否则会被预设按 minsize 覆盖
	_note_btn.offset_left = 30.0
	_note_btn.offset_top = 26.0
	_note_btn.offset_right = 178.0
	_note_btn.offset_bottom = 64.0

	_notes = PreludeUI.NotesPanel.new()
	# 【坑 41 补】笔记面板原来没有设定层级（默认 0），而对话框是 5 ——
	# 也就是说打开笔记时，对话框会盖在笔记上。这里跟回看一样抬到 6。
	_notes.z_index = 6
	add_child(_notes)

	# 7.5 回看（玩家按 R / 滚轮向上）：把已经显示过的台词原样列出来
	_history_btn = Button.new()
	_history_btn.name = "HistoryButton"
	_history_btn.text = "回看  (R)"
	PreludeUI.apply_button_skin(_history_btn)
	_history_btn.pressed.connect(_toggle_history)
	add_child(_history_btn)
	_fill(_history_btn, Control.PRESET_TOP_LEFT)
	_history_btn.offset_left = 190.0
	_history_btn.offset_top = 26.0
	_history_btn.offset_right = 318.0
	_history_btn.offset_bottom = 64.0

	_history = PreludeUI.HistoryPanel.new()
	# 回看要在对话框（5）与笔记（默认 0 但因为在其后添加而在上层）之上、
	# 小游戏面板（7）之下：给它 6 就好（坑 41 那套层级）。
	_history.z_index = 6
	add_child(_history)

	# 8. toast
	_toast = Label.new()
	_toast.name = "Toast"
	_toast.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_toast.add_theme_color_override("font_color", Color(0.90, 0.76, 0.50))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)
	_fill(_toast, Control.PRESET_CENTER_TOP)
	# 与笔记按钮同理：宽高必须写在 _fill() 之后，
	# 否则会被预设按 minsize 覆盖成 1×20 的一条细缝。
	_toast.offset_left = -240.0
	_toast.offset_right = 240.0
	_toast.offset_top = 30.0
	_toast.offset_bottom = 60.0

	# 9. 黑幕
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fill(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 1.1)


func _load_data() -> void:
	if sequence_order.is_empty():
		# configure() 没被调用时的兜底：用本脚本自带的默认序列，避免黑屏
		push_warning("[Prelude] configure() 未被调用，使用默认序列顺序")
		sequence_order = []
	var path := dialogue_path
	if not FileAccess.file_exists(path):
		push_error("[Prelude] 找不到脚本数据：%s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[Prelude] 无法打开脚本数据：%s" % path)
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not (parsed is Dictionary):
		push_error("[Prelude] 脚本数据 JSON 解析失败：%s" % path)
		return
	dialogue = parsed as Dictionary

	# JSON 里是按幕分组的：{ "week1": { "s0_maze": [...] }, "week2": {...} }
	# 运行时只关心"序列 id → 行数组"，所以把当前幕展平到顶层。
	# 这样 data/week1_dialogue.json / week2_dialogue.json 依然好读好改，运行时也不用记幕名。
	if dialogue.has(chapter_id) and dialogue[chapter_id] is Dictionary:
		var act: Dictionary = dialogue[chapter_id]
		for k in act.keys():
			dialogue[k] = act[k]
	elif not dialogue.has(chapter_id):
		push_error("[Prelude] 脚本数据里没有这一幕：%s" % chapter_id)


# ---------------------------------------------------------------- 兼容保留
## 子类依然可以覆盖这两个方法；但正式流程走 configure()，见上面的说明。
func data_path() -> String:
	return dialogue_path


func chapter_sequences() -> Array:
	return sequence_order


# ============================================================================
#  序列驱动
# ============================================================================

func _begin() -> void:
	_seq_index = -1
	# 「继续上次」：标题界面按过之后，存档系统会把"要跳到第几段"挂在这里等着领。
	# 恢复点是【段首】（见 save_game.gd 的说明）：段内的 ["space"]/["show"] 之类
	# 是在搭画面，跳过它们会看到错背景，所以只跳整段、不跳行。
	var resume := _take_resume()
	if not resume.is_empty() and not _is_resuming_walk():
		var target := maxi(0, int(resume.get("seq_index", 0)))
		# 静默快进到 target 的前一段 —— 最后那把 _next_sequence 会 +1，
		# 正好把 target 这一段从头演出来（每段开头都有自己的 ["space"]）。
		while _seq_index + 1 < target and _seq_index + 2 < sequence_order.size():
			_next_sequence(false)
		var seg := maxi(1, _seq_index + 2)
		_toast_msg("继续上次：从第 %d 段接着来。" % seg)
		print("[Prelude] 继续上次：跳到第 %d 段（存档时间 %s）" % [target, str(resume.get("saved_at", ""))])
	_next_sequence(not _is_resuming_walk())


func _next_sequence(auto_run := true) -> void:
	_seq_index += 1
	if _seq_index >= sequence_order.size():
		_active = false
		sequence_finished.emit(chapter_id)
		_on_chapter_end()
		return
	var seq_id := str(sequence_order[_seq_index])
	var seq: Variant = dialogue.get(seq_id, null)
	if not (seq is Array):
		push_warning("[Prelude] 序列不存在或格式错误：%s" % seq_id)
		_next_sequence(auto_run)
		return
	_rows = (seq as Array).duplicate(true)
	_row_is_top = []
	for _i in _rows.size():
		_row_is_top.append(true)
	_row_index = 0
	_active = true
	_autosave()
	if auto_run:
		_run_next()


# ============================================================================
#  自动存档（关掉重开还能接着玩）
# ============================================================================

## 拿 SaveGame 单例。探针 / --script 环境里没有 current_scene、也可能没有
## 单例，所以这里统统走"拿不到就什么都不做"，绝不把玩家真存档写坏。
func _save_game() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("SaveGame")


func _take_resume() -> Dictionary:
	var sg := _save_game()
	if sg == null:
		return {}
	return sg.call("take_resume", chapter_id) as Dictionary


func _autosave() -> void:
	if not _active:
		return
	var scene_path := _current_scene_path()
	if scene_path == "":
		return          # 探针：没有可恢复的位置，不写盘
	var sg := _save_game()
	if sg == null:
		return
	sg.call("write", chapter_id, scene_path, _seq_index)


## 暂停菜单（autoload PauseMenu）问的："现在有覆盖层开着吗？"
## 有的话，Esc 归我（用来关那一层），不要弹暂停菜单。
func blocks_pause() -> bool:
	if _notes == null or _dbox == null or _choice == null or _card == null:
		return true     # UI 还没搭好，先别暂停
	if _notes.is_open() or _choice.is_open() or _card.is_showing():
		return true
	if _history != null and _history.is_open():
		return true
	if _panel != null and is_instance_valid(_panel):
		return true
	if mindread_input_open():
		return true
	if _free_mode:
		return true
	if _title_layer != null and is_instance_valid(_title_layer) and _title_layer.visible:
		return true
	if _formula_layer != null and is_instance_valid(_formula_layer) and _formula_layer.visible:
		return true
	return false


## 暂停菜单里"保存进度"用的公开入口（内部就是那套自动存档）
func save_now() -> void:
	_autosave()


## 本场景是不是"从俯视角走位切回来"的
func _is_resuming_walk() -> bool:
	return bool(PreludeState.get_flag("walk_resume_active", false))


## 当前这一幕的场景文件路径（走位结束之后要切回这里）。
## 探针 / --script 环境下没有 current_scene，返回空串，调用方自己兜底。
func _current_scene_path() -> String:
	var tree := get_tree()
	if tree == null:
		return ""
	var sc := tree.current_scene
	if sc == null:
		return ""
	return sc.scene_file_path


func _run_next() -> void:
	if _row_index >= _rows.size():
		_next_sequence()
		return
	var row: Variant = _rows[_row_index]
	_row_index += 1
	if not (row is Array) or (row as Array).is_empty():
		_run_next()
		return
	var r := row as Array
	var kind := str(r[0])
	match kind:
		"n":
			# 旁白：画面上不出现「旁白」两个字（Kerry 要求），只在回看流水里留空说话人
			# 旁白时在场人物全部调暗（只有人物说话时才亮；下一条 ["d"] 会重新点亮说话人）
			_dim_all_speakers()
			_push_line("", str(r[1]), true)
		"d":
			# r[3]=true 时说话但不生成立绘 / 不点亮任何立绘（如黑屏上的「再见啦，李小星。」）
			if r.size() <= 3 or not bool(r[3]):
				_show_speaker(str(r[1]))
			_push_line(str(r[1]), str(r[2]))
		"m":
			# 心理独白：同样不画标签，改由立绘高亮告诉玩家"是李星在想"
			_highlight_existing_speaker(MONOLOGUE_SPEAKER)
			_push_line(MONOLOGUE_SPEAKER, str(r[1]), true)
		"title":
			_title_card(str(r[1]), str(r[2]) if r.size() > 2 else "")
		"space":
			_set_space(str(r[1]), r[2] if r.size() > 2 else [])
			_run_next()
		"shot":
			# 结尾演出用的"分镜帧"：只切背景、藏对话框、停住等玩家点一下再进下一帧。
			_shot_frame(str(r[1]))
		"who":
			_show_speaker(str(r[1]))
			_run_next()
		"show":
			_spawn_portrait(str(r[1]))
			_run_next()
		"hide":
			_remove_portrait(str(r[1]))
			_run_next()
		"item":
			_add_hotspot(str(r[1]), str(r[2]), r[3])
			_run_next()
		"peek":
			# 条件小段：当玩家在自由调查里第一次查看名为 r[1] 的物品后，追加播放 r[2] 的行
			_peeks[str(r[1])] = (r[2] as Array).duplicate(true) if r[2] is Array else []
			_run_next()
		"room":
			# 声明"这一段可看的东西摆在哪间可走场景里"。
			# 真正切到走位是后面的 ["free"]；这里只记住房间名，
			# 这样对话脚本里不用重复维护物件清单（清单在 data/prelude_rooms.json）。
			PreludeState.set_flag("walk_room", str(r[1]))
			_run_next()
		"free":
			_start_free()
		"goal":
			# 走位房间的"目标物件"：只要求玩家走到这件东西跟前（其余可看可不看）。
			PreludeState.set_flag("walk_goal", str(r[1]))
			_run_next()
		"panel":
			# 一周目小游戏面板（迷宫 / 手势密码 / 备忘录 / 书架 / 书桌 / 海龟汤 / 衣柜）
			_open_panel(str(r[1]))
		"card":
			_show_card(str(r[1]))
		"formula1089":
			_show_formula_1089()
		"mindread_input":
			# 1089 读心术的数字输入：不走整屏面板，弹"对话框式"输入条（见下）
			_open_mindread_input()
		"mindread_reveal":
			# 输完数字回到对话框后，刘忆按玩家报的那一位揭晓过去/现在/未来
			_show_mindread_reveal()
		"choice":
			# 第 4 参（可选）= 正确选项：int（单选）或 Array[int]（多选）
			_open_choice(str(r[1]), r[2], r[3], r[4] if r.size() > 4 else null)
		"flash":
			# 闪白转场：白屏淡入淡出一下，自动继续下一行（不占点击）
			_flash_screen()
			_run_next()
		_:
			push_warning("[Prelude] 未知行类型：%s" % kind)
			_run_next()


# ============================================================================
#  文本行 / 输入
# ============================================================================

func _push_line(speaker: String, text: String, hide_name: bool = false) -> void:
	if _dbox == null:
		return
	# 回看用的流水账：每一条真正上过对话框的台词都记一笔（含走位里点的物件）
	PreludeState.push_history(speaker, text)
	_line_ready = false
	_dbox.visible = true
	_dbox.set_hint_visible(not _free_mode)
	# 对话框上方显示真名（同学A→陈一 等）；立绘键仍是原键
	_dbox.show_line(DISPLAY_NAME.get(speaker, speaker), text, hide_name)


func _on_advance() -> void:
	# 极早期（UI 还没搭好）的防御：宁可不响应，也不要空引用
	if _dbox == null or _notes == null or _choice == null or _card == null:
		return
	if _notes.is_open() or _choice.is_open() or _free_mode:
		return
	# 回看面板开着：点击/空格只用来合上它，不推进剧情
	if _history != null and _history.is_open():
		return
	# 小游戏面板开着的时候，点击/空格不能推进对话（那是面板的地盘）
	if _panel != null and is_instance_valid(_panel):
		return
	# 1089 输入浮层开着的时候，点击/空格不能推进对话（数字得先输完）
	if mindread_input_open():
		return
	# 玩家从谜题退出去看笔记：按空格/点击先回到谜题，剧情不推进
	if _panel_pending != "":
		_reopen_pending_panel()
		return
	if _dismiss_formula_card():
		# 算式卡：点掉它，继续
		return
	if _dismiss_title_card():
		# 标题卡：点掉它，继续
		return
	if _card.is_showing():
		# 卡片显示中：点击任意处收起卡片，不推进对话
		_card.hide_card()
		return
	if not _line_ready:
		# 第一次点击：把整句显示完
		if _dbox.is_typing():
			_dbox.skip()
			_line_ready = true
		return
	# 1089 揭晓：同一页逐句展开（你的过去/未来/现在是/也就是……四行），
	# 点一下多出一行，四行都在同一个对话框页里；喂完再往下播。
	if not _reveal_pending.is_empty():
		_dbox.append_line(str(_reveal_pending.pop_front()))
		return
	# 玩家点掉"物品详情"之后，把对应的追加段落接上
	_consume_peeks()
	_run_next()


## 安全地"吃掉"这次输入。
## 【坑】切场景的过程中本节点可能已经离树，get_viewport() 会返回 null，
## 直接调 set_input_as_handled() 会报
## `SCRIPT ERROR: Cannot call method 'set_input_as_handled' on a null value.`
## 这条错误会打断正在进行的场景切换（表现为按"看完了"之后卡住）。
func _eat(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _notes == null or _dbox == null:
		return

	# 回看面板开着：滚轮 / ↑↓ 翻，R / Esc / 空格 / 点一下 合上
	if _history != null and _history.is_open():
		if event.is_action_pressed("prelude_history") \
				or event.is_action_pressed("ui_cancel") \
				or event.is_action_pressed("prelude_advance"):
			_history.close()
			_eat(event)
			return
		if event.is_action_pressed("ui_up"):
			_history.scroll_by(-48.0)
			_eat(event)
			return
		if event.is_action_pressed("ui_down"):
			_history.scroll_by(48.0)
			_eat(event)
			return
		if event is InputEventMouseButton:
			var mw := event as InputEventMouseButton
			if mw.pressed and mw.button_index == MOUSE_BUTTON_WHEEL_UP:
				_history.scroll_by(-72.0)
				_eat(event)
			elif mw.pressed and mw.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_history.scroll_by(72.0)
				_eat(event)
			return

	# 1089 输入浮层开着：键盘 / 滚轮都留给输入框（输入框自己有焦点，
	# 先吃键；这里兜底挡掉空格推进与回看 / 笔记的快捷键）
	if mindread_input_open():
		return

	# 滚轮向上 = 打开回看（只在没有别的面板开着的时候，免得和它们抢滚轮）
	if not _free_mode and _panel == null and not _notes.is_open() \
			and not _choice.is_open() and not _card.is_showing() \
			and event is InputEventMouseButton:
		var mup := event as InputEventMouseButton
		if mup.pressed and mup.button_index == MOUSE_BUTTON_WHEEL_UP and not _line_ready:
			pass          # 这句还没打完：滚轮先当"跳过打字机"，不打开回看
		elif mup.pressed and mup.button_index == MOUSE_BUTTON_WHEEL_UP:
			_open_history()
			_eat(event)
			return
		elif mup.pressed and mup.button_index == MOUSE_BUTTON_WHEEL_DOWN and _line_ready:
			# 往下滚 = 推进一句（和空格同义，手指不用离开鼠标）
			_on_advance()
			_eat(event)
			return

	if event.is_action_pressed("prelude_history"):
		_toggle_history()
		_eat(event)
		return

	if _notes.is_open():
		if event.is_action_pressed("prelude_notes") or event.is_action_pressed("ui_cancel"):
			_notes.close()
			_eat(event)
		return

	if event.is_action_pressed("prelude_notes"):
		_toggle_notes()
		_eat(event)
		return

	# 小游戏面板开着：键盘输入都归它（迷宫用方向键走、手势密码用回车确认之类）
	if _panel != null and is_instance_valid(_panel):
		if bool(_panel.call("is_open")) and bool(_panel.call("wants_input")):
			_panel.call("handle_input", event)
			_eat(event)
		return

	if event.is_action_pressed("prelude_advance"):
		# 鼠标左键交给 AdvanceArea 按钮处理，这里只接键盘
		if event is InputEventMouseButton:
			return
		_on_advance()
		_eat(event)


func _process(delta: float) -> void:
	if _dbox != null and not _line_ready and not _dbox.is_typing():
		_line_ready = true

	if _toast != null and _toast.modulate.a > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.modulate.a = maxf(0.0, _toast.modulate.a - delta * 1.6)

	_auto_advance(delta)


## 自动播放剧情（暂停菜单里的开关）。
## 只有在"这句已经打完、屏幕上没有别的覆盖层"时才走计时；
## 一进选项 / 小游戏面板 / 走位就清零 —— 免得玩家还在想就被翻页。
const AUTO_ADVANCE_DELAY := 2.6

var _auto_timer := 0.0

func _auto_advance(delta: float) -> void:
	var gs := _game_settings()
	if gs == null or not bool(gs.get("autoplay")):
		_auto_timer = 0.0
		return
	if not _line_ready or blocks_pause() or _dbox == null or not _dbox.visible:
		_auto_timer = 0.0
		return
	_auto_timer += delta
	if _auto_timer < AUTO_ADVANCE_DELAY:
		return
	_auto_timer = 0.0
	_on_advance()


func _game_settings() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameSettings")


func _toast_msg(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.modulate.a = 1.0
	_toast_time = 2.0


# ============================================================================
#  记录卡 / 笔记
# ============================================================================

func _show_card(text: String) -> void:
	var idx := PreludeState.add_card(text)
	# 记录卡也进回看流水（它不是台词，但玩家确实在屏幕上读到过）
	PreludeState.push_history("【笔记】", text)
	_autosave()
	if _card == null:
		_run_next()
		return
	_card.show_card(idx, text)
	_toast_msg("笔记已更新")


func _on_card_closed() -> void:
	pass


func _toggle_notes() -> void:
	if _notes.is_open():
		_notes.close()
	else:
		if _history != null and _history.is_open():
			_history.close()
		_notes.open(PreludeState.cards)


# ============================================================================
#  回看（把已经说过的台词再翻一遍）
# ============================================================================

func _open_history() -> void:
	if _history == null:
		return
	if _notes.is_open():
		_notes.close()
	if _history.is_open():
		# 已经开着：再按一次/再往上滚一下 = 刷新（玩家可能刚推进了几句）
		_history.refresh(PreludeState.history)
		return
	_history.open(PreludeState.history)


func _toggle_history() -> void:
	if _history == null:
		return
	if _history.is_open():
		_history.close()
	else:
		_open_history()


# ============================================================================
#  选项
# ============================================================================

func _open_choice(prompt: String, options: Array, branches: Array, correct: Variant = null) -> void:
	_dbox.set_hint_visible(false)
	_pending_branches = branches
	_choice.open(prompt, options, correct)


func _on_choice(index: int) -> void:
	var branch: Variant = null
	if index >= 0 and index < _pending_branches.size():
		branch = _pending_branches[index]
	if branch is Array and not (branch as Array).is_empty():
		var insert_at := _row_index
		var b := (branch as Array).duplicate(true)
		for i in b.size():
			_rows.insert(insert_at + i, b[i])
			_row_is_top.insert(insert_at + i, false)
	_run_next()


# ============================================================================
#  自由调查
# ============================================================================

func _start_free() -> void:
	# 这一段如果声明了可走房间，就切到俯视角走位场景去"自己走走看看"。
	# 走完（room_runtime 的"看完了"）会切回本场景，_restore_after_walk() 再把进度接上。
	var room_id := str(PreludeState.get_flag("walk_room", ""))
	# 每一处 ["free"] 都要有自己的"跑过了"标记：一周目里同一个房间（寝室）
	# 会被用三次（书架 / 书桌 / 衣柜），只按房间名记会导致后两次进不去。
	var done_key := "walk_done_%s_%d_%d" % [room_id, _seq_index, _row_index]
	# 临时取消 done_key 检查，确保第二次走位能正常进入
	# if room_id != "" and not bool(PreludeState.get_flag(done_key, false)):
	if room_id != "":
		PreludeState.set_flag(done_key, true)
		PreludeState.set_flag("walk_chapter", chapter_id)
		PreludeState.set_flag("walk_resume_seq", _seq_index)
		# 恢复点必须存【顶层行】坐标：_rows 里可能内联了 choice 分支 / peek 追加的行，
		# 运行时下标比顶层下标大；恢复时 _rows 只含顶层行，存运行时下标会越界，
		# 把这一段的剩余部分整段跳过（书架走位曾因此直接跳到第三天）。
		# 此刻 ["free"] 这一行已被 _run_next() 消费掉，_row_index 指向它的下一行。
		var free_top := -1
		var resume_top := 0
		for i in range(_row_index):
			if i < _row_is_top.size() and _row_is_top[i]:
				if i == _row_index - 1:
					free_top = resume_top
				resume_top += 1
		# free 是顶层行时 free_top 有效（= 那行 ["free"] 的顶层下标），恢复时用它作废旧 free；
		# 内联出来的 free 没有顶层行可作废，peek 保持 -1。
		PreludeState.set_flag("walk_resume_peek", free_top)
		PreludeState.set_flag("walk_resume_row", resume_top)
		# 这次走位里"看过了哪些物件"由走位场景一笔笔记（重看也算），回来时补播对应追加台词
		PreludeState.set_flag("walk_during_examined", [])
		PreludeState.set_flag("walk_resume_ok", true)
		PreludeState.set_flag("walk_resume_peeks", _peeks.duplicate(true))
		PreludeState.set_flag("walk_resume_active", true)
		# 走位这一趟也存档：玩家在房间里关掉游戏，重开还能接着（回到本幕的这一段）
		_autosave()
		# 走完之后回哪一幕？以前是"act2 就回前日谈第二幕，否则回第一幕"，
		# 周目也有走位，所以改成记下"发起走位的那一幕场景"。
		# 优先问宿主（子类都知道自己的场景路径）；宿主没给才退回 current_scene。
		var ret := _current_scene_path()
		var host := get_parent()
		if host != null and host.has_method("return_scene"):
			var hs := str(host.call("return_scene"))
			if hs != "":
				ret = hs
		PreludeState.set_flag("walk_return_scene", ret)
		# 目标模式：这一趟只要求玩家走到某件东西跟前（["goal", 名称] 声明过才有）
		var goal := str(PreludeState.get_flag("walk_goal", ""))
		PreludeState.set_flag("walk_goal_active", goal)
		PreludeState.set_flag("walk_goal", "")
		print("[Prelude] 进入走位房间：%s（第 %d 段 第 %d 行）" % [room_id, _seq_index, _row_index])
		var err := get_tree().change_scene_to_file(WALK_SCENE)
		if err != OK:
			push_error("[Prelude] 切换走位场景失败：%s（错误码 %d）" % [WALK_SCENE, err])
		return
	_free_mode = true
	_peeks_pending.clear()
	_dbox.set_hint_visible(false)
	_dbox.show_line("", "（还有些东西可以看。看完之后点右下角的「查看完毕」。）")
	_free_remaining = _hotspots.size()
	_line_ready = true
	_make_free_button()


## 走位场景看完之后回到对话：跳过那个已经走完的 ["free"] 行，继续往下播
func _restore_after_walk() -> void:
	if not bool(PreludeState.get_flag("walk_resume_active", false)):
		return
	var ok := bool(PreludeState.get_flag("walk_resume_ok", false))
	PreludeState.set_flag("walk_resume_active", false)
	PreludeState.set_flag("walk_resume_ok", false)
	if not ok:
		# 这段走位不是在当前序列里发起的（例如玩家中途重开），不恢复，从当前行继续
		return
	var seq_i := int(PreludeState.get_flag("walk_resume_seq", -1))
	var row_i := int(PreludeState.get_flag("walk_resume_row", 0))
	var peek_at := int(PreludeState.get_flag("walk_resume_peek", -1))
	# 走位必须是"本章"发起的：下面的静默快进会动序列指针，
	# 万一残留了别的章节的恢复点（walk 是在别的章节发起的、回来却在本章），
	# 直接放弃恢复，别把本章的指针推歪。
	if str(PreludeState.get_flag("walk_chapter", "")) != chapter_id:
		return
	# 【坑·已修】走位不一定发生在第一段：图书馆那次是 s3_montage（第 3 段）。
	# _begin() 发现"正在恢复"时只会把指针停在序列 0、且不自动播行，
	# 所以这里必须【静默】快进到走位时那一段（_next_sequence(false) 不播任何行）。
	# 以前少了这一步：seq_i(3) != _seq_index(0) 直接 return，
	# 玩家回到对话看到一个空对话框，再按一下空格就从"前日谈"标题卡重播
	# —— 也就是"走完一次房间，整个章节回到最开头"。
	while _seq_index < seq_i and _seq_index + 1 < sequence_order.size():
		_next_sequence(false)
	if seq_i != _seq_index:
		return
	_row_index = row_i
	# 追加台词的数据也要还原：["peek"] 注册行在恢复点之前、已经被跳过了，
	# 不还原 _peeks 就是空的，走位里新看过的物件会"没有下文"。
	var saved_peeks: Variant = PreludeState.get_flag("walk_resume_peeks", null)
	if saved_peeks is Dictionary:
		_peeks = (saved_peeks as Dictionary).duplicate(true)
	# 兜底：把已经消费掉的那行 ["free"] 作废。正常情况它已经在恢复点身后、
	# 永远走不到；万一有别的路径绕回去，也不该再进一次走位 / 自由调查。
	if peek_at >= 0 and peek_at < _rows.size():
		var stale: Variant = _rows[peek_at]
		if stale is Array and not (stale as Array).is_empty() \
				and str((stale as Array)[0]) == "free":
			_rows[peek_at] = []
	# 走位里新看过的物件 → 追加台词必须插在【恢复点】上（_queue_peek 插的
	# 就是当前 _row_index）。旧写法插在 peek_at（= 那行 ["free"] 的下标）：
	# 插入后 _row_index 正好落进刚插进来的一段里，第一条追加台词被吞掉，
	# 而被挤到恢复点之后的那个旧 ["free"] 又会在推进到它时再进一次自由调查。
	# 倒序插入 + 每次都插在同一下标 = 播放顺序仍是"看过的先后顺序"。
	var names := _examined_during_walk()
	names.reverse()
	for nm in names:
		_queue_peek(str(nm))
	_run_next()
	_skip_consumed_rows()


## 本次走位期间被查看过的物件名（走位场景每查一件记一笔；重看也算——
## 第一天看过室友的书桌，第三关再查同一件时那一段的追加台词仍要补播）
func _examined_during_walk() -> Array:
	var during: Variant = PreludeState.get_flag("walk_during_examined", [])
	return (during as Array).duplicate() if during is Array else []


## 跳过已经执行过的 ["free"] / ["room"] / ["peek"] 行。
## 兜底用：万一恢复点落在了这类"已经跑过"的行上，绝不能重进走位或重弹「查看完毕」。
func _skip_consumed_rows() -> void:
	var guard := 0
	# 临时取消跳过逻辑，确保第二次走位能正常进入
	# while _row_index < _rows.size() and guard < 8:
	# 	var r: Variant = _rows[_row_index]
	# 	if not (r is Array) or (r as Array).is_empty():
	# 		return
	# 	var k := str((r as Array)[0])
	# 	if k == "free" or k == "room" or k == "goal" or k == "panel":
	# 		_row_index += 1
	# 		guard += 1
	# 		continue
	# 	return
	pass


## 把某个物件的追加行插到指定行号处（见 _restore_after_walk 的说明）
func _queue_peek_from(item_name: String, at: int) -> void:
	if not _peeks.has(item_name):
		return
	var rows: Variant = _peeks[item_name]
	_peeks.erase(item_name)
	if not (rows is Array) or (rows as Array).is_empty():
		return
	var b := rows as Array
	var insert_at := clampi(at, 0, _rows.size())
	for i in b.size():
		_rows.insert(insert_at + i, b[i])
		_row_is_top.insert(insert_at + i, false)


func _make_free_button() -> void:
	if _free_btn == null:
		_free_btn = Button.new()
		_free_btn.name = "FreeDone"
		PreludeUI.apply_button_skin(_free_btn, true)
		_free_btn.pressed.connect(_on_free_done)
		add_child(_free_btn)
		_fill(_free_btn, Control.PRESET_BOTTOM_RIGHT)
		# offset 必须在 _fill() 之后再设
		_free_btn.offset_left = -240.0
		_free_btn.offset_right = -34.0
		_free_btn.offset_top = -96.0
		_free_btn.offset_bottom = -52.0
	_update_free_button()


func _update_free_button() -> void:
	if _free_btn == null:
		return
	if _free_remaining > 0:
		_free_btn.text = "查看完毕（还有 %d 件没看）" % _free_remaining
	else:
		_free_btn.text = "查看完毕"


func _on_free_done() -> void:
	_free_mode = false
	if _free_btn != null:
		_free_btn.queue_free()
		_free_btn = null
	_consume_peeks()
	_run_next()


# ============================================================================
#  一周目：小游戏面板
# ============================================================================

## ["panel", id]：弹出一关小游戏（见 scripts/week1/week1_panels.gd 与 week2_panels.gd 的登记表）。
## 面板自己铺满、自己搭 UI，玩家过关时它 close_panel(result) → 我们记下结果继续播台词。
func _open_panel(id: String) -> void:
	var script_path := WEEK1_PANELS.script_for(id)
	if script_path == "":
		script_path = WEEK2_PANELS.script_for(id)
	if id == "" or script_path == "":
		push_warning("[Prelude] 未知面板：%s" % id)
		_run_next()
		return
	# 这一关本次游玩里已经过掉了（比如玩家读档/重进这一幕）：不再弹一次
	if PreludeState.get_flag("week1_result_" + id, null) != null:
		_run_next()
		return
	_dbox.set_hint_visible(false)
	var p := Control.new()
	p.name = "Week1Panel_" + id
	p.set_script(load(script_path))
	if p.get_script() == null:
		push_error("[Prelude] 面板脚本加载失败：%s" % script_path)
		_run_next()
		return
	# 关键：configure 风格——必须在 add_child 之前把参数交给面板，
	# 因为 add_child 会立刻触发它的 _ready()，那时它已经开始搭界面了。
	p.call("setup", {"id": id})
	# 面板要在立绘（说话人 z_index 1）与对话框（5）之上、标题卡（9）之下（坑 41）
	p.z_index = 7
	add_child(p)
	p.connect("finished", _on_panel_finished)
	_panel = p
	print("[Prelude] 打开面板：%s" % id)


func _on_panel_finished(result: Dictionary) -> void:
	var id := str(result.get("id", ""))
	if bool(result.get("cancelled", false)):
		# 玩家从谜题里退出来看笔记：不记过关结果、不推进剧情，
		# 等玩家看完笔记按空格/点击，再回到同一个谜题。
		_panel_pending = id
		var p := _panel
		_panel = null
		if p != null and is_instance_valid(p):
			p.queue_free()
		if _dbox != null:
			_dbox.visible = true
			_dbox.set_hint_visible(true)
		_line_ready = true
		_toast_msg("谜题已收起 · 按 空格 / 点击 回到谜题")
		print("[Prelude] 面板退出（去看笔记）：%s" % id)
		return
	if id != "":
		PreludeState.set_flag("week1_result_" + id, result)
		print("[Prelude] 面板完成：%s → %s" % [id, str(result)])
		_autosave()
	var p2 := _panel
	_panel = null
	if p2 != null and is_instance_valid(p2):
		p2.queue_free()
	# 面板期间对话框是隐着的，收掉之后要还回去
	if _dbox != null:
		_dbox.visible = true
		_dbox.set_hint_visible(true)
	_line_ready = true
	_run_next()


## 玩家从谜题收起状态按空格/点击：把原来的谜题重新打开（剧情先不推进）
func _reopen_pending_panel() -> void:
	var id := _panel_pending
	_panel_pending = ""
	if id == "":
		return
	# 极端情况：读档等让这一关已经有了结果，就不再弹，直接推进
	if PreludeState.get_flag("week1_result_" + id, null) != null:
		_run_next()
		return
	_open_panel(id)


## 把"首次查看某物品后的追加行"插到当前位置，优先于后续脚本行执行
func _queue_peek(item_name: String) -> void:
	if not _peeks.has(item_name):
		return
	var rows: Variant = _peeks[item_name]
	_peeks.erase(item_name)
	if not (rows is Array) or (rows as Array).is_empty():
		return
	var b := rows as Array
	var insert_at := _row_index
	for i in b.size():
		_rows.insert(insert_at + i, b[i])
		_row_is_top.insert(insert_at + i, false)


# ============================================================================
#  场景 / 立绘 / 热区
# ============================================================================

func _clear_layer(layer: Control) -> void:
	if layer == null:
		return
	for c in layer.get_children():
		layer.remove_child(c)
		c.queue_free()


func _set_space(key: String, cast_list: Array) -> void:
	_current_bg = key
	var tint: Array = SPACE_TINT.get(key, [Color(0.10, 0.105, 0.13), Color(0.035, 0.037, 0.05)])
	var g := _bg_grad.gradient
	if g != null:
		g.set_color(0, tint[0])
		g.set_color(1, tint[1])
	# 手绘场景底换场景
	if _backdrop != null and _backdrop.has_method("set_scene"):
		_backdrop.call("set_scene", key)
	_clear_layer(_portrait_layer)
	_clear_layer(_hotspot_layer)
	_portraits.clear()
	_hotspots.clear()
	# 把"这一场一共几个人"传下去：同框人数多的时候立绘整体降一档，
	# 免得五个人挤在 1280 宽里、脑袋叠脑袋（见 Portrait.setup 的 push 说明）。
	for who in cast_list:
		_spawn_portrait(str(who), cast_list.size())


## 结尾演出用的"分镜帧"（["shot", 背景键]）：只切背景、藏对话框、
## 停住等玩家点一下再进下一帧。用于一周目结尾"星星漫过胸口→全黑"那段——
## 点一下换一张图、再点一下换下一张，最后黑屏出"再见啦，李小星。"。
func _shot_frame(key: String) -> void:
	_set_space(key, [])
	if _dbox != null:
		_dbox.visible = false
	_line_ready = true


## 闪白转场（["flash"]）：整屏白一下（淡入淡出），自动继续，不占点击。
func _flash_screen() -> void:
	if _flash_rect == null:
		_flash_rect = ColorRect.new()
		_flash_rect.name = "FlashRect"
		_flash_rect.color = Color(1, 1, 1, 0)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_flash_rect)
		_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.92, 0.14)
	tw.tween_interval(0.55)   # 白色全亮保持一会儿，再淡出
	tw.tween_property(_flash_rect, "color:a", 0.0, 0.34)


func _make_portrait(who: String, total: int = 0) -> PreludeUI.Portrait:
	var p := PreludeUI.Portrait.new()
	var path := str(ART.get(who, ""))
	var side := int(SIDE.get(who, 1))
	# 同一侧会站好几个人（教室里 C/D/E 站右边、D 与班主任站左边），
	# 全都用同一组 offset 的话会**完全重叠**，只看得见最后一个。
	# 所以按"这一侧已经站了几个"给一个错位槽位：往后站、稍微小一点。
	var slot := 0
	for k in _portraits.keys():
		if int(SIDE.get(str(k), 1)) == side:
			slot += 1
	# 【坑 53】同框人数决定基准高度：人多就整体小一号，配合 Portrait.setup 里的
	# 150px 横向错位，脸才不会互相盖住（旧版固定 660 高、只错 96px，两人就叠满了）。
	if total <= 0:
		total = _portraits.size() + 1
	var base := 660.0
	if total >= 5:
		base = 560.0
	elif total >= 4:
		base = 600.0
	elif total >= 3:
		base = 630.0
	var height := maxf(base - float(slot) * 40.0, 460.0)
	p.setup(path, who, side, height, slot)
	return p


func _spawn_portrait(who: String, total: int = 0) -> void:
	if _portraits.has(who):
		return
	# ART 表里没有的角色不生成占位立绘：占位是一块"写着名字的透明水印"，
	# 一屋子人会把水印叠成一团；说话人名字在对话框上已经有了，这里只要高亮就行。
	# （同学C/D/E、班主任、宿管阿姨已经有立绘，所以不再走这条路。）
	if not ART.has(who):
		return
	var p := _make_portrait(who, total)
	_portrait_layer.add_child(p)
	_portraits[who] = p
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.35)


func _remove_portrait(who: String) -> void:
	if not _portraits.has(who):
		return
	var p: PreludeUI.Portrait = _portraits[who]
	_portraits.erase(who)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


## 当前说话人高亮，其他人变暗
func _show_speaker(who: String) -> void:
	# 还没自报姓名时的「？？？」实际是刘忆：立绘按刘忆亮，名字仍显示？？？
	if SPEAKER_ART.has(who):
		who = SPEAKER_ART[who]
	if not _portraits.has(who):
		_spawn_portrait(who)
	for k in _portraits.keys():
		var p: PreludeUI.Portrait = _portraits[k]
		var is_speaker := str(k) == who
		p.set_dim(not is_speaker)
		# 说话人提到最前面：同一侧站了不止一个人时（教室里 C/D/E/班主任/宿管 会挤在同一边），
		# 后出现的立绘会盖住先出现的，正说话的那位可能整个被挡住。
		# z_index 只影响同一层里的绘制顺序，不动布局。
		p.z_index = 1 if is_speaker else 0


## 只高亮"已经在场"的那个人，不临时生成立绘。
## 心理独白（["m"]）用它：这条独白是李星的内心，但她这一场未必站在台上，
## 不该因为一句心里话就把她的立绘凭空拉出来。
func _highlight_existing_speaker(who: String) -> void:
	if not _portraits.has(who):
		return
	_show_speaker(who)


## 旁白时把在场人物全部调暗：只有 ["d", 谁] 那一瞬间，谁才亮。
func _dim_all_speakers() -> void:
	for k in _portraits.keys():
		var p: PreludeUI.Portrait = _portraits[k]
		p.set_dim(true)
		p.z_index = 0


func _add_hotspot(item_name: String, detail: String, rect_data: Variant) -> void:
	var rect := Rect2(0, 0, 160, 46)
	if rect_data is Array and (rect_data as Array).size() >= 4:
		var a := rect_data as Array
		rect = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	var hs := PreludeUI.ItemHotspot.new()
	hs.setup(item_name, detail, rect, true)
	hs.inspected.connect(_on_item_inspected)
	_hotspot_layer.add_child(hs)
	_hotspots.append(hs)


func _on_item_inspected(item_name: String, detail: String) -> void:
	# 玩家查看物品 → 在对话框里以"物品名：详情"的格式显示
	_push_line(item_name, detail)
	var first_time := false
	for hs in _hotspots:
		var h := hs as PreludeUI.ItemHotspot
		if h.item_name == item_name and not h.examined_once:
			h.examined_once = true
			first_time = true
	if first_time:
		# 首次查看 → 也进笔记：以前物件详情只在对话框里一闪而过，
		# 玩家按 Tab 看不到自己读过什么（Kerry：「把笔记系统完整」）。
		PreludeState.note_examined(item_name)
		PreludeState.add_card("%s：%s" % [item_name, detail])
		_toast_msg("笔记已更新")
		# 首次查看 → 记下"追加一段对话"的请求（在玩家点掉这一句之后才播）
		_peeks_pending.append(item_name)
		if _free_mode:
			_free_remaining = maxi(0, _free_remaining - 1)
			_update_free_button()


func _consume_peeks() -> bool:
	if _peeks_pending.is_empty():
		return false
	var queue := _peeks_pending.duplicate()
	_peeks_pending.clear()
	for n in queue:
		_queue_peek(str(n))
	return true


# ============================================================================
#  标题卡
# ============================================================================

func _title_card(main_text: String, sub_text: String) -> void:
	_choice.close()
	_line_ready = false
	var layer := Control.new()
	layer.name = "TitleCard"
	layer.z_index = 9
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	_fill(layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	_fill(bg)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 14)
	layer.add_child(vb)
	_fill(vb)

	var t := Label.new()
	t.text = main_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(960, 0)
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)

	if sub_text.strip_edges() != "":
		var s := Label.new()
		s.text = sub_text
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_font_size_override("font_size", 18)
		s.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(s)

	var hint := Label.new()
	hint.text = "点击 / 空格  继续"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.45, 0.44, 0.42))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

	layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(layer, "modulate:a", 1.0, 0.4)

	_dbox.visible = false
	_title_layer = layer
	_line_ready = true


func _dismiss_title_card() -> bool:
	if _title_layer == null or not is_instance_valid(_title_layer):
		_title_layer = null
		return false
	var l := _title_layer
	_title_layer = null
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.28)
	tw.tween_callback(l.queue_free)
	# 不要在这里恢复对话框：标题卡期间没有产生新文本，恢复只会把黑屏/标题卡
	# 之前那一句旧文本再亮一遍（玩家会以为"黑屏后又重复了一遍"）。
	# 下一个真正的文本行（n/d/m/card 等）会自己把对话框重新打开。
	return true


# ============================================================================
#  算式卡（["formula1089"]）
# ============================================================================

## ["formula1089"]：1089 魔术的算式卡。算式用玩家在面板里报的那一位
## （past，存在 week1_result_mindread 里）拼出 p9f ＋ f9p ＝ 1089；
## 拿不到结果就退回 past=1（198 ＋ 891 ＝ 1089 依然成立）。
func _show_formula_1089() -> void:
	var past := 1
	var res: Variant = PreludeState.get_flag("week1_result_mindread", null)
	if res is Dictionary and (res as Dictionary).has("past"):
		past = int((res as Dictionary)["past"])
	var future := 9 - past
	var diff := past * 100 + 90 + future
	var rev := future * 100 + 90 + past
	_show_formula_card("%d ＋ %d ＝ 1089" % [diff, rev])


## 全屏居中算式卡：深色底 + 居中卡片，算式文字由浅变深逐渐浮现。
func _show_formula_card(expr: String) -> void:
	_choice.close()
	_line_ready = false
	var layer := Control.new()
	layer.name = "FormulaCardLayer"
	layer.z_index = 9
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	_fill(layer)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	_fill(bg)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 18)
	layer.add_child(vb)
	_fill(vb)

	var card := PanelContainer.new()
	card.name = "FormulaCard"
	card.add_theme_stylebox_override("panel",
			PreludeUI.panel_skin(PreludeUI.C_CARD_BG, Color(0.85, 0.80, 0.70, 0.22), 4))
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(card)

	_formula_text = Label.new()
	_formula_text.name = "FormulaText"
	_formula_text.text = expr
	_formula_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_formula_text.add_theme_font_size_override("font_size", PreludeUI.FS_NAME + 6)
	_formula_text.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_formula_text.custom_minimum_size = Vector2(300, 0)
	_formula_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_formula_text)

	var hint := Label.new()
	hint.text = "点击 / 空格  继续"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	hint.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hint)

	_formula_layer = layer
	# 字由浅变深逐渐浮现：先整体淡入，颜色从很浅的暖白渐变到暖金（C_NAME）
	_formula_text.modulate.a = 0.0
	var pale := Color(0.92, 0.90, 0.84)
	_formula_text.add_theme_color_override("font_color", pale)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_formula_text, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_formula_color, pale, PreludeUI.C_NAME, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_dbox.visible = false
	_line_ready = true


func _set_formula_color(c: Color) -> void:
	if _formula_text != null:
		_formula_text.add_theme_color_override("font_color", c)


func _dismiss_formula_card() -> bool:
	if _formula_layer == null or not is_instance_valid(_formula_layer):
		_formula_layer = null
		return false
	var l := _formula_layer
	_formula_layer = null
	_formula_text = null
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.28)
	tw.tween_callback(l.queue_free)
	_dbox.visible = true
	return true


# ============================================================================
#  1089 读心术：对话框式输入（["mindread_input"] / ["mindread_reveal"]）
# ============================================================================

## ["mindread_input"]：1089 回忆段里的数字输入。不走整屏游戏面板，
## 而是"对话框式"——场景和说话框都留着，只弹一条输入条（样式与
## panel_mindread 的原输入框一致：深底 + 暖金焦点 + 只收数字）。
## 玩家输入一位数（差值里最小的那位）后收起浮层，回到对话框，
## 由刘忆接着解读；后半段的算式卡（["formula1089"]）照旧。
func _open_mindread_input() -> void:
	if PreludeState.get_flag("week1_result_mindread", null) != null:
		# 这一关已经输入过（读档 / 重进这一段）：不再弹，直接往下播
		_run_next()
		return
	if mindread_input_open():
		return
	_choice.close()
	_dbox.set_hint_visible(false)
	_line_ready = true

	var layer := Control.new()
	layer.name = "MindreadInputLayer"
	layer.z_index = 7
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_fill(layer)

	var strip := PanelContainer.new()
	strip.name = "MindreadInputStrip"
	strip.add_theme_stylebox_override("panel",
			PreludeUI.panel_skin(PreludeUI.C_CARD_BG, PreludeUI.C_LINE, 6))
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE,
			Control.PRESET_MODE_MINSIZE, 0.0)
	# 坐在对话框（底部约 232px 高）上方，不遮住说话框
	strip.offset_left = 210.0
	strip.offset_right = -210.0
	strip.offset_top = -430.0
	strip.offset_bottom = -250.0
	layer.add_child(strip)

	var vb := VBoxContainer.new()
	vb.name = "MindreadInputBox"
	vb.add_theme_constant_override("separation", 10)
	strip.add_child(vb)

	var head := Label.new()
	head.name = "MindreadInputTitle"
	head.text = "读心术 · 1089"
	head.add_theme_font_size_override("font_size", PreludeUI.FS_NAME)
	head.add_theme_color_override("font_color", PreludeUI.C_NAME)
	vb.add_child(head)

	var row := HBoxContainer.new()
	row.name = "MindreadInputRow"
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)

	var lbl := Label.new()
	lbl.text = "差值里最小的那位数（0–9）："
	lbl.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
	lbl.add_theme_color_override("font_color", PreludeUI.C_INK)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var edit := LineEdit.new()
	edit.name = "MindreadDigitInput"
	edit.placeholder_text = "一位数"
	edit.max_length = 1
	edit.custom_minimum_size = Vector2(200, 44)
	edit.text_changed.connect(_on_mindread_digits_only.bind(edit))
	edit.text_submitted.connect(_on_mindread_digit)
	edit.add_theme_stylebox_override("normal",
			PreludeUI._button_skin_box(Color(0.10, 0.105, 0.125, 0.92), PreludeUI.C_LINE))
	edit.add_theme_stylebox_override("focus",
			PreludeUI._button_skin_box(Color(0.14, 0.145, 0.17, 0.96), Color(0.95, 0.86, 0.66, 0.5)))
	edit.add_theme_color_override("font_color", PreludeUI.C_INK)
	edit.add_theme_color_override("font_placeholder_color", PreludeUI.C_INK_DIM)
	edit.add_theme_color_override("caret_color", PreludeUI.C_NAME)
	row.add_child(edit)

	var btn := Button.new()
	btn.name = "MindreadDigitConfirm"
	btn.text = "告诉她"
	PreludeUI.apply_button_skin(btn)
	btn.pressed.connect(func() -> void: _on_mindread_digit(edit.text))
	row.add_child(btn)

	var fb := Label.new()
	fb.name = "MindreadInputFeedback"
	fb.text = ""
	fb.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
	fb.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	fb.custom_minimum_size = Vector2(0, 26)
	vb.add_child(fb)

	_mindread_input_layer = layer
	_mindread_edit = edit
	_mindread_feedback = fb
	edit.call_deferred("grab_focus")
	print("[Prelude] 1089 读心术：打开对话框式输入")


## 玩家提交一位数（回车 / 点「告诉她」）：合法就记下结果、收起浮层、
## 回到对话框继续由刘忆解读。
func _on_mindread_digit(raw: String) -> void:
	if not mindread_input_open():
		return
	var text := raw.strip_edges()
	if text == "" or not text.is_valid_int():
		_set_mindread_feedback("先在上面那个框里填一位数——你那个差里最小的那位。", false)
		return
	var d := int(text)
	if d < 0 or d > 9:
		_set_mindread_feedback("一位数就好——0 到 9。", true)
		return
	PreludeState.set_flag("week1_result_mindread", {"ok": true, "past": d, "future": 9 - d})
	_autosave()
	_close_mindread_input()
	_line_ready = true
	_run_next()


func _set_mindread_feedback(text: String, accent: bool) -> void:
	if _mindread_feedback != null:
		_mindread_feedback.text = text
		_mindread_feedback.add_theme_color_override("font_color",
				PreludeUI.C_ACCENT if accent else PreludeUI.C_INK_DIM)
	if _mindread_edit != null:
		_mindread_edit.call_deferred("grab_focus")


func _close_mindread_input() -> void:
	if _mindread_input_layer != null and is_instance_valid(_mindread_input_layer):
		_mindread_input_layer.queue_free()
	_mindread_input_layer = null
	_mindread_edit = null
	_mindread_feedback = null
	if _dbox != null:
		_dbox.set_hint_visible(true)


## 探针 / 暂停菜单问："1089 输入浮层正开着吗？"（开着时空格不推进剧情）
func mindread_input_open() -> bool:
	return _mindread_input_layer != null and is_instance_valid(_mindread_input_layer)


## 探针替玩家输一位数（与回车 / 点按钮走同一条路）
func submit_mindread_input(text: String) -> void:
	_on_mindread_digit(text)


## 输入框里只留数字（手打的、粘贴进来的非数字当场剔掉）
func _on_mindread_digits_only(text: String, edit: LineEdit) -> void:
	var cleaned := ""
	for i in text.length():
		var c := text.substr(i, 1)
		if c >= "0" and c <= "9":
			cleaned += c
	if cleaned != text:
		edit.text = cleaned
		edit.caret_column = cleaned.length()


## ["mindread_reveal"]：输完数字回到对话框后，刘忆按玩家报的那一位揭晓：
## 差值＝99×k，三位数恒为「k−1, 9, 10−k」，所以最小位＝过去（k−1），
## 未来＝9−最小位，中间那位永远是 9。四句在同一页对话框里逐句展开
## （点一下多一行、分四行），展开完"我猜的没错吧？"单独一页。
func _show_mindread_reveal() -> void:
	var past := 1
	var res: Variant = PreludeState.get_flag("week1_result_mindread", null)
	if res is Dictionary and (res as Dictionary).has("past"):
		past = int((res as Dictionary)["past"])
	var future := 9 - past
	_show_speaker("刘忆")
	_reveal_pending = [
		"你的未来是 %d。" % future,
		"而你的现在是 9。",
		"也就是这个差值的十位数字。",
	]
	_push_line("刘忆", "你的过去是 %d。" % past)
	# 四句展开完之后，单独一页"我猜的没错吧？"
	_rows.insert(_row_index, ["d", "刘忆", "我猜的没错吧？"])
	_row_is_top.insert(_row_index, false)


## 章节播完后的收尾（子类覆盖：显示"第一幕 完"之类，或切到下一幕）
func _on_chapter_end() -> void:
	_dbox.set_hint_visible(false)
	_dbox.show_line("", "（本章已结束。）")
