extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— 第二天 · 告诉刘忆六位数字密码
## ============================================================================
##  书架九本书解出 053714 之后，刘忆等着你把密码告诉她。
##  输入正确 → close_panel({"ok": true, "code": "053714"})，继续剧情；
##  输入错误 → 提示重试；也可以按右上角「✕ 退出」收起面板。
##  只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

const CODE := "053714"

var _input: LineEdit = null
var _feedback: Label = null
var _done_locked := false


# ---------------------------------------------------------------- 覆盖点
## 后面几关解谜没有"收起再回来"的意义，右上角「✕ 退出」键直接藏掉
func wants_exit() -> bool:
	return false


func panel_title() -> String:
	return "告诉刘忆 · 六位数字密码"


func panel_hint() -> String:
	return "输入从书架九本书里解出来的六位密码"


func build_body(body: VBoxContainer) -> void:
	body.add_child(make_text("刘忆正等着你的答案。", PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM))
	body.add_child(make_text("六位数字密码：", PreludeUI.FS_TEXT, PreludeUI.C_INK))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)

	_input = LineEdit.new()
	_input.name = "CodeInput"
	_input.placeholder_text = "输入六位数字"
	_input.max_length = 6
	_input.custom_minimum_size = Vector2(240, 40)
	_input.text_changed.connect(_on_text_changed)
	row.add_child(_input)

	var btn := make_button("告诉她", true)
	btn.name = "CodeConfirm"
	btn.pressed.connect(_on_confirm)
	row.add_child(btn)

	_feedback = make_text("", PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	body.add_child(_feedback)

	_input.grab_focus()


# ---------------------------------------------------------------- 输入
func _on_text_changed(_t: String) -> void:
	var cleaned := ""
	for ch in _input.text:
		if ch in "0123456789":
			cleaned += ch
	if cleaned != _input.text:
		_input.text = cleaned
		_input.caret_column = cleaned.length()
	if _feedback != null:
		_feedback.text = ""


func _on_confirm() -> void:
	if _done_locked:
		return
	var val := _input.text.strip_edges()
	if val == CODE:
		_done_locked = true
		close_panel({"ok": true, "code": CODE})
	else:
		_feedback.text = "不对。这一串数字你见过的……再想想。"
