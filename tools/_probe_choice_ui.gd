extends SceneTree
## 复现二周目推理选择题的真实 UI 流程（含键盘空格兼容）：
## 第 1 题用"空格"作答（单选=选第一个），第 2-4 题用鼠标点选，
## 第 5 题多选：先试"未勾选按空格"（应提示不关闭），再勾选后按空格（=确认）。
## 跑法：godot --headless --path <项目> --script tools/_probe_choice_ui.gd

const SCENE := "res://scenes/week2/week2_1.tscn"

var _fails := 0
var _checks := 0

func _initialize() -> void:
	_run()

func _check(cond: bool, label: String, detail := "") -> void:
	_checks += 1
	var tail := ("（%s）" % detail) if detail != "" else ""
	if cond:
		print("  ✓ ", label, tail)
	else:
		_fails += 1
		print("  ✗ ", label, tail)

func _advance_event() -> InputEvent:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.physical_keycode = KEY_SPACE
	e.pressed = true
	return e

func _run() -> void:
	await process_frame
	print("========== 二周目选择题 UI 流程（含空格） ==========")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState")
		quit(1)
		return
	st.call("reset")
	st.call("set_flag", "prelude_done", true)
	var host: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(host)
	await process_frame
	await process_frame
	var rt: Node = host.get("runtime") if host.get("runtime") is Node else host.get_node_or_null("Runtime")
	_check(rt != null, "runtime 建起来了")
	if rt == null:
		quit(1)
		return

	var choice_seen := 0
	var steps := 0
	while steps < 3000:
		steps += 1
		var cm: Object = rt.get("_choice")
		if cm != null and bool(cm.call("is_open")):
			# 选择题打开时空格不能推进（等玩家作答）
			var row_before := int(rt.get("_row_index"))
			rt.call("_on_advance")
			await process_frame
			_check(int(rt.get("_row_index")) == row_before, "选择题打开时空格不推进（等玩家作答）")
			var prompt := str(cm.get("_pending"))
			choice_seen += 1
			print("  · 第 %d 题：%s" % [choice_seen, prompt])
			if choice_seen == 1:
				# 键盘流：单选按空格 = 选第一个选项
				cm.call("_unhandled_input", _advance_event())
				await create_timer(1.5).timeout
				await process_frame
				_check(int(rt.get("_row_index")) > row_before, "单选按空格 = 选第一个选项并继续")
			elif choice_seen == 5:
				# 多选：未勾选按空格 → 只提示不关闭
				cm.call("_unhandled_input", _advance_event())
				await process_frame
				_check(bool(cm.call("is_open")), "多选未勾选时空格只提示、不误提交")
				# 勾选两项（正确项 C/D = 2、3）后按空格 = 确认
				cm.call("_on_pressed", 2)
				await process_frame
				cm.call("_on_pressed", 3)
				await process_frame
				var confirm: Object = cm.get("_confirm")
				_check(confirm != null and not bool(confirm.get("disabled")), "勾选两项后确认可用")
				cm.call("_unhandled_input", _advance_event())
				await create_timer(1.5).timeout
				await process_frame
				_check(int(rt.get("_row_index")) > row_before, "多选勾选后按空格 = 确认并继续")
			else:
				# 鼠标流：点第一个选项（答错红 / 答对绿由 UI 负责）
				cm.call("_on_pressed", 0)
				await create_timer(1.5).timeout
				await process_frame
				_check(int(rt.get("_row_index")) > row_before, "鼠标点选后 0.9s 判定并继续（第 %d 题）" % choice_seen)
			if choice_seen >= 5:
				break
			continue
		var p: Node = rt.get("_panel")
		if p != null and is_instance_valid(p):
			p.call("close_panel", {})
			await process_frame
			await process_frame
			continue
		rt.call("_on_advance")
		await process_frame
		await process_frame

	_check(choice_seen == 5, "五道选择题全部以真实 UI 流程走完", "共 %d 题" % choice_seen)

	var intermission := false
	while steps < 6000:
		steps += 1
		if bool(host.get("_intermission")):
			intermission = true
			break
		var cm2: Object = rt.get("_choice")
		if cm2 != null and bool(cm2.call("is_open")):
			print("  · 意外：第 %d 步又出现选择题面板" % steps)
			break
		var p2: Node = rt.get("_panel")
		if p2 != null and is_instance_valid(p2):
			p2.call("close_panel", {})
			await process_frame
			await process_frame
			continue
		rt.call("_on_advance")
		await process_frame
		await process_frame
	_check(intermission, "五题之后一路推进到幕间（二周目结束）", "共 %d 步" % steps)

	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
