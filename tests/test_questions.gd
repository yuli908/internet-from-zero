extends RefCounted

## M4-G5：题库 `ifz-questions/1` 的加载 / 字段校验 / 评分确定性。
## fixture 只放在 `tests/fixtures/questions/`，不进 `data/`（正式题目由教学组交付）。

const FIXTURE := "res://tests/fixtures/questions/ch01_exercises.json"

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 37
const EXPECT_GROUPS := {
	"loadable": 1, "valid_doc": 6, "scoring": 14, "unknown_item": 4,
	"validation": 9, "error_codes": 3,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "fixture 文件存在且 JSON 可解析成字典",
	"valid_doc": "合法 fixture 校验零错、条数/取题/字段保留正确",
	"scoring": "选项题与数值题判对判错、形状不符、同输入同分、搭建题送人工 rubric",
	"unknown_item": "未知题 id 不判过、错误码 E_UNKNOWN_ITEM、得分 0",
	"validation": "每类非法文档（重复 id / 缺 stem / 非法 type / 解太少 / rubric 权重 / bank / format）被拒",
	"error_codes": "错因码数量与首末码（C1–C9）",
}

func run(ctx: TestContext) -> void:
	var doc := _load_fixture()
	ctx.begin_group("loadable")
	ctx.check("M4-G5 fixture 存在且可解析", not doc.is_empty(), FIXTURE)
	_test_valid_doc(ctx, doc)
	_test_score(ctx, doc)
	_test_unknown(ctx, doc)
	_test_validation(ctx, doc)
	_test_error_codes(ctx)

func _test_valid_doc(ctx: TestContext, doc: Dictionary) -> void:
	var q := QuestionBank.from_doc(doc)
	ctx.begin_group("valid_doc")
	ctx.eq("M4-G5 fixture 校验通过", q.load_errors.size(), 0)
	ctx.eq("M4-G5 fixture 条数 3", q.items.size(), 3)
	ctx.check("M4-G5 可按 id 取题", not q.item("fx-choice").is_empty())
	ctx.check("M4-G5 by_id 唯一", q.has("fx-choice") and q.has("fx-compute") and q.has("fx-build"))
	var it := q.item("fx-choice")
	ctx.eq("M4-G5 题目保留 type", str(it.get("type", "")), "understanding")
	ctx.eq("M4-G5 题目 solutions ≥2", (it.get("solutions", []) as Array).size(), 2)

func _test_score(ctx: TestContext, doc: Dictionary) -> void:
	var q := QuestionBank.from_doc(doc)
	var correct := q.score("fx-choice", {"choice": 2})
	ctx.begin_group("scoring")
	ctx.check("M4-G5 选项题判对 ok", bool(correct["ok"]))
	ctx.eq("M4-G5 选项题判对得分", int(correct["score"]), 100)
	var wrong := q.score("fx-choice", {"choice": 0})
	ctx.eq("M4-G5 选项题判错得分", int(wrong["score"]), 0)
	var bad := q.score("fx-choice", {"text": "NAND"})
	ctx.check("M4-G5 response 形状不符 ok=false", not bool(bad["ok"]))
	ctx.eq("M4-G5 response 形状不符错误码", str(bad["error_code"]), "E_RESPONSE")

	var num_ok := q.score("fx-compute", {"value": 4.0})
	ctx.eq("M4-G5 数值题判对得分", int(num_ok["score"]), 100)
	var num_bad := q.score("fx-compute", {"value": 5})
	ctx.eq("M4-G5 数值题判错得分", int(num_bad["score"]), 0)
	var num_type := q.score("fx-compute", {"value": "4"})
	ctx.check("M4-G5 数值题 response 类型不符 ok=false", not bool(num_type["ok"]))

	ctx.eq("M4-G5 同输入两次同分（对）", int(q.score("fx-choice", {"choice": 2})["score"]),
		int(correct["score"]))
	ctx.eq("M4-G5 同输入两次同分（错）", int(q.score("fx-choice", {"choice": 0})["score"]),
		int(wrong["score"]))

	var manual := q.score("fx-build", {"graph": null})
	ctx.check("M4-G5 搭建题 ok", bool(manual["ok"]))
	ctx.check("M4-G5 搭建题交人工 rubric", bool(manual.get("manual", false)))
	ctx.eq("M4-G5 搭建题不自动编分", int(manual["score"]), 0)
	ctx.eq("M4-G5 满分固定 100", int(manual["max"]), 100)

func _test_unknown(ctx: TestContext, doc: Dictionary) -> void:
	var q := QuestionBank.from_doc(doc)
	var r := q.score("fx-does-not-exist", {"choice": 0})
	ctx.begin_group("unknown_item")
	ctx.check("M4-G5 未知题 id → ok=false", not bool(r["ok"]))
	ctx.eq("M4-G5 未知题错误码", str(r["error_code"]), "E_UNKNOWN_ITEM")
	ctx.eq("M4-G5 未知题得分 0", int(r["score"]), 0)
	ctx.check("M4-G5 未知题 item() 返回空", q.item("fx-does-not-exist").is_empty())

func _test_validation(ctx: TestContext, doc: Dictionary) -> void:
	var dup := doc.duplicate(true)
	var dup_items: Array = dup["items"]
	dup_items[1]["id"] = "fx-choice"
	ctx.begin_group("validation")
	ctx.check("M4-G5 id 重复被拒", _errs(dup).size() > 0)

	var no_stem := doc.duplicate(true)
	var no_stem_items: Array = no_stem["items"]
	no_stem_items[0].erase("stem")
	ctx.check("M4-G5 缺 stem 被拒", _errs(no_stem).size() > 0)

	var bad_type := doc.duplicate(true)
	var bad_type_items: Array = bad_type["items"]
	bad_type_items[0]["type"] = "essay"
	ctx.check("M4-G5 type 非法被拒", _errs(bad_type).size() > 0)

	var one_sol := doc.duplicate(true)
	var one_sol_items: Array = one_sol["items"]
	one_sol_items[1]["solutions"] = [{"label": "唯一解", "approach": "…"}]
	ctx.check("M4-G5 solutions < 2 被拒", _errs(one_sol).size() > 0)

	var bad_rubric := doc.duplicate(true)
	var bad_rubric_items: Array = bad_rubric["items"]
	bad_rubric_items[0]["rubric"] = [{"dim": "结论", "weight": 70}]
	ctx.check("M4-G5 rubric 权重和 ≠ 100 被拒", _errs(bad_rubric).size() > 0)

	var build_no_correct := doc.duplicate(true)
	var build_items: Array = build_no_correct["items"]
	build_items[2]["rubric"] = [{"dim": "结构说明", "weight": 100}]
	ctx.check("M4-G5 搭建题缺正确性维被拒", _errs(build_no_correct).size() > 0)

	var bad_bank := doc.duplicate(true)
	bad_bank["bank"] = "exam"
	ctx.check("M4-G5 bank 非法被拒", _errs(bad_bank).size() > 0)

	var one_item := doc.duplicate(true)
	var one_item_items: Array = one_item["items"]
	one_item_items.resize(1)
	ctx.check("M4-G5 条数不写死（1 条也合法）", _errs(one_item).is_empty())

	var fmt := doc.duplicate(true)
	fmt["format"] = "ifz-questions/2"
	ctx.check("M4-G5 format 不符被拒", _errs(fmt).size() > 0)

func _test_error_codes(ctx: TestContext) -> void:
	var codes := QuestionBank.error_codes()
	ctx.begin_group("error_codes")
	ctx.eq("M4-G5 错因码 9 个（C1–C9）", codes.size(), 9)
	ctx.eq("M4-G5 首个错因码", str(codes[0]), "C1")
	ctx.eq("M4-G5 末个错因码", str(codes[8]), "C9")

func _errs(doc: Dictionary) -> Array:
	return QuestionBank.from_doc(doc).validate()

func _load_fixture() -> Dictionary:
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
