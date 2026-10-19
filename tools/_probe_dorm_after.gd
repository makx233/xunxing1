extends SceneTree
## 验证：二周目寝室走位（dorm_after）与一周目寝室（dorm_room）三项统一性
##  ① 背景＝同一张贴图底  ② F12 布置模式可用  ③ 没有第二人物（actor_a）
var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	print("—— 二周目寝室 vs 一周目寝室 统一性自检 ——")
	for rid in ["dorm_room", "dorm_after"]:
		var rt := Control.new()
		rt.set_script(load("res://scripts/ui/room_runtime.gd"))
		rt.call("configure", rid)
		root.add_child(rt)
		await process_frame
		await process_frame
		var room: Dictionary = rt.get("room")
		var bd: Control = rt.get_node_or_null("RoomBackdrop")
		var img_active := false
		if bd != null:
			var dr: Object = bd.get("_room_draw")
			if dr != null and dr.has_method("_backdrop_active"):
				img_active = bool(dr.call("_backdrop_active"))
		_check(room.get("title", "") == "寝室", "%s 标题=寝室" % rid)
		_check(img_active, "%s 贴图底背景生效（与一周目同图）" % rid)
		var actors: Array = room.get("actor_a", []) as Array
		_check(actors.size() < 2, "%s 无第二人物（actor_a=%s）" % [rid, str(actors)])
		var items: Array = rt.get("_items")
		_check(items.size() >= 9, "%s 物品 %d 件" % [rid, items.size()])
		# F12 布置模式：发送 F12 键事件
		rt.call("_unhandled_input", _key(KEY_F12))
		await process_frame
		_check(bool(rt.get("_edit_mode")), "%s F12 布置模式可开启" % rid)
		rt.call("_unhandled_input", _key(KEY_F12))
		await process_frame
		_check(not bool(rt.get("_edit_mode")), "%s F12 布置模式可关闭" % rid)
		var ov: Dictionary = rt.get("_overrides")
		var my_ov: Dictionary = ov.get(rid, {}) as Dictionary
		print("   %s 覆盖项：%s" % [rid, str(my_ov.keys())])
		rt.queue_free()
		await process_frame
	print("—— 共 %d 项，失败 %d 项 ——" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _key(kc: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = kc
	ev.pressed = true
	return ev


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)
