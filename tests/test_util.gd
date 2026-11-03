class_name TestUtil
extends RefCounted

static func read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

static func data_db() -> Node:
	## `-s` 模式下 autoload 不会走 _ready，这里手动实例化数据层并加载。
	var script: GDScript = load("res://src/autoload/data_db.gd")
	var db: Node = script.new()
	db.load_all()
	return db

static func items_doc() -> Dictionary:
	return read_json("res://data/items/items.json")

static func prices_doc() -> Dictionary:
	return read_json("res://data/economy/prices.json")

static func recipes_doc() -> Dictionary:
	return read_json("res://data/economy/recipes.json")

static func catalog() -> Catalog:
	return Catalog.from_data(items_doc(), prices_doc(), recipes_doc())

static func skill_doc() -> Dictionary:
	return read_json("res://data/skilltree.json")

static func skill_nodes() -> Dictionary:
	var out := {}
	for raw in skill_doc().get("nodes", []):
		if raw is Dictionary:
			out[str(raw["id"])] = raw
	return out

static func chapter_doc() -> Dictionary:
	return read_json("res://data/chapters/ch01_levels.json")

static func labs_doc() -> Dictionary:
	return read_json("res://data/labs/ch01_labs.json")

static func tutorial_doc() -> Dictionary:
	return read_json("res://data/tutorial.json")
