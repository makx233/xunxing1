extends "res://scripts/prelude/prelude_base.gd"
## ============================================================================
##  《寻星》二周目 —— 重新调查那一天
## ============================================================================
##  八段（这里拆成七幕，因为"自白 + 现场"是一幕、"自白 + 马克杯回忆"是一幕）；
##  幕名与 data/week2_dialogue.json 里的键一一对应：
##    s0_scene      自白（B 不可能自杀）→ 回寝室调查现场（药瓶／药片／扫帚／杯子／阳台门／栏杆／照片）
##    s1_method     自白（这是人造的密室）→ 一周目的马克杯回忆（删去阳台部分）→ 推出地板斜向 → 推理问答（附录7）
##    s2_motive     自白：寻找他杀的动机（附录8）
##    s3_classroom  自白 → 去教室，与同学 C/D/E、班主任、宿管阿姨对话（附录9）→ 归纳
##    s4_alibi      自白 → 推理不在场证明与动机（结果：有时间的没动机，有动机的没时间）
##    s5_cup        自白 → 打翻马克杯，水在地上形成圆形 → 发现地板不是斜的 → 这是真正的密室
##    s6_truth      自白 → 明白 B 的死不是他杀（附录6 真相，由我代写）→ 情感寻星（结局）
##  结束后停在幕间：回标题页（全剧终）。前日谈已整体移除，
##  整条链是：一周目四天（week1_1）→ 二周目 → 标题页。
## ============================================================================

const TITLE_SCENE := "res://scenes/title/title.tscn"
## 「前日谈已经演过」标记的键名，与 scripts/prelude/week1_1.gd 里的同名常量必须一致。
const PRELUDE_DONE_FLAG := "prelude_done"


func data_path() -> String:
	return "res://data/week2_dialogue.json"


func chapter_id() -> String:
	return "week2"


func chapter_sequences() -> Array:
	return _quick_trim([
		"s0_scene",
		"s1_method",
		"s2_motive",
		"s3_classroom",
		"s4_alibi",
		"s5_cup",
		"s6_truth",
	])


func return_scene() -> String:
	return "res://scenes/week2/week2_1.tscn"


## 这一幕播完之后接哪一幕（探针直接断言这个函数，不用真的切场景）。
## 前日谈已移除：二周目播完一律回标题页（全剧终）。
func next_scene_after_chapter() -> String:
	return TITLE_SCENE


func _on_chapter_end() -> void:
	_show_intermission("第二天 结束   ·   点击 / 空格  回到标题", _goto_next_scene)


func _goto_next_scene() -> void:
	get_tree().change_scene_to_file(next_scene_after_chapter())
