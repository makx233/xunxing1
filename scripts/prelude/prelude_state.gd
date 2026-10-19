extends Node
## ============================================================================
##  《寻星》—— 跨场景共享状态（Autoload: PreludeState）
## ============================================================================
##  目前只负责李星的"记录卡 / 笔记页"内容。
##  用 Autoload 是为了周目之间 / 走位与对话之间切换时笔记不会丢。
## ============================================================================

## 记录卡内容列表（顺序即笔记页顺序）
var cards: Array = []

## 玩家已做的选择记录（key 是标记名，value 是选项值）——为后续幕预留
var flags: Dictionary = {}


## 俯视角走位里已查看过的物件名（按查看顺序）
var examined: Array = []

## 已经显示过的台词（玩家按「回看」翻的就是这一份）。
## 元素形如 {"who": "刘忆", "text": "……"}；跨场景保留，这样切一幕之后
## 还能往回翻到上一幕说过的话。
var history: Array = []


## 追加一行台词到回看记录（跨场景共享）
func push_history(who: String, text: String) -> void:
	history.append({"who": who, "text": text})
	# 上限只是防止长流程把内存吃满；400 行足够回看用了
	if history.size() > 400:
		history = history.slice(history.size() - 400, history.size())


## 追加一张记录卡，返回它的序号（1 起）
func add_card(text: String) -> int:
	cards.append(text)
	return cards.size()


## 走位场景里记下"这个物件看过了"（同名只记一次）
func note_examined(item_name: String) -> void:
	if not examined.has(item_name):
		examined.append(item_name)


func was_examined(item_name: String) -> bool:
	return examined.has(item_name)


func examined_count() -> int:
	return examined.size()


func has_card(text: String) -> bool:
	return cards.has(text)


func card_count() -> int:
	return cards.size()


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value


func get_flag(key: String, default_value: Variant = false) -> Variant:
	return flags.get(key, default_value)


## 【测试专用 · 项目收尾时删除】快捷键（P）用的直通车：跳过全部解密，直接进宿舍走位。
## 只立 walk_room 标记（prelude_walk 场景靠它选房间），不碰存档/其它旗标。
## 按键处理在 prelude_base.gd 与 title_screen.gd 的 _unhandled_input 里（都标了同一句），
## 收尾时把三处一起删掉即可。
func test_skip_to_dorm_walk() -> void:
	set_flag("walk_room", "dorm_room")
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file("res://scenes/prelude/prelude_walk.tscn")


## 回到标题 / 重开时清空
func reset() -> void:
	cards.clear()
	flags.clear()
	examined.clear()
	history.clear()
