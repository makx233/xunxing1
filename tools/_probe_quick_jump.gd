extends SceneTree
## 验证标题页"快捷进入"的截断在走位返回（场景重建）后保持一致：
## 快捷进第 2 天 → chapter_sequences 截断为 4 段；模拟走位返回重建宿主 →
## chapter_sequences 必须仍是同样的 4 段（否则恢复点错位、会跳回第一天开头）。
## 跑法：godot --headless --path <项目> --script tools/_probe_quick_jump.gd

const SCENE := "res://scenes/week1/week1_1.tscn"
const FULL := ["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"]

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

func _make_host() -> Node:
	var host: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(host)
	await process_frame
	await process_frame
	return host

func _seqs_of(host: Node) -> Array:
	return host.call("chapter_sequences")

func _run() -> void:
	await process_frame
	print("========== 快捷进入截断一致性 ==========")
	var st := root.get_node_or_null("PreludeState")
	_check(st != null, "找得到 PreludeState")
	if st == null:
		quit(1)
		return

	# --- 正常从头开始：完整 5 段 ---
	st.call("reset")
	var h0: Node = await _make_host()
	_check(_seqs_of(h0) == FULL, "从头开始 = 完整 5 段", str(_seqs_of(h0)))
	h0.queue_free()
	await process_frame

	# --- 快捷进入第 2 天：截断为 4 段 ---
	st.call("reset")
	st.call("set_flag", "quick_start", "s1_phone")
	var h1: Node = await _make_host()
	var cut1: Array = _seqs_of(h1)
	_check(cut1 == ["s1_phone", "s3_desk", "s4b_1089", "s4_soup"],
			"快捷进第 2 天：序列截断为 4 段", str(cut1))
	_check(str(st.call("get_flag", "quick_start", "")) == "", "截断后 quick_start 已清空")
	_check(int(st.call("get_flag", "quick_trim_at", -1)) == 1, "记下截断点 1")
	_check(str(st.call("get_flag", "quick_trim_chapter", "")) == "week1", "记下章节 week1")

	# runtime 拿到的序列也是截断后的（走位恢复点按这个索引对齐）
	var rt1: Node = h1.get_node_or_null("Runtime") if h1.has_node("Runtime") else null
	_check(rt1 != null and str(rt1.get("sequence_order")) == str(cut1),
			"runtime.sequence_order = 截断序列", str(rt1.get("sequence_order") if rt1 else "无"))
	h1.queue_free()
	await process_frame

	# --- 模拟走位返回：宿主重建（不 reset，flags 原样）→ 截断必须一致 ---
	var h2: Node = await _make_host()
	var cut2: Array = _seqs_of(h2)
	_check(cut2 == cut1, "走位返回重建后仍是同一截断（不会退回第一天开头）", str(cut2))
	var rt2: Node = h2.get_node_or_null("Runtime") if h2.has_node("Runtime") else null
	_check(rt2 != null and str(rt2.get("sequence_order")) == str(cut2),
			"重建后 runtime.sequence_order 也一致", str(rt2.get("sequence_order") if rt2 else "无"))
	h2.queue_free()
	await process_frame

	# --- 快捷进入第 4 天：只剩 1 段 ---
	st.call("reset")
	st.call("set_flag", "quick_start", "s4_soup")
	var h3: Node = await _make_host()
	var cut3: Array = _seqs_of(h3)
	_check(cut3 == ["s4_soup"], "快捷进第 4 天：只剩 1 段", str(cut3))
	# 重建后仍一致
	h3.queue_free()
	await process_frame
	var h4: Node = await _make_host()
	_check(_seqs_of(h4) == cut3, "第 4 天走位返回后截断一致", str(_seqs_of(h4)))
	h4.queue_free()
	await process_frame

	# --- 切换到别的幕（week2）：不再沿用 week1 的截断 ---
	st.call("reset")
	st.call("set_flag", "quick_start", "s1_phone")
	var h5: Node = await _make_host()
	_check(_seqs_of(h5).size() == 4, "第 2 天截断就位", str(_seqs_of(h5)))
	h5.queue_free()
	await process_frame
	st.call("set_flag", "quick_start", "")   # 模拟 week1 播完进 week2：week2 自己无 quick_start
	st.call("set_flag", "quick_trim_at", "") # week2 的 _quick_trim 会清掉 week1 截断标记
	st.call("set_flag", "quick_trim_chapter", "week2")
	var w2: Node = (load("res://scenes/week2/week2_1.tscn") as PackedScene).instantiate()
	root.add_child(w2)
	await process_frame
	await process_frame
	var w2seqs: Array = w2.call("chapter_sequences")
	_check(w2seqs.size() >= 1 and str(w2seqs[0]) == "s0_scene",
			"week2 不沿用 week1 截断、从自身开头播", str(w2seqs))
	w2.queue_free()
	await process_frame

	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
