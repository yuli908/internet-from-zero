extends RefCounted

func run(ctx: TestContext) -> void:
	var st := PlayerState.new(42)
	st.gold = 77
	st.xp = 33
	st.add_item("wire", 2)
	st.grant_knowledge("voltage")
	st.complete_objective("obj_level")
	st.mark_lab_completed("level")
	st.set_flag("chapter_reward:ch01", true)

	var text := SaveCodec.encode(st)
	ctx.check("save text non-empty", text.length() > 100)
	var dec := SaveCodec.decode(text)
	ctx.check("decode ok", bool(dec["ok"]), str(dec["error"]))
	ctx.eq("decoded version", int(dec["version"]), 3)
	ctx.eq("not migrated", int(dec["migrated_from"]), 0)

	var st2 := PlayerState.from_dict(dec["payload"])
	ctx.eq("gold roundtrip", st2.gold, 77)
	ctx.eq("xp roundtrip", st2.xp, 33)
	ctx.eq("item roundtrip", st2.item_count("wire"), 2)
	ctx.check("knowledge roundtrip", st2.has_knowledge("voltage"))
	ctx.check("objective roundtrip", st2.is_objective_done("obj_level"))
	ctx.check("flag roundtrip", bool(st2.get_flag("chapter_reward:ch01", false)))
	ctx.eq("rng state roundtrip", st2.rng().state_value(), st.rng().state_value())

	var payload_str := JSON.stringify(st.to_dict(), "", true)
	var env := {
		"fmt": SaveCodec.ENVELOPE_FMT,
		"version": 3,
		"algo": "sha256",
		"checksum": "deadbeef",
		"payload": payload_str,
	}
	var tampered := SaveCodec.decode(JSON.stringify(env))
	ctx.check("tamper detected", not bool(tampered["ok"]))
	ctx.check("tamper message", str(tampered["error"]).contains("校验和"))

	var broken := SaveCodec.decode("{this is not json")
	ctx.check("broken json rejected", not bool(broken["ok"]))
	ctx.check("broken json message", str(broken["error"]).contains("JSON"))

	var legacy := {
		"version": 1,
		"player": {
			"scrap": 12, "xp": 5, "slot": 1, "chapter_id": "ch01",
			"inventory": {"wire": 2},
			"knowledge": {"voltage": true},
			"objectives": {"obj_level": true},
		},
	}
	var legacy_text := SaveCodec.encode_payload(legacy, 1)
	var migrated := SaveCodec.decode(legacy_text)
	ctx.check("legacy decode", bool(migrated["ok"]), str(migrated["error"]))
	ctx.eq("migrated from v1", int(migrated["migrated_from"]), 1)
	ctx.eq("migrated version", int(migrated["payload"]["version"]), 3)
	var lst := PlayerState.from_dict(migrated["payload"])
	ctx.eq("legacy gold", lst.gold, 12)
	ctx.eq("legacy wire", lst.item_count("wire"), 2)
	ctx.check("legacy knowledge", lst.has_knowledge("voltage"))
	ctx.check("legacy defaults labs", lst.labs_completed.is_empty())
	ctx.eq("legacy rng seed default", lst.rng_seed, 1)

	var newer := SaveCodec.encode_payload({"version": 4, "gold": 1}, 4)
	var nres := SaveCodec.decode(newer)
	ctx.check("newer version rejected", not bool(nres["ok"]))
	ctx.check("newer message", str(nres["error"]).contains("高于"))

	_test_v2_migration(ctx)
	_test_registry(ctx)
	_test_fixture_v1(ctx)
	_test_fixture_v2(ctx)
	_test_store(ctx)
	_test_determinism(ctx)

func _test_v2_migration(ctx: TestContext) -> void:
	# v2 存档：货币键仍是 scrap，且带一个 v3 不认识的字段。
	var v2 := {
		"version": 2,
		"scrap": 45,
		"xp": 12,
		"inventory": {"wire": 3},
		"legacy_extra": 7,
	}
	var res := SaveCodec.decode(SaveCodec.encode_payload(v2, 2))
	ctx.check("v2 decode ok", bool(res["ok"]), str(res["error"]))
	ctx.eq("v2 migrated_from", int(res["migrated_from"]), 2)
	ctx.eq("v2 migrated version", int(res["payload"]["version"]), 3)
	ctx.check("v2 scrap key renamed", not (res["payload"] as Dictionary).has("scrap"))
	ctx.eq("v2 gold from scrap", int(res["payload"].get("gold", -1)), 45)
	ctx.eq("v2 unknown field kept", int(res["payload"].get("legacy_extra", -1)), 7)
	var st := PlayerState.from_dict(res["payload"])
	ctx.eq("v2 gold loaded", st.gold, 45)
	ctx.eq("v2 inventory loaded", st.item_count("wire"), 3)

	# v2 存档中的进度（gate flags / 知识 / 目标）迁移后不得丢失。
	var progress := PlayerState.new(3)
	progress.gold = 88
	progress.set_flag("gate:T1.1-4", true)
	progress.set_flag("lab:level", true)
	progress.set_flag("chapter_reward:ch01", true)
	progress.grant_knowledge("voltage")
	progress.grant_knowledge("KN-ELEC-01")
	progress.complete_objective("obj_level")
	progress.mark_lab_completed("level")
	var snapshot := progress.to_dict()
	snapshot["version"] = 2
	snapshot["scrap"] = snapshot.get("gold", 0)
	snapshot.erase("gold")
	var kept := SaveCodec.decode(SaveCodec.encode_payload(snapshot, 2))
	ctx.check("v2 progress decode ok", bool(kept["ok"]), str(kept["error"]))
	var restored := PlayerState.from_dict(kept["payload"])
	ctx.eq("v2 progress gold", restored.gold, 88)
	ctx.check("v2 progress gate flag kept", bool(restored.get_flag("gate:T1.1-4", false)))
	ctx.check("v2 progress lab flag kept", bool(restored.get_flag("lab:level", false)))
	ctx.check("v2 progress chapter flag kept", bool(restored.get_flag("chapter_reward:ch01", false)))
	ctx.check("v2 progress knowledge kept", restored.has_knowledge("voltage") and restored.has_knowledge("KN-ELEC-01"))
	ctx.check("v2 progress objective kept", restored.is_objective_done("obj_level"))
	ctx.check("v2 progress lab kept", restored.is_lab_completed("level"))

func _test_registry(ctx: TestContext) -> void:
	# 契约：注册表必须覆盖 1..FORMAT_VERSION-1，且链路能把任意旧版本推到当前版本。
	ctx.eq("registry errors", SaveCodec.registry_errors().size(), 0)
	ctx.eq("registry entries", SaveCodec.MIGRATIONS.size(), SaveCodec.FORMAT_VERSION - 1)
	for v in range(1, SaveCodec.FORMAT_VERSION):
		ctx.check("registry has v%d" % v, SaveCodec.MIGRATIONS.has(v))
		var res := SaveCodec.migrate({"version": v})
		ctx.check("chain from v%d ok" % v, bool(res["ok"]), str(res["error"]))
		if bool(res["ok"]):
			ctx.eq("chain from v%d version" % v, int(res["payload"]["version"]), SaveCodec.FORMAT_VERSION)
			ctx.eq("chain from v%d from" % v, int(res["from"]), v)
	var fresh := SaveCodec.migrate({"version": SaveCodec.FORMAT_VERSION})
	ctx.check("migrate latest ok", bool(fresh["ok"]), str(fresh["error"]))
	ctx.eq("migrate latest from", int(fresh["from"]), SaveCodec.FORMAT_VERSION)

func _test_fixture_v1(ctx: TestContext) -> void:
	var fx: Dictionary = TestUtil.read_json("res://tests/data/saves/legacy_v1.json")
	var res := _load_slot_text(ctx, SaveCodec.encode_payload(fx, 1), 6)
	if not bool(res.get("ok", false)):
		return
	var p: Dictionary = res["payload"]
	var st: PlayerState = res["state"]
	ctx.eq("v1 fixture migrated_from", int(res["migrated_from"]), 1)
	ctx.eq("v1 fixture version", int(p["version"]), 3)
	ctx.check("v1 fixture no backup", not bool(res["used_backup"]))
	ctx.eq("v1 fixture gold", st.gold, 120)
	ctx.eq("v1 fixture xp", st.xp, 40)
	ctx.eq("v1 fixture slot", st.slot, 6)
	ctx.eq("v1 fixture payload slot", int(p.get("slot", -1)), 2)
	ctx.eq("v1 fixture chapter", st.chapter_id, "ch01")
	ctx.eq("v1 fixture created_at", st.created_at, "2026-01-01T00:00:00")
	ctx.eq("v1 fixture wire", st.item_count("wire"), 5)
	ctx.eq("v1 fixture resistor", st.item_count("resistor"), 2)
	ctx.check("v1 fixture knowledge", st.has_knowledge("voltage") and st.has_knowledge("KN-ELEC-01"))
	ctx.check("v1 fixture objectives", st.is_objective_done("obj_level") and st.is_objective_done("obj_binary"))
	ctx.check("v1 fixture labs", st.is_lab_completed("level") and st.is_lab_completed("binary"))
	ctx.check("v1 fixture gate flag", bool(st.get_flag("gate:T1.1-4", false)))
	ctx.check("v1 fixture lab flag", bool(st.get_flag("lab:level", false)))
	ctx.check("v1 fixture chapter flag", bool(st.get_flag("chapter_reward:ch01", false)))
	ctx.check("v1 fixture tutorial", st.is_tutorial_done("step_intro"))
	ctx.eq("v1 fixture stats saves", int(st.stats.get("saves", -1)), 3)
	ctx.eq("v1 fixture stats ticks", int(st.stats.get("ticks", -1)), 99)
	ctx.check("v1 fixture stats seconds", is_equal_approx(float(st.stats.get("play_seconds", -1.0)), 1234.5))
	ctx.eq("v1 fixture rng seed", st.rng_seed, 42)
	ctx.eq("v1 fixture rng state", st.rng().state_value(), 12345)
	var unknown: Variant = p.get("legacy_unknown", null)
	ctx.check("v1 fixture unknown kept", unknown is Dictionary and str((unknown as Dictionary).get("foo", "")) == "bar")
	ctx.check("v1 fixture scrap removed", not p.has("scrap"))

func _test_fixture_v2(ctx: TestContext) -> void:
	var fx: Dictionary = TestUtil.read_json("res://tests/data/saves/legacy_v2.json")
	var res := _load_slot_text(ctx, SaveCodec.encode_payload(fx, 2), 7)
	if not bool(res.get("ok", false)):
		return
	var p: Dictionary = res["payload"]
	var st: PlayerState = res["state"]
	ctx.eq("v2 fixture migrated_from", int(res["migrated_from"]), 2)
	ctx.eq("v2 fixture version", int(p["version"]), 3)
	ctx.check("v2 fixture no backup", not bool(res["used_backup"]))
	ctx.eq("v2 fixture gold", st.gold, 88)
	ctx.eq("v2 fixture xp", st.xp, 30)
	ctx.eq("v2 fixture slot", st.slot, 7)
	ctx.eq("v2 fixture payload slot", int(p.get("slot", -1)), 3)
	ctx.eq("v2 fixture created_at", st.created_at, "2026-02-01T00:00:00")
	ctx.eq("v2 fixture wire", st.item_count("wire"), 4)
	ctx.eq("v2 fixture diode", st.item_count("diode"), 1)
	ctx.check("v2 fixture knowledge", st.has_knowledge("voltage") and st.has_knowledge("KN-ELEC-02"))
	ctx.check("v2 fixture objective", st.is_objective_done("obj_binary"))
	ctx.check("v2 fixture lab", st.is_lab_completed("binary"))
	ctx.check("v2 fixture gate flag", bool(st.get_flag("gate:T1.1-1", false)))
	ctx.check("v2 fixture lab flag", bool(st.get_flag("lab:binary", false)))
	ctx.check("v2 fixture tutorial", st.is_tutorial_done("step_binary"))
	ctx.eq("v2 fixture stats saves", int(st.stats.get("saves", -1)), 5)
	ctx.eq("v2 fixture stats ticks", int(st.stats.get("ticks", -1)), 111)
	ctx.check("v2 fixture stats seconds", is_equal_approx(float(st.stats.get("play_seconds", -1.0)), 777.0))
	ctx.eq("v2 fixture rng seed", st.rng_seed, 9)
	ctx.eq("v2 fixture rng state", st.rng().state_value(), 54321)
	var unknown: Variant = p.get("legacy_unknown_top", null)
	ctx.check("v2 fixture unknown kept", unknown is Array and (unknown as Array).size() == 3 and int((unknown as Array)[2]) == 3)
	ctx.check("v2 fixture scrap removed", not p.has("scrap") and not st.inventory.has("scrap"))

func _load_slot_text(ctx: TestContext, text: String, slot_num: int) -> Dictionary:
	var store := SaveStore.new("user://test_saves")
	store.ensure_dir()
	var path := store.slot_path(slot_num)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		ctx.check("fixture slot writable", false, str(slot_num))
		return {"ok": false, "error": "无法写槽位 %d" % slot_num, "state": null, "used_backup": false}
	f.store_string(text)
	f.close()
	var res := store.load_slot(slot_num)
	for p in [store.slot_path(slot_num), store.backup_path(slot_num), store.slot_path(slot_num) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	return res

func _test_store(ctx: TestContext) -> void:
	var store := SaveStore.new("user://test_saves")
	store.ensure_dir()
	for p in [store.slot_path(1), store.backup_path(1), store.slot_path(1) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

	var s1 := PlayerState.new()
	s1.gold = 10
	s1.add_item("wire", 1)
	var w := store.save(s1, 1)
	ctx.check("store save ok", bool(w["ok"]), str(w["error"]))
	ctx.check("slot file exists", FileAccess.file_exists(store.slot_path(1)))
	var info := store.slot_info(1)
	ctx.check("slot info ok", bool(info["ok"]), str(info["error"]))
	ctx.eq("slot info gold", int(info["gold"]), 10)

	var loaded := store.load_slot(1)
	ctx.check("store load ok", bool(loaded["ok"]), str(loaded["error"]))
	ctx.eq("store load gold", loaded["state"].gold, 10)
	ctx.eq("store load wire", loaded["state"].item_count("wire"), 1)
	ctx.check("no backup used", not bool(loaded["used_backup"]))

	s1.gold = 999
	s1.add_item("wire", 5)
	var w2 := store.save(s1, 1)
	ctx.check("second save ok", bool(w2["ok"]))
	ctx.check("backup created", FileAccess.file_exists(store.backup_path(1)))

	var f := FileAccess.open(store.slot_path(1), FileAccess.WRITE)
	f.store_string("{broken save")
	f.close()
	var recovered := store.load_slot(1)
	ctx.check("backup recovery ok", bool(recovered["ok"]), str(recovered["error"]))
	ctx.check("backup flag", bool(recovered["used_backup"]))
	ctx.eq("recovered stale gold", recovered["state"].gold, 10)
	ctx.check("primary error reported", str(recovered.get("primary_error", "")).contains("失败"))

	var bad_info := store.slot_info(1)
	ctx.check("corrupt slot_info fails", not bool(bad_info["ok"]))

	store.delete_slot(1)
	ctx.check("slot deleted", not FileAccess.file_exists(store.slot_path(1)))
	ctx.check("missing slot load fails", not bool(store.load_slot(2)["ok"]))

func _test_determinism(ctx: TestContext) -> void:
	var a := PlayerState.new(7)
	var b := PlayerState.new(7)
	var same := true
	for i in 5:
		if a.roll(0, 100) != b.roll(0, 100):
			same = false
	ctx.check("same seed same rolls", same)
	var snapshot := a.to_dict()
	var c := PlayerState.from_dict(snapshot)
	var restored := true
	for i in 3:
		if a.roll(0, 100) != c.roll(0, 100):
			restored = false
	ctx.check("rng state restored", restored)
