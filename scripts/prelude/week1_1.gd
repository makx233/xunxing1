extends "res://scripts/prelude/prelude_base.gd"
## ============================================================================
##  《寻星》一周目（游戏最开头的一幕）
## ============================================================================
##  按最终文案（《新建 DOC 文档》）重排为四天：
##    第一天（s0_maze）：走廊 → 寝室 → 自由探索寝室 → 挑战开场 →
##                       激光迷宫（黑箱）+ 手势密码（手机）
##    第二天（s1_phone）：备忘录罗马数字凯撒密码（JAPAN）→ 书架九本书 053714
##                        → 告诉刘忆六位数字密码
##    第三天（s3_desk）：找不同 → 撕下来的纸 / 笑脸摆件（推理社初遇回忆）
##    回忆（s4b_1089）：第三天末黑屏后的「1089 读心术」（面板 id 是 mindread）
##    第四天（s4_soup）：海龟汤 → 衣柜密码盒 053714 → 「再见啦，李小星。」→ End·迷途
##
##  【新链】四天 + 校园衔接段（End·迷途 之后的空镜头：教学楼→路面→寝室楼爬楼→6F 门开）
##  播完 **直接进【二周目】**（week2_1.tscn）。前日谈已整体移除；
##  跳转二周目之前立起 prelude_done 标记（历史兼容标记，二周目侧仍会读它），
##  二周目播完一律回标题。
## ============================================================================

## 二周目场景（衔接段播完直接进这里）
const WEEK2_SCENE := "res://scenes/week2/week2_1.tscn"

## 「前日谈已经演过」标记的键名（一周目跳转二周目时立起）。
const PRELUDE_DONE_FLAG := "prelude_done"

## 一周目四天 + 回忆段：s4b_1089 是第三天末、第四天前的「1089 读心术」回忆。
const DAY_ONE_SEQS := ["s0_maze", "s1_phone", "s3_desk", "s4b_1089", "s4_soup"]


func data_path() -> String:
	return "res://data/week1_dialogue.json"


func chapter_id() -> String:
	return "week1"


## 这一幕要播的段：四天 + 1089 回忆，一路播完直接进二周目。
## 标题页"章节选择"可以从任意一段快捷进入（_quick_trim 截断序列）。
func chapter_sequences() -> Array:
	return _quick_trim(DAY_ONE_SEQS)


func return_scene() -> String:
	return "res://scenes/week1/week1_1.tscn"


## 这一幕播完之后接哪一幕（探针直接断言这个函数，不用真的切场景）。
func next_scene_after_chapter() -> String:
	return WEEK2_SCENE


func _on_chapter_end() -> void:
	if runtime != null:
		runtime.visible = false
	# 四天 + 衔接段播完（6F 门打开全白之后）→ 直接进二周目
	_show_intermission("一周目结束   ·   点击 / 空格  进入二周目", _goto_next_scene)


func _goto_next_scene() -> void:
	# 立起 prelude_done（历史兼容标记），二周目侧仍会读它。
	PreludeState.set_flag(PRELUDE_DONE_FLAG, true)
	# 不 reset：一周目的笔记（笔记 Tab）带进二周目，玩家才有"我查过一遍了"的连续性。
	get_tree().change_scene_to_file(next_scene_after_chapter())
