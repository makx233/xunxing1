extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》二周目 —— 衣柜里的密码盒（输入六位密码）
## ============================================================================
##  二周目结局段：星星引到衣柜前，摸出盒子 → 输入密码 053714 打开；
##  彩蛋：输 611089（刘忆的 1089）也能开盒，并多一句彩蛋提示。
##  盒子打开后不再管星星瓶——「盒子打开了」的文案由台词衔接（与一周目 wardrobe_code 同款）。
## ============================================================================

const CODE := "053714"
const EGG := "611089"
const CODE_LEN := 6

var _digits: Array[Label] = []
var _code_input: LineEdit = null
var _code_confirm: Button = null
var _feedback: Label = null
var _won := false


func panel_title() -> String:
	return "密码盒"


func panel_hint() -> String:
	return "输入六位数字，打开密码盒"


func build_body(body: VBoxContainer) -> void:
	body.add_child(make_text("密码盒 · 六个数字", PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var digit_row := HBoxContainer.new()
	digit_row.name = "DigitRow"
	digit_row.add_theme_constant_override("separation", 8)
	body.add_child(digit_row)

	for i in CODE_LEN:
		var slot := PanelContainer.new()
		slot.name = "Digit%d" % i
		slot.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.08, 0.085, 0.10, 0.95), Color(0.85, 0.80, 0.70, 0.30), 3))
		slot.custom_minimum_size = Vector2(46, 54)
		digit_row.add_child(slot)
		var l := make_text("－", PreludeUI.FS_NAME, PreludeUI.C_INK_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(l)
		_digits.append(l)

	body.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.14)))

	var row := HBoxContainer.new()
	row.name = "CodeInputRow"
	row.add_theme_constant_override("separation", 10)
	_code_input = LineEdit.new()
	_code_input.name = "CodeInput"
	_code_input.placeholder_text = "六位数字"
	_code_input.max_length = CODE_LEN
	_code_input.custom_minimum_size = Vector2(300, 44)
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_input.text_changed.connect(_on_code_changed)
	_code_input.add_theme_stylebox_override("normal", PreludeUI._button_skin_box(Color(0.10, 0.105, 0.125, 0.92), PreludeUI.C_LINE))
	_code_input.add_theme_stylebox_override("focus", PreludeUI._button_skin_box(Color(0.14, 0.145, 0.17, 0.96), Color(0.95, 0.86, 0.66, 0.5)))
	_code_input.add_theme_color_override("font_color", PreludeUI.C_INK)
	_code_input.add_theme_color_override("font_placeholder_color", PreludeUI.C_INK_DIM)
	_code_input.add_theme_color_override("caret_color", PreludeUI.C_NAME)
	_code_input.text_submitted.connect(_on_code_submitted)
	row.add_child(_code_input)
	_code_confirm = make_button("打开", true)
	_code_confirm.name = "CodeConfirm"
	_code_confirm.pressed.connect(func() -> void: _on_code_submitted(_code_input.text))
	row.add_child(_code_confirm)
	body.add_child(row)

	body.add_child(make_text("提示：053714。", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM))

	_feedback = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	body.add_child(_feedback)

	# 面板一开就把焦点放进输入框：玩家直接输六位数字按回车即可
	_code_input.call_deferred("grab_focus")


## 输入框里只留数字，并同步刷新上面六个数字格
func _on_code_changed(text: String) -> void:
	var cleaned := ""
	for i in text.length():
		var c := text.substr(i, 1)
		if c >= "0" and c <= "9":
			cleaned += c
	if cleaned != text:
		_code_input.text = cleaned
		_code_input.caret_column = cleaned.length()
	for i in CODE_LEN:
		if i < cleaned.length():
			_digits[i].text = cleaned.substr(i, 1)
			_digits[i].add_theme_color_override("font_color", PreludeUI.C_INK)
		else:
			_digits[i].text = "－"
			_digits[i].add_theme_color_override("font_color", PreludeUI.C_INK_DIM)


func _on_code_submitted(text: String) -> void:
	if _won:
		return
	var guess := text.strip_edges()
	if guess == "":
		_set_feedback("先在上面那个框里输入六位数字。", false)
		_code_input.call_deferred("grab_focus")
		return
	if guess == CODE:
		_won = true
		close_panel({"ok": true, "code": CODE})
		return
	if guess == EGG:
		# 彩蛋：611089 = 刘忆的 1089。也开盒，多一颗星星。
		_won = true
		close_panel({"ok": true, "code": CODE, "egg": true})
		return
	_set_feedback("不对。这一串数字你见过。", true)


func _set_feedback(text: String, accent := false) -> void:
	if _feedback == null:
		return
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT if accent else PreludeUI.C_INK_DIM)
