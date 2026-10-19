extends SceneTree
## 验证：标题页"快捷进入 · 章节选择"的路由 —— quick_start 标记 → 各幕序列正确截断
var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	print("—— 快捷进入路由自检 ——")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState autoload")
		quit(1)
		return

	# 1) 各幕在 quick_start 下的截断（前日谈已移除，只剩二周目 + 一周目）
	await _check_seq(st, "res://scripts/prelude/week2_1.gd", "week2",
			["s0_scene", "s1_method", "s2_motive", "s3_classroom", "s4_alibi", "s5_cup", "s6_truth"],
			"s3_classroom", ["s3_classroom", "s4_alibi", "s5_cup", "s6_truth"])
	# week1：从第三天（s3_desk）进入 → 截断为 第三天 + 1089 回忆 + 第四天
	await _check_seq(st, "res://scripts/prelude/week1_1.gd", "week1",
			["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"],
			"s3_desk", ["s3_desk", "s4b_1089", "s4_soup"])
	# 2) 不在序列里的 key：不截断、且标记保留（不该清掉别人的 key）
	await _check_seq(st, "res://scripts/prelude/week1_1.gd", "week1",
			["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"],
			"no_such_key", ["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"])
	# 3) 没有标记时：原样返回（默认正式流程不受影响）
	await _check_seq(st, "res://scripts/prelude/week1_1.gd", "week1",
			["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"],
			"", ["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"])
	# 4) title_screen：QUICK_ENTRIES 五项齐全（一二三四天 + 二周目；前日谈已移除）、
	#    按钮构建函数能直接调用（下划线方法不注册到 ClassDB，has_method 查不到是预期行为，
	#    所以用 call 实测）
	var ts: Script = load("res://scripts/ui/title_screen.gd")
	_check(ts != null, "title_screen.gd 可加载")
	if ts != null:
		var probe_inst: Control = ts.new()
		var qe: Array = probe_inst.get("QUICK_ENTRIES")
		_check(qe.size() == 5, "QUICK_ENTRIES 共 5 个入口", "实际 %d" % qe.size())
		var made: bool = false
		if probe_inst.has_method("_build_quick_entries"):
			probe_inst.call("_build_quick_entries")
			made = probe_inst.get_node_or_null("QuickEntry") != null
		_check(made, "标题页实际构建出 QuickEntry 按钮区")
		probe_inst.free()

	print("—— 共 %d 项，失败 %d 项 ——" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


## 设 quick_start → 实例化脚本 → 断言 chapter_sequences() 与截断结果一致、且标记被消费
func _check_seq(st: Object, script_path: String, cid: String, full: Array, qs: String, want: Array) -> void:
	st.call("reset")
	if qs != "":
		st.call("set_flag", "quick_start", qs)
	var s: Script = load(script_path)
	if s == null:
		_check(false, "%s 加载失败" % script_path)
		return
	# 不进树：add_child 会触发 _ready，而 _ready 里 configure() 已经消费过一次标记
	# （那是游戏内正确路径）。这里直接测 chapter_sequences() 本身。
	var inst: Control = s.new()
	var got: Array = inst.call("chapter_sequences")
	var ok := str(got) == str(want)
	_check(ok, "%s quick=%s → 截断正确（%d 段）" % [cid, qs, got.size()], "实际 %s" % str(got))
	# 消费后标记应被清掉（除非 qs 不在序列里，那种情况保留）
	if qs != "" and (full as Array).has(qs):
		var left: Variant = st.call("get_flag", "quick_start", "")
		_check(str(left) == "", "%s quick_start 标记已消费" % cid, "残留 %s" % str(left))
	inst.free()


func _check(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ✓ " + label)
	else:
		_fails += 1
		print("  ✗ " + label + (("　［%s］" % detail) if detail != "" else ""))
