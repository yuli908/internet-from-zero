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
