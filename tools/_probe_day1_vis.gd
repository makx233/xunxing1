extends SceneTree
## ============================================================================
##  临时探针：验证第一天三样物品在走位场景里可见（vis=1 + ITEM_TEX 贴图加载）
##  验完即删。
## ============================================================================

const WALK_SCENE := "res://scenes/prelude/prelude_walk.tscn"

var _fails := 0
var _checks := 0


func _check(ok: bool, name: String, extra: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  ✗ %s%s" % [name, ("  ——  " + extra) if extra != "" else ""])
	else:
		print("  ✓ %s" % name)


func _initialize() -> void:
	_run()


func _walk(room_id: String) -> Node:
	var st := root.get_node_or_null("PreludeState")
	st.call("reset")
	st.call("set_flag", "walk_room", room_id)
	st.call("set_flag", "walk_goal_active", "黑箱")
	st.call("set_flag", "walk_return_scene", "res://scenes/week1/week1_1.tscn")
	st.call("set_flag", "walk_chapter", "week1")
	st.call("set_flag", "walk_during_examined", [])
	var sc := (load(WALK_SCENE) as PackedScene).instantiate()
	root.add_child(sc)
	await process_frame
	await process_frame
	return sc.get_node_or_null("RoomRuntime")


func _run() -> void:
	await process_frame
	print("========== 第一天物品可见性 探针 ==========")
	for rid in ["dorm_room_d1a", "dorm_room_d1b"]:
		var rt: Node = await _walk(rid)
		_check(rt != null, "%s：走位场景建起" % rid, "" if rt != null else "RoomRuntime 缺失")
		if rt == null:
			continue
		# 1) 三样物品 vis == 1（有形常显，不再是靠近才显示）
		for nm in ["手机", "黑箱", "折纸星星"]:
			var found := false
			for d in (rt.get("_items") as Array):
				if str((d as Dictionary).get("name", "")) == nm:
					found = true
					_check(int((d as Dictionary).get("vis", -1)) == 1,
							"%s：「%s」vis=1 常显" % [rid, nm],
							str((d as Dictionary).get("vis", -1)))
					break
			if not found:
				_check(false, "%s：找不到「%s」物品" % [rid, nm])
		# 2) 绘制脚本 prelude_room_draw.gd 的 ITEM_TEX 里注册了三样图标
		#    （RoomBackdrop 是 prelude_backdrop.gd，真正的绘制脚本在其常量 ROOM_DRAW_SCRIPT）
		var draw_script: Variant = load("res://scripts/ui/prelude_room_draw.gd")
		if not (draw_script is GDScript):
			_check(false, "%s：找不到绘制脚本 prelude_room_draw.gd" % rid)
		else:
			var consts: Dictionary = (draw_script as GDScript).get_script_constant_map()
			var texmap: Dictionary = consts.get("ITEM_TEX", {})
			for nm in ["手机", "黑箱", "折纸星星"]:
				var hit: bool = texmap.has(nm) and str(texmap[nm]).contains("assets/props/")
				_check(hit, "%s：ITEM_TEX 已注册「%s」图标" % [rid, nm],
						"" if hit else "未注册")
			# 3) 图标资源文件可被 Godot 加载
			for pth in ["res://assets/props/phone.png", "res://assets/props/black_box.png",
					"res://assets/props/paper_star.png"]:
				var tex: Variant = load(pth)
				_check(tex != null and (tex as Object).is_class("Texture2D"),
						"%s：资源可加载 %s" % [rid, pth.get_file()],
						"" if tex != null else "null")
		rt.call("queue_free")
		await process_frame
	print("=========================================")
	print("共 %d 项检查，失败 %d 项" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)

