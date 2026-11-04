extends RefCounted

## M4-G6：难度三档预留（名字 / 归一 / 默认值 / 存档往返 / 缺字段回落）。
## 本轮不验任何仿真行为差异（M5 才接入 SYNC/MASK 语义）。

func run(ctx: TestContext) -> void:
	_test_names(ctx)
	_test_default(ctx)
	_test_roundtrip(ctx)
	_test_fallback(ctx)

func _test_names(ctx: TestContext) -> void:
	ctx.eq("M4-G6 三档名字", Difficulty.names(), ["EXPLAIN", "SYNC", "MASK"])
	ctx.eq("M4-G6 常量 EXPLAIN", Difficulty.EXPLAIN, "EXPLAIN")
	ctx.eq("M4-G6 常量 SYNC", Difficulty.SYNC, "SYNC")
	ctx.eq("M4-G6 常量 MASK", Difficulty.MASK, "MASK")
	for n in Difficulty.names():
		ctx.check("M4-G6 %s 合法" % str(n), Difficulty.is_valid(str(n)))
	ctx.check("M4-G6 未知值非法", not Difficulty.is_valid("HARD"))
	ctx.check("M4-G6 小写不合法", not Difficulty.is_valid("explain"))
	ctx.eq("M4-G6 未知值归一 EXPLAIN", Difficulty.normalize("HARD"), Difficulty.EXPLAIN)
	ctx.eq("M4-G6 空串归一 EXPLAIN", Difficulty.normalize(""), Difficulty.EXPLAIN)
	ctx.eq("M4-G6 SYNC 原样保留", Difficulty.normalize(Difficulty.SYNC), Difficulty.SYNC)
	ctx.eq("M4-G6 MASK 原样保留", Difficulty.normalize(Difficulty.MASK), Difficulty.MASK)

func _test_default(ctx: TestContext) -> void:
	var s := PlayerState.new(7)
	ctx.eq("M4-G6 新档默认 EXPLAIN", s.difficulty, Difficulty.EXPLAIN)
	s.difficulty = Difficulty.MASK
	var d := s.to_dict()
	ctx.check("M4-G6 to_dict 写 settings.difficulty", (d["settings"] as Dictionary).has("difficulty"))
	ctx.eq("M4-G6 存盘值", str((d["settings"] as Dictionary)["difficulty"]), "MASK")

func _test_roundtrip(ctx: TestContext) -> void:
	for n in Difficulty.names():
		var s := PlayerState.new(1)
		s.difficulty = str(n)
		var restored := PlayerState.from_dict(s.to_dict())
		ctx.eq("M4-G6 存档往返保留 %s" % str(n), restored.difficulty, str(n))

func _test_fallback(ctx: TestContext) -> void:
	var base := PlayerState.new(1).to_dict()
	base.erase("settings")
	ctx.eq("M4-G6 缺 settings 读档回落 EXPLAIN",
		PlayerState.from_dict(base).difficulty, Difficulty.EXPLAIN)

	var invalid := PlayerState.new(1).to_dict()
	invalid["settings"] = {"difficulty": "HARD"}
	ctx.eq("M4-G6 非法值读档回落 EXPLAIN",
		PlayerState.from_dict(invalid).difficulty, Difficulty.EXPLAIN)

	var weird := PlayerState.new(1).to_dict()
	weird["settings"] = "broken"
	ctx.eq("M4-G6 settings 非字典读档回落 EXPLAIN",
		PlayerState.from_dict(weird).difficulty, Difficulty.EXPLAIN)

	var v1 := {"version": 1, "gold": 0, "xp": 0}
	ctx.eq("M4-G6 v1 旧档无字段回落 EXPLAIN",
		PlayerState.from_dict(v1).difficulty, Difficulty.EXPLAIN)
	ctx.eq("M4-G6 读档不升存档版本", PlayerState.from_dict(v1).save_version, 1)
