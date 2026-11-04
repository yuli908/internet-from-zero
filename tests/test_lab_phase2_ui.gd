extends RefCounted

## 实验室阶段 2 验收：首屏三块、制作台分类/抽屉/配方、原型台吸附、模块架 6×5 与右键菜单、
## 代码编辑器三栏与真实文件系统、实验室入口回归。几何数值只读生产代码静态函数。

const Lab = preload("res://src/ui/screens/laboratory_screen.gd")
const CraftGd = preload("res://src/ui/screens/lab_craft.gd")
const RackGd = preload("res://src/ui/screens/lab_rack.gd")
const CodeGd = preload("res://src/ui/screens/lab_code_editor.gd")

const EXPECT := 120
const EXPECT_GROUPS := {
	"hub_geometry": 19, "craft_zones": 21, "craft_data": 11, "rack_zones": 15,
	"rack_menu": 9, "editor_zones": 12, "editor_fs": 15, "entry_regression": 7,
	"no_hint_text": 5, "phase1_kept": 6,
}
const GROUP_DESCRIPTIONS := {
	"hub_geometry": "首屏制作台 604×470、原型台 610×470、模块架 1232×124，间距 18、右缘 1232、4 行 580×92、12 格 88×88",
	"craft_zones": "制作台二级 236+18+724+18+236、6 段分类 236×96、抽屉头 56/体 520、行 690×56 行距 8",
	"craft_data": "配方行来自目录真实配方，M00 走购买；不自带价格字面量，合成/购买走 Economy",
	"rack_zones": "模块架 908 + 18 + 306、6×5 槽 144×112 间距 8、共 30 格且不越界",
	"rack_menu": "只有模块有右键菜单；编写代码只在 W05 出现，菜单高度按项数",
	"editor_zones": "代码编辑器 236/724/236、行号列 44、行高 22、P03 门禁、根目录可解析且为绝对路径",
	"editor_fs": "解析到宿主真实目录（非 user:// 兜底）、写入 /home/user 种子文件并读回、相对/不可用路径被拒绝且不降级、界面显示实际路径",
	"entry_regression": "章末 6/6 完成后实验室按钮不静默 return：回退最后已解锁 lab 或禁用+tooltip",
	"no_hint_text": "新增四个 UI 文件不含点击/已完成/请先等操作提示句，菜单项不是句子",
	"phase1_kept": "阶段 1 三区几何与 6 门槽保留，原型台按 110×60 吸附，首屏默认停在 hub",
}

func run(ctx: TestContext) -> void:
	if DataDB.catalog == null:
		DataDB.load_all()
	# ---- 首屏三块 ----
	var h: Dictionary = Lab.hub_rects()
	var bench: Rect2 = h["bench"]
	var proto: Rect2 = h["proto"]
	var rack: Rect2 = h["rack"]
	ctx.begin_group("hub_geometry")
	ctx.eq("制作台 x=0", bench.position.x, 0.0)
	ctx.eq("制作台宽 604", bench.size.x, 604.0)
	ctx.eq("制作台高 470", bench.size.y, 470.0)
	ctx.eq("原型台 x=622", proto.position.x, 622.0)
	ctx.eq("原型台宽 610", proto.size.x, 610.0)
	ctx.eq("原型台高 470", proto.size.y, 470.0)
	ctx.eq("模块架 y=488", rack.position.y, 488.0)
	ctx.eq("模块架宽 1232", rack.size.x, 1232.0)
	ctx.eq("模块架高 124", rack.size.y, 124.0)
	ctx.eq("首屏横向间距 18", proto.position.x - bench.end.x, 18.0)
	ctx.eq("首屏纵向间距 18", rack.position.y - bench.end.y, 18.0)
	ctx.eq("首屏右缘 1232", rack.end.x, 1232.0)
	var row: Rect2 = Lab.hub_row_rect(0)
	ctx.eq("首屏行宽 580", row.size.x, 580.0)
	ctx.eq("首屏行高 92", row.size.y, 92.0)
	ctx.eq("首屏行距 8", Lab.hub_row_rect(1).position.y - row.end.y, 8.0)
	ctx.check("4 行不越出制作台", Lab.hub_row_rect(3).end.y <= bench.size.y,
		"row3=%s" % str(Lab.hub_row_rect(3)))
	var hs: Rect2 = Lab.hub_rack_slot_rect(0)
	ctx.eq("模块架格 88×88", hs.size, Vector2(88, 88))
	ctx.eq("模块架格间距 8", Lab.hub_rack_slot_rect(1).position.x - hs.end.x, 8.0)
	ctx.check("12 格不越出模块架", Lab.hub_rack_slot_rect(11).end.x <= rack.size.x,
		"last=%s" % str(Lab.hub_rack_slot_rect(11)))

	# ---- 制作台二级几何 ----
	var cz: Dictionary = CraftGd.zone_rects()
	var band: Rect2 = cz["band"]
	var list: Rect2 = cz["list"]
	var insp: Rect2 = cz["inspector"]
	ctx.begin_group("craft_zones")
	ctx.eq("分类带 x=0", band.position.x, 0.0)
	ctx.eq("分类带宽 236", band.size.x, 236.0)
	ctx.eq("列表 x=254", list.position.x, 254.0)
	ctx.eq("列表宽 724", list.size.x, 724.0)
	ctx.eq("检查器 x=996", insp.position.x, 996.0)
	ctx.eq("检查器宽 236", insp.size.x, 236.0)
	ctx.eq("左间距 18", list.position.x - band.end.x, 18.0)
	ctx.eq("右间距 18", insp.position.x - list.end.x, 18.0)
	ctx.eq("右缘 1232", insp.end.x, 1232.0)
	ctx.eq("三栏同高 612", [band.size.y, list.size.y, insp.size.y], [612.0, 612.0, 612.0])
	ctx.eq("分类段 6 个", CraftGd.category_keys().size(), 6)
	ctx.eq("分类段高 96", CraftGd.cat_rect(0).size.y, 96.0)
	ctx.eq("分类段距 6", CraftGd.cat_rect(1).position.y - CraftGd.cat_rect(0).end.y, 6.0)
	ctx.check("第 6 段收在 606", CraftGd.cat_rect(5).end.y == 606.0,
		"end=%.1f" % CraftGd.cat_rect(5).end.y)
	ctx.eq("抽屉头高 56", CraftGd.drawer_header_rect().size.y, 56.0)
	ctx.eq("抽屉体 y=64", CraftGd.drawer_body_rect().position.y, 64.0)
	ctx.eq("抽屉体高 520", CraftGd.drawer_body_rect().size.y, 520.0)
	ctx.eq("抽屉行宽 690", CraftGd.row_rect(0).size.x, 690.0)
	ctx.eq("抽屉行高 56", CraftGd.row_rect(0).size.y, 56.0)
	ctx.eq("抽屉行距 8", CraftGd.row_rect(1).position.y - CraftGd.row_rect(0).end.y, 8.0)
	ctx.check("8 行装进 520", CraftGd.row_rect(7).end.y <= CraftGd.drawer_body_rect().size.y,
		"row7=%s" % str(CraftGd.row_rect(7)))

	# ---- 配方数据 ----
	var cat: Catalog = DataDB.catalog
	var rows: Array = CraftGd.all_rows()
	var rids := {}
	for rid in cat.recipe_ids():
		rids[str(rid)] = true
	ctx.begin_group("craft_data")
	ctx.check("配方行非空", not rows.is_empty(), "n=%d" % rows.size())
	var buy_n := 0
	for raw in rows:
		if str((raw as Dictionary).get("kind", "")) == "buy":
			buy_n += 1
	ctx.eq("购买行只有 M00 一条", buy_n, 1)
	ctx.check("购买行是 M00", _has_buy(rows, "M00"))
	var craft_bad := 0
	var hidden_bad := 0
	var layer_bad := 0
	for raw in rows:
		var r: Dictionary = raw
		if str(r.get("kind", "")) != "craft":
			continue
		var rid := str(r.get("rid", ""))
		if not rids.has(rid):
			craft_bad += 1
		if bool(cat.item(str(r.get("id", ""))).get("hidden", false)):
			hidden_bad += 1
		var lay := str(cat.item(str(r.get("id", ""))).get("layer", ""))
		if lay != str(r.get("layer", "")):
			layer_bad += 1
	ctx.check("配方行都指向真实配方", craft_bad == 0, "bad=%d" % craft_bad)
	ctx.check("配方行不包含隐藏件", hidden_bad == 0, "bad=%d" % hidden_bad)
	ctx.check("行层与目录层一致", layer_bad == 0, "bad=%d" % layer_bad)
	ctx.eq("分类键顺序 M/G/S/H/W/P", CraftGd.category_keys(), ["M", "G", "S", "H", "W", "P"])
	ctx.check("M 分类有行", CraftGd.rows_for("M").size() > 0, "n=%d" % CraftGd.rows_for("M").size())
	var src := FileAccess.get_file_as_string("res://src/ui/screens/lab_craft.gd")
	ctx.check("合成调用 Economy.craft", src.contains("Economy.craft("))
	ctx.check("价格只读 Economy.price_of", src.contains("Economy.price_of("))
	ctx.check("购买调用 Economy.buy", src.contains("Economy.buy("))

	# ---- 模块架几何 ----
	var rz: Dictionary = RackGd.zone_rects()
	var grid: Rect2 = rz["grid"]
	var detail: Rect2 = rz["detail"]
	ctx.begin_group("rack_zones")
	ctx.eq("背包网格 x=0", grid.position.x, 0.0)
	ctx.eq("背包网格宽 908", grid.size.x, 908.0)
	ctx.eq("详情 x=926", detail.position.x, 926.0)
	ctx.eq("详情宽 306", detail.size.x, 306.0)
	ctx.eq("中间间距 18", detail.position.x - grid.end.x, 18.0)
	ctx.eq("右缘 1232", detail.end.x, 1232.0)
	ctx.eq("两栏同高 612", [grid.size.y, detail.size.y], [612.0, 612.0])
	ctx.eq("槽宽 144", RackGd.slot_rect(0).size.x, 144.0)
	ctx.eq("槽高 112", RackGd.slot_rect(0).size.y, 112.0)
	ctx.eq("槽距 8", RackGd.slot_rect(1).position.x - RackGd.slot_rect(0).end.x, 8.0)
	ctx.eq("6 列", RackGd.COLS, 6)
	ctx.eq("5 行", RackGd.ROWS, 5)
	ctx.eq("共 30 格", RackGd.slot_count(), 30)
	ctx.check("最后一格不越界", RackGd.slot_rect(29).end.x <= grid.size.x and RackGd.slot_rect(29).end.y <= grid.size.y,
		"last=%s" % str(RackGd.slot_rect(29)))
	ctx.check("第 7 格换行", RackGd.slot_rect(6).position.x == RackGd.slot_rect(0).position.x
		and RackGd.slot_rect(6).position.y > RackGd.slot_rect(0).position.y,
		"slot6=%s" % str(RackGd.slot_rect(6)))

	# ---- 右键菜单 ----
	var w05: Array = RackGd.menu_items("W05")
	ctx.begin_group("rack_menu")
	ctx.eq("W05 菜单 3 项", w05.size(), 3)
	ctx.check("W05 首项是编写代码", str((w05[0] as Dictionary).get("id", "")) == "code", str(w05))
	ctx.check("W05 允许代码入口", RackGd.code_entry_allowed("W05"))
	ctx.check("W01 不允许代码入口", not RackGd.code_entry_allowed("W01"))
	ctx.check("非模块无右键菜单", RackGd.menu_items("M00").is_empty(), str(RackGd.menu_items("M00")))
	ctx.eq("W05 菜单高 132", RackGd.menu_height("W05"), 132.0)
	ctx.eq("W01 菜单高 88", RackGd.menu_height("W01"), 88.0)
	ctx.check("W05 属于模块", RackGd.is_module("W05"))
	ctx.check("M00 不是模块", not RackGd.is_module("M00"))

	# ---- 代码编辑器几何与门禁 ----
	var ez: Dictionary = CodeGd.zone_rects()
	var tree: Rect2 = ez["tree"]
	var edit: Rect2 = ez["edit"]
	var term: Rect2 = ez["terminal"]
	ctx.begin_group("editor_zones")
	ctx.eq("目录树 x=0", tree.position.x, 0.0)
	ctx.eq("目录树宽 236", tree.size.x, 236.0)
	ctx.eq("代码区 x=254", edit.position.x, 254.0)
	ctx.eq("代码区宽 724", edit.size.x, 724.0)
	ctx.eq("终端 x=996", term.position.x, 996.0)
	ctx.eq("终端宽 236", term.size.x, 236.0)
	ctx.eq("三栏同高 612", [tree.size.y, edit.size.y, term.size.y], [612.0, 612.0, 612.0])
	ctx.eq("行号列 44", CodeGd.GUTTER_W, 44.0)
	ctx.eq("行高 22", CodeGd.LINE_H, 22.0)
	ctx.check("有 P03 可运行", CodeGd.can_run(true))
	ctx.check("无 P03 禁用运行", not CodeGd.can_run(false))
	ctx.check("根目录可解析且绝对", bool(CodeGd.resolve_fs_root()["ok"]) and CodeGd.root_abs().is_absolute_path(), CodeGd.root_abs())

	# ---- 真实文件系统（宿主目录，不是 user:// 兜底） ----
	ctx.begin_group("editor_fs")
	var rr := CodeGd.resolve_fs_root()
	ctx.check("默认根解析成功", bool(rr["ok"]), str(rr["reason"]))
	ctx.check("根是宿主绝对路径", str(rr["abs"]).is_absolute_path(), str(rr["abs"]))
	ctx.eq("根首选工程内可见目录", str(rr["kind"]), "project")
	ctx.check("根不是 user:// 兜底", not str(rr["abs"]).begins_with(ProjectSettings.globalize_path("user://")), str(rr["abs"]))
	var rel := CodeGd.resolve_fs_root("relative/labfs")
	ctx.check("相对路径被拒", not bool(rel["ok"]) and str(rel["reason"]) == "relative", str(rel["reason"]))
	ctx.eq("显式指定不可用不降级", str(rel["kind"]), "override")
	ctx.eq("工程不可用才落 user 兜底", str(CodeGd.resolve_fs_root("", "relative/labfs")["kind"]), "user")
	ctx.check("根不可用时禁止运行", not CodeGd.run_allowed(true, false))
	ctx.check("根可用且有 P03 才运行", CodeGd.run_allowed(true, true))
	var edsrc := FileAccess.get_file_as_string("res://src/ui/screens/lab_code_editor.gd")
	ctx.check("界面显示实际根路径", edsrc.contains("_root_label.text = _root"))

	var editor: Control = CodeGd.new()
	editor.call("apply_root")
	editor.call("_ensure_fs")
	var root := str(editor.call("root_path"))
	ctx.check("种子 main.c 存在", FileAccess.file_exists(root + "/home/user/main.c"), root)
	ctx.check("种子 notes.txt 存在", FileAccess.file_exists(root + "/home/user/notes.txt"), root)
	ctx.check("种子 /etc/hostname 存在", FileAccess.file_exists(root + "/etc/hostname"), root)
	ctx.eq("括号平衡返回 0", CodeGd.first_brace_error("int main(void) {\n}\n"), 0)
	ctx.eq("多余右括号返回行号 1", CodeGd.first_brace_error("}\n"), 1)
	editor.free()

	# ---- 入口回归 ----
	var wb := FileAccess.get_file_as_string("res://src/ui/screens/workbench_screen.gd")
	var body := _body(wb, "func _open_laboratory", "func select_lab")
	var main_src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	var lab_src := FileAccess.get_file_as_string("res://src/ui/screens/laboratory_screen.gd")
	ctx.begin_group("entry_regression")
	ctx.check("入口兜底函数存在", wb.contains("static func resolve_entry_lab"))
	ctx.check("无可进实验时按钮灰化", wb.contains("_update_rail_lock(\"labs\", entry.is_empty())"))
	ctx.check("禁用态带 tooltip", wb.contains("本章还没有可进入的实验"))
	ctx.check("进实验室无 next_objective 静默门槛", not body.contains("next_objective"), body)
	ctx.check("进实验室直达 laboratory 屏", body.contains("show_screen\", \"laboratory\""))
	ctx.check("实验室支持逐级返回", lab_src.contains("func back_one_level"))
	ctx.check("主壳返回键先逐级", main_src.contains("func _level_back") and main_src.contains("_level_back()"))

	# ---- 无提示句 ----
	var files := [
		"res://src/ui/screens/lab_craft.gd",
		"res://src/ui/screens/lab_rack.gd",
		"res://src/ui/screens/lab_code_editor.gd",
		"res://src/ui/screens/laboratory_screen.gd",
	]
	var joined := ""
	for f in files:
		joined += FileAccess.get_file_as_string(str(f))
	ctx.begin_group("no_hint_text")
	ctx.check("无「点击」", not joined.contains("点击"))
	ctx.check("无「已完成」", not joined.contains("已完成"))
	ctx.check("无「请先」", not joined.contains("请先"))
	ctx.check("无「操作提示」", not joined.contains("操作提示"))
	var labels_ok := true
	for raw in w05:
		var label := str((raw as Dictionary).get("label", ""))
		if label.length() > 6 or label.contains("点击"):
			labels_ok = false
	ctx.check("菜单项不是句子", labels_ok, str(w05))

	# ---- 阶段 1 保留 ----
	var p1: Dictionary = Lab.zone_rects()
	ctx.begin_group("phase1_kept")
	ctx.eq("原型台元件台宽 236", (p1["bench"] as Rect2).size.x, 236.0)
	ctx.eq("原型台画布宽 724", (p1["canvas"] as Rect2).size.x, 724.0)
	ctx.eq("原型台收纳区宽 236", (p1["store"] as Rect2).size.x, 236.0)
	ctx.eq("保留 6 个门槽", Lab.palette_gates().size(), 6)
	ctx.check("原型台按 110×60 吸附", lab_src.contains("snap_grid = Vector2(110, 60)"))
	ctx.check("首屏默认 hub", lab_src.contains("show_level(\"hub\")"))

func _has_buy(rows: Array, item_id: String) -> bool:
	for raw in rows:
		var r: Dictionary = raw
		if str(r.get("kind", "")) == "buy" and str(r.get("id", "")) == item_id:
			return true
	return false

func _body(src: String, sig: String, next_sig: String) -> String:
	var a := src.find(sig)
	if a < 0:
		return ""
	var b := src.find(next_sig, a + 1)
	if b < 0:
		return src.substr(a)
	return src.substr(a, b - a)
