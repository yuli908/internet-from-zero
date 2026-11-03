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
