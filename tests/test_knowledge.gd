extends RefCounted

## 双树四态、gate 自动解锁、里程碑、旧节点兼容。

func run(ctx: TestContext) -> void:
	var db: Node = TestUtil.data_db()
	var kg: KnowledgeGraph = db.skill_graph
	ctx.eq("node count", kg.nodes.size(), 36)
	ctx.eq("progress nodes", kg.nodes_of_tree("progress").size(), 7)
	ctx.eq("knowledge nodes", kg.nodes_of_tree("knowledge").size(), 19)

	var st := PlayerState.new()
	st.scrap = 0
	ctx.eq("CH01-1 locked before gate", kg.node_state(st, "CH01-1"), "locked")
	ctx.check("CH01-1 cannot unlock", not bool(kg.can_unlock(st, "CH01-1").get("ok", false)))
	st.set_flag("gate:T1.1-4", true)
	ctx.eq("CH01-1 available after gate", kg.node_state(st, "CH01-1"), "available")
	var u1 := kg.unlock(st, "CH01-1")
	ctx.check("CH01-1 unlock", bool(u1.get("ok", false)), str(u1.get("error", "")))
	ctx.eq("CH01-1 completed", kg.node_state(st, "CH01-1"), "completed")
	ctx.eq("milestone no scrap", st.scrap, 0)

	ctx.eq("CH01-2 locked before node", kg.node_state(st, "CH01-2"), "locked")
	st.set_flag("gate:T1.2-4", true)
	ctx.eq("CH01-2 available", kg.node_state(st, "CH01-2"), "available")
	ctx.check("CH01-2 unlock", bool(kg.unlock(st, "CH01-2").get("ok", false)))

	for i in range(3, 7):
		st.set_flag("gate:T1.%d-4" % i, true)
		ctx.check("CH01-%d unlock" % i, bool(kg.unlock(st, "CH01-%d" % i).get("ok", false)))
	ctx.eq("CH01 available", kg.node_state(st, "CH01"), "available")
	var u2 := kg.unlock(st, "CH01")
	ctx.check("CH01 unlock", bool(u2.get("ok", false)))
	ctx.eq("chapter scrap award", st.scrap, 25)
	ctx.eq("chapter xp award", st.xp, 50)

	var legacy := PlayerState.new()
	legacy.scrap = 0
	ctx.eq("legacy voltage available", kg.node_state(legacy, "voltage"), "available")
	ctx.eq("legacy binary locked", kg.node_state(legacy, "binary"), "locked")
	var uv := kg.unlock(legacy, "voltage")
	ctx.check("legacy voltage unlock", bool(uv.get("ok", false)))
	ctx.eq("legacy voltage scrap", legacy.scrap, 10)
	ctx.eq("legacy voltage xp", legacy.xp, 15)
	ctx.eq("legacy binary now available", kg.node_state(legacy, "binary"), "available")

	var poor := PlayerState.new()
	ctx.eq("poor xp", poor.xp, 0)
	ctx.check("poor cannot unlock binary", not bool(kg.can_unlock(poor, "binary").get("ok", false)))

	ctx.eq("progress total", int(kg.progress(st).get("total", 0)), 36)
	ctx.check("progress done grew", int(kg.progress(st).get("done", 0)) >= 3)
	ctx.check("demorgan node exists", kg.nodes.has("demorgan"))
	ctx.check("bargain effect", str(kg.node("bargain").get("effects", {})).contains("price_discount"))
