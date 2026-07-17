extends DatasetEditor
## job_boards/<region>/*.json — one town board per file, mirroring shops/trainers. A board carries
## daily_slots / weekly_slots and a `jobs` array; each job is an objective (one of six kinds) plus 1–4
## rewards and a daily/weekly cadence. `board_id` is editable and kept in sync with the filename (editing
## it renames the .json, same folder, on the next Save via the shared stem-rename). Jobs live INSIDE the
## board that offers them — job_id is globally unique and turn-in happens at the owning board, so there
## is no separate job pool: a board's `jobs` array IS its offer set. To make a board reachable in-game,
## place a Facility on the map (script `job_board`) whose job_board_id property equals this board_id.
## Server contract: crates/pkmn-core/src/data/job_catalog.rs. Design: docs/game-server/JOBS.md.

const CADENCES := ["daily", "weekly"]
const MAX_REWARDS := 4

## Objective kinds in the order the server enumerates them (jobs.rs::JobObjective); `label` is UI text.
const OBJECTIVE_KINDS := [
	{ "value": "defeat_species", "label": "Defeat species" },
	{ "value": "catch_pokemon", "label": "Catch Pokémon" },
	{ "value": "gather_item", "label": "Gather item" },
	{ "value": "win_battles", "label": "Win battles" },
	{ "value": "defeat_trainer", "label": "Defeat trainer" },
	{ "value": "earn_skill_xp", "label": "Earn skill XP" },
]
const REWARD_KINDS := [
	{ "value": "pokeyen", "label": "PokéYen" },
	{ "value": "item", "label": "Item" },
	{ "value": "skill_xp", "label": "Skill XP" },
]
## Every payload key any objective / reward variant may carry — cleared on a kind switch so a record
## only ever holds its active kind's fields (job_catalog.rs parses with deny_unknown_fields).
const OBJECTIVE_KEYS := ["species", "item", "trainer", "skill", "count", "amount", "shiny", "trainer_only"]
const REWARD_KEYS := ["item", "skill", "amount", "qty"]

var _boards: Dictionary = {}      # path -> raw dict
var _paths: Array[String] = []
var _filter: LineEdit
var _list: VBoxContainer
var _expanded: Dictionary = {}    # path (board) / "path#i" (job card) -> bool
var _deleted: Array[String] = []  # paths removed / renamed away in the UI, deleted from disk on Save


func load_data() -> void:
	_paths = _find_jsons(base_dir + "/job_boards")
	for p in _paths:
		_boards[p] = JsonIO.load_file(p)
	var hint := Label.new()
	hint.text = "Town job boards — one file per board; its jobs ARE its offer pool. Place a board on a map as a Facility with script job_board."
	add_child(hint)
	var newb := Button.new()
	newb.text = "+ new board (kanto)"
	newb.tooltip_text = "Create a new board file under job_boards/kanto."
	newb.pressed.connect(_on_new_board)
	add_child(newb)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter boards by id…"
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	add_child(_filter)
	_list = VBoxContainer.new()
	add_child(_list)
	_rebuild()


func save_data() -> bool:
	var ok := true
	for p in _deleted:
		var abs := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			ok = DirAccess.remove_absolute(abs) == OK and ok
	_deleted.clear()
	for p in _boards:
		ok = JsonIO.save_file(p, _boards[p]) and ok
	return ok


func current_data() -> Variant:
	return _boards


func reveal(p: Problem) -> void:
	_filter.text = p.context
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var q := _filter.text.strip_edges().to_lower()
	for p in _paths:
		var board: Dictionary = _boards[p]
		var stem := p.get_file().get_basename()
		var title := "%s   (%d jobs)" % [stem, (board.get("jobs", []) as Array).size()]
		if q != "" and not title.to_lower().contains(q):
			continue
		var expanded: bool = q != "" or _expanded.get(p, false)
		var sec := _collapsible(title, expanded, func() -> void:
			_expanded[p] = not bool(_expanded.get(p, false))
			_rebuild())
		var hrow := HBoxContainer.new()
		sec["header"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(sec["header"])
		hrow.add_child(_icon_remove_button(func() -> void: _delete_board(p)))
		_list.add_child(hrow)
		if expanded:
			_build_board(board, p, sec["body"])
			_list.add_child(sec["indent"])


## Remove a board from the UI and queue its file for deletion on the next Save (Reload restores it).
func _delete_board(path: String) -> void:
	_paths.erase(path)
	_boards.erase(path)
	_expanded.erase(path)
	_deleted.append(path)
	dirty.emit()
	_rebuild()


func _build_board(board: Dictionary, path: String, into: VBoxContainer) -> void:
	into.add_child(_row("board_id", _board_id_field(board, path),
		"Unique id and filename stem. Editing it renames the board's .json (same folder) on the next Save. Must equal the job_board_id property of the map Facility that opens it."))
	into.add_child(_row("name", _str_field(board, "name"),
		"Player-facing town name, shown as the turn-in location (\"Turn in at Viridian City\") in the quest log and HUD tracker. ≤ 48 bytes."))
	into.add_child(_row("daily_slots", _int_field(board, "daily_slots", 0, 0, 99),
		"How many daily jobs show per day. Zero with no daily jobs, otherwise 1..(daily job count)."))
	into.add_child(_row("weekly_slots", _int_field(board, "weekly_slots", 0, 0, 99),
		"How many weekly jobs show per week. Zero with no weekly jobs, otherwise 1..(weekly job count)."))

	into.add_child(_section("jobs (authored order = rotation pool order)"))
	if not board.has("jobs"):
		board["jobs"] = []
	var jobs: Array = board["jobs"]
	for i in jobs.size():
		if typeof(jobs[i]) == TYPE_DICTIONARY:
			_build_job_card(jobs, i, path, into)
	var add := Button.new()
	add.text = "+ add job"
	add.pressed.connect(func() -> void:
		jobs.append(_new_job("daily"))
		_rebuild()
		dirty.emit())
	into.add_child(add)


## One job as its own collapsible card (nested under the board), so a long pool stays scannable.
func _build_job_card(jobs: Array, i: int, path: String, into: VBoxContainer) -> void:
	var job: Dictionary = jobs[i]
	var key := "%s#%d" % [path, i]
	var title := "%s   [%s]" % [str(job.get("job_id", "?")), str(job.get("cadence", "daily"))]
	var expanded: bool = _expanded.get(key, false)
	var sec := _collapsible(title, expanded, func() -> void:
		_expanded[key] = not bool(_expanded.get(key, false))
		_rebuild())
	var hrow := HBoxContainer.new()
	sec["header"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(sec["header"])
	hrow.add_child(_icon_remove_button(func() -> void:
		jobs.remove_at(i)
		_rebuild()
		dirty.emit()))
	into.add_child(hrow)
	if expanded:
		_build_job(job, sec["body"])
		into.add_child(sec["indent"])


func _build_job(job: Dictionary, into: VBoxContainer) -> void:
	into.add_child(_row("job_id", _str_field(job, "job_id"),
		"Globally-unique id across ALL boards (the player save and wire packets carry it alone). ≤ 64 bytes."))
	into.add_child(_row("title", _str_field(job, "title"), "Shown on the board and quest log. ≤ 80 bytes."))
	into.add_child(_row("description", _str_field(job, "description"), "Flavor + hint shown in the job detail. ≤ 200 bytes."))
	into.add_child(_row("cadence", _cadence_field(job), "daily rerolls/expires each day; weekly each week."))

	into.add_child(_section("objective"))
	if typeof(job.get("objective")) != TYPE_DICTIONARY:
		job["objective"] = { "kind": "defeat_species" }
	into.add_child(_variant_form(job["objective"], OBJECTIVE_KINDS, OBJECTIVE_KEYS, _build_objective_fields))

	into.add_child(_section("rewards (1–4)"))
	_build_rewards(job, into)


# -- rewards (repeatable, 1..4) --

func _build_rewards(job: Dictionary, into: VBoxContainer) -> void:
	if typeof(job.get("rewards")) != TYPE_ARRAY:
		job["rewards"] = []
	var rewards: Array = job["rewards"]
	for i in rewards.size():
		if typeof(rewards[i]) != TYPE_DICTIONARY:
			continue
		var hdr := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "reward %d" % (i + 1)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(lbl)
		hdr.add_child(_icon_remove_button(func() -> void:
			rewards.remove_at(i)
			_rebuild()
			dirty.emit()))
		into.add_child(hdr)
		into.add_child(_variant_form(rewards[i], REWARD_KINDS, REWARD_KEYS, _build_reward_fields))
	if rewards.size() < MAX_REWARDS:
		var add := Button.new()
		add.text = "+ add reward"
		add.pressed.connect(func() -> void:
			rewards.append({ "kind": "pokeyen", "amount": 1000 })
			_rebuild()
			dirty.emit())
		into.add_child(add)


# -- tagged-union sub-editor (shared by objective + each reward) --

## A `kind` dropdown over `kinds` ([{value,label}]), with the active kind's fields — built by
## `build_fields.call(kind, dict, box)` — shown beneath it. Switching kind clears every payload key in
## `all_keys` and rebuilds, so the record only ever carries its active variant's fields (the server
## parses with deny_unknown_fields). A field edit persists directly through the DatasetEditor helpers;
## only the kind switch restructures the form, so it goes through the full _rebuild like everything else.
func _variant_form(dict: Dictionary, kinds: Array, all_keys: Array, build_fields: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	var ob := OptionButton.new()
	var values: Array = []
	for k in kinds:
		ob.add_item(str(k["label"]))
		values.append(str(k["value"]))
	var cur := str(dict.get("kind", values[0]))
	ob.selected = maxi(0, values.find(cur))
	ob.item_selected.connect(func(idx: int) -> void:
		for k in all_keys:
			dict.erase(k)
		dict["kind"] = values[idx]
		dirty.emit()
		_rebuild())
	box.add_child(_row("kind", ob))
	build_fields.call(cur, dict, box)
	return box


func _build_objective_fields(kind: String, o: Dictionary, box: VBoxContainer) -> void:
	match kind:
		"defeat_species":
			box.add_child(_row("species", _species_picker(o, "species", false), "Species whose faints count."))
			box.add_child(_count_row(o))
		"catch_pokemon":
			box.add_child(_row("species", _opt_species_picker(o, "species"), "Species to catch. Empty = ANY species."))
			box.add_child(_row("shiny", _bool_field(o, "shiny", false), "Require the catch to be shiny."))
			box.add_child(_count_row(o))
		"gather_item":
			box.add_child(_row("item", _item_slug_picker(o, "item", false), "Item gathered from the world (forage / mine / gift scripts)."))
			box.add_child(_count_row(o))
		"win_battles":
			box.add_child(_row("trainer_only", _bool_field(o, "trainer_only", false), "Only trainer battles count (not wild)."))
			box.add_child(_count_row(o))
		"defeat_trainer":
			box.add_child(_row("trainer", _picker_field(ContentScan.trainers(), o, "trainer", false),
				"Trainer to defeat (unique_name). Use a daily/weekly-rebattle trainer, else the job is uncompletable once it's beaten."))
		"earn_skill_xp":
			box.add_child(_row("skill", _picker_field(Catalog.skills, o, "skill", false), "Skill to earn XP in."))
			box.add_child(_amount_row(o, "Total XP to earn."))


func _build_reward_fields(kind: String, r: Dictionary, box: VBoxContainer) -> void:
	match kind:
		"pokeyen":
			box.add_child(_amount_row(r, "PokéYen granted."))
		"item":
			box.add_child(_row("item", _item_slug_picker(r, "item", false), "Item granted."))
			box.add_child(_qty_row(r))
		"skill_xp":
			box.add_child(_row("skill", _picker_field(Catalog.skills, r, "skill", false), "Skill to grant XP in."))
			box.add_child(_amount_row(r, "Skill XP granted."))


# -- field helpers (seed the min so a freshly-shown numeric field is immediately valid) --

func _count_row(d: Dictionary) -> HBoxContainer:
	if not d.has("count"):
		d["count"] = 1
	return _row("count", _int_field(d, "count", 1, 1, 1000000), "How many (≥ 1) to complete the objective.")


func _amount_row(d: Dictionary, tip: String) -> HBoxContainer:
	if not d.has("amount"):
		d["amount"] = 1
	return _row("amount", _int_field(d, "amount", 1, 1, 100000000), tip)


func _qty_row(d: Dictionary) -> HBoxContainer:
	if not d.has("qty"):
		d["qty"] = 1
	return _row("qty", _int_field(d, "qty", 1, 1, 65535), "How many of the item to grant (≥ 1).")


func _cadence_field(job: Dictionary) -> OptionButton:
	var ob := OptionButton.new()
	for c in CADENCES:
		ob.add_item(c)
	ob.selected = maxi(0, CADENCES.find(str(job.get("cadence", "daily"))))
	ob.item_selected.connect(func(idx: int) -> void:
		job["cadence"] = CADENCES[idx]
		dirty.emit()
		_rebuild())   # the job card header shows the cadence
	return ob


## Species picker for an OPTIONAL species (catch_pokemon): "(none)" omits the key → "any species"
## (the server reads species as Option). Keeps the box-icon art of the required _species_picker.
func _opt_species_picker(dict: Dictionary, key: String) -> SearchPicker:
	var sp := SearchPicker.new()
	sp.allow_none = true
	sp.icon_provider = func(slug: String) -> Texture2D:
		return GameData.get_pokemon_icon(GameData.species_id_for_slug(slug))
	sp.set_entries(Catalog.species_slugs)
	sp.set_value(str(dict.get(key, "")))
	sp.value_changed.connect(func(v: String) -> void:
		if v == "":
			dict.erase(key)
		else:
			dict[key] = v
		dirty.emit())
	return sp


# -- board id (filename stem) + new board --

func _board_id_field(board: Dictionary, path: String) -> LineEdit:
	return _stem_id_field(str(board.get("board_id", "")),
		func(le: LineEdit) -> void: _commit_board_id(board, path, le))


func _commit_board_id(board: Dictionary, old_path: String, le: LineEdit) -> void:
	# A prior commit (Enter) rebuilds the list and frees this field; ignore the trailing focus-out it fires.
	if not is_instance_valid(le):
		return
	var new_name := le.text.strip_edges()
	if new_name == str(board.get("board_id", "")):
		return
	if _rename_stem_record(old_path, new_name, "board_id", _boards, _paths, _expanded, _deleted) == "":
		le.text = str(board.get("board_id", ""))  # illegal, or would clobber a file — revert
		return
	dirty.emit()
	_rebuild()


func _on_new_board() -> void:
	var dir := base_dir + "/job_boards/kanto"
	var n := 1
	while FileAccess.file_exists("%s/new_board_%d.json" % [dir, n]):
		n += 1
	var bid := "new_board_%d" % n
	var path := "%s/%s.json" % [dir, bid]
	_boards[path] = {
		"board_id": bid, "daily_slots": 1, "weekly_slots": 0,
		"jobs": [_new_job("daily")],
	}
	JsonIO.save_file(path, _boards[path])
	_paths.append(path)
	_expanded[path] = true
	dirty.emit()
	_rebuild()


func _new_job(cadence: String) -> Dictionary:
	return {
		"job_id": "", "title": "New Job", "description": "",
		"cadence": cadence,
		"objective": { "kind": "defeat_species", "species": "", "count": 1 },
		"rewards": [{ "kind": "pokeyen", "amount": 1000 }],
	}
