extends RefCounted

func run(ctx: TestContext) -> void:
	var kg := KnowledgeGraph.from_doc(TestUtil.skill_doc())
	ctx.eq("node count", kg.nodes.size(), 8)
	ctx.eq("knowledge count", kg.knowledge_nodes().size(), 6)

	var st := PlayerState.new()
	st.scrap = 0
	st.xp = 0
	ctx.check("voltage available", bool(kg.can_unlock(st, "voltage")["ok"]))
	var blocked := kg.can_unlock(st, "binary")
	ctx.check("binary blocked", not bool(blocked["ok"]), str(blocked["error"]))
	ctx.check("blocked message mentions prereq", str(blocked["error"]).contains("前置"))

	var u := kg.unlock(st, "voltage")
	ctx.check("voltage unlock", bool(u["ok"]))
	ctx.eq("voltage scrap award", int(u["awarded_scrap"]), 10)
	ctx.eq("voltage xp award", int(u["awarded_xp"]), 15)
	ctx.eq("state scrap", st.scrap, 10)
	ctx.eq("state xp", st.xp, 15)
	ctx.check("voltage unlocked", st.has_knowledge("voltage"))

	ctx.check("duplicate unlock rejected", not bool(kg.unlock(st, "voltage")["ok"]))
	ctx.check("binary now ok", bool(kg.can_unlock(st, "binary")["ok"]))
	ctx.check("bargain still needs xp", not bool(kg.can_unlock(st, "bargain")["ok"]))

	var prog := kg.progress(st)
	ctx.eq("progress done", int(prog["done"]), 1)
	ctx.eq("progress total", int(prog["total"]), 8)

	var u2 := kg.unlock(st, "binary")
	ctx.check("binary unlock", bool(u2["ok"]))
	ctx.eq("xp after binary", st.xp, 35)

	var buy_skill := kg.unlock(st, "bargain")
	ctx.check("bargain unlock", bool(buy_skill["ok"]), str(buy_skill["error"]))
	ctx.eq("bargain xp cost", int(buy_skill["cost_xp"]), 25)
	ctx.eq("xp after skill", st.xp, 10)

	var poor := PlayerState.new()
	poor.xp = 5
	poor.grant_knowledge("binary")
	var poor_check := kg.can_unlock(poor, "bargain")
	ctx.check("poor blocked", not bool(poor_check["ok"]))
	ctx.check("poor error mentions xp", str(poor_check["error"]).contains("经验"))

	var avail := kg.available(st)
	ctx.check("available non-empty", avail.size() > 0)
	var avail_ok := 0
	for row in avail:
		if bool(row["ok"]):
			avail_ok += 1
	ctx.check("some unlockable after progress", avail_ok >= 1)
