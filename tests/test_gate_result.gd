extends RefCounted

## M5 结构化失败回传：code 枚举、error_tags 映射、attempt 计数、每类 gate 的精度。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 315
const EXPECT_GROUPS := {
	"code_registry": 1, "per_code_contract": 90, "make_record": 15, "tag_mapping": 11,
	"tag_map_six_classes": 42, "doc_tag_table": 20, "log_only": 13, "unknown_code": 6,
	"attempts": 13, "report_shape": 13, "voltage": 10, "binary": 12, "boolean": 22,
	"gate": 18, "signal": 14, "half_adder": 15,
}
const GROUP_DESCRIPTIONS := {
	"code_registry": "反向完整性：TAG_MAP 的每个键都必须登记在 NAMES 里",
	"per_code_contract": "每个 code 的名字回读、在 TAG_MAP 里、有 describe 文案，且名字表唯一、OK=0、只有 OK 判成功",
	"make_record": "make 产出的七个字段齐全且取值正确，负 attempt 夹到 0",
	"tag_mapping": "各 code 到 K/S/C/P/M/R 标签的定稿映射",
	"tag_map_six_classes": "TAG_MAP 里每个标签都落在六类之内",
	"doc_tag_table": "19 条 code 的标签与 05-failure-diagnostics.md §1 表逐条对账",
	"log_only": "4/5/10/99 纯 R 只进日志不进阶梯，且纯 R 只允许这些码与 E_PENDING",
	"unknown_code": "未知 code 归一 E_GENERIC：名字/tags/describe/make 全部兜底",
	"attempts": "GateAttemptTracker 计数、通过清零、按 id 隔离、空 id 与整体重置、字典往返",
	"report_shape": "GateReport 的 legacy/add_case/first_failure/failure_codes/全过语义",
	"voltage": "电压 gate：正确解全过，改掉期望值后落 E_OUTPUT_MISMATCH 且回传输入/期望/实际",
	"binary": "二进制 gate：覆盖率缺失、目标未达成、选择题、未知 kind 四类失败码与字段",
	"boolean": "布尔表 gate：单元格错、缺行、部分填写计数、全错、德摩根表、未知 kind",
	"gate": "门级 gate：真值表行错、延迟超限、未封装、第二结构缺失/雷同、未知 kind",
	"signal": "信号 gate：延迟不符、毛刺、修复未做、选择题、未知 kind 五类失败码",
	"half_adder": "半加器：真值表进位错、延迟超限、未封装、随机行、悬空线回传",
}

func run(ctx: TestContext) -> void:
	_result_contract(ctx)
	_tag_mapping(ctx)
	_tag_table_matches_doc(ctx)
	_log_only_codes(ctx)
	_unknown_code(ctx)
	_attempts(ctx)
	_report_shape(ctx)
	var labs: Dictionary = TestUtil.labs_doc().get("labs", {})
	_voltage(ctx, labs.get("level", {}))
	_binary(ctx, labs.get("binary", {}))
	_boolean(ctx, labs.get("boolean", {}))
	_gate(ctx, labs.get("gate", {}))
	_signal(ctx, labs.get("signal", {}))
	_half_adder(ctx, labs.get("half_adder", {}))

# --- 枚举与形状 ---

func _result_contract(ctx: TestContext) -> void:
	var keys: Array = GateResult.NAMES.keys()
	keys.sort()
	ctx.begin_group("code_registry")
	# 反向完整性：TAG_MAP 有键而 NAMES 没有 → 说明新码只加了标签没登记名字。
	var unmapped: Array = []
	for k in GateResult.TAG_MAP.keys():
		if not GateResult.NAMES.has(int(k)):
			unmapped.append(int(k))
	ctx.check("TAG_MAP 的键都在 NAMES 内", unmapped.is_empty(), str(unmapped))
	var unique := {}
	for k in keys:
		ctx.begin_group("per_code_contract")
		ctx.eq("code name %d" % int(k), GateResult.name_of(int(k)), str(GateResult.NAMES[k]))
		unique[str(GateResult.NAMES[k])] = true
		ctx.check("code in tag map %d" % int(k), GateResult.TAG_MAP.has(int(k)))
		ctx.check("code has describe %d" % int(k), GateResult.DESCRIBE.has(int(k)))
	ctx.eq("code names unique", unique.size(), keys.size())
	ctx.check("OK is zero", GateResult.OK == 0)
	ctx.check("is_ok only for OK", GateResult.is_ok(GateResult.OK) and not GateResult.is_ok(GateResult.E_TRUTH_ROW))
	var r := GateResult.make(GateResult.E_DELAY_EXCEED, "T1.5-1", {"a": "1"}, 9, 6, 3)
	ctx.begin_group("make_record")
	for key in ["code", "code_name", "gate_id", "input", "expected", "actual", "error_tags", "attempt"]:
		ctx.check("make field %s" % key, r.has(key))
	ctx.eq("make code", int(r["code"]), GateResult.E_DELAY_EXCEED)
	ctx.eq("make code_name", str(r["code_name"]), "E_DELAY_EXCEED")
	ctx.eq("make gate_id", str(r["gate_id"]), "T1.5-1")
	ctx.eq("make expected", int(r["expected"]), 9)
	ctx.eq("make actual", int(r["actual"]), 6)
	ctx.eq("make attempt", int(r["attempt"]), 3)
	ctx.eq("make negative attempt clamped", int(GateResult.make(GateResult.E_QUIZ, "q", null, 1, 0, -5)["attempt"]), 0)

func _tag_mapping(ctx: TestContext) -> void:
	ctx.begin_group("tag_mapping")
	ctx.eq("ok no tags", GateResult.tags_for(GateResult.OK), [])
	ctx.eq("unconnected -> S", GateResult.tags_for(GateResult.E_UNCONNECTED), ["S"])
	ctx.eq("missing graph -> S", GateResult.tags_for(GateResult.E_MISSING_GRAPH), ["S"])
	ctx.eq("truth row -> K,S", GateResult.tags_for(GateResult.E_TRUTH_ROW), ["K", "S"])
	ctx.eq("table cell -> K", GateResult.tags_for(GateResult.E_TABLE_CELL), ["K"])
	ctx.eq("delay exceed -> M,S", GateResult.tags_for(GateResult.E_DELAY_EXCEED), ["M", "S"])
	ctx.eq("output mismatch -> R", GateResult.tags_for(GateResult.E_OUTPUT_MISMATCH), ["R"])
	ctx.eq("coverage -> P", GateResult.tags_for(GateResult.E_COVERAGE), ["P"])
	ctx.eq("quiz -> K", GateResult.tags_for(GateResult.E_QUIZ), ["K"])
	ctx.eq("x row -> K,M", GateResult.tags_for(GateResult.E_X_ROW), ["K", "M"])
	ctx.eq("generic -> R", GateResult.tags_for(GateResult.E_GENERIC), ["R"])
	# 所有映射都在六类标签内
	for k in GateResult.TAG_MAP.keys():
		for tag in GateResult.TAG_MAP[k]:
			ctx.begin_group("tag_map_six_classes")
			ctx.check("tag %s in six classes" % str(tag), (GateResult.TAGS as Array).has(str(tag)))

func _tag_table_matches_doc(ctx: TestContext) -> void:
	## 19 条 code 与 docs/curriculum/05-failure-diagnostics.md §1 硬编码对账。
	var expected := {
		0: [], 1: ["S"], 2: ["S"], 3: ["S"], 4: ["R"], 5: ["R"],
		6: ["K", "S"], 7: ["K"], 8: ["M", "S"], 9: ["M", "R"],
		10: ["R"], 11: ["S", "P"], 12: ["P"], 13: ["P"], 14: ["K"],
		15: ["C", "P"], 16: ["M", "S"], 17: ["K", "M"], 99: ["R"],
	}
	ctx.begin_group("doc_tag_table")
	ctx.eq("doc table size", expected.size(), 19)
	for code in expected.keys():
		ctx.eq("doc tags %d" % int(code), GateResult.tags_for(int(code)), expected[code])

func _log_only_codes(ctx: TestContext) -> void:
	## 4/5/10/99 属技术侧配置缺陷：挂 R 只为让六类闭合，只进日志、不进玩家阶梯。
	## 不新增结构：可进阶梯的 code 由“至少有一个非 R 标签”判定。
	var log_only := [4, 5, 10, 99]
	var ladder := []
	for k in GateResult.NAMES.keys():
		if GateResult.tags_for(int(k)) != ["R"]:
			ladder.append(int(k))
	for c in log_only:
		ctx.begin_group("log_only")
		ctx.eq("log-only %d is pure R" % c, GateResult.tags_for(c), ["R"])
		ctx.check("log-only %d not in ladder set" % c, not ladder.has(c))
	for k in GateResult.NAMES.keys():
		if GateResult.tags_for(int(k)) == ["R"]:
			ctx.check("pure R only log-only (%d)" % int(k), log_only.has(int(k)) or int(k) == GateResult.E_PENDING)

func _unknown_code(ctx: TestContext) -> void:
	ctx.begin_group("unknown_code")
	ctx.eq("normalize unknown", GateResult.normalize(12345), GateResult.E_GENERIC)
	ctx.eq("name unknown", GateResult.name_of(12345), "E_GENERIC")
	ctx.eq("tags unknown", GateResult.tags_for(12345), ["R"])
	ctx.check("describe unknown is fallback", GateResult.describe(12345).contains("兜底"))
	var r := GateResult.make(12345, "weird", {}, 1, 0)
	ctx.eq("make unknown code", int(r["code"]), GateResult.E_GENERIC)
	ctx.eq("make unknown tags", r["error_tags"], ["R"])

func _attempts(ctx: TestContext) -> void:
	var t := GateAttemptTracker.new()
	ctx.begin_group("attempts")
	ctx.eq("attempt #1", t.record("T1.4-2", false), 1)
	ctx.eq("attempt #2", t.record("T1.4-2", false), 2)
	ctx.eq("attempt #3", t.record("T1.4-2", false), 3)
	ctx.eq("attempts query", t.attempts("T1.4-2"), 3)
	ctx.eq("attempt reset by pass", t.record("T1.4-2", true), 0)
	ctx.eq("attempts cleared by pass", t.attempts("T1.4-2"), 0)
	ctx.eq("attempt independent gate", t.record("T1.4-1", false), 1)
	ctx.eq("attempt other gate untouched", t.attempts("T1.4-2"), 0)
	t.reset("T1.4-1")
	ctx.eq("attempt reset one", t.attempts("T1.4-1"), 0)
	ctx.eq("attempt empty id", t.record("", false), 0)
	ctx.eq("attempt empty id query", t.attempts(""), 0)
	t.reset()
	ctx.eq("attempt reset all empty", t.to_dict()["counts"], {})
	var t2 := GateAttemptTracker.new()
	t2.record("g", false)
	t2.record("g", false)
	var round := GateAttemptTracker.from_dict(t2.to_dict())
	ctx.eq("attempt dict roundtrip", round.attempts("g"), 2)

func _report_shape(ctx: TestContext) -> void:
	var rep := GateReport.new()
	rep.add("legacy", "旧入口", false, "旧的失败")
	var c: Dictionary = rep.cases[0]
	ctx.begin_group("report_shape")
	ctx.eq("legacy code", int(c["code"]), GateResult.E_GENERIC)
	ctx.eq("legacy tags", c["error_tags"], ["R"])
	ctx.check("legacy still fails", not rep.all_required_passed())
	var ff := rep.first_failure()
	ctx.eq("first failure code", int(ff.get("code", -1)), GateResult.E_GENERIC)
	ctx.eq("first failure gate", str(ff.get("gate_id", "")), "legacy")
	rep.add_case(GateResult.E_TABLE_CELL, "T1.3-1", "AND 表", {"gate": "and", "row": 2}, 0, "1", [], "", true, 4)
	var c2: Dictionary = rep.cases[1]
	ctx.eq("add_case code", int(c2["code"]), GateResult.E_TABLE_CELL)
	ctx.eq("add_case tags", c2["error_tags"], ["K"])
	ctx.eq("add_case attempt", int(c2["attempt"]), 4)
	ctx.eq("failure codes", rep.failure_codes(), [GateResult.E_GENERIC, GateResult.E_TABLE_CELL])
	var ok_rep := GateReport.new()
	ok_rep.add_case(GateResult.OK, "T1.1-1", "通过", null, null, null)
	ctx.eq("ok case code", int(ok_rep.cases[0]["code"]), GateResult.OK)
	ctx.eq("ok case tags", ok_rep.cases[0]["error_tags"], [])
	ctx.eq("ok rep first failure empty", ok_rep.first_failure(), {})
	ctx.check("ok rep passed", ok_rep.all_required_passed())

# --- 每类 gate：成功 / 失败 ---

func _voltage(ctx: TestContext, cfg: Dictionary) -> void:
	var rep := LabChecks.voltage(cfg)
	ctx.begin_group("voltage")
	ctx.check("voltage pass", rep.all_required_passed(), rep.summary())
	for i in rep.cases.size():
		ctx.eq("voltage ok code %d" % i, int(rep.cases[i]["code"]), GateResult.OK)
	var bad := cfg.duplicate(true)
	for raw in bad.get("gate_cases", []):
		var c: Dictionary = raw
		if str(c.get("id", "")) == "T1.1-4":
			c["expect"] = "0"
	var r2 := LabChecks.voltage(bad)
	var f := _case_of(r2, "T1.1-4")
	ctx.eq("voltage fail code", int(f.get("code", -1)), GateResult.E_OUTPUT_MISMATCH)
	ctx.eq("voltage fail tags", f.get("error_tags", []), ["R"])
	ctx.close("voltage fail input v", float(f.get("input", {}).get("v", -1)), 0.85)
	ctx.eq("voltage fail expected", str(f.get("expected", "")), "0")
	ctx.eq("voltage fail actual", str(f.get("actual", "")), "X")

func _binary(ctx: TestContext, cfg: Dictionary) -> void:
	var visited := {}
	for v in range(0, 16):
		visited[str(v)] = true
	var achieved := {"t137": true, "t2f": true}
	var rep := LabChecks.binary(cfg, visited, achieved, 1)
	ctx.begin_group("binary")
	ctx.check("binary pass", rep.all_required_passed(), rep.summary())

	var miss := visited.duplicate()
	miss.erase("7")
	var r2 := LabChecks.binary(cfg, miss, achieved, 1)
	var f2 := _case_of(r2, "T1.2-1")
	ctx.eq("binary coverage code", int(f2.get("code", -1)), GateResult.E_COVERAGE)
	ctx.eq("binary coverage tags", f2.get("error_tags", []), ["P"])
	ctx.eq("binary coverage input", f2.get("input", {}).get("missing", []), ["7"])

	var r3 := LabChecks.binary(cfg, visited, {"t137": true}, 1)
	var f3 := _case_of(r3, "T1.2-3")
	ctx.eq("binary target code", int(f3.get("code", -1)), GateResult.E_TARGET_UNREACHED)
	ctx.eq("binary target input", f3.get("input", {}).get("target", ""), "t2f")
	ctx.eq("binary target expected", int(f3.get("expected", -1)), 47)
	ctx.eq("binary target actual", bool(f3.get("actual", true)), false)

	var r4 := LabChecks.binary(cfg, visited, achieved, 0)
	var f4 := _case_of(r4, "T1.2-4")
	ctx.eq("binary quiz code", int(f4.get("code", -1)), GateResult.E_QUIZ)
	ctx.eq("binary quiz expected", int(f4.get("expected", -1)), 1)
	ctx.eq("binary quiz actual", int(f4.get("actual", -1)), 0)

	var unknown := cfg.duplicate(true)
	(unknown.get("gate_cases", [])[0] as Dictionary)["kind"] = "bogus"
	var r5 := LabChecks.binary(unknown, visited, achieved, 1)
	ctx.eq("binary unknown kind code", int(_case_of(r5, "T1.2-1").get("code", -1)), GateResult.E_UNKNOWN_KIND)

func _boolean(ctx: TestContext, cfg: Dictionary) -> void:
	var filled := {
		"and": ["0", "0", "0", "1"],
		"or": ["0", "1", "1", "1"],
		"not": ["1", "0"],
		"demorgan": ["1", "1", "1", "0"],
	}
	var rep := LabChecks.boolean(cfg, filled)
	ctx.begin_group("boolean")
	ctx.check("boolean pass", rep.all_required_passed(), rep.summary())

	var bad := filled.duplicate(true)
	bad["and"] = ["0", "0", "1", "1"]
	var r2 := LabChecks.boolean(cfg, bad)
	var f2 := _case_of(r2, "T1.3-1")
	ctx.eq("boolean cell code", int(f2.get("code", -1)), GateResult.E_TABLE_CELL)
	ctx.eq("boolean cell gate", f2.get("input", {}).get("gate", ""), "and")
	ctx.eq("boolean cell row", int(f2.get("input", {}).get("row", -1)), 2)
	ctx.eq("boolean cell expected", int(f2.get("expected", -1)), 0)
	ctx.eq("boolean cell actual", str(f2.get("actual", "")), "1")
	ctx.check("boolean 3/4 detail", str(f2.get("detail", "")).contains("3/4"), str(f2.get("detail", "")))

	var short := filled.duplicate(true)
	short["and"] = ["0", "0", "0"]
	var r3 := LabChecks.boolean(cfg, short)
	var f3 := _case_of(r3, "T1.3-1")
	ctx.eq("boolean missing row", int(f3.get("input", {}).get("row", -1)), 3)
	ctx.eq("boolean missing expected", int(f3.get("expected", -1)), 1)
	ctx.eq("boolean missing actual", str(f3.get("actual", "")), "(缺)")

	var partial := filled.duplicate(true)
	partial["and"] = ["1", "0"]
	var r3b := LabChecks.boolean(cfg, partial)
	var f3b := _case_of(r3b, "T1.3-1")
	ctx.check("boolean partial fill detail counts correct", str(f3b.get("detail", "")).contains("1/4"), str(f3b.get("detail", "")))
	ctx.check("boolean partial fill not filled-count", not str(f3b.get("detail", "")).contains("2/4"), str(f3b.get("detail", "")))

	var all_wrong := filled.duplicate(true)
	all_wrong["and"] = ["1", "1", "1", "0"]
	var r3c := LabChecks.boolean(cfg, all_wrong)
	var f3c := _case_of(r3c, "T1.3-1")
	ctx.check("boolean all wrong fails", not bool(f3c.get("ok", true)))
	ctx.check("boolean all wrong detail 0/4", str(f3c.get("detail", "")).contains("0/4"), str(f3c.get("detail", "")))

	var bad2 := filled.duplicate(true)
	bad2["demorgan"] = ["1", "0", "0", "1"]
	var r4 := LabChecks.boolean(cfg, bad2)
	var f4 := _case_of(r4, "T1.3-4")
	ctx.eq("demorgan code", int(f4.get("code", -1)), GateResult.E_TABLE_CELL)
	ctx.eq("demorgan row", int(f4.get("input", {}).get("row", -1)), 1)
	ctx.eq("demorgan expected", str(f4.get("expected", "")), "1")
	ctx.eq("demorgan actual", str(f4.get("actual", "")), "0")
	ctx.check("demorgan partial detail 1/4", str(f4.get("detail", "")).contains("1/4"), str(f4.get("detail", "")))

	var dm_wrong := filled.duplicate(true)
	dm_wrong["demorgan"] = ["0", "0", "0", "1"]
	var r4b := LabChecks.boolean(cfg, dm_wrong)
	var f4b := _case_of(r4b, "T1.3-4")
	ctx.check("demorgan all wrong fails", not bool(f4b.get("ok", true)))
	ctx.check("demorgan all wrong detail 0/4", str(f4b.get("detail", "")).contains("0/4"), str(f4b.get("detail", "")))

	var unknown := cfg.duplicate(true)
	(unknown.get("gate_cases", [])[0] as Dictionary)["kind"] = "bogus"
	var r5 := LabChecks.boolean(unknown, filled)
	ctx.eq("boolean unknown kind", int(_case_of(r5, "T1.3-1").get("code", -1)), GateResult.E_UNKNOWN_KIND)

func _gate(ctx: TestContext, cfg: Dictionary) -> void:
	var graphs := {
		"t_and": _and_graph(),
		"t_or": _or_graph(),
		"t_not": _not_graph(),
		"t_xor": _xor_graph_a(),
		"t_xor_2": _xor_graph_b(),
	}
	var rep := LabChecks.gate(cfg, graphs, {"encapsulated": true})
	ctx.begin_group("gate")
	ctx.check("gate pass", rep.all_required_passed(), rep.summary())

	var wrong_basic := graphs.duplicate()
	wrong_basic["t_or"] = _and_graph()
	var r2 := LabChecks.gate(cfg, wrong_basic, {"encapsulated": true})
	var f2 := _case_of(r2, "T1.4-1")
	ctx.eq("gate basic code", int(f2.get("code", -1)), GateResult.E_TRUTH_ROW)
	ctx.eq("gate basic input", f2.get("input", {}).get("b", ""), "1")
	ctx.eq("gate basic expected", f2.get("expected", {}).get("out", ""), "1")
	ctx.eq("gate basic actual", f2.get("actual", {}).get("out", ""), "0")

	var wrong_xor := graphs.duplicate()
	wrong_xor["t_xor"] = _xor_bad_graph()
	var r3 := LabChecks.gate(cfg, wrong_xor, {"encapsulated": true})
	ctx.eq("gate xor code", int(_case_of(r3, "T1.4-2").get("code", -1)), GateResult.E_TRUTH_ROW)

	var slow := cfg.duplicate(true)
	for raw in slow.get("gate_cases", []):
		var c: Dictionary = raw
		if str(c.get("id", "")) == "T1.4-2":
			c["max_delay"] = 1
	var r4 := LabChecks.gate(slow, graphs, {"encapsulated": true})
	var f4 := _case_of(r4, "T1.4-2")
	ctx.eq("gate delay code", int(f4.get("code", -1)), GateResult.E_DELAY_EXCEED)
	ctx.eq("gate delay limit", int(f4.get("expected", -1)), 1)
	ctx.check("gate delay over limit", int(f4.get("actual", 0)) > 1, str(f4.get("actual", -1)))

	var r5 := LabChecks.gate(cfg, graphs, {"encapsulated": false})
	var f5 := _case_of(r5, "T1.4-3")
	ctx.eq("encapsulation code", int(f5.get("code", -1)), GateResult.E_ENCAPSULATION)
	ctx.eq("encapsulation expected", bool(f5.get("expected", false)), true)
	ctx.eq("encapsulation actual", bool(f5.get("actual", true)), false)

	var no_second := graphs.duplicate()
	no_second.erase("t_xor_2")
	var r6 := LabChecks.gate(cfg, no_second, {"encapsulated": true})
	var f6 := _case_of(r6, "T1.4-4")
	ctx.eq("second missing code", int(f6.get("code", -1)), GateResult.E_MISSING_GRAPH)
	ctx.eq("second missing input", f6.get("input", {}).get("graph", ""), "t_xor_2")

	var same := graphs.duplicate()
	same["t_xor_2"] = _xor_graph_a()
	var r7 := LabChecks.gate(cfg, same, {"encapsulated": true})
	var f7 := _case_of(r7, "T1.4-4")
	ctx.eq("second same code", int(f7.get("code", -1)), GateResult.E_STRUCTURE_SAME)
	ctx.eq("second same expected", str(f7.get("expected", "")), "不同结构")
	ctx.eq("second same actual", str(f7.get("actual", "")), "相同结构")

	var unknown := cfg.duplicate(true)
	(unknown.get("gate_cases", [])[0] as Dictionary)["kind"] = "bogus"
	var r8 := LabChecks.gate(unknown, graphs, {"encapsulated": true})
	ctx.eq("gate unknown kind", int(_case_of(r8, "T1.4-1").get("code", -1)), GateResult.E_UNKNOWN_KIND)

func _signal(ctx: TestContext, cfg: Dictionary) -> void:
	var rep := LabChecks.signal_cases(cfg, 9, 2, true, 1)
	ctx.begin_group("signal")
	ctx.check("signal pass", rep.all_required_passed(), rep.summary())

	var r2 := LabChecks.signal_cases(cfg, 6, 2, true, 1)
	var f2 := _case_of(r2, "T1.5-1")
	ctx.eq("signal delay code", int(f2.get("code", -1)), GateResult.E_DELAY_MISMATCH)
	ctx.eq("signal delay expected", int(f2.get("expected", -1)), 9)
	ctx.eq("signal delay actual", int(f2.get("actual", -1)), 6)

	var r3 := LabChecks.signal_cases(cfg, 9, 0, true, 1)
	var f3 := _case_of(r3, "T1.5-2")
	ctx.eq("glitch code", int(f3.get("code", -1)), GateResult.E_GLITCH)
	ctx.eq("glitch expected", int(f3.get("expected", -1)), 1)
	ctx.eq("glitch actual", int(f3.get("actual", -1)), 0)

	var r4 := LabChecks.signal_cases(cfg, 9, 2, false, 1)
	var f4 := _case_of(r4, "T1.5-3")
	ctx.eq("fix code", int(f4.get("code", -1)), GateResult.E_GLITCH)
	ctx.eq("fix expected", bool(f4.get("expected", false)), true)
	ctx.eq("fix actual", bool(f4.get("actual", true)), false)

	var r5 := LabChecks.signal_cases(cfg, 9, 2, true, 0)
	var f5 := _case_of(r5, "T1.5-4")
	ctx.eq("signal quiz code", int(f5.get("code", -1)), GateResult.E_QUIZ)
	ctx.eq("signal quiz expected", int(f5.get("expected", -1)), 1)
	ctx.eq("signal quiz actual", int(f5.get("actual", -1)), 0)

	var unknown := cfg.duplicate(true)
	(unknown.get("gate_cases", [])[0] as Dictionary)["kind"] = "bogus"
	var r6 := LabChecks.signal_cases(unknown, 9, 2, true, 1)
	ctx.eq("signal unknown kind", int(_case_of(r6, "T1.5-1").get("code", -1)), GateResult.E_UNKNOWN_KIND)

func _half_adder(ctx: TestContext, cfg: Dictionary) -> void:
	var graph := _half_adder_graph()
	var rep := LabChecks.half_adder(cfg, graph, true)
	ctx.begin_group("half_adder")
	ctx.check("half_adder pass", rep.all_required_passed(), rep.summary())

	var wrong := _half_adder_wrong_carry()
	var r2 := LabChecks.half_adder(cfg, wrong, true)
	var f2 := _case_of(r2, "T1.6-1")
	ctx.eq("half_adder truth code", int(f2.get("code", -1)), GateResult.E_TRUTH_ROW)
	ctx.eq("half_adder truth input", f2.get("input", {}).get("b", ""), "1")
	ctx.eq("half_adder truth expected carry", f2.get("expected", {}).get("carry", ""), "0")
	ctx.eq("half_adder truth actual carry", f2.get("actual", {}).get("carry", ""), "1")

	var slow := cfg.duplicate(true)
	for raw in slow.get("gate_cases", []):
		var c: Dictionary = raw
		if str(c.get("id", "")) == "T1.6-2":
			c["max"] = 1
	var r3 := LabChecks.half_adder(slow, graph, true)
	var f3 := _case_of(r3, "T1.6-2")
	ctx.eq("half_adder delay code", int(f3.get("code", -1)), GateResult.E_DELAY_EXCEED)
	ctx.eq("half_adder delay limit", int(f3.get("expected", -1)), 1)
	ctx.check("half_adder delay over limit", int(f3.get("actual", 0)) > 1, str(f3.get("actual", -1)))

	var r4 := LabChecks.half_adder(cfg, graph, false)
	ctx.eq("half_adder encap code", int(_case_of(r4, "T1.6-3").get("code", -1)), GateResult.E_ENCAPSULATION)

	var or_carry := _half_adder_wrong_carry()
	var wide := cfg.duplicate(true)
	for raw in wide.get("gate_cases", []):
		var c: Dictionary = raw
		if str(c.get("id", "")) == "T1.6-4":
			c["count"] = 64
	var r5 := LabChecks.half_adder(wide, or_carry, true)
	var f5 := _case_of(r5, "T1.6-4")
	ctx.eq("random_x code", int(f5.get("code", -1)), GateResult.E_X_ROW)
	ctx.check("random_x input has a", f5.get("input", {}).has("a"))
	ctx.check("random_x input has b", f5.get("input", {}).has("b"))
	ctx.check("random_x carry mismatch", str(f5.get("expected", {}).get("carry", "?")) != str(f5.get("actual", {}).get("carry", "?")),
		"%s vs %s" % [str(f5.get("expected", {})), str(f5.get("actual", {}))])

	var loose := _half_adder_floating_b()
	var r6 := LabChecks.half_adder(cfg, loose, true)
	var f6 := _case_of(r6, "T1.6-1")
	ctx.eq("unconnected code", int(f6.get("code", -1)), GateResult.E_UNCONNECTED)
	ctx.check("unconnected lists wire", (f6.get("input", {}).get("unconnected", []) as Array).has("g_carry.b"),
		str(f6.get("input", {})))

# --- 辅助 ---

func _case_of(rep: GateReport, id: String) -> Dictionary:
	for c in rep.cases:
		if str(c.get("id", "")) == id:
			return c
	return {}

func _base_graph() -> CircuitGraph:
	return CircuitGraph.new()

func _and_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _or_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("or"), "OR", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _not_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_gate("g1", LogicGates.from_string("not"), "NOT", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _xor_bad_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _xor_graph_a() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("na", LogicGates.from_string("not"), "NOT", Vector2(90, -20))
	g.add_gate("nb", LogicGates.from_string("not"), "NOT", Vector2(90, 80))
	g.add_gate("p1", LogicGates.from_string("and"), "AND", Vector2(200, 0))
	g.add_gate("p2", LogicGates.from_string("and"), "AND", Vector2(200, 100))
	g.add_gate("o1", LogicGates.from_string("or"), "OR", Vector2(320, 40))
	g.link("a", "na", 0)
	g.link("b", "nb", 0)
	g.link("a", "p1", 0)
	g.link("nb", "p1", 1)
	g.link("na", "p2", 0)
	g.link("b", "p2", 1)
	g.link("p1", "o1", 0)
	g.link("p2", "o1", 1)
	g.add_output("out", "OUT", Vector2(440, 40))
	g.link("o1", "out", 0)
	return g

func _xor_graph_b() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("n1", LogicGates.from_string("and"), "AND", Vector2(90, 10))
	g.add_gate("n2", LogicGates.from_string("not"), "NOT", Vector2(200, 10))
	g.add_gate("o1", LogicGates.from_string("or"), "OR", Vector2(90, 100))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(320, 40))
	g.link("a", "n1", 0)
	g.link("b", "n1", 1)
	g.link("n1", "n2", 0)
	g.link("a", "o1", 0)
	g.link("b", "o1", 1)
	g.link("o1", "g1", 0)
	g.link("n2", "g1", 1)
	g.add_output("out", "OUT", Vector2(440, 40))
	g.link("g1", "out", 0)
	return g

func _half_adder_graph() -> CircuitGraph:
	var g := _xor_graph_b()
	g.add_gate("g_carry", LogicGates.from_string("and"), "AND", Vector2(320, 140))
	g.link("a", "g_carry", 0)
	g.link("b", "g_carry", 1)
	g.add_output("sum", "SUM", Vector2(440, 40))
	g.link("g1", "sum", 0)
	g.add_output("carry", "CARRY", Vector2(440, 140))
	g.link("g_carry", "carry", 0)
	return g

func _half_adder_wrong_carry() -> CircuitGraph:
	var g := _xor_graph_b()
	g.add_gate("g_carry", LogicGates.from_string("or"), "OR", Vector2(320, 140))
	g.link("a", "g_carry", 0)
	g.link("b", "g_carry", 1)
	g.add_output("sum", "SUM", Vector2(440, 40))
	g.link("g1", "sum", 0)
	g.add_output("carry", "CARRY", Vector2(440, 140))
	g.link("g_carry", "carry", 0)
	return g

func _half_adder_floating_b() -> CircuitGraph:
	## b 建了但没接到进位门 → unconnected 精确回传 "g_carry.b"
	var g := _half_adder_graph()
	g.unlink("g_carry", 1)
	return g
