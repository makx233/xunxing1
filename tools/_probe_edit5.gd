extends SceneTree
## 四期·第二轮自检：贴图重裁（脚落地）、人物放大 1.5 倍、纵向移动限位、感应同步
const RUNTIME := "res://scripts/ui/room_runtime.gd"
const DRAW := "res://scripts/ui/prelude_room_draw.gd"

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	print("—— 四期·二轮自检 ——")
	await _test_sprites()
	await _test_yclamp()
	await _test_near()
	print("—— 共 %d 项，失败 %d 项 ——" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("  ✓ " + msg)
	else:
		_fails += 1
		print("  ✗ " + msg)


func _test_sprites() -> void:
	var dr: RefCounted = load(DRAW).new()
	for k in ["down", "up", "left", "right"]:
		var tex: Texture2D = dr.call("_load_player_tex", k)
		if tex == null:
			_check(false, "贴图 %s 可加载" % k)
			continue
		_check(tex.get_height() >= 1100 and tex.get_height() <= 1400,
			"贴图 lixing_%s 已重裁（%dx%d，脚落底）" % [k, tex.get_width(), tex.get_height()])
	# 人物高度常量已放大到 352（235 的 1.5 倍）
	_check(absf(float(dr.get("PLAYER_H")) - 352.0) < 0.5, "PLAYER_H=%s（1.5 倍放大）" % dr.get("PLAYER_H"))


func _test_yclamp() -> void:
	var rt := Control.new()
	rt.set_script(load(RUNTIME))
	rt.call("configure", "dorm_room")
	root.add_child(rt)
	rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	# 从地板中部往上走：脚点应停在 326（头不顶出画面），不会冲进墙面
	rt.set("_player", Vector2(700, 420))
	Input.action_press("prelude_walk_up")
	for i in 120:
		await process_frame
	Input.action_release("prelude_walk_up")
	var y := float((rt.get("_player") as Vector2).y)
	_check(y >= 325.5 and y <= 326.5, "持续按上：脚点停在 y=%.2f（限位 326，不进墙面）" % y)
	# 左右走不受影响（x 还能动）
	var x0 := float((rt.get("_player") as Vector2).x)
	Input.action_press("prelude_walk_right")
	for i in 60:
		await process_frame
	Input.action_release("prelude_walk_right")
	var x1 := float((rt.get("_player") as Vector2).x)
	_check(x1 > x0 + 10.0, "纵向限位不影响横向走动（x %.0f → %.0f）" % [x0, x1])
	rt.queue_free()


func _test_near() -> void:
	var rt := Control.new()
	rt.set_script(load(RUNTIME))
	rt.call("configure", "dorm_room")
	root.add_child(rt)
	rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	# 身体高度变大后，站在洞洞板下方仍命中；远处仍熄灭
	rt.set("_player", Vector2(1010, 480))
	rt.set("_near", {})
	rt.call("_update_near")
	_check(str((rt.get("_near") as Dictionary).get("name", "")) == "洞洞板",
		"放大后身体任一段感应仍命中洞洞板")
	rt.set("_player", Vector2(400, 600))
	rt.call("_update_near")
	_check((rt.get("_near") as Dictionary).is_empty(), "远处仍熄灭")
	rt.queue_free()
