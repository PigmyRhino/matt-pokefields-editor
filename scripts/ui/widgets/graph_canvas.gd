class_name GraphCanvas
extends CanvasLayer
## Full-screen visual editor for a `scripted` interactable's interaction graph, built on Godot's
## GraphEdit. Node kinds: Start / Action / Condition / Choice. Wiring an output port to another node's
## input sets that edge (next / if_true / if_false / option.next); each output drives one target. The
## bound `Interactable.graph` dict is mutated in place; `changed` fires on every edit, `closed` on Done.
## Node param widgets are driven by Catalog.script_actions / script_conditions (same catalogs as Rust).

signal changed
signal closed

const COL_W := 320.0
const ROW_H := 190.0
const C_FLOW := Color(0.6, 0.8, 1.0)
const C_TRUE := Color(0.5, 1.0, 0.6)
const C_FALSE := Color(1.0, 0.5, 0.5)
const C_OPT := Color(1.0, 0.85, 0.4)

var _it: Interactable = null
var _graph: Dictionary = {}        ## bound ref == _it.graph
var _edit: GraphEdit
var _title: Label
var _id_counter := 1
var _shop_entries: Array = []
var _encounter_entries: Array = []   ## live content/encounter_data.json groups, cached per open()
var _species_entries: Array = []     ## [{value: id-as-string, label: name}] from the data cache, built once
var _flag_entries: Array = []        ## known flag keys (from every saved overlay) for the flag picker, per open()
## node id -> graph-space position (session-only; auto-laid-out on open, then preserved across rebuilds
## and updated as the designer drags — so adding/deleting a node never re-shuffles the rest).
var _positions: Dictionary = {}


func _ready() -> void:
	layer = 60
	visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var bar := HBoxContainer.new()
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	var addmenu := MenuButton.new()
	addmenu.text = "+ Node"
	_build_add_menu(addmenu.get_popup())
	bar.add_child(addmenu)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	bar.add_child(done)
	vb.add_child(bar)

	_edit = GraphEdit.new()
	_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.right_disconnects = true
	_edit.connection_request.connect(_on_connect)
	_edit.disconnection_request.connect(_on_disconnect)
	_edit.delete_nodes_request.connect(_on_delete)
	_edit.end_node_move.connect(_capture_positions)  # remember where the designer drags nodes
	vb.add_child(_edit)


## Open the editor on an interactable's graph (auto-seeding a Start node into an empty graph).
func open(it: Interactable) -> void:
	_it = it
	_graph = it.graph  # same dict ref — mutations persist onto the interactable
	if not _graph.has("nodes"):
		_graph["nodes"] = []
	if (_graph["nodes"] as Array).is_empty():
		_graph["nodes"] = [{ "kind": "start", "id": "start" }]
		_graph["entry"] = "start"
	if not _graph.has("entry"):
		_graph["entry"] = str((_graph["nodes"][0] as Dictionary)["id"])
	_shop_entries = ContentScan.shops()
	_encounter_entries = ContentScan.encounter_groups()
	_build_species_entries()
	_build_flag_entries()
	_seed_counter()
	_positions.clear()  # fresh auto-layout for this open; preserved thereafter as the session edits
	_title.text = "Interaction graph — %s   (wire output ▸ ports into ◂ inputs; right-drag a wire to cut)" % it.id
	visible = true
	_rebuild()


# -- rebuild / layout --------------------------------------------------------------------------------

func _rebuild() -> void:
	if _edit == null:
		return
	_edit.clear_connections()
	for c in _edit.get_children():
		if c is GraphNode:
			_edit.remove_child(c)
			c.queue_free()
	for node in _graph.get("nodes", []):
		_edit.add_child(_make_node(node))
	_layout()
	_draw_connections()


func _draw_connections() -> void:
	for node in _graph.get("nodes", []):
		var id := str(node["id"])
		match str(node["kind"]):
			"start", "action":
				var nxt := str(node.get("next", ""))
				if nxt != "" and _node_by_id(nxt) != null:
					_edit.connect_node(id, 0, nxt, 0)
			"condition":
				var t := str(node.get("if_true", ""))
				var f := str(node.get("if_false", ""))
				if t != "" and _node_by_id(t) != null:
					_edit.connect_node(id, 0, t, 0)
				if f != "" and _node_by_id(f) != null:
					_edit.connect_node(id, 1, f, 0)
			"choice":
				var opts: Array = node.get("options", [])
				for i in opts.size():
					var nxt := str((opts[i] as Dictionary).get("next", ""))
					if nxt != "" and _node_by_id(nxt) != null:
						_edit.connect_node(id, i, nxt, 0)


## Place each node: a remembered position (from `_positions` — a prior auto-layout or a drag) wins, so
## a rebuild never re-shuffles the graph. Only nodes without one get a fresh left-to-right BFS slot
## (then that slot is remembered). Positions are session-only (kept off the server schema).
func _layout() -> void:
	var col := {}
	var entry := str(_graph.get("entry", ""))
	var queue: Array = [entry]
	col[entry] = 0
	while not queue.is_empty():
		var id: String = str(queue.pop_front())
		var node: Variant = _node_by_id(id)
		if node == null:
			continue
		for nxt in _targets_of(node):
			if nxt != "" and not col.has(nxt):
				col[nxt] = int(col[id]) + 1
				queue.append(nxt)
	var per_col := {}
	for node in _graph.get("nodes", []):
		var id := str(node["id"])
		var gn := _edit.get_node_or_null(NodePath(id)) as GraphNode
		if gn == null:
			continue
		if not _positions.has(id):
			var c: int = col.get(id, 0)
			var row: int = per_col.get(c, 0)
			per_col[c] = row + 1
			_positions[id] = Vector2(c * COL_W, row * ROW_H)
		gn.position_offset = _positions[id]


## Remember where nodes ended up after a drag, so subsequent rebuilds keep them in place.
func _capture_positions() -> void:
	for c in _edit.get_children():
		if c is GraphNode:
			_positions[c.name] = (c as GraphNode).position_offset


# -- node construction -------------------------------------------------------------------------------

func _make_node(node: Dictionary) -> GraphNode:
	var gn := GraphNode.new()
	gn.name = str(node["id"])
	# Wide enough that titles / picker text don't wrap, and hand-resizable for long dialogue.
	gn.custom_minimum_size = Vector2(260, 0)
	gn.resizable = true
	gn.resize_request.connect(func(new_size: Vector2) -> void: gn.size = new_size)
	match str(node["kind"]):
		"start":
			gn.title = "Start"
			gn.add_child(_flow_label("next ▸"))
			gn.set_slot(0, false, 0, C_FLOW, true, 0, C_FLOW)
		"action":
			var akind := str(node["action"]["kind"])
			gn.title = "Action: " + _label_of(Catalog.script_actions, akind)
			gn.add_child(_flow_label("▸"))
			gn.set_slot(0, true, 0, C_FLOW, true, 0, C_FLOW)
			for w in _param_rows(Catalog.script_actions, akind, node["action"]):
				gn.add_child(w)
		"condition":
			var ckind := str(node["cond"]["kind"])
			gn.title = "If: " + _label_of(Catalog.script_conditions, ckind)
			gn.add_child(_flow_label("?"))
			gn.set_slot(0, true, 0, C_FLOW, false, 0, C_FLOW)
			var prows := _param_rows(Catalog.script_conditions, ckind, node["cond"])
			for w in prows:
				gn.add_child(w)
			gn.add_child(_flow_label("true ▸"))
			gn.add_child(_flow_label("false ▸"))
			var t_idx := 1 + prows.size()
			gn.set_slot(t_idx, false, 0, C_TRUE, true, 0, C_TRUE)
			gn.set_slot(t_idx + 1, false, 0, C_FALSE, true, 0, C_FALSE)
		"choice":
			gn.title = "Choice"
			gn.add_child(_flow_label("menu"))
			gn.set_slot(0, true, 0, C_FLOW, false, 0, C_FLOW)
			var opts: Array = node["options"]
			for i in opts.size():
				gn.add_child(_option_row(opts, i))
				gn.set_slot(1 + i, false, 0, C_OPT, true, 0, C_OPT)
			var add := Button.new()
			add.text = "+ option"
			add.pressed.connect(func() -> void:
				opts.append({ "label": "Option %d" % (opts.size() + 1) })
				_rebuild()
				changed.emit())
			gn.add_child(add)
	return gn


func _flow_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _option_row(opts: Array, i: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var le := LineEdit.new()
	le.text = str((opts[i] as Dictionary).get("label", ""))
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t: String) -> void:
		(opts[i] as Dictionary)["label"] = t
		changed.emit())
	hb.add_child(le)
	var rm := Button.new()
	rm.text = "✕"
	rm.pressed.connect(func() -> void:
		opts.remove_at(i)
		_rebuild()
		changed.emit())
	hb.add_child(rm)
	return hb


# -- param widgets (driven by the catalog specs; identical typing to the data editors) ---------------

## Build the species picker vocabulary once from the data cache (national-dex ids are dense from 1;
## a missing id returns null cheaply). value = id-as-string so `_picker(numeric=true)` stores the u16.
func _build_species_entries() -> void:
	if not _species_entries.is_empty():
		return
	for id in range(1, 1026):
		var sp: Variant = GameData.get_species(id)
		if sp != null:
			_species_entries.append({ "value": str(id), "label": str(sp.name) })


## Known flag keys (scanned from every saved overlay) for the flag picker's suggestions; rebuilt per open
## so a flag added on another map shows up. The picker still accepts a brand-new typed flag (allow_custom).
func _build_flag_entries() -> void:
	_flag_entries = FlagRegistry.entries()


func _param_rows(catalog: Array, kind: String, target: Dictionary) -> Array:
	var rows: Array = []
	var spec := _spec_of(catalog, kind)
	for p in spec.get("params", []):
		var hb := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = str((p as Dictionary).get("label", p["name"]))
		lbl.custom_minimum_size.x = 64
		hb.add_child(lbl)
		var w := _param_widget(target, p)
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(w)
		rows.append(hb)
	return rows


func _param_widget(target: Dictionary, p: Dictionary) -> Control:
	var key := str(p["name"])
	var optional := bool(p.get("optional", false))
	match str(p["type"]):
		"int":
			var sb := SpinBox.new()
			sb.min_value = int(p.get("min", 0))
			sb.max_value = int(p.get("max", 999999))
			sb.value = int(target.get(key, p.get("default", 0)))
			target[key] = int(sb.value)
			sb.value_changed.connect(func(v: float) -> void:
				target[key] = int(v)
				changed.emit())
			return sb
		"item":
			return _picker(target, key, Catalog.items, true, func(v: String) -> Texture2D:
				return GameData.get_item_icon(int(v)) if v.is_valid_int() else null)
		"badge":
			return _picker(target, key, Catalog.badges, true, Callable())
		"shop":
			return _picker(target, key, _shop_entries, false, Callable())
		"encounter":
			return _picker(target, key, _encounter_entries, false, Callable())
		"species":
			return _picker(target, key, _species_entries, true, func(v: String) -> Texture2D:
				return GameData.get_pokemon_icon(int(v)) if v.is_valid_int() else null)
		"flag":
			# Suggest existing flags, but still allow authoring a brand-new one (allow_custom).
			return _picker(target, key, _flag_entries, false, Callable(), true)
		_:  # text / sound / anim
			var le := LineEdit.new()
			le.text = str(target.get(key, ""))
			if optional:
				le.placeholder_text = "(default)"
			le.text_changed.connect(func(t: String) -> void:
				if t == "":
					target.erase(key)
				else:
					target[key] = t
				changed.emit())
			return le


func _picker(target: Dictionary, key: String, entries: Array, numeric: bool, icon_provider: Callable, allow_custom := false) -> SearchPicker:
	var sp := SearchPicker.new()
	sp.allow_none = false
	sp.allow_custom = allow_custom
	if icon_provider.is_valid():
		sp.icon_provider = icon_provider
	sp.set_entries(entries)
	# On load, numeric ids come back from JSON as floats (1001.0); coerce to "1001" so they match the
	# catalog entry (and the icon resolves) instead of showing the raw "1001.0".
	var cur: Variant = target.get(key, null)
	var cur_str := ""
	if cur != null:
		cur_str = str(int(cur)) if numeric else str(cur)
	sp.set_value(cur_str)
	sp.value_changed.connect(func(v: String) -> void:
		if v == "":
			target.erase(key)
		else:
			target[key] = int(v) if numeric else v
		changed.emit())
	return sp


# -- add / delete / wire -----------------------------------------------------------------------------

func _build_add_menu(pm: PopupMenu) -> void:
	var actions_pm := PopupMenu.new()
	actions_pm.name = "actions"
	for spec in Catalog.script_actions:
		actions_pm.add_item(str((spec as Dictionary)["label"]))
	actions_pm.id_pressed.connect(func(idx: int) -> void:
		_add_node("action", str(Catalog.script_actions[idx]["kind"])))
	pm.add_child(actions_pm)
	pm.add_submenu_item("Action", "actions")
	var conds_pm := PopupMenu.new()
	conds_pm.name = "conditions"
	for spec in Catalog.script_conditions:
		conds_pm.add_item(str((spec as Dictionary)["label"]))
	conds_pm.id_pressed.connect(func(idx: int) -> void:
		_add_node("condition", str(Catalog.script_conditions[idx]["kind"])))
	pm.add_child(conds_pm)
	pm.add_submenu_item("Condition", "conditions")
	pm.add_item("Choice")  # the only direct item — its press fires the parent popup
	pm.id_pressed.connect(func(_idx: int) -> void: _add_node("choice", ""))


func _add_node(group: String, sub_kind: String) -> void:
	var node := { "id": _new_id() }
	match group:
		"action":
			node["kind"] = "action"
			node["action"] = _default_params(Catalog.script_actions, sub_kind)
		"condition":
			node["kind"] = "condition"
			node["cond"] = _default_params(Catalog.script_conditions, sub_kind)
		"choice":
			node["kind"] = "choice"
			node["options"] = [{ "label": "Option 1" }, { "label": "Option 2" }]
	(_graph["nodes"] as Array).append(node)
	# Add ONLY the new node (no full rebuild), so existing nodes / scroll stay put. It drops into the
	# current view so the designer can see and wire it.
	_positions[str(node["id"])] = _spawn_position()
	var gn := _make_node(node)
	_edit.add_child(gn)
	gn.position_offset = _positions[str(node["id"])]
	changed.emit()


## A graph-space point inside the current view (offset so repeated adds don't stack exactly).
func _spawn_position() -> Vector2:
	var n: int = (_graph["nodes"] as Array).size()
	return _edit.scroll_offset / _edit.zoom + Vector2(60, 40) + Vector2(24, 24) * (n % 6)


## A fresh `{ kind, <int params seeded to default> }` body for an action/condition (string + picker
## params fill in as the designer edits).
func _default_params(catalog: Array, kind: String) -> Dictionary:
	var body := { "kind": kind }
	for p in _spec_of(catalog, kind).get("params", []):
		if str((p as Dictionary)["type"]) == "int":
			body[str(p["name"])] = int((p as Dictionary).get("default", 0))
	return body


func _on_connect(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	# One target per output port: drop any wire already leaving this port.
	for c in _edit.get_connection_list():
		if c["from_node"] == from and int(c["from_port"]) == from_port:
			_edit.disconnect_node(from, from_port, c["to_node"], int(c["to_port"]))
	var node: Variant = _node_by_id(str(from))
	if node != null:
		_set_edge(node, from_port, str(to))
	_edit.connect_node(from, from_port, to, 0)
	changed.emit()


func _on_disconnect(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	_edit.disconnect_node(from, from_port, to, to_port)
	var node: Variant = _node_by_id(str(from))
	if node != null:
		_clear_edge(node, from_port)
	changed.emit()


func _on_delete(nodes: Array) -> void:
	for nm in nodes:
		var id := str(nm)
		if id == str(_graph.get("entry", "")):
			continue  # the entry/start node anchors the graph — not deletable
		_remove_node(id)
		_positions.erase(id)
	_rebuild()  # position-stable: surviving nodes keep their remembered offsets
	changed.emit()


func _set_edge(node: Dictionary, from_port: int, to: String) -> void:
	match str(node["kind"]):
		"condition":
			node["if_true" if from_port == 0 else "if_false"] = to
		"choice":
			(node["options"][from_port] as Dictionary)["next"] = to
		_:
			node["next"] = to


func _clear_edge(node: Dictionary, from_port: int) -> void:
	match str(node["kind"]):
		"condition":
			node.erase("if_true" if from_port == 0 else "if_false")
		"choice":
			(node["options"][from_port] as Dictionary).erase("next")
		_:
			node.erase("next")


# -- helpers -----------------------------------------------------------------------------------------

func _targets_of(node: Dictionary) -> Array:
	match str(node["kind"]):
		"condition":
			return [str(node.get("if_true", "")), str(node.get("if_false", ""))]
		"choice":
			var out: Array = []
			for o in node.get("options", []):
				out.append(str((o as Dictionary).get("next", "")))
			return out
		_:
			return [str(node.get("next", ""))]


func _remove_node(id: String) -> void:
	var nodes: Array = _graph["nodes"]
	for i in nodes.size():
		if str(nodes[i]["id"]) == id:
			nodes.remove_at(i)
			break
	# Drop any edges that pointed at the removed node so nothing dangles.
	for node in nodes:
		match str(node["kind"]):
			"condition":
				if str(node.get("if_true", "")) == id: node.erase("if_true")
				if str(node.get("if_false", "")) == id: node.erase("if_false")
			"choice":
				for o in node.get("options", []):
					if str((o as Dictionary).get("next", "")) == id: (o as Dictionary).erase("next")
			_:
				if str(node.get("next", "")) == id: node.erase("next")


func _node_by_id(id: String) -> Variant:
	for node in _graph.get("nodes", []):
		if str(node["id"]) == id:
			return node
	return null


func _seed_counter() -> void:
	var maxn := 0
	for node in _graph.get("nodes", []):
		var id := str(node["id"])
		if id.begins_with("n") and id.substr(1).is_valid_int():
			maxn = maxi(maxn, int(id.substr(1)))
	_id_counter = maxn + 1


func _new_id() -> String:
	var id := "n%d" % _id_counter
	_id_counter += 1
	return id


func _spec_of(catalog: Array, kind: String) -> Dictionary:
	for e in catalog:
		if str((e as Dictionary)["kind"]) == kind:
			return e
	return {}


func _label_of(catalog: Array, kind: String) -> String:
	var spec := _spec_of(catalog, kind)
	return str(spec.get("label", kind))
