extends RefCounted

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 12
const EXPECT_GROUPS := {
	"steps": 3, "acknowledge": 2, "wrong_event": 2, "event_advance": 2,
	"progress": 2, "done": 1,
}
const GROUP_DESCRIPTIONS := {
	"steps": "步骤数 6、首步 id、初始未完成",
	"acknowledge": "确认首步返回其 id 并推进到第二步",
	"wrong_event": "无关事件被忽略且停在第二步",
	"event_advance": "lab_opened:level 事件推进并进入第三步",
	"progress": "教程进度 done=2 / total=6",
	"done": "连续确认后教程完成",
}

func run(ctx: TestContext) -> void:
	var tu := TutorialRunner.from_doc(TestUtil.tutorial_doc())
	var st := PlayerState.new()
	ctx.begin_group("steps")
	ctx.eq("step count", tu.steps.size(), 6)
	ctx.eq("first step", str(tu.current(st).get("id", "")), "t_welcome")
	ctx.check("not done at start", not tu.done(st))

	ctx.begin_group("acknowledge")
	var ack := tu.acknowledge(st)
	ctx.eq("acknowledge first", str(ack.get("id", "")), "t_welcome")
	ctx.eq("second step", str(tu.current(st).get("id", "")), "t_first_lab")

	ctx.begin_group("wrong_event")
	var wrong := tu.on_event(st, "shop_opened")
	ctx.check("wrong event ignored", wrong.is_empty())
	ctx.eq("still second", str(tu.current(st).get("id", "")), "t_first_lab")

	ctx.begin_group("event_advance")
	var right := tu.on_event(st, "lab_opened:level")
	ctx.eq("event advanced", str(right.get("id", "")), "t_first_lab")
	ctx.eq("third step", str(tu.current(st).get("id", "")), "t_shop")

	ctx.begin_group("progress")
	var prog := tu.progress(st)
	ctx.eq("tutorial progress done", int(prog["done"]), 2)
	ctx.eq("tutorial progress total", int(prog["total"]), 6)

	tu.acknowledge(st)
	tu.acknowledge(st)
	tu.acknowledge(st)
	tu.acknowledge(st)
	ctx.begin_group("done")
	ctx.check("tutorial done", tu.done(st))
