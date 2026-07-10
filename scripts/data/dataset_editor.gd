class_name DatasetEditor
extends VBoxContainer
## Base for content dataset editors. A subclass builds its UI in load_data() by mutating the parsed
## JSON structure IN PLACE (so _comment / unmodeled keys survive) and persists in save_data().
## The field helpers create label+control rows bound to dict[key] that emit `dirty` on every change.

signal dirty

var base_dir := "res://content"


func load_data() -> void:
	pass


## Returns true on success.
func save_data() -> bool:
	return false


## The in-memory parsed root in the exact shape its DataValidator entry expects (so live, unsaved edits
## are validated). Default null → the shell validates the on-disk copy instead. See DataValidator.
func current_data() -> Variant:
	return null


## Reveal the record a Problem points at (typically by setting this editor's filter). Default no-op.
func reveal(_problem: Problem) -> void:
	pass


# -- bound field helpers (mutate dict[key] in place, emit dirty) --

func _row(label_text: String, control: Control, tooltip := "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 110
	if tooltip != "":
		lbl.tooltip_text = tooltip
		control.tooltip_text = tooltip
		hb.tooltip_text = tooltip
	hb.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	return hb


func _int_field(dict: Dictionary, key: String, default: int, minv: int, maxv: int) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = int(dict.get(key, default))
	sb.value_changed.connect(func(v: float) -> void:
		dict[key] = int(v)
		dirty.emit())
	return sb


## Like _int_field, but the default value means "unset" — it erases the key so files only
## carry authored values (the erase-on-default pattern rebattle/dialogue use).
func _optional_int_field(dict: Dictionary, key: String, default: int, minv: int, maxv: int) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = int(dict.get(key, default))
	sb.value_changed.connect(func(v: float) -> void:
		if int(v) == default:
			dict.erase(key)
		else:
			dict[key] = int(v)
		dirty.emit())
	return sb


func _str_field(dict: Dictionary, key: String) -> LineEdit:
	var le := LineEdit.new()
	le.text = str(dict.get(key, ""))
	le.text_changed.connect(func(t: String) -> void:
		dict[key] = t
		dirty.emit())
	return le


## LineEdit whose empty text means JSON null (e.g. trainer sprite/music_key are string-or-null).
func _nullable_str_field(dict: Dictionary, key: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = "(none)"
	var cur: Variant = dict.get(key, null)
	le.text = "" if cur == null else str(cur)
	le.text_changed.connect(func(t: String) -> void:
		dict[key] = null if t == "" else t
		dirty.emit())
	return le


func _bool_field(dict: Dictionary, key: String, default: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.button_pressed = bool(dict.get(key, default))
	cb.toggled.connect(func(p: bool) -> void:
		dict[key] = p
		dirty.emit())
	return cb


## String-valued picker (e.g. skill, loot name). `icon_dir` shows "{icon_dir}/{value}.png" art;
## `icon_provider` (value -> Texture2D) takes precedence for art that isn't a plain file (ROM sprites).
func _picker_field(entries: Array, dict: Dictionary, key: String, allow_none := true, icon_dir := "", icon_provider := Callable()) -> SearchPicker:
	var sp := SearchPicker.new()
	sp.allow_none = allow_none
	sp.icon_dir = icon_dir
	if icon_provider.is_valid():
		sp.icon_provider = icon_provider
	sp.set_entries(entries)
	sp.set_value(str(dict.get(key, "")))
	sp.value_changed.connect(func(v: String) -> void:
		dict[key] = v
		dirty.emit())
	return sp


## Species picker bound to dict[key] (slug) with Pokémon box-icon art (when the B/W ROM is loaded).
func _species_picker(dict: Dictionary, key: String, allow_none := false) -> SearchPicker:
	return _picker_field(Catalog.species_slugs, dict, key, allow_none, "",
		func(slug: String) -> Texture2D: return GameData.get_pokemon_icon(GameData.species_id_for_slug(slug)))


## Item picker bound to dict[key] (slug) with item-icon art (bundled PNG for custom ids; ROM icon for
## poké-items when the B/W ROM is loaded). TM/HM labels are annotated with the move they teach.
func _item_slug_picker(dict: Dictionary, key: String, allow_none := false) -> SearchPicker:
	return _picker_field(_item_slugs_labeled(), dict, key, allow_none, "",
		func(slug: String) -> Texture2D: return GameData.get_item_icon(_item_id_for_slug(slug)))


## Int-valued picker that round-trips null (e.g. tool = null for bare-hand, or item_id).
func _picker_int_field(entries: Array, dict: Dictionary, key: String, allow_none := true, icon_dir := "", icon_provider := Callable()) -> SearchPicker:
	var sp := SearchPicker.new()
	sp.allow_none = allow_none
	sp.icon_dir = icon_dir
	if icon_provider.is_valid():
		sp.icon_provider = icon_provider
	sp.set_entries(entries)
	var cur: Variant = dict.get(key, null)
	sp.set_value("" if cur == null else str(int(cur)))
	sp.value_changed.connect(func(v: String) -> void:
		dict[key] = null if v == "" else int(v)
		dirty.emit())
	return sp


## Item picker bound to dict[key] (numeric item_id) over the full item catalog, with item-icon art
## (bundled PNG / ROM icon). TM/HM labels are annotated with the move they teach. allow_none
## round-trips null (e.g. bare-hand tool).
func _item_id_picker(dict: Dictionary, key: String, allow_none := false) -> SearchPicker:
	return _picker_int_field(_items_labeled(), dict, key, allow_none, "",
		func(v: String) -> Texture2D: return GameData.get_item_icon(int(v)))


## String picker that round-trips null (e.g. trainer held_item / gender = null).
func _picker_nullable(entries: Array, dict: Dictionary, key: String) -> SearchPicker:
	var sp := SearchPicker.new()
	sp.allow_none = true
	sp.set_entries(entries)
	var cur: Variant = dict.get(key, null)
	sp.set_value("" if cur == null else str(cur))
	sp.value_changed.connect(func(v: String) -> void:
		dict[key] = null if v == "" else v
		dirty.emit())
	return sp


## Item icon for a custom id, or null. Delegates to GameData so it matches the game exactly:
## a ROM icon when the item carries a rom_item_id (e.g. Mushroom → Big Mushroom), else the
## bundled res://assets/sprites/items/{id}.png. GameData caches, so no local cache is needed.
func _item_icon(item_id: int) -> Texture2D:
	return GameData.get_item_icon(item_id)


func _icon_remove_button(on_press: Callable) -> Button:
	var b := Button.new()
	b.text = "✕"
	b.pressed.connect(on_press)
	return b


## A collapsible section header (encounter-style ▸/▾) plus an indented body container. The caller adds
## `header` always, fills + adds `indent` only when expanded, and flips its own state in `on_toggle`.
## Returns { header: Button, body: VBoxContainer, indent: MarginContainer }.
func _collapsible(title: String, expanded: bool, on_toggle: Callable) -> Dictionary:
	var header := Button.new()
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.text = "%s  %s" % ["▾" if expanded else "▸", title]
	header.pressed.connect(on_toggle)
	var body := VBoxContainer.new()
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 16)
	indent.add_child(body)
	return { "header": header, "body": body, "indent": indent }


## A section divider label (e.g. "— team —").
func _section(title: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % title
	return l


## Wrap a plain string list as picker entries ([{value,label}]).
func _enum(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append({ "value": v, "label": v })
	return out


## All *.json paths under `dir` (recursive), sorted. For multi-file datasets (shops, trainers).
func _find_jsons(dir: String) -> Array[String]:
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


# -- multi-file dataset: filename-stem id rename (trainers unique_name, shops shop_id) --

## Cached matcher for a safe filename stem (one segment: letters, digits, _ and -). Compiled once.
static var _stem_re: RegEx


## A stem must map 1:1 to "<stem>.json": letters, digits, _ and - only (no separators, dots, spaces).
func _is_valid_stem(s: String) -> bool:
	if _stem_re == null:
		_stem_re = RegEx.new()
		_stem_re.compile("^[A-Za-z0-9_-]+$")
	return _stem_re.search(s) != null


## An editable id field that doubles as the record's filename stem. Commits on Enter / focus-out (not
## per keystroke), so a half-typed name never renames a file; `on_commit` receives the LineEdit and
## should apply/revert via _rename_stem_record. Backs the trainers (unique_name) and shops (shop_id) cards.
func _stem_id_field(value: String, on_commit: Callable) -> LineEdit:
	var le := LineEdit.new()
	le.text = value
	le.text_submitted.connect(func(_s: String) -> void: on_commit.call(le))
	le.focus_exited.connect(func() -> void: on_commit.call(le))
	return le


## Move a record to a new path when its filename-stem id changes, mutating the editor's shared
## structures in place and queuing the old file for deletion on the next Save (the same deferred-delete
## mechanism as removals). Returns the new path, or "" if rejected — an illegal stem, or one that would
## clobber another loaded record's file (a clash with a record in a different folder is allowed through
## so validation can flag the duplicate). `id_key` is the dict key holding the id (unique_name/shop_id).
func _rename_stem_record(old_path: String, new_name: String, id_key: String,
		records: Dictionary, paths: Array, expanded: Dictionary, deleted: Array) -> String:
	if not _is_valid_stem(new_name):
		return ""
	var new_path := old_path.get_base_dir() + "/" + new_name + ".json"
	if new_path != old_path and records.has(new_path):
		return ""
	var record: Dictionary = records[old_path]
	record[id_key] = new_name
	records.erase(old_path)
	records[new_path] = record
	var i := paths.find(old_path)
	if i >= 0:
		paths[i] = new_path
	expanded[new_path] = bool(expanded.get(old_path, true))
	expanded.erase(old_path)
	deleted.erase(new_path)   # an earlier rename may have queued this name for deletion
	deleted.append(old_path)  # drop the old file on the next Save
	return new_path


## Compact inline label + control (for grid-like rows).
func _mini(label_text: String, control: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	hb.add_child(l)
	hb.add_child(control)
	return hb


## Catalog entries ([{value,label}]) of the .png basenames in a bundled sprite dir (for sprite pickers).
func _sprite_entries(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".png"):
			var n := f.get_basename()
			out.append({ "value": n, "label": n })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] < b["value"])
	return out


static var _item_slug_to_id: Dictionary = {}

## item_id for an item slug (shops/trainers reference items by lower-snake name), or 0 if unknown.
## Built once from the Catalog item list (slugify of each display name -> id).
func _item_id_for_slug(slug: String) -> int:
	if _item_slug_to_id.is_empty():
		for e in Catalog.items:
			_item_slug_to_id[GameData.slugify(str(e["label"]))] = int(str(e["value"]))
	return int(_item_slug_to_id.get(slug, 0))


static var _items_decorated: Array = []
static var _item_slugs_decorated: Array = []

## The full item catalog (value = item_id) with TM/HM labels annotated by the move they teach
## ("TM01" -> "TM01 — Focus Punch"), so machines are identifiable — and searchable by move — in
## pickers. Values are untouched; only labels change. Built once from the embedded DB.
func _items_labeled() -> Array:
	if _items_decorated.is_empty():
		_items_decorated = _label_machines(Catalog.items,
			func(e: Dictionary) -> int: return int(str(e["value"])))
	return _items_decorated

## The item-slug catalog (value = slug) with the same TM/HM move annotation. Slugs are untouched, so
## shop/trainer pickers still store and resolve items by slug (icons and saved data are unaffected).
func _item_slugs_labeled() -> Array:
	if _item_slugs_decorated.is_empty():
		_item_slugs_decorated = _label_machines(Catalog.item_slugs,
			func(e: Dictionary) -> int: return _item_id_for_slug(str(e["value"])))
	return _item_slugs_decorated

## A copy of `entries` with each TM/HM label suffixed by the move it teaches; `id_of` maps an entry to
## its item_id. Non-machines (and items whose move can't be resolved) keep their plain label.
func _label_machines(entries: Array, id_of: Callable) -> Array:
	var out: Array = []
	for e in entries:
		var move := _machine_move_name(int(id_of.call(e)))
		var label: String = e["label"] if move == "" else "%s — %s" % [e["label"], move]
		out.append({ "value": e["value"], "label": label })
	return out

## The move a TM/HM teaches (e.g. "Focus Punch"), or "" if the item teaches no move or it can't be
## resolved from the embedded DB.
func _machine_move_name(item_id: int) -> String:
	var item := GameData.get_item(item_id)
	if item == null or item.move_id < 0:
		return ""
	var mv := GameData.get_move(item.move_id)
	return str(mv.name) if mv != null else ""


## Catalog entries ([{value,label}]) for the distinct values of `key` across an array of record dicts.
func _distinct_entries(records: Array, key: String) -> Array:
	var seen := {}
	var out: Array = []
	for r in records:
		if typeof(r) == TYPE_DICTIONARY and r.has(key):
			var v := str(r[key])
			if v != "" and not seen.has(v):
				seen[v] = true
				out.append({ "value": v, "label": v })
	return out
