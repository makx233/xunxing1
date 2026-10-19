extends "res://scripts/week1/panel_base.gd"
## ============================================================================
##  《寻星》一周目 —— 第 3 关 · 书架九本书（数字从书名 / 作者名的谐音里读）
## ============================================================================
##  上一关解出的关键词是 JAPAN。书架上九本书，**书里一个字都不写数字**
##  （书脊上没有编号/索书号/序号，翻开的详情页里也没有）；每本书"翻开"之后
##  只有一页：书名 / 作者 / 一句话简介 / 作者小传。
##
##  上一关的答案 JAPAN 就是筛子：与日本有关的六本 —— 绫辻行人 / 青崎有吾 /
##  三津田信三 / 泡坂妻夫 / 乙一 / 岛田庄司 —— 按它们在架子上的先后顺序，
##  各自从书名或作者名里读出一个数字（读音的谐音，不是印在书上的）：
##      钟表馆事件（钟停在零点 / 圆表盘就是一个圈）   → 0
##      青崎有**吾**（吾 ≈ 五）                       → 5
##      三津田信**三**（三）                          → 3
##      泡坂**妻**夫（妻 ≈ 七）                       → 7
##      **乙**一（一）                                → 1
##      岛田庄**司**（司 ≈ 四）                       → 4
##      连起来 = 0 5 3 7 1 4
##  另外三本（约翰·迪克森·卡尔 / 柯南·道尔 / 阿加莎·克里斯蒂）不是日本作家，
##  与这一关的数字无关。
##
##  交互：点书脊 → 翻开（右侧详情区显示 书名 / 作者·国家 / 一句话简介 / 作者小传，
##        并累计"已经翻过 N / 9 本"）→ 这一关**不用输入数字**：面板只提醒
##        「记住你从作家名字里算出来的数字。」，点「记住了」确认 → close_panel
##        直接过关，回到对话后 053714 卡片与"告诉刘忆"输密码的环节照旧。
##
##  面板上**不显示任何数字**、也不写出上一关的关键词（那两条都是把答案直接
##  摆出来）：整个面板只留一句提示「书籍？密码？数字？」。数字的线索就在详情页
##  第 2 行的作者名里（书名 / 作者名的谐音），翻开就能看见，不用滚。
##  过关：close_panel({"ok": true, "code": "053714"})
##
##  美术：Kerry 给过一张九本书脊的图（2280x1280，九条书脊从左到右并排，
##        顺序 = BOOKS 的顺序，书脊上没有印任何数字），约定放在 SPINES_TEX。
##        贴图版**按比例切九条、绝不拉伸**：整图平均切成 9 列（每列 ≈ 253.33 宽），
##        每列一条 AtlasTexture，塞进一个 expand_icon = true 的 Button —— 按钮
##        自己就是热区，图按原比例缩进格子，于是书脊上的书名不再被压扁。
##        取不到（文件不在 / 不是贴图）就退回代码手绘的书脊，绝不让面板崩。
##
##  注意：本文件只依赖 panel_base.gd 与 PreludeUI，不读 json、不切场景。
## ============================================================================

## Kerry 给的九本书脊整图：2280x1280，九条书脊从左到右并排（顺序 = BOOKS）。
## 缺文件时自动退回手绘书脊（见 _load_spines_texture）。
const SPINES_TEX := "res://assets/books/week1_spines.jpg"

## ————————————————— 尺寸账（面板外框 900x540，见 panel_base.gd）—————————————
##   宽：900 − 18x2（PanelFrame 的 panel_skin content margin）
##          − 26x2（MarginContainer）                        = 812 ← body 实宽
##   高：540 − 14x2（panel_skin）− 18x2（margin）             = 476 给整列
##       再减 标题(~31) + 分隔线(1) + 底部 hint(~20) + 3x10(separation)
##                                                          ≈ 394 ← body 实高
##       （最保守按 380 算，下面的预算都按 380 复核过）
##   贴图版书架行高度 = 394 − 反馈(24) − 8(separation)         ≈ 362
##       （原来这里还压着一行"上一关的关键词"26px；那一行说破答案，已经删掉，
##        省出来的高度顺着 ShelfRow → 右侧栏 → BookReader 全给了详情页的滚动区。）
## ————————————————————————————————————————————————————————————————————

## 贴图版书架区的最小高度。
## 【为什么是 300】九条书脊是"宽受限"的：格子约 54 宽 / 328 高时，按 253.33:1280
## 的原比例只能缩到 54 x 272，再往上加高只是多留上下黑边。300 已经足够看清书名，
## 又给右侧栏与底部反馈留足余量：body 最小总高 = 300 + 8 + 24 = 332 ≤ 394。
## （手绘版不用这个值，它的高度由"书脊按钮 100 + 作者名"自己撑出来。）
const SHELF_H := 300.0
## 贴图版书架区的最小宽度：9 x SPINE_MIN_W。Godot 的 stretch_ratio 只分配
## "扣掉各自最小宽度之后的余量"，所以光写 2.0 兜不住下限，还要这个值兜底，
## 保证右侧栏拿走它那份之后，每条书脊仍有 40px 宽（书名还认得出来）。
const TEXTURED_SHELF_MIN_W := 360.0
## 贴图版单条书脊（= 单列）的最小宽度，同时是 expand_icon 按钮的尺寸兜底
## （expand_icon = true 时按钮最小尺寸不再包含贴图尺寸，不兜底会缩到 0）。
const SPINE_MIN_W := 40.0
## 底部反馈行的高度（原来是在 build_body 里硬写的 24，这里提出来好算总高）。
const FEEDBACK_H := 24.0

## 九本书，按书架上的先后顺序。
##   jp      —— 是不是日本作家（第 1/2/3/6/7/9 本是，按顺序读出 0 5 3 7 1 4）
##   country —— 详情页里的作者国籍（日本 / 美国 / 英国），帮玩家一眼筛出六本日本作家
##   digit   —— 这一本对应的数字。**只给开发者对账用，面板上绝不显示**：
##              玩家得自己从书名 / 作者名的谐音里读出来（见文件头的对照表）。
##   blurb   —— 详情页里的"一句话简介"（0 的线索藏在钟表馆那本的简介里）
##   note    —— 详情页里的"作者小传"
const BOOKS: Array = [
	{
		"title": "钟表馆事件", "author": "绫辻行人", "jp": true, "country": "日本", "digit": "0",
		"blurb": "馆系列的代表作：一座宅邸里的钟全部停摆，指针都停在零点；圆圆的表盘本身就是一个圈。",
		"note": "作者绫辻行人，日本新本格推理的旗手。他笔下的馆，每一座都按一张时间表杀人。",
	},
	{
		"title": "体育馆之谜", "author": "青崎有吾", "jp": true, "country": "日本", "digit": "5",
		"blurb": "雨夜，体育馆中央躺着一具尸体，门从里面反锁。",
		"note": "作者青崎有吾，本格推理的新锐。他笔下的侦探只凭现场剩下的一点点痕迹破案。",
	},
	{
		"title": "如首无作祟之物", "author": "三津田信三", "jp": true, "country": "日本", "digit": "3",
		"blurb": "深山里的旧家族，代代相传的怪谈，和一具没有头的尸体。",
		"note": "作者三津田信三，怪谈与推理两条线一起铺，很多人把这一本当成他的最高作。",
	},
	{
		"title": "三口棺材", "author": "约翰·迪克森·卡尔", "jp": false, "country": "美国", "digit": "",
		"blurb": "密室推理的教科书：没有人能钻进那口棺材，可里面确实有个人。",
		"note": "作者约翰·迪克森·卡尔，人称密室之王。",
	},
	{
		"title": "四签名", "author": "柯南·道尔", "jp": false, "country": "英国", "digit": "",
		"blurb": "一份宝藏、四个签名，和一条断过的腿。",
		"note": "作者柯南·道尔，福尔摩斯的创造者。",
	},
	{
		"title": "失控的玩具", "author": "泡坂妻夫", "jp": true, "country": "日本", "digit": "7",
		"blurb": "会自己走动的机关人偶，和一场提前写好的死亡。",
		"note": "作者泡坂妻夫，本行是魔术师，写机关，也写人心。",
	},
	{
		"title": "动物园", "author": "乙一", "jp": true, "country": "日本", "digit": "1",
		"blurb": "每天一封来自动物园的信，越写越不像人写的。",
		"note": "作者乙一，一支笔写两副面孔：温柔的，和残忍的。",
	},
	{
		"title": "四魔头", "author": "阿加莎·克里斯蒂", "jp": false, "country": "英国", "digit": "",
		"blurb": "四个化名的敌人，各自握着一把钥匙。",
		"note": "作者阿加莎·克里斯蒂，侦探小说的女王。",
	},
	{
		"title": "占星术杀人魔法", "author": "岛田庄司", "jp": true, "country": "日本", "digit": "4",
		"blurb": "一具被肢解的尸体，和一封用占星术写成的挑战书。",
		"note": "作者岛田庄司，日本新本格的开拓者，这一本是他的出道作。",
	},
]

## 正确的六位密码（面板本身不再判定输入，只把过关结果交给对话里的输密码环节）
const CODE := "053714"

var _textured := false                 # 书脊是不是用了 Kerry 的贴图
var _spine_buttons: Array[Button] = [] # 九本书的点击热区（顺序 = 书架顺序）
var _opened: Dictionary = {}           # 书下标 → 已经翻开过
var _open_count := 0
var _click_counts: Dictionary = {}      # 书下标 → 被点击的次数（点击两次同一本书触发星星）
var _star_shown := false                # 星星是不是已经显示过了
var _count_label: Label = null         # 「已翻开 n / 9」
var _scroll: ScrollContainer = null    # 详情区的滚动容器（翻开新的一页时回到顶部）
var _detail: RichTextLabel = null      # 右侧详情区（书名 / 作者 / 简介 / 作者小传）
var _confirm_btn: Button = null        # 底部「记住了」：确认后直接过关
var _feedback: Label = null
var _done_locked := false              # 已过关，屏蔽重复提交
var _hint_btn: Button = null           # 提示按钮
var _hint_level := 0                   # 提示等级（0=没提示，1/2/3=依次显示三行提示）
var _code_input: LineEdit = null       # 六位密码输入框
var _code_submit_btn: Button = null    # 密码提交按钮
var _code_correct := false             # 密码是否已验证正确
var _code_label: Label = null          # 密码输入提示文字
var _code_row: HBoxContainer = null   # 密码输入框所在的行
var HINTS: Array = [
	"应该是和刚才解出的“日本”有关。",
	"这些日本作家的名字……似乎有一些共同的特点。",
	"数字和汉字会有什么联系呢？……对，谐音。"
]


# ---------------------------------------------------------------- 覆盖点
## 后面几关解谜没有"收起再回来"的意义，右上角「✕ 退出」键直接藏掉
func wants_exit() -> bool:
	return false


func panel_title() -> String:
	return "书架"


func panel_hint() -> String:
	# 全关唯一的提示。原来写的是「上一关的答案是 JAPAN：与日本有关的那几本，
	# 借阅卡数字按书架顺序读」——那是把答案连同读法一起摆出来，等于不用想。
	# 后按用户要求改成三个线索词：书籍？密码？数字？
	return "书籍？密码？数字？"


func build_body(body: VBoxContainer) -> void:
	# 【已删】这里原本有一行「上一关的关键词：JAPAN」（把答案直接写在脸上）。
	# 删掉之后省出的 ~26px 高 + 8px separation 顺着 ShelfRow（EXPAND_FILL）
	# 全落进右侧栏的详情滚动区，正好补上"没常驻数字行"之后的可视高度。

	# _build_shelf() 顺带把 _textured 定下来；两种书架的排版不一样，分开搭。
	var shelf := _build_shelf()
	if _textured:
		_build_textured_layout(body, shelf)
	else:
		_build_drawn_layout(body, shelf)

	_feedback = make_text("", PreludeUI.FS_TEXT, PreludeUI.C_ACCENT)
	_feedback.custom_minimum_size = Vector2(0, FEEDBACK_H)
	body.add_child(_feedback)

	_show_welcome()


## 贴图版的排版：书架在左、右侧栏在右（详情 + 密码框竖着摞）。
## 关键词标签已经删掉（说破答案），书架行因此多出 ~34px 高，全部给了详情滚动区。
func _build_textured_layout(body: VBoxContainer, shelf: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "ShelfRow"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	# 书架吃可分配余量的 2/3；下限由 shelf 自己的 custom_minimum_size 兜住
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.size_flags_stretch_ratio = 2.0
	row.add_child(shelf)

	var side := VBoxContainer.new()
	side.name = "SideColumn"
	side.add_theme_constant_override("separation", 8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.0
	row.add_child(side)

	# 详情面板吃满竖高、确认列留在它下面（_build_reader 里已给 EXPAND_FILL）
	_build_reader(side)
	_build_confirm_column(side)


## 手绘版的排版：保持原来的竖排
## （书架 → 分隔线 → HBox(详情 + 确认) → 反馈）。
func _build_drawn_layout(body: VBoxContainer, shelf: Control) -> void:
	body.add_child(shelf)
	body.add_child(PreludeUI.hline(0.0, Color(0.85, 0.80, 0.70, 0.16)))

	var row := HBoxContainer.new()
	row.name = "BookRow"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	_build_reader(row)
	_build_confirm_column(row)


# ---------------------------------------------------------------- 书架
## 有 Kerry 的书脊贴图就用贴图，否则用手绘书脊。
## 两条路都产出九本、书脊上零数字（贴图那版本就不在书脊上写字，
## 手绘那版只写书名与作者）。
func _build_shelf() -> Control:
	var tex := _load_spines_texture()
	if tex != null:
		_textured = true
		return _build_shelf_textured(tex)
	_textured = false
	return _build_shelf_drawn()


## 取书脊贴图。文件不在 / 加载失败 / 不是 Texture2D → 一律返回 null，由调用方退手绘。
##
## 【坑】`assets/books/week1_spines.jpg` 是直接从外面拷进来的，**没有 .import 文件**，
## 也就是从没被编辑器导入过。这种情况下 `ResourceLoader.exists()` 返回 **false**，
## `load()` 也拿不到（实测：存在性检查 false、贴图路根本不触发，面板一直退回手绘版）。
## 但工程是"从源码跑"的，运行期读 res:// 的原始文件是允许的，所以这里补一条
## `Image.load_from_file()` + `ImageTexture` 的路子，不必等编辑器导入。
func _load_spines_texture() -> Texture2D:
	if ResourceLoader.exists(SPINES_TEX):
		var res: Resource = load(SPINES_TEX)
		if res is Texture2D:
			return res as Texture2D
	# 回退：绕过导入系统，直接读原始图片文件
	var img: Image = Image.load_from_file(SPINES_TEX)
	if img != null:
		var tex := ImageTexture.create_from_image(img)
		if tex != null:
			return tex
	return null


## 用整幅书脊图铺书架：整图**按比例切成九条**，绝不拉伸。
##   列宽 = 图宽 / 9（2280 / 9 ≈ 253.33），第 i 条 = region(253.33*i, 0, 253.33, 1280)
##   一条书脊 = 一个 AtlasTexture = 一个 expand_icon 的 Button（按钮自己就是热区）
## 因为走 expand_icon，图标是按"原图 253.33x1280"的宽高比缩进格子并居中的，
## 所以格子多宽多高都只会等比缩放 + 留黑边，书脊上的书名不会像以前那样被压扁。
func _build_shelf_textured(tex: Texture2D) -> Control:
	var n := BOOKS.size()
	var tex_h := float(tex.get_height())
	# 先 float 再除：GDScript 里 i / n 是整除（INTEGER_DIVISION 警告）
	var col_w := float(tex.get_width()) / float(n)

	var shelf := HBoxContainer.new()
	shelf.name = "Shelf"
	shelf.add_theme_constant_override("separation", 0)
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf.custom_minimum_size = Vector2(TEXTURED_SHELF_MIN_W, SHELF_H)

	for i in n:
		var b: Dictionary = BOOKS[i]

		# 第 i 条书脊。region 用浮点乘出来，九列不累计误差
		var slice := AtlasTexture.new()
		slice.atlas = tex
		slice.region = Rect2(col_w * float(i), 0.0, col_w, tex_h)
		# 不让线性过滤采样越出本列，否则书脊边缘会渗出邻列的一条细线
		slice.filter_clip = true

		var hot := Button.new()
		hot.name = "Book%d" % i
		hot.text = ""
		hot.tooltip_text = "%s · %s" % [str(b["author"]), str(b["title"])]
		hot.icon = slice
		# 关键一：expand_icon = true 时，按钮的最小尺寸**不再**把贴图原始尺寸算进去
		#（否则 253x1280 的原图会把每个按钮撑到 1280 高、整条书架爆炸），
		# 图标按比例缩进按钮的可用矩形并居中。
		hot.expand_icon = true
		hot.alignment = HORIZONTAL_ALIGNMENT_CENTER
		hot.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		# 关键二：expand_icon 下按钮可以被压到 0，所以自己给个最小宽度兜底
		hot.custom_minimum_size = Vector2(SPINE_MIN_W, 0.0)
		hot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_hotspot_skin(hot, false)
		shelf.add_child(hot)
		hot.pressed.connect(_on_spine_pressed.bind(i))
		_spine_buttons.append(hot)

	return shelf


## 兜底：代码手绘的书脊。九列，每列只有书名与作者 —— 一个数字都没有。
func _build_shelf_drawn() -> Control:
	var shelf := HBoxContainer.new()
	shelf.name = "Shelf"
	shelf.add_theme_constant_override("separation", 6)
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for i in BOOKS.size():
		var b: Dictionary = BOOKS[i]
		var cell := VBoxContainer.new()
		cell.name = "Cell%d" % i
		cell.add_theme_constant_override("separation", 3)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shelf.add_child(cell)

		var spine := Button.new()
		spine.name = "Book%d" % i
		spine.text = str(b["title"])
		spine.tooltip_text = "%s · %s" % [str(b["author"]), str(b["title"])]
		spine.custom_minimum_size = Vector2(0, 100)
		spine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spine.focus_mode = Control.FOCUS_ALL
		spine.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_spine_skin(spine, false)
		spine.pressed.connect(_on_spine_pressed.bind(i))
		cell.add_child(spine)
		_spine_buttons.append(spine)

		var author := make_text(str(b["author"]), PreludeUI.FS_TIP - 3, PreludeUI.C_INK_DIM)
		author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		author.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cell.add_child(author)

	return shelf


## 手绘书脊的皮肤：opened = true 代表这本已经翻开过，整条翻成暖黄高亮
func _apply_spine_skin(book: Button, opened: bool) -> void:
	var bg := Color(0.87, 0.79, 0.62, 0.94) if opened else Color(0.13, 0.135, 0.16, 0.92)
	var edge := Color(0.98, 0.90, 0.70, 0.95) if opened else Color(0.85, 0.80, 0.70, 0.16)
	var hover := Color(0.90, 0.82, 0.64, 0.98) if opened else Color(0.21, 0.22, 0.26, 0.96)
	var fg := Color(0.10, 0.09, 0.08) if opened else PreludeUI.C_INK

	book.add_theme_stylebox_override("normal", _spine_box(bg, edge))
	book.add_theme_stylebox_override("hover", _spine_box(hover, edge))
	book.add_theme_stylebox_override("pressed", _spine_box(bg, edge))
	book.add_theme_stylebox_override("focus", _spine_box(hover, edge))
	book.add_theme_color_override("font_color", fg)
	book.add_theme_color_override("font_hover_color", fg)
	book.add_theme_color_override("font_pressed_color", fg)
	book.add_theme_font_size_override("font_size", PreludeUI.FS_TIP - 2)


## 贴图版的书脊热区皮肤：平时只有一圈极淡的边，鼠标移上去才亮；
## opened = true 时留一圈暖黄的"已翻开"标记。
func _hotspot_skin(hot: Button, opened: bool) -> void:
	hot.focus_mode = Control.FOCUS_ALL
	hot.clip_text = true
	hot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hot.add_theme_font_size_override("font_size", PreludeUI.FS_TIP - 2)
	hot.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84, 0.72))
	hot.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))

	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.90, 0.86, 0.74, 0.05)
	sb_normal.border_color = Color(0.95, 0.86, 0.66, 0.75) if opened else Color(0.90, 0.86, 0.74, 0.16)
	sb_normal.set_border_width_all(1)
	sb_normal.set_corner_radius_all(2)

	var sb_hover := sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.92, 0.84, 0.62, 0.18)
	sb_hover.border_color = Color(0.95, 0.86, 0.66, 0.80)

	var sb_down := sb_hover.duplicate() as StyleBoxFlat
	sb_down.bg_color = Color(0.95, 0.86, 0.66, 0.30)

	hot.add_theme_stylebox_override("normal", sb_normal)
	hot.add_theme_stylebox_override("hover", sb_hover)
	hot.add_theme_stylebox_override("pressed", sb_down)
	hot.add_theme_stylebox_override("focus", sb_hover)


func _spine_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


# ---------------------------------------------------------------- 右侧：翻开的详情
func _build_reader(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "BookReader"
	panel.add_theme_stylebox_override("panel", PreludeUI.panel_skin(PreludeUI.C_PANEL, PreludeUI.C_LINE, 6))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 放在 HBox 里时这一行等于没写（BoxContainer 在交叉轴上只看 FILL，EXPAND 被忽略）；
	# 但贴图版把它放进右侧栏（VBox）里，就需要它把余下的高度吃满，密码框留在下面。
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "ReaderColumn"
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.name = "ReaderHead"
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)

	_count_label = make_text("已翻开 0 / %d" % BOOKS.size(), PreludeUI.FS_TIP, PreludeUI.C_INK_DIM)
	_count_label.name = "OpenCount"
	# 【坑】make_text 默认开自动换行；这个标签在 HBox 里被挤压时，不关换行会把
	# 「已翻开 0 / 9」竖着排成一列、把详情区挤成 0 高（实测截图确认过）。
	_count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_count_label)

	# 【已删】这里原本还有一行常驻的「卡上数字：0」（_digit_label / CardDigit），
	# 是上一轮为了解决"数字藏在详情页最末、可视高度太矮、玩家永远看不到"才钉上去的。
	# 但它等于把答案直接摆在右栏 —— 现在删掉，而且连详情页里的数字一起删干净：
	# 数字改成从书名 / 作者名的谐音里读（见文件头的对照表）。
	# 拆掉它的三处代价都已经补上：
	#   ① 那一行是 FS_TEXT(19)，比「已翻开」那行高 7px → 头行 27 → 20，全给了滚动区；
	#   ② 它占的 132px 宽度还给标题区，正文每行能多放几个字；
	#   ③ 顶部"上一关的关键词"那一行也删了，省出的 34px 高顺着 EXPAND_FILL 落进
	#      ReaderScroll（实测：可见高 124 → 163，一页 6 行详情不用滚就看得全）。

	col.add_child(PreludeUI.hline(0.0, PreludeUI.C_LINE))

	_scroll = ScrollContainer.new()
	_scroll.name = "ReaderScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_detail = make_rich("")
	_detail.name = "ReaderText"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(1.0, 0.0)
	_scroll.add_child(_detail)


## 「已翻开 N / 9」的刷新口（翻开新书、回到欢迎语都要用）
func _refresh_count() -> void:
	if _count_label != null:
		_count_label.text = "已翻开 %d / %d" % [_open_count, BOOKS.size()]


func _show_welcome() -> void:
	_refresh_count()
	# 【尺寸账】贴图版的详情区可视高度约 165px（≈7 行），这一页只占两行。
	# 只说"没有数字"，不说数字从哪来 —— 那是玩家自己要想的
	# （想不出来时由面板底部那句 hint「书籍？密码？数字？」引路）。
	_detail.text = "点书脊翻开。\n九本书里都没有印数字。"


# ---------------------------------------------------------------- 右侧：确认列
## 这一关需要在面板里直接输入六位密码，输入正确了才可以过关。
func _build_confirm_column(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.name = "ConfirmColumn"
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(252, 0)
	parent.add_child(col)

	# 密码输入提示，一开始隐藏
	_code_label = make_text("输入你算出的六位数字密码：",
			PreludeUI.FS_TEXT, PreludeUI.C_INK_DIM)
	_code_label.visible = false
	col.add_child(_code_label)
	
	# 密码输入框 + 提交按钮，放在同一行，一开始隐藏
	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 8)
	_code_row.visible = false
	col.add_child(_code_row)
	
	# 密码输入框，加上明显的边框
	_code_input = LineEdit.new()
	_code_input.max_length = 6
	_code_input.placeholder_text = "6位数字"
	_code_input.add_theme_font_size_override("font_size", PreludeUI.FS_TEXT)
	# 给输入框加上边框
	var code_box := StyleBoxFlat.new()
	code_box.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	code_box.border_color = Color(0.95, 0.86, 0.66, 0.9)
	code_box.set_border_width_all(2)
	code_box.set_corner_radius_all(4)
	code_box.content_margin_left = 8.0
	code_box.content_margin_right = 8.0
	code_box.content_margin_top = 6.0
	code_box.content_margin_bottom = 6.0
	_code_input.add_theme_stylebox_override("normal", code_box)
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.add_child(_code_input)
	
	# 密码提交按钮
	_code_submit_btn = make_button("提交", false)
	_code_submit_btn.pressed.connect(_on_code_submit)
	_code_row.add_child(_code_submit_btn)
	
	# 提示按钮
	_hint_btn = make_button("提示", false)
	_hint_btn.pressed.connect(_on_hint_pressed)
	col.add_child(_hint_btn)

	_confirm_btn = make_button("记住了", true)
	_confirm_btn.name = "ConfirmButton"
	# 翻开过书脊才放行：不然一句都没看就能秒过这一关
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	col.add_child(_confirm_btn)


func _on_hint_pressed() -> void:
	if _hint_level >= HINTS.size():
		_feedback.text = "已经没有更多提示了。"
		return
	_feedback.text = HINTS[_hint_level]
	_hint_level += 1


# ---------------------------------------------------------------- 密码提交
func _on_code_submit() -> void:
	if _done_locked:
		return
	var input_code := ""
	if _code_input != null:
		input_code = _code_input.text.strip_edges()
	if input_code != CODE:
		_feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		_feedback.text = "密码不正确，再想想。"
		_code_correct = false
		return
	_feedback.add_theme_color_override("font_color", PreludeUI.C_NAME)
	_feedback.text = "密码正确！"
	_code_correct = true
	_done_locked = true
	# 密码正确之后，自动关闭面板，回到宿舍走位场景
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		close_panel({"ok": true, "code": CODE})
	)


# ---------------------------------------------------------------- 翻书
func _on_spine_pressed(index: int) -> void:
	if _done_locked:
		return
	if index < 0 or index >= BOOKS.size():
		return
	
	# 记录点击次数，点击两次同一本书触发星星
	_click_counts[index] = int(_click_counts.get(index, 0)) + 1
	if _click_counts[index] == 2 and not _star_shown:
		_show_star_popup()
		return
	
	_open_book(index)


## 翻开一本书：书脊留个"已翻开"的记号、计数 +1、右侧写满这一页的详情。
func _open_book(index: int) -> void:
	var b: Dictionary = BOOKS[index]
	var btn: Button = _spine_buttons[index] if index < _spine_buttons.size() else null

	if not _opened.has(index):
		_opened[index] = true
		_open_count += 1
		if _confirm_btn != null and _confirm_btn.disabled:
			_confirm_btn.disabled = false
		if btn != null:
			if _textured:
				_hotspot_skin(btn, true)
			else:
				_apply_spine_skin(btn, true)
			btn.tooltip_text = "已经翻过 · %s · %s" % [str(b["author"]), str(b["title"])]

	_refresh_count()
	# 【可读性】旧版把数字钉在正文最末（玩家要滚到底才看得到）；现在这一页只有
	# 书名 / 作者 / 简介 / 作者小传，一共 6 行，详情区（约 7 行）不用滚就看得全。
	# 谐音的线索就在第 2 行的作者名里，翻开即见 —— 别再往这一页塞东西。
	if _scroll != null:
		_scroll.scroll_vertical = 0

	var name_hex := _hex(PreludeUI.C_NAME)
	var dim_hex := _hex(PreludeUI.C_INK_DIM)
	var lines := PackedStringArray()
	lines.append("[color=#%s]《%s》[/color]" % [name_hex, str(b["title"])])
	# 作者名旁直接标国籍（如 绫辻行人 · 日本），点开书脊就能看见作家名字和国家，
	# 六本日本作家一眼可筛；这一行不额外占高度（与作者同行）。
	lines.append("[color=#%s]%s · %s[/color]" % [dim_hex, str(b["author"]), str(b.get("country", ""))])
	lines.append("")
	lines.append(str(b["blurb"]))
	lines.append("")
	lines.append("[color=#%s]%s[/color]" % [dim_hex, str(b["note"])])
	_detail.text = "\n".join(lines)


# ---------------------------------------------------------------- 确认
## 翻完书点"记住了"之后，显示密码输入框
func _on_confirm() -> void:
	if _done_locked:
		return
	if _code_correct:
		return
	# 显示密码输入框和提示文字
	_code_label.visible = true
	_code_row.visible = true
	# 隐藏"记住了"按钮和提示按钮
	_confirm_btn.visible = false
	_hint_btn.visible = false
	_feedback.add_theme_color_override("font_color", PreludeUI.C_ACCENT)
	_feedback.text = "输入你算出的六位数字密码："


func _hex(c: Color) -> String:
	return c.to_html(false)


# ---------------------------------------------------------------- 星星弹窗
func _show_star_popup() -> void:
	_star_shown = true
	# 创建弹窗
	var popup := PanelContainer.new()
	popup.add_theme_stylebox_override("panel", PreludeUI.panel_skin(Color(0.15, 0.12, 0.10, 0.98), Color(0.95, 0.86, 0.66, 0.8), 8))
	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(400, 300)
	add_child(popup)
	
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup.add_child(col)
	
	# 两颗星星重叠显示
	var star_container := Control.new()
	star_container.custom_minimum_size = Vector2(0, 150)
	star_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(star_container)
	
	var star_tex: Texture2D = load("res://assets/props/paper_star.png")
	if star_tex != null:
		# 第一颗星星，偏左
		var star1 := TextureRect.new()
		star1.texture = star_tex
		star1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star1.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		star1.offset_left = -30
		star1.offset_right = 50
		star1.offset_top = 10
		star1.offset_bottom = 130
		star_container.add_child(star1)
		
		# 第二颗星星，偏右，和第一颗重叠50%
		var star2 := TextureRect.new()
		star2.texture = star_tex
		star2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star2.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		star2.offset_left = 10
		star2.offset_right = 90
		star2.offset_top = 10
		star2.offset_bottom = 130
		star_container.add_child(star2)
	
	# 星星文案
	var text := make_rich("【两粒黄色的折纸星星：……】\n\n其中两个角被书压扁了。")
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(text)
	
	# 关闭按钮
	var close_btn := make_button("先收起来吧", true)
	close_btn.pressed.connect(func() -> void:
		popup.queue_free()
		_open_book(0)  # 关闭后回到第一本书的详情
	)
	col.add_child(close_btn)
