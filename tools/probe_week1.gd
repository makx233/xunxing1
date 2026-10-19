extends SceneTree
## ============================================================================
##  《寻星》· 一周目端到端自检（headless，不用开游戏窗口）
## ============================================================================
##  一周目是"对话 → 小游戏面板 → 走位 → 对话"拼起来的，链条长、又全靠 flag 串，
##  所以这里把它整幕按真实流程跑一遍：
##    ① 数据层静态检查：段/面板/走位目标/房间/peek 名字是不是都对得上；
##    ② 一路点到幕间：面板一开就替玩家"过关"（close_panel），
##       走位一旦触发就检查恢复点、记下"看过目标物件"、重建场景继续；
##    ③ 结束时检查幕间文案与所有面板的结果 flag。
##
##  跑法：
##    godot --headless --path <项目> --script tools/probe_week1.gd
##  退出码 0 = 全绿。
## ============================================================================

const DATA := "res://data/week1_dialogue.json"
const ROOMS := "res://data/prelude_rooms.json"
const SCENE := "res://scenes/week1/week1_1.tscn"
const CHAPTER := "week1"
## 一周目一共 5 段：四天 + 第三天末的 1089 回忆（s4b_1089）。
const SEQS := ["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"]
## 新链：一周目四天 + 校园衔接段播完直接进二周目（week2_1.tscn）。
## 跳转二周目时立起 prelude_done。
const WEEK2_SCENE := "res://scenes/week2/week2_1.tscn"
## 一周目跳转二周目时立起这个标记，week2_1 读它判断存档「继续上次」时要不要先补前日谈。
const PRELUDE_DONE_FLAG := "prelude_done"
const SPACES := ["hallway", "classroom", "activity", "star_jar", "star_hand", "star_rise", "star_riddle", "star_sorrow", "star_burst1", "star_burst2", "star_burst3", "star_burst4", "star_burst5", "trans_toilet", "trans_paper", "trans_backdoor", "trans_corridor", "trans_stairs", "trans_road1", "trans_road2", "trans_road3", "trans_road4", "trans_small_gate", "trans_stairs_dark", "trans_stairs_2", "trans_floor3", "trans_stairs_3", "trans_door_closed", "trans_door_open", "trans_white", "montage", "roofline", "dorm_corridor", "dorm_room", "black"]
## 用 preload 而不是全局类名 Week1Panels：--script 模式下 .godot 里的
## global_script_class_cache 是旧的，新加的 class_name 会 "not declared"。
const WEEK1_PANELS := preload("res://scripts/week1/week1_panels.gd")
## 读心术那一关（回忆段 s4b_1089）的静态数学 solve_1089 / reverse3 / sum_1089
## 直接从面板脚本上调 —— 同一个套路：preload，不用全局类名。
const MINDREAD_SCRIPT := preload("res://scripts/week1/panel_mindread.gd")
## 一周目第一天的段表（四天之间还夹着回忆段 s4b_1089）在 week1_1.gd 里，
## 这里用常量表读它，别为了断言去改那个文件。
## 【坑】get_script_constant_map() 不是静态函数：preload 出来的常量会被当成"在类上直接调"，
## 所以走 load + as GDScript（probe_week2 也是这么读的）。
const WEEK1_1_PATH := "res://scripts/prelude/week1_1.gd"

var _fails := 0
var _checks := 0
var _seen_panels: Array = []
var _seen_walks: Array = []
var _walk_index := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# --script 模式下要等第一帧，root 才会正常派发子节点的 _ready
	await process_frame
	print("========== 一周目 端到端自检 ==========")
	var st := root.get_node_or_null("PreludeState")
	if st == null:
		print("✗ 找不到 PreludeState 自动加载")
		quit(1)
		return

	_static_checks()
	await _wardrobe_ui_checks()
	await _wardrobe_grab_checks()
	await _mindread_checks()

	st.call("reset")
	var host: Node = await _make_host()
	var rt: Node = _runtime_of(host)
	_check(rt != null, "一周目场景（week1_1.tscn）建起来了", _runtime_debug(host) if rt == null else "")
	if rt == null:
		_finish()
		return

	# ---- 一路点到幕间
	var steps := 0
	var formula_seen := ""
	# 1089 揭晓：四句同一页逐句展开、分四行；"我猜的没错吧？"单独一页
	var reveal_merged_seen := false
	var reveal_merged_text := ""
	var guess_page_seen := false
	while steps < 8000:
		steps += 1
		if bool(host.get("_intermission")):
			break
		var p: Node = _panel_of(rt)
		if p != null:
			var pid := _panel_id(p)
			var want := WEEK1_PANELS.script_for(pid)
			var got := str((p.get_script() as Script).resource_path) if p.get_script() is Script else ""
			_check(got == want, "面板 %s 挂的脚本是登记表里那个" % pid, "期望 %s 实际 %s" % [want, got])
			_seen_panels.append(pid)
			# 替玩家过关：面板的 finished 会由 close_panel 发出来
			p.call("close_panel", {})
			await process_frame
			await process_frame
			_check(st.call("get_flag", "week1_result_" + pid, null) != null,
					"过关结果写进了 week1_result_%s" % pid)
			_check(_panel_of(rt) == null, "过关后面板收掉了")
			continue
		if bool(st.call("get_flag", "walk_resume_active", false)):
			await _handle_walk(st, host, rt)
			host = _cur_host()
			rt = _runtime_of(host)
			if rt == null:
				_check(false, "走位之后对话场景重建失败")
				break
			continue
		if rt.has_method("mindread_input_open") and bool(rt.call("mindread_input_open")):
			# 1089 读心术现在是"对话框式"输入（不再弹整屏面板）：替玩家报一位数
			rt.call("submit_mindread_input", "1")
			await process_frame
			await process_frame
			continue
		if _choice_open(rt):
			_pick_choice(rt, 0)
		else:
			if rt.get("_formula_layer") != null:
				formula_seen = _title_text(rt.get("_formula_layer"))
			rt.call("_on_advance")
		await process_frame
		await process_frame
		# 1089 揭晓的呈现：四句在同一页（\n 分四行）逐句展开完的瞬间，
		# 对话框文本会同时含"你的过去/未来/现在是/也就是"四句；
		# 紧接着单独一页"我猜的没错吧？"（整页文本正好是这一句）。
		var dbt := _dbox_text(rt)
		if dbt.contains("你的过去是") and dbt.contains("你的未来是") \
				and dbt.contains("而你的现在是") and dbt.contains("也就是这个差值"):
			reveal_merged_seen = true
			reveal_merged_text = dbt
		if dbt.strip_edges() == "我猜的没错吧？":
			guess_page_seen = true

	_check(bool(host.get("_intermission")), "整幕点到了幕间（一周目结束）", "点了 %d 步" % steps)
	_check(reveal_merged_seen,
			"1089 揭晓四句在同一页对话框里逐句展开、分四行（你的过去/未来/现在是/也就是……）",
			reveal_merged_text)
	_check(guess_page_seen, "「我猜的没错吧？」单独一页播出")
	_check(formula_seen.contains("1089") and formula_seen.contains("198") and formula_seen.contains("891"),
			"对话流里真的弹过 1089 算式卡（past 缺失时兜底 1 → 198 ＋ 891 ＝ 1089）", formula_seen)
	# 【同步】对话行里的面板顺序：第二天 memo → code；第三天 desk；第四天 soup →
	# wardrobe_grab（翻衣服拿密码盒，不输密码）→ wardrobe_code（输密码）。
	# 1089 回忆段（mindread）不再弹整屏面板，改走"对话框式"输入（见 _mindread_checks）。
	# 黑箱迷宫（maze）、手势密码（gesture）与书架九本书（bookshelf）
	# 都在走位里由物品 open_panel 标签弹出，不走对话行。
	_check(_seen_panels == ["memo", "code", "desk", "soup", "wardrobe_grab", "wardrobe_code"],
			"六个对话行面板按顺序都弹过了（1089 回忆是对话框式输入；书架九本书在走位里弹）", str(_seen_panels))
	_check(_seen_walks == ["黑箱", "手机", "书架", "刘忆的书桌", "刘忆的书桌"],
			"五次走位分别要求走到黑箱 / 手机 / 书架 / 刘忆的书桌 / 刘忆的书桌（第三天找不同后不再进 d3b 宿舍场景，撕下来的纸与初遇回忆直接播）",
			str(_seen_walks))
	for id in ["maze", "gesture", "memo", "bookshelf", "code", "desk", "soup", "mindread", "wardrobe_grab", "wardrobe_code"]:
		_check(st.call("get_flag", "week1_result_" + id, null) != null, "%s 有完成记录" % id)

	# ---- 新链：四天 + 校园衔接段播完直接进二周目（前日谈不再从一周目出口接入）
	var hint := _title_text(host.get("_label"))
	_check(hint.contains("一周目结束") and hint.contains("二周目"),
			"幕间告诉玩家一周目播完接下来进二周目", hint)
	_check(str(host.call("next_scene_after_chapter")) == WEEK2_SCENE,
			"一周目播完后的下一幕是 week2_1.tscn", str(host.call("next_scene_after_chapter")))
	_check(host.call("chapter_sequences") == ["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"],
			"chapter_sequences 就是四天 + 1089 回忆（没有收尾分支）", str(host.call("chapter_sequences")))

	# ---- 存档 / 继续上次：写一条存盘记录，再模拟"关掉游戏重开"：
	# 清掉内存状态 → request_resume()（它会把 flags 一起灌回来）→ 重建这一幕，一路点到幕间。
	var sg := root.get_node_or_null("SaveGame")
	_check(sg != null, "找得到 SaveGame 自动加载")
	if sg != null:
		sg.call("write", CHAPTER, SCENE, 0)
		st.call("reset")
		var back_scene := str(sg.call("request_resume"))
		_check(back_scene.ends_with("week1_1.tscn"), "「继续上次」指向一周目这一幕", back_scene)
		host = await _make_host()
		rt = _runtime_of(host)
		_check(rt != null, "读档后一周目场景重建成功", _runtime_debug(host) if rt == null else "")
		if rt != null:
			# 读档会从段首重播整条链：走位/面板计数器清零，让房间映射按 1..7 重新对齐
			_seen_panels.clear()
			_seen_walks.clear()
			_walk_index = 0
			var steps3 := 0
			while steps3 < 8000:
				steps3 += 1
				if bool(host.get("_intermission")):
					break
				var p3: Node = _panel_of(rt)
				if p3 != null:
					p3.call("close_panel", {})
					await process_frame
					await process_frame
					continue
				if bool(st.call("get_flag", "walk_resume_active", false)):
					await _handle_walk(st, host, rt)
					host = _cur_host()
					rt = _runtime_of(host)
					if rt == null:
						break
					continue
				if rt.has_method("mindread_input_open") and bool(rt.call("mindread_input_open")):
					rt.call("submit_mindread_input", "1")
					await process_frame
					await process_frame
					continue
				if _choice_open(rt):
					_pick_choice(rt, 0)
				else:
					rt.call("_on_advance")
				await process_frame
				await process_frame
			_check(bool(host.get("_intermission")), "读档接着播也走到了幕间", "点了 %d 步" % steps3)
		sg.call("clear")

	_finish()


func _finish() -> void:
	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- 走位站点

func _handle_walk(st: Node, host: Node, rt: Node) -> void:
	var goal := str(st.call("get_flag", "walk_goal_active", ""))
	var room := str(st.call("get_flag", "walk_room", ""))
	var seq_i := int(st.call("get_flag", "walk_resume_seq", -1))
	var row_i := int(st.call("get_flag", "walk_resume_row", -1))
	var back := str(st.call("get_flag", "walk_return_scene", ""))
	_seen_walks.append(goal)
	_walk_index += 1
	print("  · 走位 %d：房间 %s，目标「%s」，第 %d 段第 %d 行，回 %s" % [_walk_index, room, goal, seq_i, row_i, back])
	_check(goal != "", "这次走位声明了目标物件（[\"goal\"]）")
	_check(back.ends_with("week1_1.tscn"), "记下了回一周目这一幕的场景", back)
	# 五次走位的房间映射（第三天找不同后的 d3b 宿舍场景已删：
	# 撕下来的纸与初遇回忆改为找不同后直接顺序播放，不再走位）
	var ROOM_BY_WALK := {
		1: "dorm_room_d1b",      # 第一天 桌面黑箱迷宫（走位里弹 maze）
		2: "dorm_room_d1b_phone",# 第一天 桌面手势密码（走位里弹 gesture，房间变体带手机）
		3: "dorm_room_d2",    # 第二天 书架九本书
		4: "dorm_room_d3a",   # 第三天 自由探索（找不同前）
		5: "dorm_room",       # 第四天 海龟汤（刘忆的书桌）
	}
	var expected_room := str(ROOM_BY_WALK.get(_walk_index, ""))
	_check(room == expected_room, "第 %d 次走位走的房间正确" % _walk_index, room)

	# 玩家在走位里走到目标物件跟前看了它（走位场景每查一件就把名字记进 walk_during_examined）
	if goal != "":
		st.call("note_examined", goal)
		var wl: Array = (st.call("get_flag", "walk_during_examined", []) as Array).duplicate()
		if not wl.has(goal):
			wl.append(goal)
			st.call("set_flag", "walk_during_examined", wl)

	# 第一次走位（黑箱）：玩家先收起桌上的折纸星星，再点黑箱弹出迷宫并解开。
	# 黑箱迷宫是在走位场景里弹的（不走对话行），探针替玩家把这两步做完并落 flag。
	if goal == "黑箱":
		st.call("set_flag", "week1_collected_star", true)
		st.call("set_flag", "week1_result_maze", {"ok": true, "shape": "S"})
		st.call("note_examined", "黑箱")
		print("  · 走位 1 模拟：收起星星 · 解开黑箱迷宫")

	# 第二次走位（手机）：玩家点开手势密码面板并解开（面板在走位场景里弹，不走对话行）。
	if goal == "手机":
		st.call("set_flag", "week1_result_gesture", {"ok": true})
		print("  · 走位 2 模拟：解开手机手势密码")

	# 第三次走位（书架）：书架物品带 open_panel:bookshelf 标签，点书架直接在走位里弹出
	# 九本书解谜面板并解开（不走对话行）；room_runtime 解完自动 _on_done 切回对话，
	# 不再走回宿舍。
	if goal == "书架":
		st.call("set_flag", "week1_result_bookshelf", {"ok": true, "code": "053714"})
		print("  · 走位 3 模拟：解开书架九本书（053714）")

	await process_frame
	await process_frame
	_free_walk_scene()
	if is_instance_valid(host):
		root.remove_child(host)
		host.free()
	await process_frame
	await process_frame
	var h2: Node = await _make_host()
	var rt2: Node = _runtime_of(h2)
	_check(rt2 != null, "点完「看完了」回来，对话场景建起来了")
	if rt2 == null:
		return
	_check(int(rt2.get("_seq_index")) == seq_i, "回来之后停在走位时那一段",
			"期望 %d 实际 %d" % [seq_i, int(rt2.get("_seq_index"))])
	_check(int(rt2.get("_row_index")) > row_i, "回来之后确实往下播了",
			"_row_index=%d（恢复点 %d）" % [int(rt2.get("_row_index")), row_i])
	_check(rt2.get("_title_layer") == null, "回来之后没有重播标题卡")
	_check(not bool(rt2.get("_free_mode")), "回来之后没有掉进「查看完毕」兜底模式")
	if goal != "":
		# 追加台词按"发起走位的那一段"找（黑箱这一段没注册 peek，就跳过）
		var order: Variant = rt2.get("sequence_order")
		var seq_id := ""
		if order is Array and seq_i >= 0 and seq_i < (order as Array).size():
			seq_id = str((order as Array)[seq_i])
		var want := _first_peek_line(goal, seq_id)
		if want != "":
			var body := rt2.get_node_or_null("DialogueBox/Panel/VB/BodyText")
			var got := "" if body == null else str(body.get("text"))
			_check(got == want, "接着播的正是「%s」的追加台词" % goal,
					"期望「%s」实际「%s」" % [want, got])


var _host: Node = null


func _cur_host() -> Node:
	return _host


func _make_host() -> Node:
	if is_instance_valid(_host):
		root.remove_child(_host)
		_host.free()
	_host = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_host)
	if _runtime_of(_host) == null:
		await process_frame
		await process_frame
	return _host


func _runtime_of(host: Node) -> Node:
	if not is_instance_valid(host):
		return null
	var v: Variant = host.get("runtime")
	if v is Node:
		return v as Node
	return host.get_node_or_null("Runtime")


func _runtime_debug(host: Node) -> String:
	if not is_instance_valid(host):
		return "host 已释放"
	var v: Variant = host.get("runtime")
	var sc: Variant = host.get_script()
	return "children=%s runtime=%s script=%s" % [
			str(host.get_children()), str(v),
			str((sc as Script).resource_path) if sc is Script else "null"]


func _panel_of(rt: Node) -> Node:
	if rt == null:
		return null
	var p: Variant = rt.get("_panel")
	if p is Node and is_instance_valid(p as Node):
		return p as Node
	return null


func _panel_id(p: Node) -> String:
	var ctx: Variant = p.get("_ctx")
	if ctx is Dictionary:
		return str((ctx as Dictionary).get("id", ""))
	return ""


func _choice_open(rt: Node) -> bool:
	var c: Variant = rt.get("_choice")
	if c == null or not (c is Object):
		return false
	return bool((c as Object).call("is_open"))


func _pick_choice(rt: Node, index: int) -> void:
	# ChoiceMenu 现在带对错反馈：点选后要等 0.9s 才收盘。探针不关心动画，
	# 直接把面板收掉、按 index 插分支推进，避免循环里反复点选。
	var c: Variant = rt.get("_choice")
	if c is Object and (c as Object).has_method("close"):
		(c as Object).call("close")
	rt.call("_on_choice", index)


func _free_walk_scene() -> void:
	for c in root.get_children():
		if str(c.name) == "PreludeWalk":
			root.remove_child(c)
			c.free()


# ---------------------------------------------------------------- 衣柜面板几何
## 第 ① 屏的"文字重叠"：面板里的字要么是 Label（容器排版），要么是 draw_string 画的。
##  无头模式截不了图，所以改成**量矩形**——两条判据：
##    ① 第 ① 屏不该有"参与排版"的文字节点（Label / Button / LineEdit / RichTextLabel）。
##       旧版那一屏是「四张按钮卡片（色块 + 名字）」，光这一条就挂 4 个；
##       新版整面柜子画在一张固定尺寸的子画布上，是 0 个 —— 重叠的地基被抽掉了。
##    ② 所有**可见**文字块的全局矩形两两求交，必须 0 对重叠；
##       再顺手查"文字被挤爆"（最小高度/宽度 > 实际尺寸）——
##       旧版最离谱的那张卡片要 163px 高，只分到 48px，多出来的 115px 就画到
##       隔壁两件衣服的名字上去了，这才是 Kerry 说的"文字重叠"。
func _wardrobe_ui_checks(tree: SceneTree = null) -> void:
	if tree == null:
		tree = self
	var script_path := WEEK1_PANELS.script_for("wardrobe")
	# 临时对照用：设了 DSH_WARDROBE_SCRIPT 就把这套断言套到别的脚本上，
	# 拿旧布局跑一遍，证明这几条真的会失败（不然断言只是"永远绿"的摆设）。
	var override := OS.get_environment("DSH_WARDROBE_SCRIPT")
	if override != "":
		script_path = override
	_check(script_path != "", "衣柜面板在登记表里有脚本路径", script_path)
	if script_path == "" or not ResourceLoader.exists(script_path):
		return

	var host := Control.new()
	host.name = "WardrobeProbeHost"
	tree.root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var p := Control.new()
	p.name = "WardrobeProbe"
	p.set_script(load(script_path))
	p.call("setup", {"id": "wardrobe"})
	host.add_child(p)
	# 【坑】等帧要等**面板所在的那棵树**：这个函数可能被一个"只是 new 出来的"
	# 探针实例调用（tools/_probe_wardrobe_assert.gd 就这么干），那种实例的
	# process_frame 根本不会发、get_tree() 也会报 "Parameter data.tree is null"，
	# 所以树由调用方传进来，默认才是自己。
	await tree.process_frame
	await tree.process_frame

	var geo := _geometry_scan(p)

	# 判据 ①：第 ① 屏（手绘衣柜）里没有参与排版的文字节点
	var layout_nodes := -1
	if p.has_method("ui_layout_text_nodes"):
		layout_nodes = int(p.call("ui_layout_text_nodes"))
	_check(layout_nodes == 0,
			"衣柜第①屏没有参与排版的文字节点（文字重叠的地基）",
			"实测 %d 个（-1 = 面板没提供这个方法）" % layout_nodes)

	# 判据 ②：可见文字块两两不重叠
	_check(int(geo["overlaps"]) == 0,
			"衣柜界面可见文字块两两求交：0 对重叠",
			"实测 %d 对重叠 / 共 %d 个可见文字块（含手绘 %d 个）" % [
					int(geo["overlaps"]), int(geo["rects"]), int(geo["drawn"])])
	if int(geo["overlaps"]) > 0:
		for s in geo["samples"]:
			print("      · 重叠：%s" % str(s))

	# 判据 ③：没有文字被挤爆（文字画出去、压到下一块上）
	_check(int(geo["squeezed"]) == 0,
			"衣柜界面没有文字被挤爆（最小尺寸 ≤ 实际尺寸）",
			"实测 %d 个被挤爆" % int(geo["squeezed"]))
	if int(geo["squeezed"]) > 0:
		for s in geo["squeeze_samples"]:
			print("      · 挤爆：%s" % str(s))

	# ------------------------------------------------ 主视图按"被点的那一件"画
	# 【为什么补这几条】Kerry 报过「围巾的主视图居然是衣服」：旧版 `_draw_coat_view()` 里写死
	#   `var c := Color(0.62, 0.24, 0.26)`（"主视图一律按红外套画"），所以点围巾也画一件外套。
	#   下面把"按件画"钉住：颜色逐件对上 CLOTHES、围巾没有口袋（不画口袋、也没有命中区）、
	#   标题跟着被点的那一件走。
	var consts: Dictionary = {}
	if p.get_script() != null:
		consts = p.get_script().get_script_constant_map()
	var clothes: Array = consts.get("CLOTHES", [])
	_check(clothes.size() == 4, "衣柜常量表 CLOTHES 是四件", "实测 %d 件" % clothes.size())

	var color_ok := true
	var color_detail := ""
	for i in clothes.size():
		if not p.has_method("cloth_color"):
			color_ok = false
			color_detail = "面板没有 cloth_color 方法"
			break
		var got: Color = p.call("cloth_color", i)
		var want: Color = clothes[i]["color"]
		if not got.is_equal_approx(want):
			color_ok = false
			color_detail = "第 %d 件 %s ≠ %s" % [i, str(got), str(want)]
			break
	_check(color_ok, "主视图的颜色逐件读 CLOTHES（点哪件画哪件的色）", color_detail)

	if not p.has_method("garment_has_pockets"):
		_check(false, "面板提供 garment_has_pockets（主视图按件决定画不画口袋）", "没有这个方法")
	else:
		var pockets_ok := true
		var pockets_bad := ""
		for i in clothes.size():
			var want_p := bool(clothes[i].get("pockets", true))
			if bool(p.call("garment_has_pockets", i)) != want_p:
				pockets_ok = false
				pockets_bad = "第 %d 件（%s）" % [i, str(clothes[i]["name"])]
				break
		_check(pockets_ok, "三件外套有口袋 / 围巾没有口袋，与 CLOTHES.pockets 一致", pockets_bad)

		# —— 点围巾：标题说的是围巾，且没有"看不见的命中区"
		p.call("_open_cloth", 3)
		var title_node: Variant = p.get("_detail_title")
		var scarf_title := str(title_node.text) if title_node != null else ""
		_check(scarf_title.contains("围巾") and not scarf_title.contains("外套"),
				"点围巾 → 主视图标题说的是围巾（不是外套）", scarf_title)
		var scarf_hit := int(p.call("_pocket_at", Vector2(320.0, 140.0)))
		_check(scarf_hit == -1, "围巾上没有口袋可点（右侧那块命中区返回 -1）", "实测 %d" % scarf_hit)

		# —— 点第三件（红）：右上袋仍然可点（这一条守着"解谜那条路没被改坏"）
		p.call("_open_cloth", 2)
		var coat_node: Variant = p.get("_detail_title")
		var coat_title := str(coat_node.text) if coat_node != null else ""
		_check(coat_title.contains("红色外套"), "点第三件（红）→ 标题是红色外套", coat_title)
		var coat_hit := int(p.call("_pocket_at", Vector2(320.0, 140.0)))
		_check(coat_hit == 1, "红外套上右侧那块是「右上袋」（第 2 个口袋）", "实测 %d" % coat_hit)

	tree.root.remove_child(host)
	host.free()
	await tree.process_frame


## 量一遍面板里"玩家看得见的文字"：
##   · Label / Button / LineEdit / RichTextLabel 的 get_global_rect()（隐藏屏的跳过）
##   · 面板报出来的手绘文字矩形（ui_text_rects）
## 返回 rects / drawn / overlaps / squeezed / samples。
func _geometry_scan(p: Node) -> Dictionary:
	var rects: Array = []
	var names: Array = []
	var squeezed: Array = []
	_geometry_collect(p, p, rects, names, squeezed)

	var drawn := 0
	if p.has_method("ui_text_rects"):
		for r in p.call("ui_text_rects"):
			rects.append(r)
			names.append("(手绘文字)")
			drawn += 1

	var overlaps := 0
	var samples: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				overlaps += 1
				if samples.size() < 5:
					samples.append("%s %s × %s %s" % [
							str(names[i]), str(rects[i]), str(names[j]), str(rects[j])])

	var squeeze_samples: Array = []
	for s in squeezed:
		if squeeze_samples.size() < 5:
			squeeze_samples.append(str(s))

	return {
		"rects": rects.size(),
		"drawn": drawn,
		"overlaps": overlaps,
		"samples": samples,
		"squeezed": squeezed.size(),
		"squeeze_samples": squeeze_samples,
	}


func _geometry_collect(n: Node, panel: Node, rects: Array, names: Array, squeezed: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if _geometry_is_text(n):
		var c := n as Control
		var txt := _geometry_text(n)
		if txt.strip_edges() != "":
			rects.append(c.get_global_rect())
			names.append("%s(%s)" % [str(n.name), txt.substr(0, 10)])
			# "挤爆"：容器分给它的地方比它自己需要的还小 → 文字只能画出去
			var need := c.get_combined_minimum_size()
			if need.y > c.size.y + 0.5 or need.x > c.size.x + 0.5:
				squeezed.append("%s 需要(%d,%d) 实际(%d,%d)" % [
						str(n.name), int(need.x), int(need.y), int(c.size.x), int(c.size.y)])
	for ch in n.get_children():
		_geometry_collect(ch, panel, rects, names, squeezed)


func _geometry_is_text(n: Node) -> bool:
	return n is Label or n is Button or n is LineEdit or n is RichTextLabel


func _geometry_text(n: Node) -> String:
	if n is Label:
		return str((n as Label).text)
	if n is Button:
		return str((n as Button).text)
	if n is LineEdit:
		return str((n as LineEdit).text)
	if n is RichTextLabel:
		return str((n as RichTextLabel).text)
	return ""


# ---------------------------------------------------------------- 衣柜 · 只找密码盒（wardrobe_grab）
## 第四天拆成两段：先翻衣服拿密码盒（grab，**不输密码**），文案之后才轮到输密码
## （wardrobe_code）。这里只验证 grab 段：摸对口袋停在「获得密码盒：六位密码」屏，
## 屏上只有展示与「收好密码盒」，没有输入框；收好即关面板。
func _wardrobe_grab_checks(tree: SceneTree = null) -> void:
	if tree == null:
		tree = self
	var script_path := WEEK1_PANELS.script_for("wardrobe_grab")
	_check(script_path != "", "wardrobe_grab 在登记表里有脚本路径", script_path)
	if script_path == "" or not ResourceLoader.exists(script_path):
		return

	var host := Control.new()
	host.name = "WardrobeGrabProbeHost"
	tree.root.add_child(host)

	var p := Control.new()
	p.name = "WardrobeGrabProbe"
	p.set_script(load(script_path))
	p.call("setup", {"id": "wardrobe_grab"})
	host.add_child(p)
	await tree.process_frame
	await tree.process_frame

	# 摸对口袋：左起第三件红外套（下标 2）的右上袋（下标 1）
	p.call("_open_cloth", 2)
	p.call("_on_pocket_pressed", 1)
	await tree.process_frame
	var si := int(p.get("_screen_index"))
	_check(si == 2, "grab 模式摸对口袋后停在密码盒屏（不输密码）", "实测 _screen_index=%d" % si)

	# 「获得密码盒：六位密码」标题在屏上
	var found_text := ""
	var stack: Array[Node] = [p]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Label and str((cur as Label).text).contains("获得密码盒"):
			found_text = str((cur as Label).text)
			break
		for ch in cur.get_children():
			stack.append(ch)
	_check(found_text == "获得密码盒：六位密码", "grab 屏标题是「获得密码盒：六位密码」", found_text)

	# grab 屏**没有**输入框（密码留给后面的 wardrobe_code）
	var has_input := false
	stack = [p]
	while not stack.is_empty():
		var cur2: Node = stack.pop_back()
		if cur2 is LineEdit:
			has_input = true
			break
		for ch in cur2.get_children():
			stack.append(ch)
	_check(not has_input, "grab 屏不出现输入框（这里不要求输密码）")

	# 「收好密码盒」按钮：点了面板就收掉
	# （不写死节点路径：基类的 MarginContainer 运行时会被重命名为 @MarginContainer@N）
	var take: Variant = null
	var stk: Array[Node] = [p]
	while not stk.is_empty():
		var cur3: Node = stk.pop_back()
		if str(cur3.name) == "TakeBox" and cur3 is Button:
			take = cur3
			break
		for ch in cur3.get_children():
			stk.append(ch)
	_check(take != null and take is Button, "grab 屏有「收好密码盒」按钮")
	if take is Button:
		(take as Button).pressed.emit()
		await tree.process_frame
		_check(not bool(p.call("is_open")), "点「收好密码盒」后面板关闭（密码留给 wardrobe_code）")
	host.queue_free()


# ---------------------------------------------------------------- 读心术（1089）
##  回忆段 s4b_1089「1089 读心术」是第三天末、第四天前的一段回忆，两头都要量：
##    · 数学：solve_1089 / reverse3 / sum_1089 是纯函数，按表逐个核；
##    · 界面：四屏显隐切换，真的按玩家的走法点一遍（填数 → 相减 → 报数 → 揭晓 → 收尾）；
##      算式卡（["formula1089"]）改在整幕推进里断言：对话流真的弹过那张居中算式卡；
##    · 接线：登记表里有这一关、DAY_ONE_SEQS 把它夹在两关中间、json 里有且只有一条 panel 行。
func _mindread_checks(tree: SceneTree = null) -> void:
	if tree == null:
		tree = self

	# ---- ① 登记表里有这一关，脚本文件也真的在
	_check(WEEK1_PANELS.has_panel("mindread"), "读心术面板在登记表里（week1_panels.gd）")
	var script_path := WEEK1_PANELS.script_for("mindread")
	_check(script_path != "" and ResourceLoader.exists(script_path),
			"读心术面板的脚本文件确实存在", script_path)

	# ---- ② solve_1089 的数学表
	#      rev / diff / past / future 分开断言：挂了能一眼看出是哪一格错。
	var legal := {
		123: {"rev": 321, "diff": 198, "past": 1, "future": 8},
		456: {"rev": 654, "diff": 198, "past": 1, "future": 8},
		789: {"rev": 987, "diff": 198, "past": 1, "future": 8},
		591: {"rev": 195, "diff": 396, "past": 3, "future": 6},
	}
	for n in legal.keys():
		var want: Dictionary = legal[n]
		var r: Dictionary = MINDREAD_SCRIPT.solve_1089(int(n))
		var tail := str(r)
		_check(bool(r.get("ok", false)), "solve_1089(%d) 认这个数" % int(n), tail)
		_check(int(r.get("rev", -1)) == int(want["rev"]),
				"solve_1089(%d).rev = %d" % [int(n), int(want["rev"])], tail)
		_check(int(r.get("diff", -1)) == int(want["diff"]),
				"solve_1089(%d).diff = %d" % [int(n), int(want["diff"])], tail)
		_check(int(r.get("past", -1)) == int(want["past"]),
				"solve_1089(%d).past = %d" % [int(n), int(want["past"])], tail)
		_check(int(r.get("future", -1)) == int(want["future"]),
				"solve_1089(%d).future = %d" % [int(n), int(want["future"])], tail)

	# 非法的两类都要挡住：越界（99 / 1000）与「百位个位挨太近」（倒过来减只剩两位数）
	for bad in [100, 111, 191, 293, 99, 1000]:
		var rb: Dictionary = MINDREAD_SCRIPT.solve_1089(int(bad))
		_check(not bool(rb.get("ok", true)), "solve_1089(%d) 判为不合法" % int(bad), str(rb))

	# ---- ③ sum_1089 对每一个合法 diff 都恒为 1089；顺带核 reverse3
	_check(MINDREAD_SCRIPT.reverse3(123) == 321, "reverse3(123) = 321",
			str(MINDREAD_SCRIPT.reverse3(123)))
	var diffs := [198, 297, 396, 495, 594, 693, 792, 891]
	for d in diffs:
		var s: int = MINDREAD_SCRIPT.sum_1089(int(d))
		_check(s == 1089, "sum_1089(%d) = 1089" % int(d), "实测 %d" % s)

	# 把 100..999 全扫一遍：只要 solve_1089 认了，diff 就必须落在上面那八个里、
	# 十位必须是 9、加起来必须是 1089 —— 这才是「1089 的把戏」真正成立的范围。
	var sweep_ok := true
	var sweep_diff_ok := true
	for n2 in range(100, 1000):
		var rs: Dictionary = MINDREAD_SCRIPT.solve_1089(n2)
		if not bool(rs.get("ok", false)):
			continue
		var dv := int(rs["diff"])
		var rv := int(rs["rev"])
		if dv != absi(n2 - rv) or rv != MINDREAD_SCRIPT.reverse3(n2):
			sweep_ok = false
		if not diffs.has(dv) or (dv / 10) % 10 != 9 or MINDREAD_SCRIPT.sum_1089(dv) != 1089:
			sweep_diff_ok = false
	_check(sweep_ok, "100..999 里所有合法数的 rev / diff 都对得上（含 100、1000 的边界）")
	_check(sweep_diff_ok, "100..999 里所有合法数的 diff 都落在那八个里且加起来是 1089")

	# ---- ④ 章节顺序：s4b_1089 夹在 s3_desk 与 s4_soup 中间（第三天末的回忆）
	var day_one: Array = []
	var cm: Dictionary = (load(WEEK1_1_PATH) as GDScript).get_script_constant_map()
	if cm.has("DAY_ONE_SEQS"):
		day_one = cm["DAY_ONE_SEQS"]
	var i_desk := day_one.find("s3_desk")
	var i_recall := day_one.find("s4b_1089")
	var i_soup := day_one.find("s4_soup")
	_check(i_recall >= 0, "week1_1.gd 的 DAY_ONE_SEQS 里有 s4b_1089", str(day_one))
	_check(i_desk >= 0 and i_recall == i_desk + 1, "s4b_1089 紧跟在 s3_desk 后面", str(day_one))
	_check(i_recall >= 0 and i_soup == i_recall + 1, "s4_soup 又紧跟在 s4b_1089 后面", str(day_one))

	# ---- ⑤ 对话数据：s4b_1089 里 1089 游戏改成了"对话框式"——
	#      不再弹整屏面板 ["panel", "mindread"]；取而代之一条 ["mindread_input"]
	#      （输一位数）与一条 ["mindread_reveal"]（输完回对话框由刘忆揭晓）。
	var data: Variant = _read_json(DATA)
	var chap: Variant = (data as Dictionary).get(CHAPTER, null) if data is Dictionary else null
	var rows: Variant = (chap as Dictionary).get("s4b_1089", null) if chap is Dictionary else null
	_check(rows is Array, "week1.s4b_1089 在 week1_dialogue.json 里")
	_check(rows is Array and (rows as Array).size() >= 1 \
			and (rows as Array)[0] is Array and (rows as Array)[0].size() >= 2 \
			and str((rows as Array)[0][0]) == "space",
			"1089 回忆开头的「1089回忆」标题卡已删，段首直接黑屏进教室", str((rows as Array)[0] if rows is Array and not (rows as Array).is_empty() else ""))
	var panel_rows := 0
	var input_rows := 0
	var reveal_rows := 0
	var input_pos := -1
	var reveal_pos := -1
	if rows is Array:
		for i in (rows as Array).size():
			var rr: Variant = (rows as Array)[i]
			if not (rr is Array) or (rr as Array).is_empty():
				continue
			var k := str((rr as Array)[0])
			if k == "panel" and (rr as Array).size() >= 2 and str((rr as Array)[1]) == "mindread":
				panel_rows += 1
			elif k == "mindread_input":
				input_rows += 1
				input_pos = i
			elif k == "mindread_reveal":
				reveal_rows += 1
				reveal_pos = i
	_check(panel_rows == 0, "s4b_1089 不再弹整屏面板（[\"panel\", \"mindread\"] 已删）", "实测 %d 条" % panel_rows)
	_check(input_rows == 1, "s4b_1089 里恰好一条 [\"mindread_input\"]", "实测 %d 条" % input_rows)
	_check(reveal_rows == 1, "s4b_1089 里恰好一条 [\"mindread_reveal\"]", "实测 %d 条" % reveal_rows)
	_check(input_pos >= 0 and reveal_pos == input_pos + 2,
			"输入（mindread_input）之后一句台词、再紧接揭晓（mindread_reveal）",
			"输入行 %d / 揭晓行 %d" % [input_pos, reveal_pos])

	# 算式行：["formula1089"] 必须紧跟在那句「答案一定是1089，对吧。」之后
	var line_pos := -1
	var formula_pos := -1
	if rows is Array:
		for i in (rows as Array).size():
			var rr: Variant = (rows as Array)[i]
			if rr is Array and (rr as Array).size() >= 1 and str((rr as Array)[0]) == "formula1089":
				formula_pos = i
			elif rr is Array and (rr as Array).size() >= 3 and str((rr as Array)[0]) == "d" \
					and str((rr as Array)[2]).contains("1089"):
				line_pos = i
	_check(line_pos >= 0 and formula_pos == line_pos + 1,
			"「…答案一定是1089，对吧。」后面紧跟 [\"formula1089\"] 算式行",
			"台词行 %d / 算式行 %d" % [line_pos, formula_pos])

	# ---- ⑥ 运行时认得新行类型；整条"输入 → 揭晓 → 算式卡"的行为由
	#      主流程"一路点到幕间"里的 submit_mindread_input 实际走一遍验证。
	var rt_src := ""
	var rt_file := FileAccess.open("res://scripts/ui/dialogue_runtime.gd", FileAccess.READ)
	if rt_file != null:
		rt_src = rt_file.get_as_text()
		rt_file.close()
	_check(rt_src.contains("\"mindread_input\"") and rt_src.contains("\"mindread_reveal\""),
			"dialogue_runtime.gd 认得 mindread_input / mindread_reveal 两种行")
	_check(rt_src.contains("_reveal_pending") and rt_src.contains("append_line") \
			and rt_src.contains("我猜的没错吧？"),
			"运行时把揭晓四句做成同一页逐句展开（append_line），并在末尾单独插一页「我猜的没错吧？」")


# ---------------------------------------------------------------- 静态检查

func _static_checks() -> void:
	var data: Variant = _read_json(DATA)
	_check(data is Dictionary, "week1_dialogue.json 能解析成字典")
	if not (data is Dictionary):
		return
	var chap: Variant = (data as Dictionary).get(CHAPTER, null)
	_check(chap is Dictionary, "里有 chapter 键 %s" % CHAPTER)
	if not (chap is Dictionary):
		return
	var rooms_data: Variant = _read_json(ROOMS)
	var room_items: Dictionary = {}
	# Godot 4 的 GDScript 是块级作用域：rooms 声明在 if 里外面就用不了，
	# 所以提到函数作用域（行为不变：读不到就保持空字典）。
	var rooms: Variant = {}
	if rooms_data is Dictionary:
		rooms = (rooms_data as Dictionary).get("rooms", {})
		if rooms is Dictionary:
			for rid in (rooms as Dictionary).keys():
				var it: Array = []
				var rv: Variant = (rooms as Dictionary)[rid]
				if rv is Dictionary and (rv as Dictionary).get("items", null) is Array:
					for it_row in ((rv as Dictionary)["items"] as Array):
						# 兼容两种格式（与 room_runtime.gd 一致）：直接数组，
						# 或 {value: 数组, Count: 数字} 的字典格式。
						var ia: Array
						if it_row is Dictionary:
							ia = (it_row as Dictionary).get("value", []) as Array
						else:
							ia = it_row as Array
						if ia.size() >= 6:
							it.append(str(ia[5]))
				room_items[str(rid)] = it
	_check(room_items.has("dorm_room"), "prelude_rooms.json 里有 dorm_room")
	_check(room_items.has("dorm_room_d1b"),
			"第一天宿舍变体 dorm_room_d1b 存在")
	_check((chap as Dictionary).size() > 0, "chapter 里有序列")

	var panel_ids: Array = []
	var goal_names: Array = []
	for sid in SEQS:
		var rows: Variant = (chap as Dictionary).get(sid, null)
		_check(rows is Array, "序列 %s 存在" % sid)
		if not (rows is Array):
			continue
		# 第一遍：收集本序列出现的全部房间 id。goal 行可能写在 room 行**之前**
		# （备份 zip 的原始顺序就是 goal → room），所以"目标在不在房间 items 里"
		# 只能等房间全收集完再判，不能依赖"上一条 room 行"。
		var seq_rooms: Array = []
		for rr in (rows as Array):
			if rr is Array and (rr as Array).size() >= 2 and str((rr as Array)[0]) == "room":
				seq_rooms.append(str((rr as Array)[1]))
		var room_id := ""
		var peeks: Array = []
		for i in (rows as Array).size():
			var r: Variant = (rows as Array)[i]
			if not (r is Array) or (r as Array).is_empty():
				continue
			var a := r as Array
			var kind := str(a[0])
			match kind:
				"panel":
					var pid := str(a[1])
					panel_ids.append(pid)
					_check(WEEK1_PANELS.has_panel(pid), "面板 %s 在登记表里" % pid)
					var sp := WEEK1_PANELS.script_for(pid)
					_check(sp != "" and ResourceLoader.exists(sp), "面板 %s 的脚本文件存在" % pid, sp)
				"room":
					room_id = str(a[1])
					_check(room_items.has(room_id), "房间 %s 在 prelude_rooms.json 里" % room_id)
					peeks = []
				"goal":
					var gname := str(a[1])
					goal_names.append(gname)
					var in_room := false
					for rid2 in seq_rooms:
						if ((room_items.get(rid2, []) as Array)).has(gname):
							in_room = true
							break
					_check(in_room,
							"目标物件「%s」确实在本序列房间 %s 的 items 里" % [gname, str(seq_rooms)])
				"peek":
					peeks.append(str(a[1]))
					var in_room2 := false
					for rid2 in seq_rooms:
						if ((room_items.get(rid2, []) as Array)).has(str(a[1])):
							in_room2 = true
							break
					_check(in_room2,
							"peek 物件「%s」确实在本序列房间 %s 的 items 里" % [str(a[1]), str(seq_rooms)])
				"space":
					_check(SPACES.has(str(a[1])), "背景键 %s 有效" % str(a[1]))
				"shot":
					_check(SPACES.has(str(a[1])), "分镜帧背景键 %s 有效" % str(a[1]))
				"choice":
					# 面板可以嵌在选项分支里（第二天「我要输入密码」分支里弹 code 面板），
					# 分支内的面板也要收进顺序断言。
					_collect_panels_in(r, panel_ids, sid, i)
				"title", "n", "m", "d", "card", "show", "hide", "who", "item", "free", "formula1089", "mindread_input", "mindread_reveal":
					pass
				_:
					_check(false, "序列 %s 第 %d 行是未知行类型 %s" % [sid, i, kind])
	# 「我再想想」重试会把 code 面板的行重复一份（choice 分支里内嵌同样的分支），
	# 去重后才是玩家真正走到的面板流：memo → code → desk → soup →
	# wardrobe_grab（找密码盒，不输密码）→ wardrobe_code（输密码）。
	# 1089 回忆段已改"对话框式"输入（mindread_input），不再是面板。
	var deduped: Array = []
	for pid in panel_ids:
		if deduped.is_empty() or deduped[deduped.size() - 1] != pid:
			deduped.append(pid)
	_check(deduped == ["memo", "code", "desk", "soup", "wardrobe_grab", "wardrobe_code"],
			"一整幕里六个对话行面板的顺序对（黑箱迷宫/手势密码/书架九本书从走位里弹，1089 回忆是对话框式输入）", str(deduped))
	_check(goal_names == ["黑箱", "手机", "书架", "刘忆的书桌", "刘忆的书桌"],
			"五次走位的目标顺序对（第三天找不同后的 d3b 宿舍场景已删；撕下来的纸与初遇回忆直接播）", str(goal_names))

	# 第二天书架解谜面板由走位里的书架物品（open_panel:bookshelf 标签）直接弹出：
	# 交互书架即见一排书，点书脊看作家名字和国家、输入谐音数字；解出 053714 后
	# room_runtime 的 _on_walk_panel_finished 直接 _on_done 切回对话（不回到宿舍）。
	var bookshelf_tag_ok := false
	if (rooms as Dictionary).has("dorm_room_d2"):
		var d2: Variant = (rooms as Dictionary)["dorm_room_d2"]
		if d2 is Dictionary and (d2 as Dictionary).get("items", null) is Array:
			for it_row in ((d2 as Dictionary)["items"] as Array):
				# 兼容数组 / {value, Count} 两种物品格式（与 room_runtime.gd 一致）
				var ia: Array
				if it_row is Dictionary:
					ia = (it_row as Dictionary).get("value", []) as Array
				else:
					ia = it_row as Array
				if ia.size() > 9 \
						and str(ia[5]) == "书架" \
						and str(ia[9]) == "open_panel:bookshelf":
					bookshelf_tag_ok = true
	_check(bookshelf_tag_ok, "dorm_room_d2 的书架物品带 open_panel:bookshelf 标签（交互直接弹书架解谜面板）")

	# 第三天自由探索：房间配 free_explore → 走位里「看完了（自由探索）」，
	# 点过任意一件就能离开，不逼着把每件都看完。
	var d3a_free := false
	if (rooms as Dictionary).has("dorm_room_d3a"):
		var d3a_v: Variant = (rooms as Dictionary)["dorm_room_d3a"]
		if d3a_v is Dictionary and bool((d3a_v as Dictionary).get("free_explore", false)):
			d3a_free = true
	_check(d3a_free, "dorm_room_d3a 配了 free_explore（第三天自由探索不强制看完）")
	# 第四天海龟汤前的宿舍探索（dorm_room）：自由探索 + free_exit，
	# 「看完了（自由探索）」一件没看也能直接退出。
	var d4_free_exit := false
	if (rooms as Dictionary).has("dorm_room"):
		var d4_v: Variant = (rooms as Dictionary)["dorm_room"]
		if d4_v is Dictionary and bool((d4_v as Dictionary).get("free_exit", false)):
			d4_free_exit = true
	_check(d4_free_exit, "dorm_room 配了 free_exit（第四天自由探索一件没看也能点「看完了」退出）")
	# s3_desk：自由探索不再补播衣柜/卫生间/室友的桌子的文案页；
	# 走位回来先黑屏显示「【刘忆的桌子】之前是什么样的呢？」再进找不同面板。
	var s3: Variant = (chap as Dictionary).get("s3_desk", null)
	var s3_has_old_peeks := false
	var s3_has_desk_lead := false
	var s3_has_any_peek := false
	var s3_has_d3b_walk := false
	var s3_has_memory_inline := false
	if s3 is Array:
		for r in (s3 as Array):
			if r is Array and not (r as Array).is_empty():
				var a := r as Array
				if str(a[0]) == "peek":
					s3_has_any_peek = true
					if ["衣柜", "卫生间", "室友的桌子"].has(str(a[1])):
						s3_has_old_peeks = true
				if str(a[0]) == "room" and str(a[1]) == "dorm_room_d3b":
					s3_has_d3b_walk = true
				if str(a[0]) == "n" and str(a[1]).contains("之前是什么样的呢"):
					s3_has_desk_lead = true
				if str(a[0]) == "d" and str(a[1]) == "李星" and str(a[2]).contains("这是推理社的纪念品吧"):
					s3_has_memory_inline = true
	_check(not s3_has_old_peeks, "s3_desk 不再有衣柜/卫生间/室友的桌子的补播文案页")
	_check(not s3_has_any_peek, "s3_desk 里没有走位补播（peek）行了（撕下来的纸与初遇回忆直接播）")
	_check(not s3_has_d3b_walk, "s3_desk 不再进 dorm_room_d3b 宿舍场景（找不同后的交互已删）")
	_check(s3_has_memory_inline, "找不同后直接播「……这是推理社的纪念品吧。」的初遇回忆（不再走位触发）")
	_check(s3_has_desk_lead, "s3_desk 里有一句「【刘忆的桌子】之前是什么样的呢？」的黑屏过渡句")

	# 一周目重排为四天后没有收尾段：旧 s6_ending / s5_wardrobe / s2_books 都已移除，
	# 四天播完直接进二周目。
	_check(not (chap as Dictionary).has("s6_ending"), "week1_dialogue.json 里不再有 s6_ending")
	_check(not (chap as Dictionary).has("s5_wardrobe"), "week1_dialogue.json 里不再有 s5_wardrobe")
	_check(not (chap as Dictionary).has("s2_books"), "week1_dialogue.json 里不再有 s2_books")


## 递归收集选项分支里的面板行（分支里不会换房间/目标，只关心面板与行类型合法）。
func _collect_panels_in(r: Variant, panel_ids: Array, sid: String, i: int) -> void:
	if not (r is Array) or (r as Array).is_empty():
		return
	var a := r as Array
	var kind := str(a[0])
	match kind:
		"panel":
			var pid := str(a[1])
			panel_ids.append(pid)
			_check(WEEK1_PANELS.has_panel(pid), "面板 %s 在登记表里" % pid)
			var sp := WEEK1_PANELS.script_for(pid)
			_check(sp != "" and ResourceLoader.exists(sp), "面板 %s 的脚本文件存在" % pid, sp)
		"choice":
			for br in (a[3] as Array):
				for sub in (br as Array):
					_collect_panels_in(sub, panel_ids, sid, i)
		"room", "goal", "peek", "space", "shot":
			pass
		"title", "n", "m", "d", "card", "show", "hide", "who", "item", "free", "formula1089", "mindread_input", "mindread_reveal":
			pass
		_:
			_check(false, "序列 %s 的 choice 分支里（第 %d 行）有未知行类型 %s" % [sid, i, kind])


# ---------------------------------------------------------------- 工具

## 行类型序列（["n", …] → "n"），用来断言某一段里有没有某类行。
func _kinds(rows: Variant) -> Array:
	var out: Array = []
	if rows is Array:
		for r in (rows as Array):
			if r is Array and not (r as Array).is_empty():
				out.append(str((r as Array)[0]))
	return out


func _has_kind(rows: Variant, kind: String) -> bool:
	return _kinds(rows).has(kind)


## 把一个节点（Label，或含 Label 的容器）上的文字都收起来，
## 用来断言"幕间提示 / 标题卡上写的到底是什么"。
func _title_text(node: Variant) -> String:
	var out: Array = []
	_collect_texts(node, out)
	return " | ".join(out)


## 读对话框正文（DialogueBox 的 RichTextLabel）当前显示的整页文本。
func _dbox_text(rt: Node) -> String:
	if rt == null:
		return ""
	var dbox: Variant = rt.get("_dbox")
	if dbox == null:
		return ""
	var rtl: Variant = dbox.get("_text")
	if rtl == null:
		return ""
	return str((rtl as RichTextLabel).text)


func _collect_texts(node: Variant, out: Array) -> void:
	if not (node is Node):
		return
	var n := node as Node
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_texts(c, out)


func _check(cond: bool, label: String, detail := "") -> void:
	_checks += 1
	var tail := ("（%s）" % detail) if detail != "" else ""
	if cond:
		print("  ✓ ", label, tail)
	else:
		_fails += 1
		print("  ✗ ", label, tail)


## 在面板里按名字找控件（读心术那一关的节点名是固定的：Step1Continue / Step3Box …）。
## 找不到返回 null，调用方自己判 —— 断言挂了要能看出是"节点没建出来"还是"值不对"。
func _node(root_node: Node, node_name: String) -> Node:
	if root_node == null:
		return null
	if str(root_node.name) == node_name:
		return root_node
	for c in root_node.get_children():
		var hit := _node(c, node_name)
		if hit != null:
			return hit
	return null


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)


func _line_text(row: Variant) -> String:
	if not (row is Array) or (row as Array).is_empty():
		return ""
	var a := row as Array
	match str(a[0]):
		"n", "m", "card":
			return str(a[1]) if a.size() >= 2 else ""
		"d":
			return str(a[2]) if a.size() >= 3 else ""
	return ""


func _first_peek_line(item_name: String, seq_id: String = "") -> String:
	var data: Variant = _read_json(DATA)
	if not (data is Dictionary):
		return ""
	var chap: Variant = (data as Dictionary).get(CHAPTER, null)
	if not (chap is Dictionary):
		return ""
	var scopes: Array = [seq_id] if seq_id != "" else []
	if seq_id == "":
		scopes = (chap as Dictionary).keys()
	for key in scopes:
		var rows: Variant = (chap as Dictionary).get(key, null)
		if not (rows is Array):
			continue
		for r in (rows as Array):
			if not (r is Array) or (r as Array).size() < 3:
				continue
			var a := r as Array
			if str(a[0]) != "peek" or str(a[1]) != item_name:
				continue
			if not (a[2] is Array):
				continue
			for inner in (a[2] as Array):
				var t := _line_text(inner)
				if t != "":
					return t
	return ""
