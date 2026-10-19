extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 · 回忆段（第 5、6 关之间）—— 1089 读心术
## ============================================================================
##  刘忆让李星自己在脑子里走一遍 1089 魔术，一屏一屏往下走，四屏一关：
##
##    ① Step1Box   想一个三位数 —— 不能太特殊（百位与个位之差的绝对值 ≥ 2）
##                 纯文案，玩家点「想好了。」/ 按空格继续（不在电脑上输入）。
##    ② Step2Box   倒过来，用大的减小的 —— 差必是三位数，十位永远落在 9 上
##                 纯文案，玩家点「算好了。」/ 按空格继续（不在电脑上输入）。
##    ③ Step3Box   把差里最小的那位数（= 过去）告诉她 —— 唯一需要玩家输入数字的屏。
##    ④ RevealBox  揭晓：报上来的那一位是「过去」，9 是「现在」，9 − 过去 是「未来」，
##                 点「……好吧。」/ 按空格收尾过关。
##
##  过关：close_panel({"ok": true, "past": p, "future": f})
##  过关后：对话继续播「……最后一定是 1089，对吧。」，随后由对话运行时
##  （dialogue_runtime 的 ["formula1089"] 行）单独出一屏居中的算式卡片，
##  算式文字由浅变深逐渐浮现 —— 面板里不再带算式。
##
##  【实现】四屏在同一个 build_body 里一次建好，靠 visible 切换，不销毁节点。
##  【手感】每屏的可交互控件（按钮 / 输入框）出现时都把光标放进去，键盘玩家按
##  空格 / 回车就能推进，不会觉得"没反应"。
##
##  本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

## 塔罗牌第九张 —— 隐士那一段，一字不改照抄《附录2》
const TAROT_TEXT := "隐士提着灯，一个人走在雪地里。他不是没有人同行，是他先走开了。……你现在大概也觉得，身边有很多人，但没有一个真的知道你。"


# ================================================================ 数学
# 探针会直接调这三个静态函数，所以它们不碰任何节点、不依赖 _ready。
# 玩家现在不在电脑上输入三位数了，这组函数只留给探针做数学回归。

## n 必须是 100..999 且「百位与个位之差的绝对值 ≥ 2」；否则 ok=false。
## 成立时：rev = 倒过来的数；diff = abs(n - rev)（必为三位数）；
##        past = diff 的百位与个位里较小的那个；future = 9 - past。
@warning_ignore("integer_division")
static func solve_1089(n: int) -> Dictionary:
	var out := {
		"ok": false, "num": n, "rev": 0, "diff": 0, "past": 0, "future": 0,
	}
	if n < 100 or n > 999:
		return out
	var hi := n / 100          # 百位
	var lo := n % 10           # 个位
	# 百位和个位挨得太近（含相等）时，n - rev 只剩两位数，1089 那一步就不成立了
	if absi(hi - lo) < 2:
		return out
	var rev := reverse3(n)
	var diff := absi(n - rev)
	var past := mini(diff / 100, diff % 10)
	return {
		"ok": true, "num": n, "rev": rev, "diff": diff,
		"past": past, "future": 9 - past,
	}


## 123 -> 321
@warning_ignore("integer_division")
static func reverse3(v: int) -> int:
	var hi := v / 100
	var mid := (v / 10) % 10
	var lo := v % 10
	return lo * 100 + mid * 10 + hi


## diff + reverse3(diff)，对上面所有合法 diff 恒为 1089
static func sum_1089(diff: int) -> int:
	return diff + reverse3(diff)


# ================================================================ 状态

var _screens: Array[Control] = []       # Step1Box / Step2Box / Step3Box / RevealBox
var _screen_index := -1
var _state: Dictionary = {}             # {"past": p, "future": 9-p}
var _done_locked := false               # 已过关，屏蔽重复提交

var _step1_continue: Button = null
var _step2_continue: Button = null

var _digit_input: LineEdit = null
var _digit_confirm: Button = null
var _step3_feedback: Label = null

var _reveal_past: Label = null
var _reveal_now: Label = null
var _reveal_future: Label = null
var _reveal_comfort: Label = null
var _finish_btn: Button = null


# ================================================================ 覆盖点
## 后面几关解谜没有"收起再回来"的意义，右上角「✕ 退出」键直接藏掉
func wants_exit() -> bool:
	return false


func panel_title() -> String:
	return "读心术 · 1089"


func panel_hint() -> String:
	return "想一个三位数 → 倒过来相减 → 报出最小的那位数"


func build_body(body: VBoxContainer) -> void:
	_screens.append(_build_step1())
	_screens.append(_build_step2())
	_screens.append(_build_step3())
	_screens.append(_build_reveal())
	for s in _screens:
		s.visible = false
		body.add_child(s)

	_show_screen(0)


# ================================================================ ① 想一个数（纯文案）
func _build_step1() -> Control:
	var box := _make_screen("Step1Box")

	box.add_child(make_text("刘忆说：你先在脑子里想一个三位数。别太特殊——123、456 这种太整了，随机一点。",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var row := HBoxContainer.new()
	row.name = "Step1Row"
	box.add_child(row)

	var spacer := Control.new()
	spacer.name = "Step1Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_step1_continue = make_button("想好了。", true)
	_step1_continue.name = "Step1Continue"
	_step1_continue.pressed.connect(func() -> void: _show_screen(1))
	row.add_child(_step1_continue)
	return box


# ================================================================ ② 倒过来相减（纯文案）
func _build_step2() -> Control:
	var box := _make_screen("Step2Box")

	box.add_child(make_text("刘忆说：把这个数倒过来，再用大的减小的。",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var row := HBoxContainer.new()
	row.name = "Step2Row"
	box.add_child(row)

	var spacer := Control.new()
	spacer.name = "Step2Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_step2_continue = make_button("算好了。", true)
	_step2_continue.name = "Step2Continue"
	_step2_continue.pressed.connect(func() -> void: _show_screen(2))
	row.add_child(_step2_continue)
	return box


# ================================================================ ③ 报一个数（唯一需要输入）
func _build_step3() -> Control:
	var box := _make_screen("Step3Box")

	box.add_child(make_text("刘忆说：这个三位数的个位、十位、百位，分别是你的过去、现在和未来。",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))
	box.add_child(make_text("刘忆说：我需要你的过去作为基础来推断你的现在和未来，但是我能感觉到你的过去并没有现在或者未来如意，所以大概率数字最小的那位数代表了你的过去。你能把它告诉我吗？",
			PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var row := HBoxContainer.new()
	row.name = "Step3Row"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_digit_input = _make_input("DigitInput", "最小的那位数", 1)
	_digit_input.text_submitted.connect(_on_digit_submitted)
	row.add_child(_digit_input)

	_digit_confirm = make_button("告诉你", true)
	_digit_confirm.name = "DigitConfirm"
	_digit_confirm.pressed.connect(func() -> void: _on_digit_submitted(_digit_input.text))
	row.add_child(_digit_confirm)

	_step3_feedback = _make_feedback("Step3Feedback")
	box.add_child(_step3_feedback)
	return box


## 玩家在脑子里走完了 1089，报上来差里最小的那位数。
## 游戏不再校验（玩家心里的数游戏看不见），接住这一位数当作「过去」。
func _on_digit_submitted(text: String) -> void:
	if _done_locked or _screen_index != 2:
		return
	var raw := text.strip_edges()
	if raw == "" or not raw.is_valid_int():
		_set_step3("先在上面那个框里填一位数 —— 你那个差里最小的那位。", false)
		return
	var d := int(raw)
	if d < 0 or d > 9:
		_set_step3("一位数就好 —— 0 到 9。", true)
		return
	_state = {
		"ok": true,
		"num": 0,
		"rev": 0,
		"diff": 0,
		"past": d,
		"future": 9 - d,
	}
	_digit_input.editable = false
	_digit_confirm.disabled = true
	_set_step3("", false)
	_enter_reveal()


func _set_step3(text: String, accent: bool) -> void:
	_set_feedback_line(_step3_feedback, text, accent)
	if _screen_index == 2:
		_focus(_digit_input)


# ================================================================ ④ 揭晓
func _build_reveal() -> Control:
	var box := _make_screen("RevealBox")

	# 揭晓的三行字比别处稍大一号
	_reveal_past = make_text("", PreludeUI.FS_TEXT + 2, PreludeUI.C_INK)
	_reveal_past.name = "RevealPast"
	box.add_child(_reveal_past)

	_reveal_now = make_text("", PreludeUI.FS_TEXT + 2, PreludeUI.C_INK)
	_reveal_now.name = "RevealNow"
	box.add_child(_reveal_now)

	_reveal_future = make_text("", PreludeUI.FS_TEXT + 2, PreludeUI.C_NAME)
	_reveal_future.name = "RevealFuture"
	box.add_child(_reveal_future)

	box.add_child(make_text("至于你的现在——塔罗牌里的第九张，是隐士。",
			PreludeUI.FS_TEXT, PreludeUI.C_NAME))
	box.add_child(make_text(TAROT_TEXT, PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM))

	_reveal_comfort = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK)
	_reveal_comfort.name = "RevealComfort"
	box.add_child(_reveal_comfort)

	# 算式卡不在面板里：过关后由对话运行时（["formula1089"] 行）单独出一屏
	var row := HBoxContainer.new()
	row.name = "RevealRow"
	box.add_child(row)

	var spacer := Control.new()
	spacer.name = "RevealSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_finish_btn = make_button("……好吧。", true)
	_finish_btn.name = "FinishButton"
	_finish_btn.pressed.connect(_on_finish_pressed)
	row.add_child(_finish_btn)
	return box


func _enter_reveal() -> void:
	_fill_reveal()
	_show_screen(3)


func _fill_reveal() -> void:
	if _state.is_empty():
		return
	var past := int(_state["past"])
	var future := int(_state["future"])
	_reveal_past.text = "你的过去是 %d。" % past
	_reveal_now.text = "你的现在是 9。"
	_reveal_future.text = "你的未来是 %d。" % future
	_reveal_comfort.text = "不过没关系。你的未来是 %d——比 %d 大。我能感觉到，你以后会更好。" % [future, past]


func _on_finish_pressed() -> void:
	if _done_locked or _state.is_empty():
		return
	_done_locked = true
	_finish_btn.disabled = true
	close_panel({
		"ok": true,
		"past": int(_state["past"]),
		"future": int(_state["future"]),
	})


# ================================================================ 公用小工具
func _make_screen(box_name: String) -> Control:
	var box := VBoxContainer.new()
	box.name = box_name
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


## 换屏：只改 visible，不销毁节点（玩家回头也看不到已经填过的东西，但状态还在）
## 每一屏的可交互控件出现时都 grab_focus，键盘玩家按空格 / 回车就能推进。
func _show_screen(index: int) -> void:
	if index < 0 or index >= _screens.size():
		return
	for i in _screens.size():
		_screens[i].visible = i == index
	_screen_index = index
	if index == 0:
		if _step1_continue != null:
			_step1_continue.call_deferred("grab_focus")
	elif index == 1:
		if _step2_continue != null:
			_step2_continue.call_deferred("grab_focus")
	elif index == 2:
		_focus(_digit_input)
	elif index == 3:
		if _finish_btn != null:
			_finish_btn.call_deferred("grab_focus")


## 【手感】输入框出现时把光标放进去，不然玩家直接敲键盘是"没反应"的
func _focus(edit: LineEdit) -> void:
	if edit == null or not edit.editable:
		return
	edit.call_deferred("grab_focus")


func _set_feedback_line(label: Label, text: String, accent: bool) -> void:
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", PreludeUI.C_ACCENT if accent else PreludeUI.C_INK_DIM)


# 输入框：样式与 panel_memo / panel_wardrobe 一致，另外只收数字
func _make_input(input_name: String, placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.name = input_name
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(300, 44)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(_on_digits_only.bind(e))
	e.add_theme_stylebox_override("normal",
			PreludeUI._button_skin_box(Color(0.10, 0.105, 0.125, 0.92), PreludeUI.C_LINE))
	e.add_theme_stylebox_override("focus",
			PreludeUI._button_skin_box(Color(0.14, 0.145, 0.17, 0.96), Color(0.95, 0.86, 0.66, 0.5)))
	e.add_theme_stylebox_override("read_only",
			PreludeUI._button_skin_box(Color(0.07, 0.07, 0.08, 0.7), Color(0.4, 0.4, 0.4, 0.3)))
	e.add_theme_color_override("font_color", PreludeUI.C_INK)
	e.add_theme_color_override("font_placeholder_color", PreludeUI.C_INK_DIM)
	e.add_theme_color_override("caret_color", PreludeUI.C_NAME)
	return e


## 输入框里只留数字（非数字当场剔掉，粘贴进来的也一样）
func _on_digits_only(text: String, edit: LineEdit) -> void:
	var cleaned := ""
	for i in text.length():
		var c := text.substr(i, 1)
		if c >= "0" and c <= "9":
			cleaned += c
	if cleaned != text:
		edit.text = cleaned
		edit.caret_column = cleaned.length()


func _make_feedback(label_name: String) -> Label:
	var l := make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	l.name = label_name
	l.custom_minimum_size = Vector2(0, 24)
	return l
