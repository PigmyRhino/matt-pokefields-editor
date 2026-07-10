class_name ContentScan
## Shared scanners that turn the content/ datasets into picker entries ([{value,label}]). Used by the
## Inspector (trainer link, shop link) and the action-list builder, so the directory walk lives once.

const TRAINERS_DIR := "res://content/trainers"
const SHOPS_DIR := "res://content/shops"
const JOB_BOARDS_DIR := "res://content/job_boards"
const ENCOUNTERS_FILE := "res://content/encounter_data.json"
const RESOURCE_NODES_FILE := "res://content/resource_nodes.json"


## Distinct encounter group names from content/encounter_data.json — the LIVE source the designer edits
## on the Data → Encounters card. (The bundled Catalog.encounters snapshot drifts and goes stale.)
static func encounter_groups() -> Array:
	var seen := {}
	var out: Array = []
	var d: Variant = JsonIO.load_file(ENCOUNTERS_FILE)
	if typeof(d) == TYPE_DICTIONARY:
		for e in d.get("entries", []):
			var g := str((e as Dictionary).get("encounter", ""))
			if g != "" and not seen.has(g):
				seen[g] = true
				out.append({ "value": g, "label": g })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["value"]) < str(b["value"]))
	return out


## Resource-node group names (the OBJECT_TYPE values) from content/resource_nodes.json — the LIVE source
## the designer edits on the Data → Resource nodes card. (Catalog.object_types is a stale snapshot.)
static func object_types() -> Array:
	var out: Array = []
	var d: Variant = JsonIO.load_file(RESOURCE_NODES_FILE)
	if typeof(d) == TYPE_DICTIONARY:
		for g in (d.get("groups", {}) as Dictionary):
			out.append({ "value": str(g), "label": str(g) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["value"]) < str(b["value"]))
	return out


## Trainer entries ({value: unique_name, label: "Display (unique_name)"}).
static func trainers() -> Array:
	return entries(TRAINERS_DIR, func(t: Dictionary) -> Variant:
		if not t.has("unique_name"):
			return null
		var uid := str(t["unique_name"])
		return { "value": uid, "label": "%s  (%s)" % [str(t.get("display_name", uid)), uid] })


## { unique_name: rebattle } across every trainer file ("once" when the key is absent). The job-board
## validator uses it to warn on a defeat_trainer objective that targets a non-rebattlable trainer —
## once beaten, its daily/weekly job is uncompletable forever (docs/game-server/JOBS.md §3).
static func trainer_rebattle() -> Dictionary:
	var out := {}
	for t in _all(TRAINERS_DIR):
		if t.has("unique_name"):
			out[str(t["unique_name"])] = str(t.get("rebattle", "once"))
	return out


## Job-board entries ({value: board_id, label: "board_id  (N jobs)"}) — for the map inspector's
## job_board_id link on a `job_board` Facility.
static func job_boards() -> Array:
	return entries(JOB_BOARDS_DIR, func(b: Dictionary) -> Variant:
		if not b.has("board_id"):
			return null
		var bid := str(b["board_id"])
		return { "value": bid, "label": "%s  (%d jobs)" % [bid, (b.get("jobs", []) as Array).size()] })


## { board_id: true } over every configured board — for validating a map's job_board_id references
## without a disk scan in the hot path (the caller scans once and passes it to MapRules).
static func job_board_id_set() -> Dictionary:
	var out := {}
	for e in job_boards():
		out[str((e as Dictionary)["value"])] = true
	return out


## { shop_id: true } over every configured shop — for validating shop references without a disk scan
## in the hot path (the caller scans once and passes it to MapRules).
static func shop_id_set() -> Dictionary:
	var out := {}
	for e in shops():
		out[str((e as Dictionary)["value"])] = true
	return out


## Shop entries ({value: shop_id, label: "shop_id  (N items)"}).
static func shops() -> Array:
	return entries(SHOPS_DIR, func(s: Dictionary) -> Variant:
		if not s.has("shop_id"):
			return null
		var sid := str(s["shop_id"])
		return { "value": sid, "label": "%s  (%d items)" % [sid, (s.get("entries", []) as Array).size()] })


## Picker entries from every *.json under `dir` (recursive), each parsed dict mapped through `to_entry`
## (-> {value,label}, or null to skip), sorted by label.
static func entries(dir: String, to_entry: Callable) -> Array:
	var out: Array = []
	_collect(dir, to_entry, out)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["label"]) < str(b["label"]))
	return out


## Every parsed *.json dict under `dir` (recursive) — the raw records, before mapping to picker entries.
static func _all(dir: String) -> Array:
	var out: Array = []
	_collect(dir, func(d: Dictionary) -> Variant: return d, out)
	return out


static func _collect(dir: String, to_entry: Callable, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir + "/" + n
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect(full, to_entry, out)
		elif n.ends_with(".json"):
			var parsed: Variant = JsonIO.load_file(full)
			if typeof(parsed) == TYPE_DICTIONARY:
				var entry: Variant = to_entry.call(parsed)
				if entry != null:
					out.append(entry)
		n = d.get_next()
	d.list_dir_end()
