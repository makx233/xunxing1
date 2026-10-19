extends SceneTree
## 临时调试：dump wardrobe_grab 面板的节点树，看 TakeBox 实际挂在哪儿

func _init() -> void:
	var script := load("res://scripts/week1/panel_wardrobe.gd")
	var p := Control.new()
	p.set_script(script)
	p.call("setup", {"id": "wardrobe_grab"})
	root.add_child(p)
	await process_frame
	await process_frame
	_dump(p, "")
	quit()


func _dump(n: Node, indent: String) -> void:
	var extra := ""
	if n is Label:
		extra = "  text=" + str((n as Label).text).substr(0, 20)
	elif n is Button:
		extra = "  text=" + str((n as Button).text)
	print("%s%s [%s]%s" % [indent, n.name, n.get_class(), extra])
	for ch in n.get_children():
		_dump(ch, indent + "  ")
