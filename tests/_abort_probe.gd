extends RefCounted

## 自测探针：故意在第 3 项前抛运行时错误，使 run() 中途中止。
## run_tests.gd 用它验证「检查总数下限」机制确实会判红。DECLARED 必须与实际声明的项数一致。

const DECLARED := 4

func run(ctx: TestContext) -> void:
	ctx.check("probe 1", true)
	ctx.check("probe 2", true)
	var d := {}
	var v = d.no_such_key   # 运行时错误：本函数在此中断，第 3/4 项永不执行
	ctx.check("probe 3 (should never run)", true)
	ctx.check("probe 4 (should never run)", true)
