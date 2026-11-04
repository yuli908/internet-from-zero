extends RefCounted

## CH05 5.1（波形对齐）扩 kind `waveform_align` 的单测。
## 依据 `docs/curriculum/17-ch05-06-lecture-copy.md` §1：终值、四阶段起止拍、逐拍拍号
## 三样同时成立才过；只交阶段顺序的「填表式」提交必须被拒。
## 失败统一落 `E_OUTPUT_MISMATCH`(10)，detail 前缀分「终值 / 阶段 / 拍号」。

## LDI 波形：取指两拍、译码一拍、执行空段、写回一拍，末拍 rf0 = 42。
const WAVE := [
	{"tick": 0, "waves": {"mem_rd": 1, "ir_ld": 0, "alu_op": 0, "rf_wr": 0, "rf0": 0}},
	{"tick": 1, "waves": {"mem_rd": 1, "ir_ld": 0, "alu_op": 0, "rf_wr": 0, "rf0": 0}},
	{"tick": 2, "waves": {"mem_rd": 0, "ir_ld": 1, "alu_op": 0, "rf_wr": 0, "rf0": 0}},
	{"tick": 3, "waves": {"mem_rd": 0, "ir_ld": 0, "alu_op": 0, "rf_wr": 1, "rf0": 42}},
]
const CFG := {
	"id": "T5.1-2",
	"title": "波形对齐",
	"kind": "waveform_align",
	"stage_signals": {"fetch": "mem_rd", "decode": "ir_ld", "execute": "alu_op", "writeback": "rf_wr"},
	"final_signal": "rf0",
	"waveform": WAVE,
}
const GOOD := {
	"final_value": 42,
	"spans": {
		"fetch": {"start": 0, "end": 1},
		"decode": {"start": 2, "end": 2},
		"execute": {"start": -1, "end": -1},
		"writeback": {"start": 3, "end": 3},
	},
	"beats": {0: "fetch", 1: "fetch", 2: "decode", 3: "writeback"},
}

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 35
const EXPECT_GROUPS := {
	"expected_model": 4, "all_correct": 5, "beat_only": 6,
	"value_only": 5, "span_only": 5, "table_form": 4, "gate_dispatch": 6,
}
const GROUP_DESCRIPTIONS := {
	"expected_model": "只从波形历史推导四阶段起止拍、逐拍拍号与终值，空段为 -1/-1",
	"all_correct": "三样全对时返回绿、code OK、无 detail 与 failures，expected 原样回显",
	"beat_only": "只把一个拍号标错即判红，detail 指到阶段/拍/项，其余三样仍对只报一条",
	"value_only": "只把终值写错即判红，detail 指到终值与末拍，其余项仍对",
	"span_only": "只把起止拍写错即判红，detail 指到阶段与拍区间",
	"table_form": "只交阶段顺序的填表式提交被拒，detail 写明「填表不算」",
	"gate_dispatch": "LabChecks 登记该 kind、填表与缺标注都 fail closed、失败码 10 的 TAG_MAP 未漂移",
}

func run(ctx: TestContext) -> void:
	ctx.begin_group("expected_model")
	var model: Dictionary = WaveformAlign.expected(CFG)
	ctx.eq("fetch 起止拍 0-1", model["stages"]["fetch"], {"start": 0, "end": 1})
	ctx.eq("execute 空段 -1/-1", model["stages"]["execute"], {"start": -1, "end": -1})
	ctx.eq("拍号 tick 2 = decode", str(model["beats"][2]), "decode")
	ctx.eq("终值取末拍 rf0 = 42", model["final_value"], 42)

	ctx.begin_group("all_correct")
	var good: Dictionary = WaveformAlign.verify(CFG, GOOD)
	ctx.check("三样全对 → 绿", bool(good["ok"]))
	ctx.eq("全对 code OK", int(good["code"]), GateResult.OK)
	ctx.eq("全对无 detail", str(good["detail"]), "")
	ctx.eq("全对无 failures", (good["failures"] as Array).size(), 0)
	ctx.eq("expected 回显终值", good["expected"]["final_value"], 42)

	ctx.begin_group("beat_only")
	var beat_ans: Dictionary = GOOD.duplicate(true)
	beat_ans["beats"][2] = "fetch"
	var r_beat: Dictionary = WaveformAlign.verify(CFG, beat_ans)
	ctx.check("只错一个拍号 → 红", not bool(r_beat["ok"]))
	ctx.eq("拍号错落 E_OUTPUT_MISMATCH(10)", int(r_beat["code"]), GateResult.E_OUTPUT_MISMATCH)
	ctx.eq("只报一条不符（其余项仍对）", (r_beat["failures"] as Array).size(), 1)
	ctx.eq("不符项=拍号", str(r_beat["failures"][0]["item"]), "拍号")
	ctx.eq("指到第 2 拍", int(r_beat["failures"][0]["tick"]), 2)
	ctx.check("detail 指到「拍号 tick 2 ≠ 波形 decode」",
		str(r_beat["detail"]).contains("拍号 tick 2") and str(r_beat["detail"]).contains("波形 decode"))

	ctx.begin_group("value_only")
	var val_ans: Dictionary = GOOD.duplicate(true)
	val_ans["final_value"] = 37
	var r_val: Dictionary = WaveformAlign.verify(CFG, val_ans)
	ctx.check("只错终值 → 红", not bool(r_val["ok"]))
	ctx.eq("终值错落 E_OUTPUT_MISMATCH(10)", int(r_val["code"]), GateResult.E_OUTPUT_MISMATCH)
	ctx.eq("只报一条不符", (r_val["failures"] as Array).size(), 1)
	ctx.eq("不符项=终值", str(r_val["failures"][0]["item"]), "终值")
	ctx.check("detail 指到「终值 rf0=37 ≠ 波形 42」",
		str(r_val["detail"]).contains("终值 rf0=37") and str(r_val["detail"]).contains("波形 42"))

	ctx.begin_group("span_only")
	var span_ans: Dictionary = GOOD.duplicate(true)
	span_ans["spans"]["fetch"]["end"] = 0
	var r_span: Dictionary = WaveformAlign.verify(CFG, span_ans)
	ctx.check("只错起止拍 → 红", not bool(r_span["ok"]))
	ctx.eq("起止拍错落 E_OUTPUT_MISMATCH(10)", int(r_span["code"]), GateResult.E_OUTPUT_MISMATCH)
	ctx.eq("只报一条不符", (r_span["failures"] as Array).size(), 1)
	ctx.eq("不符项=阶段且指到 fetch", str(r_span["failures"][0]["item"]) + "/"
		+ str(r_span["failures"][0]["stage"]), "阶段/fetch")
	ctx.check("detail 指到「阶段 fetch 起止拍 0-0 ≠ 波形 0-1」",
		str(r_span["detail"]).contains("阶段 fetch 起止拍 0-0") and str(r_span["detail"]).contains("波形 0-1"))

	ctx.begin_group("table_form")
	var table_ans := {"order": ["fetch", "decode", "execute", "writeback"]}
	var r_tab: Dictionary = WaveformAlign.verify(CFG, table_ans)
	ctx.check("填表式提交被拒", not bool(r_tab["ok"]))
	ctx.eq("填表式落 E_OUTPUT_MISMATCH(10)", int(r_tab["code"]), GateResult.E_OUTPUT_MISMATCH)
	ctx.check("detail 写明填表不算", str(r_tab["detail"]).contains("填表不算"))
	ctx.eq("不符项=填表", str(r_tab["failures"][0]["item"]), "填表")

	ctx.begin_group("gate_dispatch")
	var lab := {"id": "datapath", "gate_cases": [CFG]}
	var ok_run: Dictionary = Ch05Checks.run("datapath", lab, {"answers": {"T5.1-2": GOOD}})
	ctx.check("Ch05Checks 已登记 waveform_align（标注对则过）", bool(ok_run["ok"]))
	ctx.eq("接入后不再落 pending", (ok_run["pending"] as Array).size(), 0)
	var bad_run: Dictionary = Ch05Checks.run("datapath", lab, {"answers": {"T5.1-2": table_ans}})
	ctx.check("填表经 Ch05Checks 仍被拒", not bool(bad_run["ok"]))
	ctx.eq("Ch05Checks 失败码 10",
		((bad_run["report"] as GateReport).failure_codes() as Array)[0], GateResult.E_OUTPUT_MISMATCH)
	var miss_run: Dictionary = Ch05Checks.run("datapath", lab, {})
	ctx.check("未交标注不被默认放行（fail closed）", not bool(miss_run["ok"]))
	ctx.check("TAG_MAP 同步：10 仍为 [R]、名未改",
		GateResult.tags_for(GateResult.E_OUTPUT_MISMATCH) == ["R"]
		and GateResult.name_of(GateResult.E_OUTPUT_MISMATCH) == "E_OUTPUT_MISMATCH")
