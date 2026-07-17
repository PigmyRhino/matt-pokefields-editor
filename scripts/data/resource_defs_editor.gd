extends DatasetEditor
## resource_defs.json — { "defs": { <name>: { skill, level_required, tool, xp, hp_max, respawn_ms, loot } } }
## Per-resource economy (referenced by `ref` from resource nodes). One def at a time via NamedCatalog.
## `loot` is a live loot_tables name; `tool` is the minimum tool item (null = bare-hand).

var _raw: Dictionary = {}
var _path := ""
var _loot: Array = []
var _cat: NamedCatalog


func load_data() -> void:
	_path = base_dir + "/resource_defs.json"
	_raw = JsonIO.load_file(_path)
	if not _raw.has("defs"):
		_raw["defs"] = {}
	_loot = _loot_entries()
	var hint := Label.new()
	hint.text = "One entry per real resource (referenced by `ref` from resource nodes)."
	add_child(hint)
	_cat = NamedCatalog.new()
	add_child(_cat)
	_cat.setup(_raw["defs"], "new_def", _make_def, _build_def)
	_cat.dirty.connect(func() -> void: dirty.emit())


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _raw.get("defs", {})


func reveal(p: Problem) -> void:
	_cat.reveal(p.context)


func _make_def() -> Variant:
	return { "skill": "foraging", "level_required": 1, "tool": null, "xp": 1, "hp_max": 1, "respawn_ms": 60000, "loot": "" }


func _build_def(_name: String, record: Variant, into: VBoxContainer) -> void:
	var d: Dictionary = record
	into.add_child(_row("Skill", _picker_field(Catalog.skills, d, "skill", false), "Which skill this resource trains."))
	into.add_child(_row("Level req", _int_field(d, "level_required", 1, 1, 99), "Minimum skill level to gather."))
	into.add_child(_row("Tool (item)", _item_id_picker(d, "tool", true), "Minimum tool item; empty = bare-hand."))
	into.add_child(_row("XP", _int_field(d, "xp", 0, 0, 100000), "Skill XP granted per gather."))
	into.add_child(_row("HP max", _int_field(d, "hp_max", 1, 1, 1000), "Swings needed to deplete the node."))
	into.add_child(_row("Respawn ms", _int_field(d, "respawn_ms", 0, 0, 100000000), "Per-player respawn delay in milliseconds."))
	into.add_child(_row("Loot", _picker_field(_loot, d, "loot", false), "Drop table rolled on gather (from Loot tables)."))


func _loot_entries() -> Array:
	var lt: Variant = JsonIO.load_file(base_dir + "/loot_tables.json")
	var out: Array = []
	if typeof(lt) == TYPE_DICTIONARY and lt.has("tables"):
		for name in lt["tables"]:
			out.append({ "value": name, "label": name })
	return out
