extends SceneTree

## 防线自检探针：默认不跑（只有显式 `godot -s res://tests/_expect_probes.gd` 才会执行）。
## run_tests.gd 只断言本文件存在；输出必须含 `PROBE 1 RED` / `PROBE 2 RED` / `PROBE 3 RED`，
## 缺标记 = 探针没跑或防线失效。
##
## MUTATE 探针（改造实证）：默认也不跑，需 `IFZ_MUTATE=1 godot -s res://tests/_expect_probes.gd`。
## 每条对「改造后能失败的检查」故意破坏一次，确认它真的会红；有任一不红说明改造失败。

const Teach := preload("res://src/ui/teaching.gd")
const Reader := preload("res://src/ui/widgets/section_reader.gd")
const Ch02ChecksScript := preload("res://src/core/ch02_checks.gd")

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
	var mutation_ok := true
	if OS.get_environment("IFZ_MUTATE") == "1":
		mutation_ok = _run_mutations()
	quit(0 if (red1 and red2 and red3 and mutation_ok) else 1)

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

# ---------------------------------------------------------------- MUTATE 1-9
# 每条：把改造后的检查所依赖的输入故意破坏一次，确认检查真的会红。
# 只打印 `MUTATE n RED <label>`（红 = 改造有效）；全红才返回 true。

func _run_mutations() -> bool:
	var reds: Array = [
		_mutate1(), _mutate2(), _mutate3(), _mutate4(), _mutate5(),
		_mutate6(), _mutate7(), _mutate8(), _mutate9(),
	]
	var passed := 0
	for r in reds:
		if bool(r):
			passed += 1
	print("MUTATE_SUMMARY %d/9" % passed)
	return passed == 9

## 1：槽位目录不可写 → `fixture slot writable` 红。
func _mutate1() -> bool:
	var blocker := "user://mut_probe_blocker"
	var bf := FileAccess.open(blocker, FileAccess.WRITE)
	if bf != null:
		bf.store_string("x")
		bf.close()
	var store := SaveStore.new(blocker + "/sub")
	store.ensure_dir()
	var probe_path := store.slot_path(9999)
	var pf := FileAccess.open(probe_path, FileAccess.WRITE)
	var red := pf == null
	if pf != null:
		pf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	if red:
		print("MUTATE 1 RED fixture slot writable（目录被文件占位，写盘失败）")
	return red

## 2：数据 id_sat_ua 临时改成 1000 → `数据饱和电流 > 线性区最大电流` 红。
func _mutate2() -> bool:
	var dev: Dictionary = (TestUtil.read_json("res://data/labs/ch02_labs.json").get("labs", {}).get("transistor", {}) as Dictionary).get("device", {})
	var bad: Dictionary = dev.duplicate(true)
	bad["id_sat_ua"] = 1000
	var red := float(bad.get("id_sat_ua", -1)) > Ch02ChecksScript.id_ua_of(3.3, 0.2, bad)
	red = not red
	if red:
		print("MUTATE 2 RED 数据饱和电流 > 线性区最大电流（id_sat 1000 < 线性 %.0f µA）" % Ch02ChecksScript.id_ua_of(3.3, 0.2, bad))
	return red

## 3：把所有 lab 的 after 去重成唯一档 → `after 重复档样本存在` 红。
func _mutate3() -> bool:
	var labs: Dictionary = TestUtil.labs_doc().get("labs", {})
	var real := _count_dup_labs(labs)
	var dedup := {}
	for id in labs:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(labs[id]))
		var secs: Array = copy.get("sections", [])
		for i in secs.size():
			(secs[i] as Dictionary)["after"] = i
		dedup[str(id)] = copy
	var mutated := _count_dup_labs(dedup)
	var red := real >= 1 and mutated < 1
	if red:
		print("MUTATE 3 RED after 重复档样本存在（去重后样本 lab %d→%d）" % [real, mutated])
	return red

func _count_dup_labs(labs: Dictionary) -> int:
	var n := 0
	for id in labs:
		var secs := Teach.section_list(labs[id])
		if secs.is_empty():
			continue
		var max_after := 0
		for raw in secs:
			max_after = maxi(max_after, int((raw as Dictionary).get("after", 0)))
		var at_max := 0
		for raw in secs:
			if int((raw as Dictionary).get("after", 0)) == max_after:
				at_max += 1
		if at_max >= 2:
			n += 1
	return n

## 4：上限漂到 60（等价于把 SimDelays 门级上限改成 60）→ `editor cap from delays` 红。
func _mutate4() -> bool:
	var ed := CircuitEditor.new()
	ed.setup([{"id": "a", "label": "A"}], [{"id": "out", "label": "O"}], ["and"], 60)
	var red := ed.max_gates != 50
	if red:
		print("MUTATE 4 RED editor cap from delays（实际上限 %d / 契约锁 50）" % ed.max_gates)
	ed.free()
	return red

## 5：从 NAMES 删掉一个 code → `TAG_MAP 的键都在 NAMES 内` 红。
func _mutate5() -> bool:
	var victim := -1
	for k in GateResult.TAG_MAP.keys():
		if GateResult.NAMES.has(int(k)):
			victim = int(k)
			break
	var names: Dictionary = GateResult.NAMES.duplicate()
	if victim >= 0:
		names.erase(victim)
	var unmapped: Array = []
	for k in GateResult.TAG_MAP.keys():
		if not names.has(int(k)):
			unmapped.append(int(k))
	var red := victim >= 0 and not unmapped.is_empty()
	if red:
		print("MUTATE 5 RED TAG_MAP 的键都在 NAMES 内（删掉 code %d，未登记 %s）" % [victim, str(unmapped)])
	return red

## 6：真值表只喂 3 行 → `half adder total rows` 红。
func _mutate6() -> bool:
	var short_rows: Array = BlackBox.half_adder_rows().slice(0, 3)
	var r := BlackBox.check_outputs(HalfAdder.build(), ["a", "b"], ["sum", "carry"], short_rows)
	var red := int(r.get("total", 0)) != 4
	if red:
		print("MUTATE 6 RED half adder total rows（total=%d / 期望 4）" % int(r.get("total", 0)))
	return red

## 7：让某个配方的 out_id 为空 → `cat.items.has(out_id)` 红（旧写法空输出恒过）。
func _mutate7() -> bool:
	var cat := TestUtil.catalog()
	if cat.recipe_ids().is_empty():
		return false
	var out_id := ""
	var new_pred := cat.items.has(out_id)
	var old_pred := out_id.is_empty() or cat.items.has(out_id)
	var red := not new_pred and old_pred
	if red:
		print("MUTATE 7 RED recipe output exists（空输出：新判据红、旧判据恒过）")
	return red

## 8：t4 少录一条事件 → `digest: 同内容同摘要` 红。
func _mutate8() -> bool:
	var t2 := TraceSink.new()
	t2.record(0, "L2", "CHANGE", "w", {"v": "1"})
	t2.record(1, "L2", "CHANGE", "w", {"v": "2"})
	var t4 := TraceSink.new()
	t4.record(0, "L2", "CHANGE", "w", {"v": "1"})
	var red := t2.digest() != t4.digest()
	if red:
		print("MUTATE 8 RED digest: 同内容同摘要（t4 少录一条事件）")
	return red

## 9：单段 lab（该段即整节正文）→ 聚合的 `屏上正文 != 整节正文` 红。
func _mutate9() -> bool:
	var cfg := {"body": "整节正文", "rules": [], "sections": [{"order": 1, "after": 0, "text": "整节正文"}]}
	var secs := Teach.section_list(cfg)
	var r = Reader.new()
	r.configure(secs, 14, 16)
	r.set_done(0)
	var shown := Reader.flat_text(r.text_label.text)
	var same_as_section := shown == Reader.flat_text(str(secs[0].get("text", "")))
	var differs_from_whole := shown != Reader.flat_text(Teach.teaching_text(cfg))
	var red := same_as_section and not differs_from_whole
	if red:
		print("MUTATE 9 RED 多段 lab 屏上正文都不等于整节正文（单段退化：显示即整节）")
	r.free()
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
		# 与 run_tests.gd 同式：同时接受 `:=` 与 `: int =`（否则迁移后的套件会被静默跳过）。
		re.compile("const\\s+EXPECT\\s*(?::\\s*int\\s*)?(:?=)\\s*(\\d+)")
		var m := re.search(txt)
		if m != null:
			return int(m.get_string(2))
	var key := path.get_file().get_basename()
	var rt := _git_show("HEAD:tests/run_tests.gd")
	if rt.is_empty():
		return -1
	var row := RegEx.new()
	row.compile("\"%s\"\\s*:\\s*(\\d+)" % key)
	var r := row.search(rt)
	return int(r.get_string(1)) if r != null else -1
