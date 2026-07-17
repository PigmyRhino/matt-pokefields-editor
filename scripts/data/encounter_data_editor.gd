extends DatasetEditor
## encounter_data.json — { "entries": [ { encounter (group id), pokemon (species slug), min_level,
## max_level, slots (relative weight), held_item_groups (loot name | ""), morning/day/night_allowed } ] }
##
## Organised by AREA → encounter GROUP → a dense per-Pokémon table. The area is derived from the group
## id (`johto_route29_patch1` → `johto_route29`); 2-token ids like `lilypad_water` fall under "(shared)".
## Areas collapse so the whole region is browsable at a glance; expanding one shows its groups, each a
## card listing every Pokémon with icon, level range, weight + auto % share, and time-of-day toggles.
## A group is added by choosing an area (existing or new) + a group name, composed as `area_group`, so
## it lands in the chosen area rather than "(shared)". An area header's ✕ deletes that whole area; a
## group header's ✕ deletes just that group.
##
## `weather_spawn_rates` was removed everywhere (spawn selection never read it) — any legacy key is
## stripped on load so a save cleans the file.

var _raw: Dictionary = {}
var _entries: Array = []
var _loot: Array = []
var _path := ""

var _filter: LineEdit
var _new_area: LineEdit    # add-group: area prefix (existing or freshly typed)
var _new_group: LineEdit   # add-group: the group name appended to the area → `area_group`
var _stats: Label
var _tree_box: VBoxContainer
var _expanded: Dictionary = {}  # area key -> bool (persisted across rebuilds)


func load_data() -> void:
	_path = base_dir + "/encounter_data.json"
	var loaded: Variant = JsonIO.load_file(_path)
	_raw = loaded if typeof(loaded) == TYPE_DICTIONARY else { "entries": [] }
	if not _raw.has("entries"):
		_raw["entries"] = []
	_entries = _raw["entries"]
	for e in _entries:  # migration: drop the dead weather block so saving rewrites it clean
		(e as Dictionary).erase("weather_spawn_rates")
	_loot = _loot_entries()

	var hint := Label.new()
	hint.text = "Wild encounters by area. `wt` is the relative spawn weight; the % is its share of the group."
	add_child(hint)

	var bar := HBoxContainer.new()
	_new_area = LineEdit.new()
	_new_area.placeholder_text = "area, e.g. johto_route31"
	_new_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_area.tooltip_text = "Area the new group belongs to (pick an existing one with ▾, or type a new one)."
	_new_area.text_submitted.connect(func(_t: String) -> void: _on_add_group())
	bar.add_child(_new_area)
	var area_pick := MenuButton.new()
	area_pick.text = "▾"
	area_pick.tooltip_text = "Fill the area field from an existing area."
	var pm := area_pick.get_popup()
	pm.about_to_popup.connect(func() -> void:
		pm.clear()
		for a in _existing_areas():
			pm.add_item(a))
	pm.index_pressed.connect(func(index: int) -> void: _new_area.text = pm.get_item_text(index))
	bar.add_child(area_pick)
	var us := Label.new()
	us.text = "_"
	bar.add_child(us)
	_new_group = LineEdit.new()
	_new_group.placeholder_text = "group, e.g. patch9"
	_new_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_group.tooltip_text = "Group name appended to the area; the full id becomes `area_group`."
	_new_group.text_submitted.connect(func(_t: String) -> void: _on_add_group())
	bar.add_child(_new_group)
	var addg := Button.new()
	addg.text = "+ add group"
	addg.tooltip_text = "Create a new encounter group (area_group) with an empty first Pokémon to fill in."
	addg.pressed.connect(_on_add_group)
	bar.add_child(addg)
	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.custom_minimum_size.x = 150
	bar.add_child(_stats)
	add_child(bar)

	_filter = LineEdit.new()
	_filter.placeholder_text = "filter by area, group or pokémon…"
	_filter.text_changed.connect(func(_t: String) -> void: _rebuild())
	add_child(_filter)

	_tree_box = VBoxContainer.new()
	add_child(_tree_box)
	_rebuild()


func save_data() -> bool:
	return JsonIO.save_file(_path, _raw)


func current_data() -> Variant:
	return _entries


func reveal(p: Problem) -> void:
	_filter.text = p.context
	_rebuild()


# -- structure --

## group id -> Array[int] of its indices into _entries (first-seen order preserved).
func _group_index() -> Dictionary:
	var idx: Dictionary = {}
	for i in _entries.size():
		var g := str((_entries[i] as Dictionary).get("encounter", ""))
		if not idx.has(g):
			idx[g] = []
		idx[g].append(i)
	return idx


## Area key for a group id: first two underscore-tokens, or "(shared)" for short/anchorless ids.
func _area_of(group: String) -> String:
	var toks := group.split("_", false)
	return "%s_%s" % [toks[0], toks[1]] if toks.size() >= 3 else "(shared)"


func _group_matches(group: String, indices: Array, area: String, q: String) -> bool:
	if q == "":
		return true
	if group.to_lower().contains(q) or area.to_lower().contains(q):
		return true
	for idx in indices:
		if str((_entries[idx] as Dictionary).get("pokemon", "")).to_lower().contains(q):
			return true
	return false


# -- rendering --

func _rebuild() -> void:
	for c in _tree_box.get_children():
		c.queue_free()
	var groups := _group_index()
	var areas: Dictionary = {}  # area -> Array[String] groups (first-seen order)
	for g in groups:
		var a := _area_of(g)
		if not areas.has(a):
			areas[a] = []
		areas[a].append(g)
	var area_keys := areas.keys()
	area_keys.sort()
	var q := _filter.text.strip_edges().to_lower()

	for a in area_keys:
		var vis: Array = []
		for g in areas[a]:
			if _group_matches(g, groups[g], a, q):
				vis.append(g)
		if vis.is_empty():
			continue
		var expanded := q != "" or bool(_expanded.get(a, false))
		var hrow := HBoxContainer.new()
		var head := _area_header(a, vis.size(), expanded)
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(head)
		if a != "(shared)":  # "(shared)" is a catch-all, not a real area — delete its groups individually
			var dela := _icon_remove_button(_delete_area.bind(a))
			dela.tooltip_text = "Delete this whole area — every group and Pokémon under it."
			hrow.add_child(dela)
		_tree_box.add_child(hrow)
		if expanded:
			var body := VBoxContainer.new()
			for g in vis:
				body.add_child(_group_card(g, groups[g]))
			var indent := MarginContainer.new()
			indent.add_theme_constant_override("margin_left", 16)
			indent.add_child(body)
			_tree_box.add_child(indent)

	_stats.text = "%d groups · %d entries" % [groups.size(), _entries.size()]


func _area_header(area: String, count: int, expanded: bool) -> Button:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s  %s   (%d %s)" % ["▾" if expanded else "▸", area, count, "group" if count == 1 else "groups"]
	b.pressed.connect(func() -> void:
		_expanded[area] = not bool(_expanded.get(area, false))
		_rebuild())
	return b


func _group_card(group: String, indices: Array) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)

	var hdr := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = group
	name_edit.custom_minimum_size.x = 240
	name_edit.tooltip_text = "Encounter group id. Editing renames the group (updates every Pokémon in it)."
	var commit_rename := func() -> void:
		var nn := name_edit.text.strip_edges()
		if nn != "" and nn != group:
			for idx in indices:
				(_entries[idx] as Dictionary)["encounter"] = nn
			dirty.emit()
			_rebuild()
	name_edit.text_submitted.connect(func(_t: String) -> void: commit_rename.call())
	name_edit.focus_exited.connect(commit_rename)
	hdr.add_child(name_edit)
	var sigma := Label.new()
	sigma.custom_minimum_size.x = 80
	sigma.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(sigma)
	var delg := _icon_remove_button(func() -> void:
		var desc := (indices as Array).duplicate()
		desc.sort()
		desc.reverse()
		for idx in desc:
			_entries.remove_at(idx)
		dirty.emit()
		_rebuild())
	delg.tooltip_text = "Delete this whole encounter group."
	hdr.add_child(delg)
	card.add_child(hdr)

	var pct_labels: Array = []
	# Spawn chance is rolled per time-of-day, so each phase has its own pool: only entries enabled for
	# that phase compete. We show each entry's share within every phase it's active in.
	var recompute := func() -> void:
		var totals := { "morning": 0, "day": 0, "night": 0 }
		for idx in indices:
			var e := _entries[idx] as Dictionary
			var w := int(e.get("slots", 0))
			for ph in totals:
				if bool(e.get(ph + "_allowed", true)):
					totals[ph] += w
		sigma.text = "Σ wt %d" % (totals["morning"] + totals["day"] + totals["night"])
		for pl in pct_labels:
			var e := _entries[pl["idx"]] as Dictionary
			var w := int(e.get("slots", 0))
			var parts: Array = []
			for ph in [["morning", "M"], ["day", "D"], ["night", "N"]]:
				if bool(e.get(ph[0] + "_allowed", true)) and totals[ph[0]] > 0:
					parts.append("%s %d%%" % [ph[1], roundi(100.0 * w / totals[ph[0]])])
			pl["label"].text = "   ".join(parts) if not parts.is_empty() else "—"
	for idx in indices:
		card.add_child(_entry_row(idx, pct_labels, recompute))
	recompute.call()

	var addp := Button.new()
	addp.text = "+ add pokémon"
	addp.pressed.connect(func() -> void:
		_entries.append(_new_entry(group))
		dirty.emit()
		_rebuild())
	card.add_child(addp)
	card.add_child(HSeparator.new())
	return card


func _entry_row(idx: int, pct_labels: Array, recompute: Callable) -> HBoxContainer:
	var e: Dictionary = _entries[idx]
	var row := HBoxContainer.new()

	# The species picker's button shows the box icon (and the dropdown lists icons too).
	var sp := _species_picker(e, "pokemon", false)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)

	row.add_child(_mini("L", _lvl_spin(e, "min_level")))
	var dash := Label.new()
	dash.text = "–"
	row.add_child(dash)
	row.add_child(_lvl_spin(e, "max_level"))

	var wt := _int_field(e, "slots", 0, 0, 1000)
	wt.custom_minimum_size.x = 72
	wt.tooltip_text = "Relative spawn weight within this group."
	wt.value_changed.connect(func(_v: float) -> void: recompute.call())
	row.add_child(_mini("wt", wt))

	var pct := Label.new()
	pct.custom_minimum_size.x = 132
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.tooltip_text = "Spawn share within each time-of-day pool the entry belongs to."
	pct_labels.append({ "label": pct, "idx": idx })
	row.add_child(pct)

	row.add_child(_tod_check(e, "morning_allowed", "M", "Appears in the morning.", recompute))
	row.add_child(_tod_check(e, "day_allowed", "D", "Appears during the day (and dusk).", recompute))
	row.add_child(_tod_check(e, "night_allowed", "N", "Appears at night.", recompute))

	var held := _picker_field(_loot, e, "held_item_groups", true)
	held.custom_minimum_size.x = 110
	held.tooltip_text = "Loot table for a wild held item; empty = none."
	row.add_child(held)

	row.add_child(_icon_remove_button(func() -> void:
		_entries.remove_at(idx)
		dirty.emit()
		_rebuild()))
	return row


func _lvl_spin(e: Dictionary, key: String) -> SpinBox:
	var sb := _int_field(e, key, 1, 1, 100)
	sb.custom_minimum_size.x = 64
	return sb


func _tod_check(e: Dictionary, key: String, text: String, tip: String, recompute: Callable) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(e.get(key, true))
	cb.tooltip_text = tip
	cb.toggled.connect(func(p: bool) -> void:
		e[key] = p
		recompute.call()  # toggling a phase changes that pool, so refresh the shares
		dirty.emit())
	return cb


func _new_entry(group: String) -> Dictionary:
	return {
		"encounter": group, "pokemon": "", "min_level": 1, "max_level": 1, "slots": 10,
		"held_item_groups": "", "morning_allowed": true, "day_allowed": true, "night_allowed": true,
	}


## Compose the new group id from the area + group fields (`area_group`), so it derives back to the
## chosen area instead of falling into "(shared)". A bare group name (no area) is still allowed.
func _on_add_group() -> void:
	var area := _new_area.text.strip_edges()
	var grp := _new_group.text.strip_edges()
	var gid := (area + "_" + grp) if area != "" else grp
	if gid == "":
		return
	_entries.append(_new_entry(gid))
	_expanded[_area_of(gid)] = true
	_new_group.text = ""  # keep the area so several groups can be added to it in a row
	dirty.emit()
	_rebuild()


## Distinct real areas currently present (derived from the group ids), sorted; excludes the "(shared)"
## catch-all. Backs the add-group area picker.
func _existing_areas() -> Array:
	var seen := {}
	for e in _entries:
		var a := _area_of(str((e as Dictionary).get("encounter", "")))
		if a != "(shared)":
			seen[a] = true
	var out := seen.keys()
	out.sort()
	return out


## Delete an entire area: drop every entry whose group resolves to it. Recoverable by reloading the
## dataset (re-select Encounters) before Save, like the per-group delete.
func _delete_area(area: String) -> void:
	var idxs: Array = []
	for i in _entries.size():
		if _area_of(str((_entries[i] as Dictionary).get("encounter", ""))) == area:
			idxs.append(i)
	idxs.sort()
	idxs.reverse()
	for i in idxs:
		_entries.remove_at(i)
	_expanded.erase(area)
	dirty.emit()
	_rebuild()


func _loot_entries() -> Array:
	var lt: Variant = JsonIO.load_file(base_dir + "/loot_tables.json")
	var out: Array = []
	if typeof(lt) == TYPE_DICTIONARY and lt.has("tables"):
		for name in lt["tables"]:
			out.append({ "value": name, "label": name })
	return out
