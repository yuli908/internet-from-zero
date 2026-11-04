extends RefCounted

## M3 · T5 奖励入库机制：幂等 + 原子校验。数值不在本测试里定，夹具仅测试用。

func run(ctx: TestContext) -> void:
	var fx := TestUtil.read_json("res://tests/data/ch99_reward_fixture.json")
	var cat := TestUtil.catalog()
	ctx.check("fixture: 夹具可读", not fx.is_empty())
	var lab := str(fx.get("lab_id", ""))
	var grants: Dictionary = fx.get("grants", {})

	var st := PlayerState.new(7)
	var r1 := st.grant_items(lab, grants, cat)
	ctx.check("首次：ok", bool(r1.get("ok", false)), str(r1.get("error", "")))
	ctx.check("首次：非重复", not bool(r1.get("already", true)))
	ctx.eq("首次：M03 入库 2", st.item_count("M03"), 2)
	ctx.eq("首次：M09 入库 1", st.item_count("M09"), 1)
	ctx.check("首次：写 granted 标记", st.has_flag("granted:%s" % lab))

	var r2 := st.grant_items(lab, grants, cat)
	ctx.check("重复：ok", bool(r2.get("ok", false)))
	ctx.check("重复：already=true", bool(r2.get("already", false)))
	ctx.eq("重复：M03 不二次发放", st.item_count("M03"), 2)
	ctx.eq("重复：M09 不二次发放", st.item_count("M09"), 1)

	var st_bad := PlayerState.new(8)
	var rb := st_bad.grant_items("ch99_bad", fx.get("bad_unknown", {}), cat)
	ctx.check("原子：未知物品整单拒绝", not bool(rb.get("ok", true)), str(rb.get("error", "")))
	ctx.eq("原子：连合法项 M03 也未发", st_bad.item_count("M03"), 0)
	ctx.check("原子：拒绝后不写标记", not st_bad.has_flag("granted:ch99_bad"))
	ctx.eq("原子：未知物品错误信息", str(rb.get("error", "")), "未知物品 NOPE：整单拒绝")

	var rz := PlayerState.new(9)
	ctx.check("原子：数量 0 被拒", not bool(rz.grant_items("ch99_z", fx.get("bad_qty_zero", {}), cat).get("ok", true)))
	ctx.eq("原子：数量 0 未入库", rz.item_count("M03"), 0)
	ctx.check("原子：数量 1.5 被拒", not bool(rz.grant_items("ch99_f", fx.get("bad_qty_frac", {}), cat).get("ok", true)))
	ctx.eq("原子：数量 1.5 未入库", rz.item_count("M03"), 0)

	var st_rep := PlayerState.new(10)
	var rep: Dictionary = fx.get("repeatable", {})
	st_rep.grant_items("ch99_rep", rep, cat)
	st_rep.grant_items("ch99_rep", rep, cat)
	ctx.eq("once=false：可重复发放 2 次", st_rep.item_count("M03"), 2)
	ctx.check("once=false：不写 granted 标记", not st_rep.has_flag("granted:ch99_rep"))

	var st_dry := PlayerState.new(11)
	var rd := st_dry.grant_items(lab, grants, cat, true)
	ctx.check("dry_run：校验通过", bool(rd.get("ok", false)))
	ctx.eq("dry_run：不入库", st_dry.item_count("M03"), 0)
	ctx.check("dry_run：不写标记", not st_dry.has_flag("granted:%s" % lab))

	# 存档往返保留物品与 granted 标记。
	var text := SaveCodec.encode(st)
	var dec := SaveCodec.decode(text)
	var st3 := PlayerState.from_dict(dec["payload"])
	ctx.eq("存档：M03 保留", st3.item_count("M03"), 2)
	ctx.eq("存档：M09 保留", st3.item_count("M09"), 1)
	ctx.check("存档：granted 标记保留", st3.has_flag("granted:%s" % lab))
	var r3 := st3.grant_items(lab, grants, cat)
	ctx.check("存档后重复：仍判重复", bool(r3.get("already", false)))
	ctx.eq("存档后重复：仍不二次发放", st3.item_count("M03"), 2)
