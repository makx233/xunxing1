extends Control
## ============================================================================
##  《寻星》前日谈 —— 俯视角走位运行时
## ============================================================================
##  玩法：玩家用 WASD / 方向键在房间里走，走到可交互物件附近时提示条浮出，
##        按空格（或点鼠标）打开"放大细节"弹窗，看完所有物件后按右下角返回对话。
##
##  设计原则（和 dialogue_runtime.gd 一致）：
##    · 所有节点在代码里 new 出来并直接持有强类型引用，不用 %UniqueName / 长路径 get_node，
##      从根本上避免 Node not found 与空引用。
##    · 【重要】"先 add_child，再 set_anchors_and_offsets_preset"必须写成
##      `node.set_anchors_and_offsets_preset(...)`（带接收者）——不带接收者时它作用于 self，
##      会把运行时自己改成 TOP_WIDE 之类，子节点反而没布局，表现为"弹窗挤成一条竖条"。
##    · 自己设死 offset 的控件：先 preset，再赋 offset。
##
##  数据来源：
##    · res://data/prelude_rooms.json —— 房间（地板可走区、固定陈设、可交互物件）
##    · 物件名与详情必须和对话数据里的 ["item", ...] / ["peek", ...] 完全一致
## ============================================================================

const ROOMS_PATH := "res://data/prelude_rooms.json"
const BACKDROP_SCRIPT := "res://scripts/ui/prelude_backdrop.gd"
## 布置模式（F12）保存的坐标覆盖：{房间id: {物品名: [x, y, w, h]}}
const OVERRIDES_PATH := "res://data/room_item_overrides.json"
const EDIT_KEY := KEY_F12
## 兜底：走位完成但没有登记返回场景时退回的主对话场景（前日谈已移除，回一周目）
const DIALOGUE_FALLBACK := "res://scenes/week1/week1_1.tscn"

## 有贴图就用贴图，没有就退回代码占位（出图之后放对路径即可，不改代码）
const PLAYER_TEX_CANDIDATES := [
	"res://assets/sprites/lixing_down.png",
	"res://assets/sprites/lixing.png",
]
const LIUYI_TEX_CANDIDATES := [
	"res://assets/sprites/liuyi_down.png",
	"res://assets/sprites/liuyi.png",
]

const DEFAULT_SCALE := 1.0
## 走路速度：走廊逻辑宽 2400，250 px/s 走一遍约 9.6 秒，不至于让人等得不耐烦
const WALK_SPEED := 250.0
## 人物的"身体半径"：新的俯视角人物约两格高（180 逻辑像素），
## 脚点判定要按这个尺度偏下去，否则走到物件正下方会被判成"太远"。
const PLAYER_BODY_R := 48.0

## 交互半径的宽松系数：判定距离 = reach × 这个系数。
## 【关键】距离不再是"脚点到物件中心的直线距离"，而是"脚点到**物件矩形**的距离"，
## 所以这个系数就是"在物件外多近算身边"：1.15 × reach（reach 一般是 130~160 逻辑像素），
## 也就是人物往前走一到两格就能触发；再叠加"身体任一段"判定（脚点到头顶一整条都算），
## 只要人物的任何部位够得着就亮提示（用户要求：扩大感应范围）。
const NEAR_FACTOR := 1.15
## 迟滞：已经选中的物件要走出 1.18 倍距离才会失去高亮，
## 免得两个物件的判定圈交界处提示反复闪。
const NEAR_HYST := 1.18
## 人物身体高度（与绘制层 PLAYER_H=352 一致）：脚点到头顶一整条都算“任一部位”。
const BODY_H := 352.0
## 脚点最低允许值：人物放大后站在地板最上排时头会顶出画面，
## 所以把可走带顶部再收一段（352 - 顶部留白 26 ≈ 326），人物不能随意往上走。
const PLAYER_Y_MIN := 326.0

signal walk_finished()

var room_id := ""
var room: Dictionary = {}

var _walk_rects: Array = []      # 可走矩形（逻辑坐标）
var _items: Array = []           # 可交互物件
var _props: Array = []           # 固定陈设
var _solids: Array = []          # 挡路的陈设（脚点不能踩进去）
var _goal_item := ""             # 本房间要求的"必看物件"名（空 = 要看完所有物件）
## 自由探索模式（房间数据 free_explore）：不设必看物件，点过任意一件就能按
## 「看完了（自由探索）」离开；第三天找不同前的寝室探索用这个。
var _free_explore := false
## 自由探索且"零件可退"（房间数据 free_exit=true）：第四天海龟汤前的宿舍探索，
## 一件没看也能直接按「看完了（自由探索）」退出（第三天仍要求点过任意一件）。
var _free_exit := false
## 走位完成门槛：`_on_done` 检查这个 flag（房间数据 gate_flag）——没满足就提示、
## 不离开走位。第一天第二次进宿舍用它保证"先解开黑箱迷宫才能按「看完了」"。
var _gate_flag := ""
var _gate_hint := ""

# ---------------------------------------------------------------- 状态
var _player := Vector2(600, 520)
var _facing := Vector2(0, 1)
var _bob := 0.0
var _near: Dictionary = {}       # 当前最近的可交互物件
var _popup_item: Dictionary = {}
var _popup := false
var _act_lock := 0.0            # 收起弹窗后的输入冷却，避免一次按键反复开合
var _examine_count := 0
## 走位里由物品直接弹出的谜题面板（第一天：点黑箱 → 七色镜廊迷宫）。
## 平时为 null；面板打开期间走位输入全部归它，完成/退出后回收。
var _walk_panel: Node = null

# ---------------------------------------------------------------- 节点
var _root: Control = null
var _backdrop: Control = null
var _hint: Label = null
# --- 布置模式（F12）：鼠标拖拽调整物品位置 ---
var _edit_mode := false
var _edit_sel := -1
var _drag_off := Vector2.ZERO
## 拖动模式：0=无，1=移动，2=改大小（拖右下角把手）
var _drag_mode := 0
var _overrides: Dictionary = {}
var _help: Label = null
var _popup_layer: Control = null
var _done_btn: Button = null
var _toast: Label = null
var _toast_t := 0.0
var _notes: PreludeUI.NotesPanel = null   # 走位里也能翻笔记（Kerry：要能随时查看全部笔记）
var _notes_btn: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_room()
	_build_ui()
	set_process(true)


## 宿主在 add_child 之前调用：指定要走的房间
func configure(p_room_id: String) -> void:
	room_id = p_room_id


# ============================================================================
#  数据
# ============================================================================

func _load_room() -> void:
	if room_id == "":
		push_error("[Walk] 没有指定房间 id")
		return
	if not FileAccess.file_exists(ROOMS_PATH):
		push_error("[Walk] 找不到房间数据：%s" % ROOMS_PATH)
		return
	var txt := FileAccess.get_file_as_string(ROOMS_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_error("[Walk] 房间数据不是合法的 JSON 对象")
		return
	var rooms: Dictionary = (parsed as Dictionary).get("rooms", {}) as Dictionary
	if not rooms.has(room_id):
		push_error("[Walk] 房间数据里没有这个房间：%s" % room_id)
		return
	room = (rooms[room_id] as Dictionary).duplicate(true)

	# 地板：新格式是墙高 + 地板行数 + 左右边界（单位＝格子），
	# 旧格式是若干个矩形 [x,y,w,h, ...]（并集），两种都支持。
	var fl: Array = room.get("floor", []) as Array
	if not fl.is_empty():
		var i := 0
		while i + 3 < fl.size():
			_walk_rects.append(Rect2(float(fl[i]), float(fl[i + 1]),
					float(fl[i + 2]), float(fl[i + 3])))
			i += 4
	else:
		var glyph := 96.0
		var wall_h := float(int(room.get("wall_rows", 3))) * glyph
		var fx := float(room.get("floor_x", 120.0))
		var fw := float(room.get("floor_w", 2160.0))
		var fh := float(int(room.get("floor_rows", 4))) * glyph
		# 可走带比地面略内缩，免得人物站到墙里或画到画面外
		_walk_rects.append(Rect2(fx + 10.0, wall_h + 8.0, fw - 20.0, fh - 16.0))

	# 固定陈设（在地面上、有厚度的东西）
	# 第 6 项可以是字符串（旧格式＝只写画法 kind），也可以是字典：
	#   {"kind": "rect", "solid": true}         → 拿自身矩形当碰撞体（略微内缩）
	#   {"kind": "rect", "solid": [x,y,w,h]}    → 拿给定矩形当碰撞体（比画面小一圈时用）
	# 【重要】默认 **不** 挡路：只有大型家具才写 solid（书架 / 柜台 / 衣柜 / 床 / 桌子），
	# 海报、便签、杯子这类小道具一律不挡路，否则人物会在细碎的地方被卡住。
	for p in (room.get("props", []) as Array):
		var pa: Array = p as Array
		var extra: Variant = pa[5] if pa.size() > 5 else null
		var kind := "rect"
		var solid: Variant = false
		if extra is Dictionary:
			var ed: Dictionary = extra
			kind = str(ed.get("kind", "rect"))
			solid = ed.get("solid", false)
		elif extra is String:
			kind = str(extra)
		_props.append({
			"x": float(pa[0]), "y": float(pa[1]),
			"w": float(pa[2]), "h": float(pa[3]),
			"label": str(pa[4]) if pa.size() > 4 else "",
			"kind": kind,
			"solid": solid,
		})

	# 嵌在墙上的东西（门 / 窗 / 柜）也交给绘制层，它是另一套画法
	# 第 6 项可选：字典，额外参数直接并进这条陈设（例如洞洞板的插板位置 shelves）
	for wl in (room.get("wall", []) as Array):
		var wa: Array = wl as Array
		if wa.size() < 3:
			continue
		var wd := {
			"kind": str(wa[0]),
			"x": float(wa[1]),
			"y": 0.0,
			"w": float(wa[2]),
			"h": float(wa[4]) if wa.size() > 4 else 168.0,
			"label": str(wa[3]) if wa.size() > 3 else "",
			"on_wall": true,
		}
		if wa.size() > 5 and wa[5] is Dictionary:
			for k in (wa[5] as Dictionary):
				wd[k] = (wa[5] as Dictionary)[k]
		_props.append(wd)

	# 挡路的陈设：只有数据里写了 solid 的大型家具（书架 / 柜台 / 衣柜 / 床 / 桌子）才挡路，
	# 人物要绕着走；海报、便签、杯子这类小道具不挡路。
	# 【说明】可交互物件（门牌、便签、地上的水渍…）**不**挡路——它们是"热区"不是障碍物，
	# 站到水渍上、贴着门牌站都是合理的；踩进桌子里就不合理了。
	for p in _props:
		var pd: Dictionary = p
		if bool(pd.get("on_wall", false)):
			continue
		var sp: Variant = pd.get("solid", false)
		if sp is bool:
			if not bool(sp):
				continue
			_solids.append(Rect2(float(pd["x"]) + 4.0, float(pd["y"]) + 6.0,
					maxf(8.0, float(pd["w"]) - 8.0), maxf(8.0, float(pd["h"]) - 6.0)))
		elif sp is Array and (sp as Array).size() >= 4:
			var sa: Array = sp
			_solids.append(Rect2(float(sa[0]), float(sa[1]),
					float(sa[2]), float(sa[3])))

	# 先读取目标物件，这样加载物品的时候就能判断手机是不是不能交互。
	# 目标名在进入走位时由 dialogue_runtime 挪进 walk_goal_active（walk_goal 会被清空），
	# 所以优先读 active，读不到再退回 walk_goal。
	var st: Node = get_node_or_null("/root/PreludeState")
	_goal_item = str(room.get("goal_item", ""))
	if st != null:
		var wg := str(st.get_flag("walk_goal_active", ""))
		if wg == "":
			wg = str(st.get_flag("walk_goal", ""))
		if wg != "":
			_goal_item = wg

	# 可交互物件：[x, y, w, h, reach, 名称, 详情, closeup路径]
	for it in (room.get("items", []) as Array):
		# 兼容两种格式：直接数组，或者 {value: 数组, Count: 数字} 的字典格式
		var ia: Array
		if it is Dictionary:
			ia = (it as Dictionary).get("value", []) as Array
		else:
			ia = it as Array
		if ia.size() < 7:
			continue
		var nm := str(ia[5])
		# 书后的折纸星星：只有书架解密完成之后才显示，解谜之前不显示
		if nm == "书后的折纸星星" and st != null:
			if st.call("get_flag", "week1_result_bookshelf", null) == null:
				continue
		var d := {
			"x": float(ia[0]), "y": float(ia[1]),
			"w": float(ia[2]), "h": float(ia[3]),
			"reach": float(ia[4]),
			"name": nm,
			"detail": str(ia[6]),
			"closeup": str(ia[7]) if ia.size() > 7 else "",
			"center": Vector2(float(ia[0]) + float(ia[2]) * 0.5,
					float(ia[1]) + float(ia[3]) * 0.5),
			# 交互框显示方式：1=有形（默认画黑框） 2=靠近时显示 0=隐形
			"vis": int(ia[8]) if ia.size() > 8 else 1,
			# 第 9 项：物品的特殊动作（第一天桌面物品用）：
			#   "open_panel:<面板id>" → 点它直接弹出小游戏面板（黑箱 → 迷宫）
			#   "collect_star"       → 弹窗带「先收起来吧」按键，点了把星星收进口袋
			"act": str(ia[9]) if ia.size() > 9 else "",
			"seen": false,
		}
		# 第一次走位（目标是黑箱）的时候，手机只是图片，不能交互
		if nm == "手机" and _goal_item == "黑箱":
			d["reach"] = 0.0
			d["act"] = ""
		if st != null and bool(st.call("get_flag", "seen_" + nm, false)):
			d["seen"] = true
			_examine_count += 1
		_items.append(d)

	# 布置模式保存过的坐标覆盖（data/room_item_overrides.json）优先于基础数据
	_apply_overrides()

	# 强制重新读取目标，确保第一次走位的目标是黑箱
	var st2: Node = get_node_or_null("/root/PreludeState")
	if st2 != null:
		var wg2 := str(st2.get_flag("walk_goal_active", ""))
		if wg2 == "":
			wg2 = str(st2.get_flag("walk_goal", ""))
		if wg2 != "":
			_goal_item = wg2
	# 强制第一次走位的手机不能交互
	if _goal_item == "黑箱":
		for d in _items:
			var dd: Dictionary = d
			if str(dd.get("name", "")) == "手机":
				dd["reach"] = 0.0
				dd["act"] = ""
				d = dd

	# 走位完成门槛（第一天第二次进宿舍：不把黑箱迷宫解开不许按「看完了」）
	_gate_flag = str(room.get("gate_flag", ""))
	_gate_hint = str(room.get("gate_hint", ""))
	# 自由探索（房间数据 free_explore）：不设必看物件，点过任意一件就能按「看完了」离开；
	# 若房间还配了 free_exit=true（第四天海龟汤前的宿舍探索），一件没看也能直接退。
	_free_explore = bool(room.get("free_explore", false))
	_free_exit = bool(room.get("free_exit", false))

	# 起点
	var ps_v: Variant = room.get("player_start", null)
	if ps_v is Array and (ps_v as Array).size() >= 2:
		var pa2: Array = ps_v as Array
		_player = Vector2(float(pa2[0]), float(pa2[1]))
	else:
		_player = _floor_center()
	_player = _first_free_spot(_player)


func _floor_center() -> Vector2:
	if _walk_rects.is_empty():
		return Vector2(600, 520)
	var r: Rect2 = _walk_rects[0]
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.62)


## 找一个不压住物件热区、也没踩进陈设里的落脚点（螺旋外扩）
func _first_free_spot(p: Vector2) -> Vector2:
	var probe := _clamp_to_floor(p)
	if _spot_ok(probe):
		return probe
	for ring in range(1, 16):
		var rad := float(ring) * 34.0
		for k in 12:
			var ang := TAU * float(k) / 12.0
			var q := _clamp_to_floor(probe + Vector2(cos(ang), sin(ang)) * rad)
			if _spot_ok(q):
				return q
	return probe


func _spot_ok(p: Vector2) -> bool:
	return not _overlaps_item(p) and not _blocked(p)


func _overlaps_item(p: Vector2) -> bool:
	for d in _items:
		var r := Rect2(float(d["x"]) - 40.0, float(d["y"]) - 30.0,
				float(d["w"]) + 80.0, float(d["h"]) + 60.0)
		if r.has_point(p):
			return true
	return false


# ============================================================================
#  走位
# ============================================================================

func _can_stand(p: Vector2) -> bool:
	for r in _walk_rects:
		if (r as Rect2).has_point(p):
			return true
	return false


func _clamp_to_floor(p: Vector2) -> Vector2:
	if _walk_rects.is_empty():
		return p
	for r in _walk_rects:
		if (r as Rect2).has_point(p):
			# 人物脚点不能高于 PLAYER_Y_MIN：放大后头才不会顶出画面上缘
			if p.y < PLAYER_Y_MIN:
				p.y = PLAYER_Y_MIN
			return p
	var best := p
	var best_d := 1.0e20
	for r in _walk_rects:
		var rr: Rect2 = r
		var q := Vector2(clampf(p.x, rr.position.x, rr.end.x),
				clampf(p.y, rr.position.y, rr.end.y))
		var dist := q.distance_squared_to(p)
		if dist < best_d:
			best_d = dist
			best = q
	best.y = maxf(best.y, PLAYER_Y_MIN)
	return best


## 脚点是否踩进了挡路陈设里
func _blocked(p: Vector2) -> bool:
	for r in _solids:
		if (r as Rect2).has_point(p):
			return true
	return false


## 带着阻挡走一步：先试整体位移，撞上了再分轴滑动。
## 分轴的好处是"贴着桌子横着走"不会卡死（整体位移会被判撞、分轴能过）。
func _try_move(cur: Vector2, step: Vector2) -> Vector2:
	# 万一起点本身就落在陈设里（数据改了 / 被别的东西推进去），
	# 直接放行整体位移，免得人物被永久卡死。
	if _blocked(cur):
		return _clamp_to_floor(cur + step)
	var full := _clamp_to_floor(cur + step)
	if not _blocked(full):
		return full
	var mx := _clamp_to_floor(Vector2(cur.x + step.x, cur.y))
	if not _blocked(mx):
		return mx
	var my := _clamp_to_floor(Vector2(cur.x, cur.y + step.y))
	if not _blocked(my):
		return my
	return cur


func _update_near() -> void:
	# 【关键·已修】两处都改：
	#  1) 判定点用 _player 本身——绘制层就是把 _player 当**脚点**画的
	#     （prelude_room_draw.gd 的 _draw_actors 直接把 _player 交给 _draw_person）。
	#     旧版在这里又加了 PLAYER_BODY_R * 1.2（+57.6）往下探，等于把身位算了两遍，
	#     于是"人明明站在门牌前"却判不出身边的物件。
	#  2) 距离用"到物件**矩形**的距离"，而不是到物件中心的距离。
	#     旧版是一张 280 宽的门牌也要算中心距，站在门牌正下方反而更远。
	var foot := _player
	var cur := str(_near["name"]) if not _near.is_empty() else ""
	_near = {}
	var best: Dictionary = {}
	var best_d := 1.0e20
	for d in _items:
		var dist := _distance_to_body(foot, d)
		var limit := float(d["reach"]) * NEAR_FACTOR
		if cur != "" and str(d["name"]) == cur:
			limit *= NEAR_HYST
		if dist <= limit and dist < best_d:
			best_d = dist
			best = d
	_near = best


## 点到物件矩形的距离（点在矩形内为 0）
func _distance_to_rect(p: Vector2, d: Dictionary) -> float:
	var x := float(d["x"])
	var y := float(d["y"])
	var q := Vector2(clampf(p.x, x, x + float(d["w"])),
			clampf(p.y, y, y + float(d["h"])))
	return p.distance_to(q)


## 人物"身体任一段"到物件矩形的距离：从脚点到头（约 210 逻辑px，覆盖全身与手臂高度）
## 取线段上 6 个采样点到矩形的最短距离，只要任一部位够着就算靠近。
func _distance_to_body(foot: Vector2, d: Dictionary) -> float:
	var top := foot + Vector2(0.0, -BODY_H)
	var best := 1.0e20
	for i in 6:
		var p := foot.lerp(top, float(i) / 5.0)
		best = minf(best, _distance_to_rect(p, d))
	return best


# ============================================================================
#  UI
# ============================================================================

func _build_ui() -> void:
	# 0. 手绘底（同一支铅笔画的房间）
	_backdrop = Control.new()
	_backdrop.name = "RoomBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_script(load(BACKDROP_SCRIPT))
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 1. 靠近提示（屏幕中下方："可交互"字样用深色 + 浅底，任何背景上都看得清）
	_hint = Label.new()
	_hint.name = "WalkHint"
	_hint.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
	_hint.add_theme_color_override("font_color", Color(0.13, 0.13, 0.16))
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.97, 0.96, 0.90, 0.94)
	hs.border_color = Color(0.16, 0.16, 0.20, 0.85)
	hs.set_border_width_all(1)
	hs.set_corner_radius_all(9)
	hs.content_margin_left = 18.0
	hs.content_margin_right = 18.0
	hs.content_margin_top = 5.0
	hs.content_margin_bottom = 5.0
	_hint.add_theme_stylebox_override("normal", hs)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.modulate.a = 0.0
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -320.0
	_hint.offset_right = 320.0
	_hint.offset_top = -172.0
	_hint.offset_bottom = -142.0

	# 2. 操作提示（左下角，避开右下角的按钮）
	_help = Label.new()
	_help.name = "WalkHelp"
	_help.text = "WASD / 方向键  走动          空格 / 点击  查看"
	_help.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_help.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help)
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_help.offset_left = 34.0
	_help.offset_top = -34.0
	_help.offset_right = 640.0
	_help.offset_bottom = -8.0

	# 3. 场景名（左上）
	var title := Label.new()
	title.name = "WalkTitle"
	title.text = "%s   ·   %s" % [str(room.get("title", "")), str(room.get("subtitle", ""))]
	title.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	title.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.offset_left = 34.0
	title.offset_top = 26.0
	title.offset_right = 700.0
	title.offset_bottom = 56.0

	# 3.5 笔记按钮（右上角）+ 笔记面板：走位里也能随时翻看读过的全部笔记
	#     （Kerry：「把笔记系统完整，放一个按钮可以查看过去全部笔记」——
	#      以前只有对话界面能按 Tab 翻笔记，走位的时候翻不了。）
	_notes_btn = Button.new()
	_notes_btn.name = "WalkNotes"
	_notes_btn.text = "笔记  (Tab)"
	PreludeUI.apply_button_skin(_notes_btn)
	_notes_btn.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_notes_btn.pressed.connect(_toggle_notes)
	add_child(_notes_btn)
	_notes_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_notes_btn.offset_left = -178.0
	_notes_btn.offset_top = 22.0
	_notes_btn.offset_right = -34.0
	_notes_btn.offset_bottom = 60.0

	_notes = PreludeUI.NotesPanel.new()
	_notes.name = "WalkNotesPanel"
	_notes.z_index = 8          # 比弹窗层（默认 0）高，翻开笔记时不会被弹窗盖住
	_notes.closed.connect(_on_notes_closed)
	add_child(_notes)
	_notes.visible = false

	# 4. "看完了"按钮（右下）
	_done_btn = Button.new()
	_done_btn.name = "WalkDone"
	PreludeUI.apply_button_skin(_done_btn, true)
	_done_btn.pressed.connect(_on_done)
	add_child(_done_btn)
	_done_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_done_btn.offset_left = -260.0
	_done_btn.offset_right = -34.0
	_done_btn.offset_top = -96.0
	_done_btn.offset_bottom = -52.0
	_update_done_button()

	# 5. 提示气泡（顶部）
	_toast = Label.new()
	_toast.name = "WalkToast"
	_toast.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	_toast.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -320.0
	_toast.offset_right = 320.0
	_toast.offset_top = 30.0
	_toast.offset_bottom = 60.0

	# 弹窗层按需创建，省掉空引用
	_popup_layer = null


func _update_done_button() -> void:
	if _done_btn == null:
		return
	# 强制重新读取目标，确保按钮显示正确
	var st: Node = get_node_or_null("/root/PreludeState")
	if st != null:
		var wg := str(st.get_flag("walk_goal_active", ""))
		if wg == "":
			wg = str(st.get_flag("walk_goal", ""))
		if wg != "":
			_goal_item = wg
	# 自由探索房间：按钮固定写「看完了（自由探索）」，点过任意一件就能走
	if _free_explore:
		_done_btn.text = "看完了（自由探索）"
		return
	# 【一周目】有些房间只要求"走到某件东西旁边看完它"（goal_item），
	# 这时按钮只认那一件，不逼玩家把屋里每样东西都点一遍。
	if _goal_item != "":
		if _goal_seen():
			_done_btn.text = "看完了"
		else:
			_done_btn.text = "看完了（先去%s看看）" % _goal_item
		return
	# 同样直接数物件表，别信计数器
	var left := 0
	for d in _items:
		if not bool((d as Dictionary).get("seen", false)):
			left += 1
	if left > 0:
		_done_btn.text = "看完了（还有 %d 件没看）" % left
	else:
		_done_btn.text = "看完了"


## 这个房间要求的"必看物件"是否已经看过（没设 goal_item 时恒为 true）
func _goal_seen() -> bool:
	if _goal_item == "":
		return true
	for d in _items:
		var dd: Dictionary = d
		if str(dd.get("name", "")) == _goal_item:
			return bool(dd.get("seen", false))
	return true


func _toast_msg(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.modulate.a = 1.0
	_toast_t = 2.2


# ============================================================================
#  每帧
# ============================================================================

func _process(delta: float) -> void:
	if _act_lock > 0.0:
		_act_lock = maxf(0.0, _act_lock - delta)
	if _backdrop != null and _backdrop.has_method("set_room"):
		_backdrop.call("set_room", room, _player, _near, _items, _props, _popup)
	if _backdrop != null and _backdrop.has_method("set_edit"):
		_backdrop.call("set_edit", _edit_mode, _edit_sel)
	if _backdrop != null and _backdrop.has_method("set_facing"):
		_backdrop.call("set_facing", _facing)

	if not _popup and not _notes_open() and not _edit_mode and not _panel_open():
		var dir := Vector2.ZERO
		dir.x = Input.get_action_strength("prelude_walk_right") - Input.get_action_strength("prelude_walk_left")
		dir.y = Input.get_action_strength("prelude_walk_down") - Input.get_action_strength("prelude_walk_up")
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
			_facing = dir
			_player = _try_move(_player, dir * WALK_SPEED * delta)
			_bob += delta * 9.0
		_update_near()

	if _hint != null:
		if _edit_mode:
			if _edit_sel >= 0 and _edit_sel < _items.size():
				var ed: Dictionary = _items[_edit_sel]
				_hint.text = "「%s」 (%.0f, %.0f) %dx%d   ·   拖动=移动 / 右下角=改大小 / V=显隐 / F12=保存退出" % [
					str(ed.get("name", "")), float(ed["x"]), float(ed["y"]),
					int(ed["w"]), int(ed["h"])]
			else:
				_hint.text = "布置模式：拖动=移动 · 右下角=改大小 · V=显示方式(有形/靠近/隐形) · F12=保存退出"
			_hint.modulate.a = 1.0
		elif _near.is_empty():
			_hint.modulate.a = maxf(0.0, _hint.modulate.a - 0.12)
		else:
			_hint.text = "可交互   空格 / 点击 查看"
			_hint.modulate.a = 1.0

	if _toast != null and _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.modulate.a = 0.0


## 安全地"吃掉"这次输入。
## 【坑】按「看完了」会切场景，切换过程中本节点可能已经离树、
## get_viewport() 返回 null，直接调 set_input_as_handled() 会报
## `SCRIPT ERROR: Cannot call method 'set_input_as_handled' on a null value.`，
## 这条错误会打断场景切换，表现成"按了看完了之后卡住 / 像退出去了"。
func _eat() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# 布置模式开关：弹窗/笔记开着时不响应（避免拖拽时误触）
	if not _popup and not _notes_open() and event is InputEventKey \
			and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == EDIT_KEY:
		_edit_mode = not _edit_mode
		_edit_sel = -1
		_near = {}
		if _edit_mode:
			_toast_msg("布置模式：拖动=移动 / 右下角=改大小 / V=显示方式 / F12=保存退出")
		else:
			_save_overrides()
		_eat()
		return
	# 布置模式：鼠标选择 / 拖动，其他输入全部吃掉
	if _edit_mode:
		_edit_input(event)
		_eat()
		return
	# 笔记翻开着：只让笔记吃输入（Tab / Esc / 空格 合上），走位与查看都停住
	if _notes_open():
		if event.is_action_pressed("prelude_notes") or event.is_action_pressed("ui_cancel") \
				or event.is_action_pressed("prelude_advance"):
			_notes.close()
			_eat()
		return
	if event.is_action_pressed("prelude_notes"):
		_toggle_notes()
		_eat()
		return
	# 走位里的谜题面板开着：键盘输入都归它（迷宫用方向键走），其余输入也吃掉，
	# 免得"按空格"在面板底下又弹出一个详情窗。
	if _panel_open():
		if bool(_walk_panel.call("is_open")) and bool(_walk_panel.call("wants_input")):
			_walk_panel.call("handle_input", event)
		_eat()
		return
	if _popup:
		if event.is_action_pressed("prelude_walk_act") or event.is_action_pressed("prelude_advance"):
			_close_popup()
			_eat()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_close_popup()
			_eat()
		return
	# 收起弹窗后短暂锁一下：否则"按一下空格"会同一帧把弹窗又打开，
	# 玩家看到的是弹窗闪一下就没了（长按空格更是完全打不开）。
	if _act_lock > 0.0:
		return
	if event.is_action_pressed("prelude_walk_act"):
		if not _near.is_empty():
			_examine(_near)
		else:
			# 身边没东西时按空格：不要让玩家以为"按了没反应、是不是卡住了"，
			# 明确告诉他该干什么。
			_toast_msg("走到东西旁边再按空格（WASD / 方向键 走动）")
		_eat()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if not _near.is_empty():
			_examine(_near)
			_eat()


# ============================================================================
#  布置模式（F12）：在游戏界面上用鼠标拖动调整可交互物品的位置，松手保存
#  保存到 data/room_item_overrides.json，下次进房间自动套用（不改基础数据文件）
# ============================================================================

func _apply_overrides() -> void:
	_overrides = {}
	var f := FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	_overrides = parsed as Dictionary
	var ov: Dictionary = _overrides.get(room_id, {}) as Dictionary
	for d in _items:
		var nm := str(d.get("name", ""))
		if not ov.has(nm):
			continue
		var arr: Array = ov[nm] as Array
		if arr.size() < 4:
			continue
		d["x"] = float(arr[0])
		d["y"] = float(arr[1])
		d["w"] = float(arr[2])
		d["h"] = float(arr[3])
		# 第 5 项：1=有形，2=靠近时显示，0=隐形
		if arr.size() >= 5:
			d["vis"] = int(arr[4])
		d["center"] = Vector2(float(arr[0]) + float(arr[2]) * 0.5,
				float(arr[1]) + float(arr[3]) * 0.5)


func _save_overrides() -> void:
	var ov: Dictionary = _overrides.get(room_id, {}) as Dictionary
	for d in _items:
		var nm := str(d.get("name", ""))
		if nm == "":
			continue
		ov[nm] = [int(round(float(d["x"]))), int(round(float(d["y"]))),
				int(round(float(d["w"]))), int(round(float(d["h"]))),
				int(d.get("vis", 1))]
	_overrides[room_id] = ov
	var f := FileAccess.open(OVERRIDES_PATH, FileAccess.WRITE)
	if f == null:
		_toast_msg("保存失败：写不了 %s" % OVERRIDES_PATH)
		return
	f.store_string(JSON.stringify(_overrides, "\t"))
	_toast_msg("已保存 %d 个物品的位置" % _items.size())


## 屏幕坐标（窗口像素）→ 房间逻辑坐标：先用 canvas 变换回到 1280x720 设计空间，
## 再用房间绘制的 xform 逆变换（xform 经 backdrop 转发，和画出来的是同一套）。
func _screen_to_world(sp: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null or _backdrop == null or not _backdrop.has_method("room_xform"):
		return Vector2.ZERO
	var design := vp.get_canvas_transform().affine_inverse() * sp
	var xf: Transform2D = _backdrop.call("room_xform", vp.get_visible_rect().size)
	return xf.affine_inverse() * design


func _edit_input(event: InputEvent) -> void:
	# V：切换选中物品交互框的显示方式（有形 → 靠近时显示 → 隐形 → 有形）
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_V:
		if _edit_sel >= 0 and _edit_sel < _items.size():
			var vd: Dictionary = _items[_edit_sel]
			vd["vis"] = int((int(vd.get("vis", 1)) + 1) % 3)
			_save_overrides()
			var vis_name: String = ["隐形", "有形", "靠近时显示"][int(vd["vis"])]
			_toast_msg("「%s」交互框已设为：%s" % [str(vd["name"]), vis_name])
		return
	if event is InputEventMouseMotion:
		if _edit_sel >= 0 and _edit_sel < _items.size():
			var w := _screen_to_world((event as InputEventMouseMotion).position)
			var d: Dictionary = _items[_edit_sel]
			if _drag_mode == 2:
				# 改大小：左上角不动，宽高跟随右下角
				d["w"] = maxf(12.0, w.x - float(d["x"]))
				d["h"] = maxf(12.0, w.y - float(d["y"]))
				d["center"] = Vector2(float(d["x"]) + float(d["w"]) * 0.5,
						float(d["y"]) + float(d["h"]) * 0.5)
			elif _drag_mode == 1:
				d["x"] = w.x - _drag_off.x
				d["y"] = w.y - _drag_off.y
				d["center"] = Vector2(float(d["x"]) + float(d["w"]) * 0.5,
						float(d["y"]) + float(d["h"]) * 0.5)
			_near = d
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	var w2 := _screen_to_world(mb.position)
	if mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# 点中选中物品的右下角把手 → 进入改大小；否则按普通点选
			var corner := false
			if _edit_sel >= 0 and _edit_sel < _items.size():
				var sd: Dictionary = _items[_edit_sel]
				corner = (w2 - Vector2(float(sd["x"]) + float(sd["w"]),
						float(sd["y"]) + float(sd["h"]))).length() <= 18.0
			if corner:
				_drag_mode = 2
				_near = _items[_edit_sel]
				return
			var idx := _pick_item(w2)
			if idx >= 0:
				_edit_sel = idx
				var d2: Dictionary = _items[idx]
				_drag_off = w2 - Vector2(float(d2["x"]), float(d2["y"]))
				_drag_mode = 1
				_near = d2
			else:
				_edit_sel = -1
				_near = {}
				_drag_mode = 0
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_edit_sel = -1
			_near = {}
			_drag_mode = 0
	else:
		if mb.button_index == MOUSE_BUTTON_LEFT and _edit_sel >= 0 \
				and _edit_sel < _items.size():
			_save_overrides()
			_drag_mode = 0


## 取鼠标下最靠上的物品（数组后面画的在上面，从后往前找）
func _pick_item(w: Vector2) -> int:
	for i in range(_items.size() - 1, -1, -1):
		var d: Dictionary = _items[i]
		if w.x >= float(d["x"]) and w.x <= float(d["x"]) + float(d["w"]) \
				and w.y >= float(d["y"]) and w.y <= float(d["y"]) + float(d["h"]):
			return i
	return -1


# ============================================================================
#  查看 / 弹窗
# ============================================================================

func _examine(d: Dictionary) -> void:
	# 特殊动作：点物品直接弹出小游戏面板（第一天黑箱 → 七色镜廊）。
	# 这一支【不】先记 seen——黑箱要等迷宫真正解开才算"看过"（看完了才能按），
	# 中途从面板退出（✕）不算数。
	var act := str(d.get("act", ""))
	
	# 强制重新读取目标，确保第一次点手机的时候正确判断
	var st_goal: Node = get_node_or_null("/root/PreludeState")
	if st_goal != null:
		var wg_goal := str(st_goal.get_flag("walk_goal", ""))
		if wg_goal != "":
			_goal_item = wg_goal

	# 第一次走位（目标是黑箱）的时候，点手机显示介绍，不直接打开解谜面板
	if str(d["name"]) == "手机" and act.begins_with("open_panel:") and _goal_item == "黑箱":
		act = ""
	
	if act.begins_with("open_panel:"):
		_open_panel_from_walk(act.substr("open_panel:".length()).strip_edges())
		return
	# 记下"这次走位里看过它"（第一次看、以前看过这次又看都算）——
	# 走位结束回对话时，这一段的追加台词（peek）按这次的查看记录补播：
	# 第一天走位看过室友的书桌，第三关再走位看同一件，也要播那一段的追加台词。
	var st: Node = get_node_or_null("/root/PreludeState")
	if st != null:
		var wl: Array = (st.call("get_flag", "walk_during_examined", []) as Array).duplicate()
		if not wl.has(str(d["name"])):
			wl.append(str(d["name"]))
			st.call("set_flag", "walk_during_examined", wl)
	var first_time := not bool(d.get("seen", false))
	if first_time:
		d["seen"] = true
		_examine_count += 1
		_update_done_button()
		if st != null:
			st.call("set_flag", "seen_" + str(d["name"]), true)
			st.call("note_examined", str(d["name"]))
			# 走位里读到的东西也要进笔记 —— 以前只记"看过"，按 Tab 一片空白
			# （Kerry：「把笔记系统完整，放一个按钮可以查看过去全部笔记」）。
			var detail := str(d.get("detail", ""))
			if detail == "":
				detail = str(d.get("text", ""))
			st.call("add_card", "%s：%s" % [str(d["name"]), detail] if detail != "" else str(d["name"]))
	_show_popup(d, first_time)


func _show_popup(d: Dictionary, first_time: bool) -> void:
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null

	_popup_item = d
	_popup = true
	var act := str(d.get("act", ""))

	_popup_layer = Control.new()
	_popup_layer.name = "CloseupPopup"
	# 【坑】这里（连同下面的 dim）必须是 IGNORE：面板以外的地方点了要能传给
	# _unhandled_input 去关弹窗，否则提示写着"点击 / 空格 收起来"，
	# 点空白处却毫无反应（STOP 会把全屏的鼠标事件吃掉）。
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popup_layer)
	_popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 压暗（手绘底是亮的，要压得够狠，弹窗上的字才读得清）
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 纸面板：贴在画面偏上的位置，避免和底部提示/按钮打架
	var panel := PanelContainer.new()
	panel.name = "CloseupPanel"
	panel.add_theme_stylebox_override("panel",
			PreludeUI.panel_skin(Color(0.070, 0.068, 0.080, 0.97),
					Color(0.88, 0.80, 0.62, 0.60), 4))
	_popup_layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 214.0
	panel.offset_right = -214.0
	panel.offset_top = 34.0
	panel.offset_bottom = panel.offset_top + 556.0

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	# 关键：不设 expand-fill 时 VBox 会按"最大子项的最小宽度"撑高，
	# 之前就把面板内容撑成 1248 高、文字溢出到面板外面。
	vb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_child(vb)

	# 放大图：居中、留白，别顶到面板边
	var art_row := HBoxContainer.new()
	art_row.name = "CloseupArtRow"
	art_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(art_row)

	var art := TextureRect.new()
	art.name = "CloseupArt"
	art.custom_minimum_size = Vector2(0, 260)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := _load_first(str(d.get("closeup", "")))
	if tex != null:
		art.texture = tex
	else:
		# 没有贴图：放一块占位（不是画图，是明确标出"这里等一张美术"）
		art.texture = _placeholder_texture(str(d["name"]))
	art_row.add_child(art)

	var name_label := Label.new()
	name_label.name = "CloseupName"
	name_label.text = str(d["name"])
	name_label.add_theme_font_size_override("font_size", PreludeUI.FS_NAME)
	name_label.add_theme_color_override("font_color", PreludeUI.C_NAME)
	vb.add_child(name_label)

	var sep := PreludeUI.hline(0.0, PreludeUI.C_LINE)
	vb.add_child(sep)

	var body := RichTextLabel.new()
	body.name = "CloseupBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(0, 104)
	body.add_theme_font_size_override("normal_font_size", PreludeUI.FS_TEXT)
	body.add_theme_color_override("default_color", PreludeUI.C_INK)
	body.text = str(d["detail"])
	vb.add_child(body)

	# 第一天：折纸星星的弹窗带「先收起来吧」按键——点了把它收进口袋并从桌面消失
	if act == "collect_star" and not _star_collected():
		var collect := Button.new()
		collect.name = "CloseupCollect"
		collect.text = "先收起来吧"
		PreludeUI.apply_button_skin(collect, true)
		collect.pressed.connect(func() -> void: _collect_star(d))
		vb.add_child(collect)

	var tip := Label.new()
	tip.name = "CloseupTip"
	tip.text = "（点击 / 空格  收起来）"
	tip.add_theme_font_size_override("font_size", PreludeUI.FS_TIP)
	tip.add_theme_color_override("font_color", PreludeUI.C_INK_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(tip)

	if first_time:
		_toast_msg("已记下：「%s」" % str(d["name"]))

	# 弹窗打开期间把走位 UI 收起来，避免文字叠在一起
	_set_walk_ui_visible(false)

	# 淡入
	_popup_layer.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_popup_layer, "modulate:a", 1.0, 0.16)


func _set_walk_ui_visible(v: bool) -> void:
	if _hint != null:
		_hint.visible = v
	if _help != null:
		_help.visible = v
	if _done_btn != null:
		_done_btn.visible = v
	if _toast != null:
		_toast.visible = v
	if _notes_btn != null:
		_notes_btn.visible = v


# ---------------------------------------------------------------- 笔记

## 走位里也能翻笔记（Kerry：「放一个按钮可以查看过去全部笔记」）
func _toggle_notes() -> void:
	if _notes == null:
		return
	if _notes.is_open():
		_notes.close()
	else:
		_notes.open(PreludeState.cards)
		_set_walk_ui_visible(false)


func _notes_open() -> bool:
	return _notes != null and _notes.is_open()


## 暂停菜单（autoload PauseMenu）问的："现在有覆盖层开着吗？"
## 走位里开着笔记、正弹着物件详情、或谜题面板打开时，Esc 归我，不弹暂停菜单。
func blocks_pause() -> bool:
	return _notes_open() or _popup or _panel_open()


func _on_notes_closed() -> void:
	if not _popup:
		_set_walk_ui_visible(true)


func _close_popup() -> void:
	_popup = false
	_popup_item = {}
	_act_lock = 0.22
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null
	_set_walk_ui_visible(true)


# ============================================================================
#  物品特殊动作（第一天桌面交互）
# ============================================================================

func _star_collected() -> bool:
	var st := get_node_or_null("/root/PreludeState")
	return st != null and bool(st.call("get_flag", "week1_collected_star", false))


## 点「先收起来吧」：记 flag、加笔记、把星星从桌面拿走，然后收起弹窗
func _collect_star(d: Dictionary) -> void:
	var st := get_node_or_null("/root/PreludeState")
	if st != null:
		st.call("set_flag", "week1_collected_star", true)
		st.call("add_card", "折纸星星：星星的五个角长得大小不均……（已收进口袋）")
	d["seen"] = true
	_items.erase(d)
	_update_done_button()
	_toast_msg("已收进口袋")
	_close_popup()


func _panel_open() -> bool:
	return _walk_panel != null and is_instance_valid(_walk_panel)


## 走位里弹的面板（物品 open_panel:<id> 标签）——解完自动加一张完成卡片、取消时给
## 一句"回到哪件东西旁重新打开"的提示。键 = 面板 id；没登记的沿用第一天（黑箱）原文案，
## 保证黑箱迷宫 / 手机手势密码的卡片与提示一字不变。
const PANEL_DONE_CARD := {
	"bookshelf": "书架：九本书（已解开）",
}
const PANEL_CANCEL_TOAST := {
	"bookshelf": "谜题已收起 · 走到书架旁按 空格 重新打开",
}


## 点带 open_panel:<id> 标签的物品：直接在走位里弹出对应小游戏面板
## （黑箱 → 迷宫、手机 → 手势、书架 → 九本书解谜），替代"详情弹窗"
func _open_panel_from_walk(id: String) -> void:
	if _panel_open():
		return
	if id == "" or not Week1Panels.has_panel(id):
		push_warning("[Walk] 未知面板：%s" % id)
		return
	var st := get_node_or_null("/root/PreludeState")
	# 这一关这次游玩已经解过了（读档 / 重进）：对应物件直接记为已看，不重复弹
	if st != null and st.call("get_flag", "week1_result_" + id, null) != null:
		_mark_panel_item_seen(id)
		return
	var p := Control.new()
	p.name = "Week1Panel_" + id
	p.set_script(load(Week1Panels.script_for(id)))
	if p.get_script() == null:
		push_error("[Walk] 面板脚本加载失败：%s" % id)
		return
	# 关键：先 setup 再 add_child（add_child 会立刻触发 _ready）
	p.call("setup", {"id": id})
	p.z_index = 7
	add_child(p)
	p.connect("finished", _on_walk_panel_finished)
	_walk_panel = p
	_set_walk_ui_visible(false)


func _on_walk_panel_finished(result: Dictionary) -> void:
	var id := str(result.get("id", ""))
	var p := _walk_panel
	_walk_panel = null
	if p != null and is_instance_valid(p):
		p.queue_free()
	_set_walk_ui_visible(true)
	if bool(result.get("cancelled", false)):
		# 玩家从谜题里退出来：不算过关，物件保持"没看过"，走位不结束
		_toast_msg(str(PANEL_CANCEL_TOAST.get(id, "谜题已收起 · 走到黑箱旁按 空格 重新打开")))
		return
	if id != "":
		var st := get_node_or_null("/root/PreludeState")
		if st != null:
			st.call("set_flag", "week1_result_" + id, result)
			st.call("add_card", str(PANEL_DONE_CARD.get(id, "黑箱：激光小迷宫（已解开）")))
	_mark_panel_item_seen(id)
	_toast_msg("解开了！")
	# 面板解完后直接切回对话，不停留、不用点"看完了"
	# _on_done()


## 面板解开后把对应物件记为"看过"，目标达成，「看完了」放行
func _mark_panel_item_seen(panel_id: String) -> void:
	for d in _items:
		var act := str(d.get("act", ""))
		if act == "open_panel:" + panel_id:
			if not bool(d.get("seen", false)):
				d["seen"] = true
				_examine_count += 1
				_update_done_button()
			return


## 占位图：一张写着物件名的纸，明确告诉美术"这里等一张放大图"
func _placeholder_texture(label_text: String) -> Texture2D:
	var img := Image.create(640, 300, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.175, 0.170, 0.190, 1.0))
	# 边框
	for x in img.get_width():
		img.set_pixel(x, 0, Color(0.92, 0.84, 0.64, 0.85))
		img.set_pixel(x, img.get_height() - 1, Color(0.92, 0.84, 0.64, 0.85))
	for y in img.get_height():
		img.set_pixel(0, y, Color(0.92, 0.84, 0.64, 0.85))
		img.set_pixel(img.get_width() - 1, y, Color(0.92, 0.84, 0.64, 0.85))
	# 交叉对角线，一眼看出是占位
	var w := img.get_width()
	var h := img.get_height()
	for i in maxi(w, h):
		if i < w:
			img.set_pixel(i, int(float(i) * float(h) / float(w)), Color(0.84, 0.78, 0.64, 0.34))
			img.set_pixel(i, h - 1 - int(float(i) * float(h) / float(w)), Color(0.84, 0.78, 0.64, 0.34))
	return ImageTexture.create_from_image(img)


func _load_first(paths: String) -> Texture2D:
	if paths == "":
		return null
	if ResourceLoader.exists(paths):
		var res := load(paths)
		if res is Texture2D:
			return res as Texture2D
	return null


func _on_done() -> void:
	# 自由探索房间：不设必看物件，点过任意一件就能按「看完了」离开；
	# 配了 free_exit 的房间（第四天）一件没看也能直接退。
	if _free_explore:
		if not _free_exit:
			var seen_any := false
			for d in _items:
				if bool((d as Dictionary).get("seen", false)):
					seen_any = true
					break
			if not seen_any:
				_toast_msg("先看看这里有什么吧（WASD / 方向键 走动，空格查看）")
				return
	# 【一周目】只要求"必看物件"的房间：没看完那一件就先别走
	elif _goal_item != "" and not _goal_seen():
		_toast_msg("先去「%s」看看（WASD / 方向键 走动，空格查看）" % _goal_item)
		return
	# 完成门槛（房间数据 gate_flag）：第一天第二次进宿舍要先把黑箱迷宫解开
	if _gate_flag != "":
		var st := get_node_or_null("/root/PreludeState")
		var res: Variant = null
		if st != null:
			res = st.call("get_flag", _gate_flag, null)
		var gate_ok := res is Dictionary and not bool((res as Dictionary).get("cancelled", false))
		if not gate_ok:
			_toast_msg(_gate_hint if _gate_hint != "" else "还有谜题没解开")
			return
	# 剩余件数直接从物件表里数，不用任何缓存计数器——
	# 计数器只要有一处漏加，就会出现"明明都看完了却一直说还有 4 件没看"。
	var left := 0
	for d in _items:
		if not bool((d as Dictionary).get("seen", false)):
			left += 1
	if left > 0 and _goal_item == "" and not _free_explore:
		_toast_msg("还有 %d 件没看（再走走看）" % left)
		return
	var st: Node = get_node_or_null("/root/PreludeState")
	var back := ""
	if st != null:
		st.call("set_flag", "walk_return", true)
		back = str(st.call("get_flag", "walk_return_scene", ""))
	walk_finished.emit()
	if back != "":
		# 发起走位的是哪一幕就回哪一幕
		get_tree().change_scene_to_file(back)
		return
	# 兜底：没有登记返回场景时退回主对话场景
	get_tree().change_scene_to_file(DIALOGUE_FALLBACK)
