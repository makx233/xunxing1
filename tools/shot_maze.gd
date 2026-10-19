extends SceneTree
## headless 把「七色镜廊」面板渲染成 PNG：空棋盘 + 摆答案（含光路）。
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var st := root.get_node_or_null("PreludeState")
	if st != null:
		st.call("reset")

	var vp := SubViewport.new()
	vp.size = Vector2i(960, 600)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = true
	root.add_child(vp)

	var s: Script = load("res://scripts/week1/panel_maze.gd")
	var p = s.new()
	p.setup({"id": "maze"})
	vp.add_child(p)
	await process_frame
	await process_frame

	# 图 1：空棋盘（黑框 + 灰格 + 可放格小圈 + 三面预设黑镜 + 端口）
	await process_frame
	var img1: Image = vp.get_texture().get_image()
	img1.save_png("res://_shot_maze_empty.png")
	print("空棋盘已存 _shot_maze_empty.png")

	# 图 2：直接摆答案（绕过点击，不触发 _win 的延时关闭），点亮全部光路
	var ans := {}
	for c in p.SOL_MIRRORS.keys():
		if not p._is_preset(c):
			ans[c] = str(p.SOL_MIRRORS[c])
	p._placed = ans
	p._refresh()
	for i in 6:
		await process_frame
	var img2: Image = vp.get_texture().get_image()
	img2.save_png("res://_shot_maze_solved.png")
	print("答案棋盘已存 _shot_maze_solved.png")
	print("亮灯数 = %d（应为 7）" % p._lit_count())
	print("蓝光 S = %s" % str(p._blue_is_s()))
	quit(0)
