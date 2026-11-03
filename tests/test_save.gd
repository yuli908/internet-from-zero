extends RefCounted

func run(ctx: TestContext) -> void:
	var st := PlayerState.new(42)
	st.scrap = 77
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
	ctx.eq("decoded version", int(dec["version"]), 2)
	ctx.eq("not migrated", int(dec["migrated_from"]), 0)

	var st2 := PlayerState.from_dict(dec["payload"])
	ctx.eq("scrap roundtrip", st2.scrap, 77)
	ctx.eq("xp roundtrip", st2.xp, 33)
	ctx.eq("item roundtrip", st2.item_count("wire"), 2)
	ctx.check("knowledge roundtrip", st2.has_knowledge("voltage"))
	ctx.check("objective roundtrip", st2.is_objective_done("obj_level"))
	ctx.check("flag roundtrip", bool(st2.get_flag("chapter_reward:ch01", false)))
	ctx.eq("rng state roundtrip", st2.rng().state_value(), st.rng().state_value())

	var payload_str := JSON.stringify(st.to_dict(), "", true)
	var env := {
		"fmt": SaveCodec.ENVELOPE_FMT,
		"version": 2,
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
	ctx.eq("migrated version", int(migrated["payload"]["version"]), 2)
	var lst := PlayerState.from_dict(migrated["payload"])
	ctx.eq("legacy scrap", lst.scrap, 12)
	ctx.eq("legacy wire", lst.item_count("wire"), 2)
	ctx.check("legacy knowledge", lst.has_knowledge("voltage"))
	ctx.check("legacy defaults labs", lst.labs_completed.is_empty())
	ctx.eq("legacy rng seed default", lst.rng_seed, 1)

	var newer := SaveCodec.encode_payload({"version": 3, "scrap": 1}, 3)
	var nres := SaveCodec.decode(newer)
	ctx.check("newer version rejected", not bool(nres["ok"]))
	ctx.check("newer message", str(nres["error"]).contains("高于"))

	_test_store(ctx)
	_test_determinism(ctx)

func _test_store(ctx: TestContext) -> void:
	var store := SaveStore.new("user://test_saves")
	store.ensure_dir()
	for p in [store.slot_path(1), store.backup_path(1), store.slot_path(1) + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

	var s1 := PlayerState.new()
	s1.scrap = 10
	s1.add_item("wire", 1)
	var w := store.save(s1, 1)
	ctx.check("store save ok", bool(w["ok"]), str(w["error"]))
	ctx.check("slot file exists", FileAccess.file_exists(store.slot_path(1)))
	var info := store.slot_info(1)
	ctx.check("slot info ok", bool(info["ok"]), str(info["error"]))
	ctx.eq("slot info scrap", int(info["scrap"]), 10)

	var loaded := store.load_slot(1)
	ctx.check("store load ok", bool(loaded["ok"]), str(loaded["error"]))
	ctx.eq("store load scrap", loaded["state"].scrap, 10)
	ctx.eq("store load wire", loaded["state"].item_count("wire"), 1)
	ctx.check("no backup used", not bool(loaded["used_backup"]))

	s1.scrap = 999
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
	ctx.eq("recovered stale scrap", recovered["state"].scrap, 10)
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
