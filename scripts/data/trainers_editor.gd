extends DatasetEditor
## trainers/<region>/<route>/*.json — one trainer per file. All load at once and show as a filterable
## collapsible list (expand one to edit it); Save writes all. `unique_name` is editable and is kept in
## sync with the filename — editing it renames the .json file (in the same folder) on the next Save,
## via the same deferred-delete queue as removals. `initial_field` exposes pre-battle weather/terrain;
## its `field_effects` / `global_effects` (no UI yet) are round-tripped untouched.

const RANKS := ["Novice", "Amateur", "Ace", "Pro", "Master", "Champion", "Elite"]
const REBATTLE := ["once", "daily", "weekly"]
const WEATHERS := ["Clear", "Rain", "SunnyDay", "Sandstorm", "Hail", "Snow"]
const TERRAINS := ["None", "Electric", "Grassy", "Misty", "Psychic", "SoaringWinds", "WrithingMire", "HauntedArena"]
const GENDERS := ["male", "female", "genderless"]
const NATURES := ["hardy", "lonely", "brave", "adamant", "naughty", "bold", "docile", "relaxed",
	"impish", "lax", "timid", "hasty", "serious", "jolly", "naive", "modest", "mild", "quiet",
	"bashful", "rash", "calm", "gentle", "sassy", "careful", "quirky"]
const STATS := ["hp", "atk", "def", "spa", "spd", "spe"]
const _DIALOGUE_TIP := {
	"start": "Said before the battle begins.",
	"loss": "Said when the player wins (the trainer loses).",
	"post_defeat": "Said on re-interaction after defeat (optional; falls back to loss).",
}

var _trainers: Dictionary = {}     # path -> raw dict
var _paths: Array[String] = []
var _filter: LineEdit
var _list: VBoxContainer
var _expanded: Dictionary = {}     # path -> bool
var _deleted: Array[String] = []   # paths removed from / renamed away in the UI, deleted from disk on Save


func load_data() -> void:
	_paths = _find_jsons(base_dir + "/trainers")
	for p in _paths:
		_trainers[p] = JsonIO.load_file(p)
	var hint := Label.new()
	hint.text = "Battlers — one file per trainer. Expand one to set its scalars, bag and team."
	add_child(hint)
	var newb := Button.new()
	newb.text = "+ new trainer (kanto)"
	newb.tooltip_text = "Create a new trainer file under trainers/kanto."
	newb.pressed.connect(_on_new_trainer)
	add_child(newb)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter trainers by name…"
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	add_child(_filter)
	_list = VBoxContainer.new()
	add_child(_list)
	_rebuild()


## Create a fresh trainer file (unique_name == filename stem) under trainers/kanto and expand it.
func _on_new_trainer() -> void:
	var dir := base_dir + "/trainers/kanto"
	var n := 1
	while FileAccess.file_exists("%s/new_battler_%d.json" % [dir, n]):
		n += 1
	var uname := "new_battler_%d" % n
	var path := "%s/%s.json" % [dir, uname]
	_trainers[path] = {
		"unique_name": uname, "display_name": "New Trainer", "sprite": null,
		"rank": "Novice", "music_key": null, "payout_base": 0, "payout_per_level": 0,
		"badge_award": null, "items": [], "initial_field": null,
		"team": [{ "species": "", "ability": "", "nature": "hardy", "fixed_level": 5, "moves": [] }],
	}
	JsonIO.save_file(path, _trainers[path])
	_paths.append(path)
	_expanded[path] = true
	dirty.emit()
	_rebuild()


func save_data() -> bool:
	var ok := true
	for p in _deleted:
		var abs := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			ok = DirAccess.remove_absolute(abs) == OK and ok
	_deleted.clear()
	for p in _trainers:
		ok = JsonIO.save_file(p, _trainers[p]) and ok
	return ok


func current_data() -> Variant:
	return _trainers


func reveal(p: Problem) -> void:
	_filter.text = p.context
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var q := _filter.text.strip_edges().to_lower()
	for p in _paths:
		var t: Dictionary = _trainers[p]
		var base := p.get_file().get_basename()
		var title := "%s   (%s)" % [str(t.get("display_name", base)), base]
		if q != "" and not title.to_lower().contains(q):
			continue
		var expanded: bool = q != "" or _expanded.get(p, false)
		var sec := _collapsible(title, expanded, func() -> void:
			_expanded[p] = not bool(_expanded.get(p, false))
			_rebuild())
		var hrow := HBoxContainer.new()
		sec["header"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(sec["header"])
		hrow.add_child(_icon_remove_button(func() -> void: _delete_trainer(p)))
		_list.add_child(hrow)
		if expanded:
			_build_trainer(t, p, sec["body"])
			_list.add_child(sec["indent"])


## Remove a trainer from the UI and queue its file for deletion on the next Save (Reload restores it).
func _delete_trainer(path: String) -> void:
	_paths.erase(path)
	_trainers.erase(path)
	_expanded.erase(path)
	_deleted.append(path)
	dirty.emit()
	_rebuild()


## Editable unique_name field — kept in sync with the filename. Editing it moves the record to a new
## path in the same folder and queues the old file for deletion on Save; reverts an illegal name or one
## that would clobber another loaded trainer's file. Shared rename logic lives in DatasetEditor.
func _unique_name_field(t: Dictionary, path: String) -> LineEdit:
	return _stem_id_field(str(t.get("unique_name", "")),
		func(le: LineEdit) -> void: _commit_unique_name(t, path, le))


func _commit_unique_name(t: Dictionary, old_path: String, le: LineEdit) -> void:
	# A prior commit (Enter) rebuilds the list and frees this field; ignore the trailing focus-out it fires.
	if not is_instance_valid(le):
		return
	var new_name := le.text.strip_edges()
	if new_name == str(t.get("unique_name", "")):
		return
	if _rename_stem_record(old_path, new_name, "unique_name", _trainers, _paths, _expanded, _deleted) == "":
		le.text = str(t.get("unique_name", ""))  # illegal, or would clobber a file — revert
		return
	dirty.emit()
	_rebuild()


func _build_trainer(t: Dictionary, path: String, into: VBoxContainer) -> void:
	into.add_child(_row("unique_name", _unique_name_field(t, path),
		"Unique id and filename stem. Editing this renames the trainer's .json file (same folder) on the next Save."))
	into.add_child(_row("display_name", _str_field(t, "display_name"), "Name shown in the battle UI."))
	if t.has("rank"):
		into.add_child(_row("rank", _picker_field(_enum(RANKS), t, "rank", false), "Trainer rank; affects AI tier."))
	if t.has("sprite"):
		into.add_child(_row("sprite", _nullable_str_field(t, "sprite"), "Overworld/battle sprite asset name. Empty = default."))
	if t.has("music_key"):
		into.add_child(_row("music_key", _picker_nullable(Catalog.bbgm, t, "music_key"), "Battle music track (BBGM). Empty = map default."))
	if t.has("payout_base"):
		into.add_child(_row("payout_base", _int_field(t, "payout_base", 0, 0, 1000000), "Base PokéYen awarded on victory."))
	if t.has("payout_per_level"):
		into.add_child(_row("payout_per_level", _int_field(t, "payout_per_level", 0, 0, 100000), "Extra PokéYen × the trainer's highest mon level."))
	if t.has("badge_award"):
		into.add_child(_row("badge_award", _picker_int_field(Catalog.badges, t, "badge_award", true), "Gym leaders only: which badge (0–7) this awards. Empty = none."))
	into.add_child(_row("rebattle", _rebattle_field(t),
		"once: defeated permanently. daily / weekly: re-challengeable each day / week — the block lifts at the reset and the payout repeats."))
	into.add_child(_row("level scaling", _scaling_bounds_field(t),
		"Clamps the player's highest-mon level BEFORE Offset levels resolve — min is the floor (stops an all-low party from dragging a scaled trainer down to cheese its badge/payout), max the cap. min 1 / max 100 = unbounded (keys omitted). Only valid when at least one team member uses an Offset level."))

	into.add_child(_section("initial field (pre-battle)"))
	into.add_child(_row("weather", _initial_field_picker(t, "weather", WEATHERS, "Clear"),
		"Weather active (indefinitely) when the battle opens. Clear = none."))
	into.add_child(_row("terrain", _initial_field_picker(t, "terrain", TERRAINS, "None"),
		"Terrain active (indefinitely) when the battle opens. None = none."))

	into.add_child(_section("battle dialogue"))
	# Lines live in this trainer's own file under a `dialogue` block (kept absent until non-empty).
	var dlg: Dictionary = t["dialogue"] if (t.has("dialogue") and typeof(t["dialogue"]) == TYPE_DICTIONARY) else {}
	for suffix in ["start", "loss", "post_defeat"]:
		var key := str(suffix)
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 48)
		te.text = str(dlg.get(key, ""))
		te.text_changed.connect(func() -> void:
			if te.text.strip_edges() == "":
				dlg.erase(key)
			else:
				dlg[key] = te.text
			if dlg.is_empty():
				t.erase("dialogue")
			else:
				t["dialogue"] = dlg
			dirty.emit())
		into.add_child(_row(key, te, _DIALOGUE_TIP.get(suffix, "")))

	if t.has("items"):
		into.add_child(_section("bag items (AI uses mid-battle)"))
		var items: Array = t["items"]
		for i in items.size():
			var entry: Dictionary = items[i]
			var row := HBoxContainer.new()
			var ip := _item_slug_picker(entry, "item", false)
			ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ip.tooltip_text = "Item the AI may use during battle."
			row.add_child(ip)
			row.add_child(_mini("qty", _int_field(entry, "qty", 1, 1, 99)))
			row.add_child(_icon_remove_button(func() -> void:
				items.remove_at(i)
				_rebuild()
				dirty.emit()))
			into.add_child(row)
		var addi := Button.new()
		addi.text = "+ add bag item"
		addi.pressed.connect(func() -> void:
			items.append({ "item": "", "qty": 1 })
			_rebuild()
			dirty.emit())
		into.add_child(addi)

	into.add_child(_section("team (lead first, max 6)"))
	var team: Array = t.get("team", [])
	for i in team.size():
		into.add_child(_member_block(team, i))
	if team.size() < 6:
		var add := Button.new()
		add.text = "+ add pokemon"
		add.pressed.connect(func() -> void:
			team.append({ "species": "", "ability": "", "nature": "hardy", "fixed_level": 5, "moves": [] })
			_rebuild()
			dirty.emit())
		into.add_child(add)


## Scaling bounds — clamp the player's highest-mon reference level before Offset
## levels resolve (mirrors trainer_catalog.rs::parse_scaling_bounds). Defaults
## (min 1 / max 100) are erased from the file, and the server rejects bounds on
## a team with no Offset member, so plain fixed-level files must stay bound-free.
func _scaling_bounds_field(t: Dictionary) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_child(_mini("min", _optional_int_field(t, "scaling_min_level", 1, 1, 100)))
	hb.add_child(_mini("max", _optional_int_field(t, "scaling_max_level", 100, 1, 100)))
	return hb


## Rebattle cadence. Stored as `rebattle: "daily"` / `"weekly"`; "once" (the
## default, index 0) omits the key entirely so once-only files stay untouched —
## same erase-on-default pattern the dialogue block uses.
func _rebattle_field(t: Dictionary) -> OptionButton:
	var ob := OptionButton.new()
	for cadence in REBATTLE:
		ob.add_item(cadence)
	ob.selected = maxi(0, REBATTLE.find(str(t.get("rebattle", "once"))))
	ob.item_selected.connect(func(idx: int) -> void:
		if idx == 0:
			t.erase("rebattle")
		else:
			t["rebattle"] = REBATTLE[idx]
		dirty.emit())
	return ob


## Weather / terrain dropdown backed by t["initial_field"][key]. The default option (Clear / None)
## erases the key; the server treats a missing key, null, or the default as "no effect".
func _initial_field_picker(t: Dictionary, key: String, options: Array, default_value: String) -> SearchPicker:
	var sp := SearchPicker.new()
	sp.allow_none = false
	sp.set_entries(_enum(options))
	sp.set_value(_initial_field_value(t, key, options, default_value))
	sp.value_changed.connect(func(v: String) -> void: _set_initial_field_key(t, key, v, default_value))
	return sp


## Current canonical value for an initial_field key, tolerant of case drift; default when unset.
func _initial_field_value(t: Dictionary, key: String, options: Array, default_value: String) -> String:
	var raw: Variant = t.get("initial_field", null)
	if typeof(raw) != TYPE_DICTIONARY:
		return default_value
	var v: Variant = (raw as Dictionary).get(key, null)
	if v == null:
		return default_value
	var lower := str(v).strip_edges().to_lower()
	for opt in options:
		if str(opt).to_lower() == lower:
			return str(opt)
	return default_value


## Write one initial_field key; the default erases it. An all-default block collapses to null so
## plain files stay untouched, while any authored field_effects / global_effects are preserved.
func _set_initial_field_key(t: Dictionary, key: String, value: String, default_value: String) -> void:
	var raw: Variant = t.get("initial_field", null)
	var f: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	if value == default_value:
		f.erase(key)
	else:
		f[key] = value
	t["initial_field"] = null if _initial_field_is_empty(f) else f
	dirty.emit()


## True when nothing in the block would change the battle (default/absent weather + terrain, no effects).
func _initial_field_is_empty(f: Dictionary) -> bool:
	var w: Variant = f.get("weather", null)
	if w != null and str(w).to_lower() != "clear":
		return false
	var ter: Variant = f.get("terrain", null)
	if ter != null and str(ter).to_lower() != "none":
		return false
	var fe: Variant = f.get("field_effects", null)
	if typeof(fe) == TYPE_DICTIONARY:
		for k in (fe as Dictionary):
			if typeof(fe[k]) == TYPE_ARRAY and (fe[k] as Array).size() > 0:
				return false
	var ge: Variant = f.get("global_effects", null)
	if typeof(ge) == TYPE_DICTIONARY and not (ge as Dictionary).is_empty():
		return false
	return true


func _member_block(team: Array, i: int) -> VBoxContainer:
	var m: Dictionary = team[i]
	var box := VBoxContainer.new()
	var hdr := HBoxContainer.new()
	var h := Label.new()
	h.text = "#%d  %s" % [i + 1, str(m.get("species", "?"))]
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(h)
	hdr.add_child(_icon_remove_button(func() -> void:
		team.remove_at(i)
		_rebuild()
		dirty.emit()))
	box.add_child(hdr)
	# The species picker's button shows the box icon (and the dropdown lists icons too).
	var species := _species_picker(m, "species", false)
	species.value_changed.connect(func(v: String) -> void:
		h.text = "#%d  %s" % [i + 1, v])
	box.add_child(_row("species", species, "Pokémon species."))
	box.add_child(_row("ability", _picker_field(Catalog.ability_slugs, m, "ability", false), "Ability slug."))
	box.add_child(_row("nature", _picker_field(_enum(NATURES), m, "nature", false), "Nature (stat bias)."))
	box.add_child(_row("gender", _picker_nullable(_enum(GENDERS), m, "gender"), "male / female / genderless. Empty = randomized."))
	box.add_child(_row("is_shiny", _bool_field(m, "is_shiny", false), "Shiny variant."))
	box.add_child(_row("held_item", _picker_nullable(Catalog.item_slugs, m, "held_item"), "Held item slug. Empty = none."))
	box.add_child(_level_row(m))
	box.add_child(_stat_row("IV", m, "iv_", 0, 31, "Individual Values, 0–31 per stat."))
	box.add_child(_stat_row("EV", m, "ev_", 0, 252, "Effort Values, 0–252 per stat (total ≤ 510)."))
	var moves := ChipSelect.new()
	box.add_child(_row("moves", moves, "Up to 4 moves; fewer auto-fills from the learnset."))
	moves.set_entries(Catalog.move_slugs)
	moves.set_values((m.get("moves", []) as Array).duplicate())
	moves.changed.connect(func(values: Array) -> void:
		m["moves"] = values
		dirty.emit())
	box.add_child(HSeparator.new())
	return box


## Fixed level vs. offset-from-player — stores exactly one of fixed_level / level_offset.
func _level_row(m: Dictionary) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "level"
	lbl.custom_minimum_size.x = 110
	var tip := "Fixed: exact level (1–100). Offset: added to the player's highest mon level (may be negative), clamped 1–100. Exactly one is stored."
	lbl.tooltip_text = tip
	hb.add_child(lbl)
	var mode := OptionButton.new()
	mode.add_item("Fixed")   # 0
	mode.add_item("Offset")  # 1
	var is_offset := m.has("level_offset")
	mode.selected = 1 if is_offset else 0
	mode.tooltip_text = tip
	hb.add_child(mode)
	var sb := SpinBox.new()
	sb.max_value = 100
	sb.min_value = -100 if is_offset else 1
	sb.value = int(m.get("level_offset", m.get("fixed_level", 5)))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.tooltip_text = tip
	hb.add_child(sb)
	var apply := func() -> void:
		var off := mode.selected == 1
		sb.min_value = -100 if off else 1
		m.erase("fixed_level")
		m.erase("level_offset")
		m["level_offset" if off else "fixed_level"] = int(sb.value)
		dirty.emit()
	mode.item_selected.connect(func(_i: int) -> void: apply.call())
	sb.value_changed.connect(func(_v: float) -> void: apply.call())
	return hb


func _stat_row(label_text: String, m: Dictionary, prefix: String, minv: int, maxv: int, tooltip: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 30
	l.tooltip_text = tooltip
	hb.add_child(l)
	for s in STATS:
		hb.add_child(_mini(s, _int_field(m, prefix + s, 0, minv, maxv)))
	return hb
