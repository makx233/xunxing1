extends SceneTree
## 逐个验证封面"快捷进入"入口：reset → 立 quick_start（+附加 flag）→ 实例化场景 →
## 断言 chapter_sequences 首段 = 按钮声明的段、runtime.sequence_order 一致、首段存在且
## 段内第一个 title 卡正确。不切场景（change_scene 会让探针环境复杂），直接实例化验证。
## 跑法：godot --headless --path <项目> --script tools/_probe_quick_entries.gd

const ENTRIES := [
	["一周目 · 第 1 天", "res://scenes/week1/week1_1.tscn", "s0_maze", [], "week1", "第一天"],
	["一周目 · 第 2 天", "res://scenes/week1/week1_1.tscn", "s1_phone", [], "week1", "第二天"],
	["一周目 · 第 3 天", "res://scenes/week1/week1_1.tscn", "s3_desk", [], "week1", "第三天"],
	["一周目 · 第 4 天", "res://scenes/week1/week1_1.tscn", "s4_soup", [], "week1", "第四天"],
	["二周目 · 第 2 天", "res://scenes/week2/week2_1.tscn", "s0_scene", ["prelude_done"], "week2", "二周目"],
]

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

func _make_host(scene_path: String) -> Node:
	var host: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(host)
	await process_frame
	await process_frame
	return host

func _run() -> void:
	await process_frame
	print("========== 封面快捷键逐个验证 ==========")
	var st := root.get_node_or_null("PreludeState")
	_check(st != null, "找得到 PreludeState")
	if st == null:
		quit(1)
		return

	for opt: Array in ENTRIES:
		st.call("reset")
		st.call("set_flag", "quick_start", str(opt[2]))
		for k: Variant in (opt[3] as Array):
			st.call("set_flag", str(k), true)
		var host: Node = await _make_host(str(opt[1]))
		print("  [调试] host=", host, " class=", host.get_class() if host != null else "null")
		var r: Variant = host.call("chapter_sequences") if host != null else null
		print("  [调试] chapter_sequences -> ", r, " typeof=", typeof(r))
		var seqs: Array = [] if r == null else (r as Array)
		var cid: String = str(host.call("chapter_id"))
		_check(seqs.size() > 0 and str(seqs[0]) == str(opt[2]),
				"「%s」chapter_sequences 首段 = %s（共 %d 段）" % [str(opt[0]), str(opt[2]), seqs.size()], str(seqs))
		_check(cid == str(opt[4]), "「%s」章节 id = %s" % [str(opt[0]), str(opt[4])], cid)
		var rt: Node = host.get_node_or_null("Runtime") if host.has_node("Runtime") else null
		if rt != null:
			var order: Array = rt.get("sequence_order")
			_check(str(order[0]) == str(opt[2]), "「%s」runtime 首段一致" % str(opt[0]), str(order))
		else:
			_check(false, "「%s」找到 Runtime" % str(opt[0]), "")
		# 首段数据存在 + 段内第一个 title 卡（段在 data[chapter_id] 下）
		var dpath: String = str(host.call("data_path"))
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dpath))
		var data: Dictionary = parsed if parsed is Dictionary else {}
		var ch: Variant = data.get(str(host.call("chapter_id")), {})
		var seg: Variant = (ch as Dictionary).get(str(opt[2]), null)
		_check(seg is Array and (seg as Array).size() > 0, "「%s」数据段 %s 存在且非空" % [str(opt[0]), str(opt[2])], str(dpath))
		var t: String = _first_title(seg)
		_check(t.contains(str(opt[5])), "「%s」段首标题卡 = %s" % [str(opt[0]), str(opt[5])], t)
		host.queue_free()
		await process_frame

	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)

func _first_title(seg: Variant) -> String:
	if not (seg is Array):
		return ""
	for r: Variant in (seg as Array):
		if r is Array and r.size() >= 2 and str(r[0]) == "title":
			return str(r[1])
	return ""
