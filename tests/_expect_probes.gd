extends SceneTree

## 防线自检探针：默认不跑（只有显式 `godot -s res://tests/_expect_probes.gd` 才会执行）。
## run_tests.gd 只断言本文件存在；输出必须含 `PROBE 1 RED` / `PROBE 2 RED` / `PROBE 3 RED`，
## 缺标记 = 探针没跑或防线失效。

class SuiteA extends RefCounted:
	const EXPECT := 4
	const EXPECT_GROUPS := {"g": 4}
	func run(ctx: TestContext) -> void:
		ctx.begin_group("g")
		ctx.check("a", true)
		ctx.check("b", true)
		ctx.check("c", true)

class SuiteC extends RefCounted:
	const EXPECT := 4
	const EXPECT_GROUPS := {"g": 2, "h": 2}
	func run(ctx: TestContext) -> void:
		ctx.begin_group("g")
		ctx.check("a", true)
		ctx.check("b", true)

func _initialize() -> void:
	var red1 := _probe1()
	var red2 := _probe2()
	var red3 := _probe3()
	print("PROBE_SUMMARY 1=%s 2=%s 3=%s" % [str(red1), str(red2), str(red3)])
	quit(0 if (red1 and red2 and red3) else 1)

## 探针 1：删一条断言、组计数不跟着改 → 组计数必须红。
func _probe1() -> bool:
	var ctx := TestContext.new()
	ctx.begin("probe1")
	(SuiteA.new() as RefCounted).run(ctx)
	var got := int(ctx.group_counts.get("g", 0))
	var red := got != SuiteA.EXPECT_GROUPS["g"]
	if red:
		print("PROBE 1 RED group=g 实际 %d / 声明 %d" % [got, int(SuiteA.EXPECT_GROUPS["g"])])
	return red

## 探针 3：整组删掉（断言与计数一起删）→ 该组计数为 0，必须红。
func _probe3() -> bool:
	var ctx := TestContext.new()
	ctx.begin("probe3")
	(SuiteC.new() as RefCounted).run(ctx)
	var got := int(ctx.group_counts.get("h", 0))
	var red := got != SuiteC.EXPECT_GROUPS["h"] and ctx.checks != SuiteC.EXPECT
	if red:
		print("PROBE 3 RED group=h 实际 %d / 声明 %d；总数 实际 %d / EXPECT %d" % [
			got, int(SuiteC.EXPECT_GROUPS["h"]), ctx.checks, SuiteC.EXPECT])
	return red

## 探针 2：相对 HEAD 基线降 15%（>10% 硬线）+ 理由写「优化」→ 两条都必须红。
func _probe2() -> bool:
	var prev := _expect_in_head("tests/test_ch01_sections.gd")
	if prev <= 0:
		print("PROBE 2 [skip] no baseline（下降检查未生效）")
		return false
	var expect := int(prev * 0.85)
	var drop := 1.0 - float(expect) / float(prev)
	var banned := ["", "无", "调整", "优化", "清理", "重构"]
	var rationale := "优化"
	var red_drop := drop > 0.10
	var red_reason := rationale in banned
	var red := red_drop and red_reason
	if red:
		print("PROBE 2 RED drop=%.1f%% > 10%%（需人工复核）；rationale=\"%s\"（空话理由）" % [
			drop * 100.0, rationale])
	return red

func _git_show(spec: String) -> String:
	var out := []
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var rc := OS.execute("git", ["-C", root, "show", spec], out)
	if rc != 0 or out.size() == 0:
		return ""
	return str(out[0])

func _expect_in_head(path: String) -> int:
	var txt := _git_show("HEAD:" + path)
	if not txt.is_empty():
		var re := RegEx.new()
		re.compile("const\\s+EXPECT\\s*:\\s*int\\s*=\\s*(\\d+)")
		var m := re.search(txt)
		if m != null:
			return int(m.get_string(1))
	var key := path.get_file().get_basename()
	var rt := _git_show("HEAD:tests/run_tests.gd")
	if rt.is_empty():
		return -1
	var row := RegEx.new()
	row.compile("\"%s\"\\s*:\\s*(\\d+)" % key)
	var r := row.search(rt)
	return int(r.get_string(1)) if r != null else -1
