class_name DataValidator
## Maps a dataset name (the labels in DataEditor.DATASETS) to its DataRules validator, and knows how to
## load each dataset's file(s) from disk into the shape that validator expects. `validate(name, dir)`
## checks the on-disk copy; pass `override` (the active editor's in-memory, shaped root from
## DatasetEditor.current_data()) to validate unsaved live edits instead. One place owns the
## name→shape→rules wiring, so the live check and the "check all" sweep can't drift.

static func validate(name: String, content_dir: String, override: Variant = null) -> Array:
	var data: Variant = override if override != null else _load(name, content_dir)
	if data == null:
		return []
	match name:
		"Tips": return DataRules.tips(data)
		"Tool categories": return DataRules.tool_categories(data, content_dir)
		"Loot tables": return DataRules.loot_tables(data, content_dir)
		"Resource defs": return DataRules.resource_defs(data, content_dir)
		"Resource nodes": return DataRules.resource_nodes(data, content_dir)
		"Shops": return DataRules.shops(data, content_dir)
		"Clothing": return DataRules.clothing(data)
		"Items": return DataRules.custom_items(data)
		"Encounters": return DataRules.encounters(data, content_dir)
		"Trainers": return DataRules.trainers(data, content_dir)
		"Job boards": return DataRules.job_boards(data, content_dir)
	return []


static func _load(name: String, content_dir: String) -> Variant:
	match name:
		"Tips":
			var r: Variant = JsonIO.load_file(content_dir + "/game_tips.json")
			return r if typeof(r) == TYPE_DICTIONARY else { "tips": [] }
		"Tool categories":
			return _sub(content_dir + "/tool_categories.json", "categories")
		"Loot tables":
			return _sub(content_dir + "/loot_tables.json", "tables")
		"Resource defs":
			return _sub(content_dir + "/resource_defs.json", "defs")
		"Resource nodes":
			return _sub(content_dir + "/resource_nodes.json", "groups")
		"Clothing":
			var r: Variant = JsonIO.load_file(content_dir + "/clothing_data.json")
			return r if typeof(r) == TYPE_DICTIONARY else {}
		"Items":
			var r: Variant = JsonIO.load_file(content_dir + "/custom_items.json")
			return r if typeof(r) == TYPE_ARRAY else []
		"Encounters":
			var r: Variant = JsonIO.load_file(content_dir + "/encounter_data.json")
			return (r.get("entries", []) as Array) if typeof(r) == TYPE_DICTIONARY else []
		"Shops":
			return _multi(content_dir + "/shops")
		"Trainers":
			return _multi(content_dir + "/trainers")
		"Job boards":
			return _multi(content_dir + "/job_boards")
	return null


## The named sub-object of a single-file dataset (e.g. the "defs" map), or {} if absent.
static func _sub(path: String, key: String) -> Dictionary:
	var r: Variant = JsonIO.load_file(path)
	if typeof(r) == TYPE_DICTIONARY and r.has(key) and typeof(r[key]) == TYPE_DICTIONARY:
		return r[key]
	return {}


## { absolute_path: parsed_dict } for every *.json under a multi-file dataset dir (shops / trainers).
static func _multi(dir: String) -> Dictionary:
	var out := {}
	for p in _find_jsons(dir):
		var r: Variant = JsonIO.load_file(p)
		if typeof(r) == TYPE_DICTIONARY:
			out[p] = r
	return out


static func _find_jsons(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_find_jsons(full))
		elif name.ends_with(".json"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
