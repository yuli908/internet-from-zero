extends RefCounted

func run(ctx: TestContext) -> void:
	var tu := TutorialRunner.from_doc(TestUtil.tutorial_doc())
	var st := PlayerState.new()
	ctx.eq("step count", tu.steps.size(), 6)
	ctx.eq("first step", str(tu.current(st).get("id", "")), "t_welcome")
	ctx.check("not done at start", not tu.done(st))

	var ack := tu.acknowledge(st)
	ctx.eq("acknowledge first", str(ack.get("id", "")), "t_welcome")
	ctx.eq("second step", str(tu.current(st).get("id", "")), "t_first_lab")

	var wrong := tu.on_event(st, "shop_opened")
	ctx.check("wrong event ignored", wrong.is_empty())
	ctx.eq("still second", str(tu.current(st).get("id", "")), "t_first_lab")

	var right := tu.on_event(st, "lab_opened:level")
	ctx.eq("event advanced", str(right.get("id", "")), "t_first_lab")
	ctx.eq("third step", str(tu.current(st).get("id", "")), "t_shop")

	var prog := tu.progress(st)
	ctx.eq("tutorial progress done", int(prog["done"]), 2)
	ctx.eq("tutorial progress total", int(prog["total"]), 6)

	tu.acknowledge(st)
	tu.acknowledge(st)
	tu.acknowledge(st)
	tu.acknowledge(st)
	ctx.check("tutorial done", tu.done(st))
