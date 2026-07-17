class_name FlagRegistry
## Scans every authored map overlay (res://output/*.meta.json) for string-flag references and aggregates
## them by flag key. There is no flag *declaration* site — a flag "exists" because something writes or
## reads it — so this derives the registry from usage. One scan powers both the Flag Browser and the
## node-editor's flag autocomplete, so the two can't drift.
##
## Reads the SAVED overlays directly as raw JSON (not the MapDoc model, which seeds ROM warps); the Flag
## Browser notes that it reflects last-saved maps. A Usage is
## { map_id, object_id, object_kind, kind } where object_kind is "interactable" (jump selects by id) or
## "zone" (by name), and kind is the usage verb.

const WRITE_KINDS := ["set_flag", "clear_flag"]   ## scripted Action nodes that mutate a flag
const READ_KINDS := ["flag_set", "flag_unset"]    ## scripted Condition nodes that branch on a flag


## { flag_key: { "writes": Array, "reads": Array, "gates": Array } }. Each bucket holds Usage dicts.
static func scan() -> Dictionary:
	var out: Dictionary = {}
	for map_id in _map_ids():
		var meta: Variant = _load_meta(map_id)
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		_scan_interactables(map_id, meta.get("interactables", []), out)
		_scan_gates(map_id, meta.get("gate_zones", []), out)
	return out


## Just the flag keys (sorted), for seeding a picker / autocomplete.
static func keys() -> Array:
	var k := scan().keys()
	k.sort()
	return k


## Known flag keys as picker entries ([{value,label}]) for a SearchPicker / ChipSelect.
static func entries() -> Array:
	var out: Array = []
	for k in keys():
		out.append({ "value": k, "label": k })
	return out


static func _map_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open(EditorConfig.OUTPUT_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".meta.json"):
			out.append(f.trim_suffix(".meta.json"))
	out.sort()
	return out


static func _load_meta(map_id: String) -> Variant:
	var path := EditorConfig.output_path(map_id)
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _scan_interactables(map_id: String, interactables: Array, out: Dictionary) -> void:
	for it in interactables:
		if typeof(it) != TYPE_DICTIONARY or str(it.get("script", "")) != "scripted":
			continue
		var oid := str(it.get("id", ""))
		var graph: Dictionary = it.get("graph", {})
		for node in graph.get("nodes", []):
			if typeof(node) != TYPE_DICTIONARY:
				continue
			match str(node.get("kind", "")):
				"action":
					var a: Dictionary = node.get("action", {})
					var ak := str(a.get("kind", ""))
					if ak in WRITE_KINDS:
						_add(out, str(a.get("key", "")), "writes", map_id, oid, "interactable", ak)
				"condition":
					var c: Dictionary = node.get("cond", {})
					var ck := str(c.get("kind", ""))
					if ck in READ_KINDS:
						_add(out, str(c.get("key", "")), "reads", map_id, oid, "interactable", ck)


static func _scan_gates(map_id: String, gates: Array, out: Dictionary) -> void:
	for z in gates:
		if typeof(z) != TYPE_DICTIONARY:
			continue
		var zone_name := str(z.get("name", ""))
		var g: Dictionary = z.get("gate", {})
		for f in g.get("requires_flag", []):
			_add(out, str(f), "gates", map_id, zone_name, "zone", "requires_flag")
		for f in g.get("forbids_flag", []):
			_add(out, str(f), "gates", map_id, zone_name, "zone", "forbids_flag")


static func _add(out: Dictionary, key: String, bucket: String, map_id: String,
		object_id: String, object_kind: String, kind: String) -> void:
	key = key.strip_edges()
	if key == "":
		return
	if not out.has(key):
		out[key] = { "writes": [], "reads": [], "gates": [] }
	(out[key][bucket] as Array).append({
		"map_id": map_id, "object_id": object_id, "object_kind": object_kind, "kind": kind })
