extends SceneTree
## 渲染验证：把一周目宿舍（dorm_room）渲染成 PNG，
## 检查贴图替代黑框 / 马克杯隐藏 / 小纸片无影子 / 浅底标签 / 人物不挡标签。
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var st := root.get_node_or_null("PreludeState")
	if st != null:
		st.call("reset")

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = true
	root.add_child(vp)

	var rt = load("res://scripts/ui/room_runtime.gd").new()
	rt.call("configure", "dorm_room")
	vp.add_child(rt)
	for i in 4:
		await process_frame

	# 把玩家挪到小纸片（override 位置 1045,330）附近，验证靠近时标签在人物上层
	rt._player = Vector2(1045, 430)
	for i in 12:
		await process_frame

	var img: Image = vp.get_texture().get_image()
	img.save_png("res://_shot_dorm_items.png")
	print("near name = ", str(rt._near.get("name", "")))
	print("已存 _shot_dorm_items.png")
	quit(0)
