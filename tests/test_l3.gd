extends RefCounted

## M3 · L3 时序层（T1 DFF）。向量语义对齐 docs/simulation/ref/tests/test_sequential.py。
## 先用本套件锁住 M2 的 add_dff 行为（上升沿、clk→Q=2、下降沿不采样），再验证新增违例路径。

func run(ctx: TestContext) -> void:
	_test_m2_baseline(ctx)
	_test_chain(ctx)
	_test_setup(ctx)
	_test_hold(ctx)
	_test_reset(ctx)

func _mk(name: String) -> SimCircuit:
	var c := SimCircuit.new(name)
	c.add_wire("d", SimValue.ZERO)
	c.add_wire("clk", SimValue.ZERO)
	return c

func _test_m2_baseline(ctx: TestContext) -> void:
	## M2 既有行为（替换 add_dff 前先用测试锁住）：
	##  - 上升沿 t=5 采样，Q 在 t=7 变；
	##  - 下降沿不采样；下一次上升沿 t=15 → t=17 更新。
	var c := _mk("l3_m2")
	c.add_dff("q", "d", "clk")
	c.set_input("d", SimValue.ONE, 0)
	c.set_input("clk", SimValue.ONE, 5)
	c.set_input("clk", SimValue.ZERO, 7)
	c.set_input("d", SimValue.ZERO, 10)
	c.set_input("clk", SimValue.ONE, 15)
	c.run_until(4)
	ctx.eq("M2: Q 初值 X", c.probe("q"), SimValue.X)
	c.run_until(6)
	ctx.eq("M2: clk→Q 未到前保持 X", c.probe("q"), SimValue.X)
	c.run_until(7)
	ctx.eq("M2: 上升沿 t=5 → Q 在 t=7 变", c.probe("q"), SimValue.ONE)
	c.run_until(9)
	ctx.eq("M2: 下降沿不采样", c.probe("q"), SimValue.ONE)
	c.run_until(16)
	ctx.eq("M2: 第二沿 t=15 后 +1 仍未更新", c.probe("q"), SimValue.ONE)
	c.run_until(17)
	ctx.eq("M2: 第二沿 t=15 → t=17 更新", c.probe("q"), SimValue.ZERO)
	c.settle()
	ctx.check("M2: 收敛后队列为空", c.is_quiescent())

func _test_chain(ctx: TestContext) -> void:
	## 3 级链：每级 clk→Q=2，边沿每 4 tick，链式传递必须全 1（M2 bench 的同一结构）。
	var c := _mk("l3_chain")
	c.add_wire("din", SimValue.ONE)
	c.add_dff("q0", "din", "clk")
	c.add_dff("q1", "q0", "clk")
	c.add_dff("q2", "q1", "clk")
	for i in range(6):
		c.set_input("clk", SimValue.ONE, 4 + i * 8)
		c.set_input("clk", SimValue.ZERO, 6 + i * 8)
	c.run_until(12)
	ctx.eq("chain: q0 已为 1", c.probe("q0"), SimValue.ONE)
	ctx.eq("chain: q1 尚未传播", c.probe("q1"), SimValue.X)
	c.run_until(14)
	ctx.eq("chain: q1 已为 1", c.probe("q1"), SimValue.ONE)
	c.run_until(22)
	ctx.eq("chain: q2 已为 1", c.probe("q2"), SimValue.ONE)
	ctx.check("chain: 无亚稳态", c.metastable.is_empty(), str(c.metastable))

func _test_setup(ctx: TestContext) -> void:
	## setup=2：边沿前 1 tick 变 D → Q=X + METASTABLE；边沿前 2 tick 变 → 正常采样。
	var bad := _mk("l3_setup_bad")
	bad.add_dff("q", "d", "clk")
	bad.set_input("clk", SimValue.ONE, 5)
	bad.set_input("clk", SimValue.ZERO, 7)
	bad.set_input("d", SimValue.ONE, 14)
	bad.set_input("clk", SimValue.ONE, 15)
	bad.run_until(7)
	ctx.eq("setup: 首沿正常采样", bad.probe("q"), SimValue.ZERO)
	bad.run_until(17)
	ctx.eq("setup: 违例 → Q=X", bad.probe("q"), SimValue.X)
	ctx.eq("setup: 记录 1 条 METASTABLE", bad.metastable.size(), 1)
	ctx.eq("setup: subject 为 DFF 名", str(bad.metastable[0]["subject"]), "q")
	ctx.eq("setup: reason", str(bad.metastable[0]["reason"]), "setup")
	ctx.eq("setup: 违例 tick", int(bad.metastable[0]["t"]), 15)

	var ok := _mk("l3_setup_ok")
	ok.add_dff("q", "d", "clk")
	ok.set_input("clk", SimValue.ONE, 5)
	ok.set_input("clk", SimValue.ZERO, 7)
	ok.set_input("d", SimValue.ONE, 13)
	ok.set_input("clk", SimValue.ONE, 15)
	ok.run_until(17)
	ctx.eq("setup: Δ=2 边界不违例", ok.probe("q"), SimValue.ONE)
	ctx.check("setup: 边界无 METASTABLE", ok.metastable.is_empty(), str(ok.metastable))

func _test_hold(ctx: TestContext) -> void:
	## hold=1：边沿同 tick 写 D → Q=X + METASTABLE；Δ=1 边界不违例。
	var bad := _mk("l3_hold_bad")
	bad.add_dff("q", "d", "clk")
	bad.set_input("clk", SimValue.ONE, 5)
	bad.set_input("d", SimValue.ONE, 5)
	bad.set_input("clk", SimValue.ZERO, 7)
	bad.run_until(7)
	ctx.eq("hold: 边沿后 0 tick 变 D → Q=X", bad.probe("q"), SimValue.X)
	ctx.eq("hold: 记录 1 条 METASTABLE", bad.metastable.size(), 1)
	ctx.eq("hold: reason", str(bad.metastable[0]["reason"]), "hold")
	ctx.eq("hold: 违例 tick", int(bad.metastable[0]["t"]), 5)

	var ok := _mk("l3_hold_ok")
	ok.add_dff("q", "d", "clk")
	ok.set_input("clk", SimValue.ONE, 5)
	ok.set_input("d", SimValue.ONE, 6)
	ok.set_input("clk", SimValue.ZERO, 7)
	ok.run_until(7)
	ctx.eq("hold: Δ=1 边界不违例", ok.probe("q"), SimValue.ZERO)
	ctx.check("hold: 边界无 METASTABLE", ok.metastable.is_empty(), str(ok.metastable))

func _test_reset(ctx: TestContext) -> void:
	## RESET 异步高有效、在上升沿优先于采样：Q=0；撤 RESET 后恢复采样。
	var c := _mk("l3_reset")
	c.add_wire("rst", SimValue.ZERO)
	c.add_dff("q", "d", "clk", -1, "rst")
	c.set_input("d", SimValue.ONE, 0)
	c.set_input("rst", SimValue.ONE, 4)
	c.set_input("clk", SimValue.ONE, 5)
	c.set_input("clk", SimValue.ZERO, 7)
	c.set_input("rst", SimValue.ZERO, 8)
	c.set_input("clk", SimValue.ONE, 15)
	c.run_until(6)
	ctx.eq("reset: clk→Q 前仍为 X", c.probe("q"), SimValue.X)
	c.run_until(7)
	ctx.eq("reset: 上升沿复位 → Q=0（不采纳 D=1）", c.probe("q"), SimValue.ZERO)
	c.run_until(8)
	ctx.check("reset: RESET 期间无采样违例", c.metastable.is_empty(), str(c.metastable))
	c.run_until(17)
	ctx.eq("reset: 撤销后恢复采样 D=1", c.probe("q"), SimValue.ONE)
