extends RefCounted

func run(ctx: TestContext) -> void:
	var ch := ChapterRuntime.from_doc(TestUtil.chapter_doc())
	ctx.eq("chapter id", ch.id(), "ch01")
	ctx.eq("lab count", ch.labs.size(), 6)
	ctx.eq("objective count", ch.objectives.size(), 6)
	ctx.eq("dsl errors", ch.dsl_errors().size(), 0)

	var st := PlayerState.new()
	ctx.check("level unlocked", ch.lab_unlocked(st, "level"))
	ctx.check("binary locked", not ch.lab_unlocked(st, "binary"))
	ctx.check("lock reason", ch.lab_lock_reason(st, "binary").contains("电"))

	var o := ch.complete_objective(st, "obj_level")
	ctx.check("objective newly", bool(o["newly"]))
	ctx.check("all_done false", not bool(o["all_done"]))
	ctx.eq("progress 1", int(ch.progress(st)["done"]), 1)
	ctx.eq("next objective", str(ch.next_objective(st).get("id", "")), "obj_binary")

	st.mark_lab_completed("level")
	ctx.check("binary unlocked after lab", ch.lab_unlocked(st, "binary"))

	ctx.check("duplicate objective no-op", not bool(ch.complete_objective(st, "obj_level")["newly"]))
	ctx.eq("progress unchanged", int(ch.progress(st)["done"]), 1)

	for id in ["obj_binary", "obj_boolean", "obj_gate", "obj_signal", "obj_half_adder"]:
		ch.complete_objective(st, id)
	ctx.check("all done", ch.all_done(st))
	ctx.eq("progress complete", int(ch.progress(st)["done"]), 6)
	ctx.check("next objective empty", ch.next_objective(st).is_empty())

	var bad_doc := {
		"id": "bad",
		"labs": [{"id": "x", "objective": "nope", "requires": "ghost"}],
		"objectives": [],
	}
	var bad := ChapterRuntime.from_doc(bad_doc)
	ctx.check("dsl errors detected", bad.dsl_errors().size() >= 2)

	# ---- 内容级锁定：2.4 整节 deferred，进 lab 前就拦住 ----
	var ch2 := ChapterRuntime.from_doc(TestUtil.read_json("res://data/chapters/ch02_levels.json"))
	var st2 := PlayerState.new()
	st2.mark_lab_completed("half_adder")
	ctx.check("ready 节正常进入", ch2.lab_unlocked(st2, "transistor"))
	ctx.eq("ready 节 available", ch2.lab_content_available("transistor"),
		{"available": true, "reason": ""})
	st2.mark_lab_completed("nand")  # 2.4 前置已满足，但仍因内容延后禁入
	ctx.eq("deferred 节状态", ch2.content_status("replace"), "deferred")
	ctx.check("deferred 节不可进入", not ch2.lab_unlocked(st2, "replace"))
	var avail := ch2.lab_content_available("replace")
	ctx.check("lab_content_available 返回值形状",
		avail.has("available") and avail.has("reason")
		and avail["available"] is bool and avail["reason"] is String)
	ctx.check("deferred 给出玩家可读原因", not str(avail["reason"]).is_empty())
	ctx.check("deferred 原因不含内部术语",
		not str(avail["reason"]).contains("static_current") and not str(avail["reason"]).contains("E_PENDING"))
	ctx.eq("锁定原因即 deferred 原因", ch2.lab_lock_reason(st2, "replace"), str(avail["reason"]))
	ctx.check("缺省 content_status 视为 ready", ch.content_status("level") == "ready")
	ctx.check("旧数据缺字段仍可进入", ch.lab_unlocked(st, "level")
		and bool(ch.lab_content_available("level").get("available", false)))
	ctx.eq("技能树节点照常保留", ch2.lab("replace").get("skill_node", ""), "SK-REPLACE")

	# ---- 2.5 不再以 2.4 为前置：deferred 期间照常可进可做 ----
	ctx.check("2.4 deferred 时 2.5 可进入", ch2.lab_unlocked(st2, "power"))
	ctx.check("2.5 目标可完成", bool(ch2.complete_objective(st2, "obj_power").get("ok", false)))

	# ---- 版本内可完成度：分母 = requirement==MUST 且 content_status==ready ----
	var st3 := PlayerState.new()
	ctx.eq("2.4 必修属性", ch2.requirement("replace"), "OPT")
	ctx.eq("未写的节缺省 MUST", ch2.requirement("power"), "MUST")
	ctx.eq("分母只算 MUST∧ready", ch2.progress(st3), {"done": 0, "total": 4})
	ctx.eq("下一目标跳过不进分母的节", str(ch2.next_objective(st3).get("id", "")), "obj_transistor")
	ctx.check("未完成不可领章末奖", not ch2.chapter_reward_claimable(st3))
	var rej := ch2.complete_objective(st3, "obj_replace")
	ctx.check("deferred 不产生任何完成记录",
		not bool(rej.get("ok", true)) and not st3.is_objective_done("obj_replace"))
	for oid in ["obj_transistor", "obj_inverter", "obj_nand", "obj_power"]:
		ctx.check("完成 MUST 节: %s" % str(oid),
			bool(ch2.complete_objective(st3, str(oid)).get("ok", false)))
	ctx.eq("ch02 完成度 4/4", ch2.progress(st3), {"done": 4, "total": 4})
	ctx.check("4/4 即全完成", ch2.all_done(st3))
	ctx.check("章末奖励可发放", ch2.chapter_reward_claimable(st3))
	# 两个维度互不推导：content_status × requirement 四种组合各测一遍
	var combos := [
		{"status": "ready", "req": "MUST", "total": 5, "enter": true},
		{"status": "ready", "req": "OPT", "total": 4, "enter": true},
		{"status": "deferred", "req": "MUST", "total": 4, "enter": false},
		{"status": "deferred", "req": "OPT", "total": 4, "enter": false},
	]
	for combo in combos:
		var tag := "%s/%s" % [str(combo["status"]), str(combo["req"])]
		var v := _ch02_variant(str(combo["status"]), str(combo["req"]))
		ctx.eq("%s 分母" % tag, int((v.progress(st3) as Dictionary).get("total", -1)), int(combo["total"]))
		ctx.eq("%s requirement 独立读出" % tag, v.requirement("replace"), str(combo["req"]))
		ctx.eq("%s 可进入" % tag, v.lab_unlocked(st2, "replace"), bool(combo["enter"]))
	# 转正模拟：OPT 不追补；改成 MUST 才会变 5
	var ch2r := _ch02_variant("ready", "OPT")
	ctx.eq("2.4 转正（OPT）分母仍 4", ch2r.progress(st3), {"done": 4, "total": 4})
	ctx.check("2.4 转正（OPT）不追补", ch2r.all_done(st3))
	st3.set_flag(ch2r.chapter_reward_key(), true)
	ctx.check("已领奖励不重复发放", not ch2r.chapter_reward_claimable(st3))
	var ch2m := _ch02_variant("ready", "MUST")
	ctx.eq("2.4 若转正为 MUST 分母 5", ch2m.progress(st3), {"done": 4, "total": 5})
	ctx.check("转正为 MUST 需补做", not ch2m.all_done(st3))

func _ch02_variant(status: String, req: String) -> ChapterRuntime:
	## 构造 2.4 的变体：同一份 CH02 数据，只改 `content_status` / `requirement`。
	## 用于证明两个维度独立——任意组合都不能由另一个推导出来。
	var doc: Dictionary = TestUtil.read_json("res://data/chapters/ch02_levels.json")
	for raw in doc.get("labs", []):
		if not (raw is Dictionary):
			continue
		var seg: Dictionary = raw
		if str(seg.get("id", "")) != "replace":
			continue
		seg.erase("content_status")
		seg.erase("deferred_reason")
		seg.erase("requirement")
		if not status.is_empty():
			seg["content_status"] = status
		if not req.is_empty():
			seg["requirement"] = req
	return ChapterRuntime.from_doc(doc)
