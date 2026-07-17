class_name MapRules
## Pure validator for one map's meta.json overlay (a MapDoc). Mirrors the game-server map loader and
## the map-processor's build-time checks. ERROR = the data is rejected/dropped (duplicate id, missing
## INTERACT_TYPE, malformed resource area, degenerate gate). WARNING = it loads but is silently broken
## at runtime (unresolved warp target, uncatalogued resource node → inert, zone polygon that never
## matches, patrol waypoint problems). Every Problem's locator is the offending model object, so the
## shell can select it on the map.

## trainer_names: { unique_name: true } from content/trainers (a "trainer" NPC's id must match one).
## region: this map's id (used to tell same-map warps from cross-map ones).
## is_blocked: optional Callable(Vector2i) -> bool for patrol-waypoint collision checks ({} skips it).
## shop_ids / encounter_groups / object_types / item_ids: reference sets the caller scans ONCE from the
## LIVE content/ datasets (not the bundled Catalog snapshot, which drifts) — passed in rather than
## re-read here, since validate runs on every edit. item_ids is { int item_id: true } from
## ValCheck.item_id_set (DB snapshot ∪ working-copy items.json), so a freshly-authored item —
## e.g. a new fishing rod — resolves in map validation before the DB is regenerated.
static func validate(doc: MapDoc, trainer_names: Dictionary, region: String,
		is_blocked: Callable = Callable(), shop_ids: Dictionary = {},
		encounter_groups: Dictionary = {}, object_types: Dictionary = {},
		job_board_ids: Dictionary = {}, item_ids: Dictionary = {}) -> Array:
	var out: Array = []
	var encounters := encounter_groups

	# Interactables: ids must be present and unique (the server keys a HashMap on id — dups drop).
	var seen_ids := {}
	for it in doc.interactables:
		var loc: Variant = it
		var here := "%s at (%d,%d)" % [it.kind, it.tile.x, it.tile.y]
		if it.id.strip_edges() == "":
			out.append(Problem.err("%s has an empty id" % it.kind, "(unnamed)", loc))
		elif seen_ids.has(it.id):
			out.append(Problem.err("duplicate interactable id %s" % it.id, it.id, loc))
		else:
			seen_ids[it.id] = true
		# Both the id and the display name travel to the client on the wire (EntityView), so both are
		# capped at the 255-byte string limit.
		_check_len("%s id" % it.kind, it.id, here, loc, out)
		if it.kind == "Npc":
			_check_len("NPC display name", it.display_name, here, loc, out)
		_interactable(it, trainer_names, object_types, is_blocked, out)
		_dialogue_lines(it, here, out)
		if it.script_name == "scripted":
			_scripted_graph(it, item_ids, shop_ids, encounters, out)
		if it.script_name == "job_board":
			_job_board(it, job_board_ids, out)

	# Warp targets: names present + unique (the server keys a HashMap on name — dups overwrite).
	var seen_targets := {}
	for t in doc.warp_targets:
		if t.name.strip_edges() == "":
			out.append(Problem.err("warp target has an empty name", "(unnamed)", t))
		elif seen_targets.has(t.name):
			out.append(Problem.err("duplicate warp target name %s (later one overwrites)" % t.name, t.name, t))
		seen_targets[t.name] = true

	# Warps: a warp needs a target map (a blank one resolves to a non-existent map and silently does
	# nothing — set it to this region for a same-map warp), and a target warp. For a same-map warp the
	# target must resolve to one of this map's warp targets; cross-map targets can't be checked here.
	for w in doc.warps:
		if w.name.strip_edges() == "":
			out.append(Problem.err("warp has an empty name", "(unnamed)", w))
		if w.target_map == "":
			out.append(Problem.warn("warp %s has no target map — it won't go anywhere (set it to %s for a same-map warp)" % [w.name, region], w.name, w))
		if w.target_warp == "":
			out.append(Problem.warn("warp %s has no target warp selected" % w.name, w.name, w))
		elif w.target_map == region and not seen_targets.has(w.target_warp):
			out.append(Problem.warn("warp %s targets %s, which is not a warp target on this map" % [w.name, w.target_warp], w.name, w))

	for z in doc.zones:
		_zone(z, object_types, encounters, out)
		# Surface what a resource area actually governs (reuses the real binding) — so it's obvious when
		# nodes inside the polygon are excluded by object_types, or max_active can't be met.
		if z.category == "ResourceArea":
			var bound: int = doc._placement_ids_in(z).size()
			var zc := z.name if z.name != "" else "ResourceArea"
			if bound == 0:
				out.append(Problem.warn("resource area %s governs no nodes — none inside it has a matching object_type" % zc, zc, z))
			elif z.max_active > bound:
				out.append(Problem.warn("resource area %s: max_active %d exceeds its %d bound node(s)" % [zc, z.max_active, bound], zc, z))
	return out


## A wire-bound string longer than the 255-byte protocol limit crashes the game-server the instant it
## encodes the packet carrying it (`frame()` panics on StringTooLong, see ValCheck.MAX_WIRE_STRING_BYTES).
## Flag it as an ERROR — with the exact byte size and the limit — so the designer knows precisely how
## much to trim, and Save stays blocked until they do.
static func _check_len(label: String, value: String, ctx: String, loc: Variant, out: Array) -> void:
	var n := ValCheck.utf8_len(value)
	if n > ValCheck.MAX_WIRE_STRING_BYTES:
		out.append(Problem.err("%s is too long: %d bytes (max %d) — it will crash the game; shorten it"
			% [label, n, ValCheck.MAX_WIRE_STRING_BYTES], ctx, loc))


## Inline sign / plain-NPC dialogue (properties["dialogue"]) is sent one wire step PER LINE —
## simple_dialogue.lua splits the text on newlines — so the 255-byte limit applies per line, not to the
## whole block: a single over-long line crashes, but a long multi-line block of short lines is fine. Only
## objects that actually render through simple_dialogue (no explicit script, or script "simple_dialogue")
## use this property, so the others are skipped to avoid flagging dormant leftover text.
static func _dialogue_lines(it: Interactable, ctx: String, out: Array) -> void:
	if not it.script_name in ["", "simple_dialogue"]:
		return
	var dlg := str(it.properties.get("dialogue", ""))
	if dlg == "":
		return
	for line in dlg.split("\n"):
		var t := (line as String).strip_edges()
		if t != "":
			_check_len("dialogue line", t, ctx, it, out)


static func _interactable(it: Interactable, trainer_names: Dictionary, object_types: Dictionary,
		is_blocked: Callable, out: Array) -> void:
	var ctx := it.id if it.id != "" else it.kind
	match it.kind:
		"Npc":
			if it.script_name.strip_edges() == "":
				out.append(Problem.err("NPC %s is missing its interact type (script)" % ctx, ctx, it))
			elif it.script_name == "trainer" and not trainer_names.has(it.id):
				out.append(Problem.warn("trainer NPC %s has no matching trainer file (id must equal a trainer unique_name)" % ctx, ctx, it))
			if it.sprite < 0:
				out.append(Problem.warn("NPC %s has no sprite assigned" % ctx, ctx, it))
			_patrol(it, is_blocked, out)
		"ResourceNode":
			var ot := str(it.properties.get("OBJECT_TYPE", ""))
			if ot == "":
				out.append(Problem.warn("resource node %s has no OBJECT_TYPE (inert)" % ctx, ctx, it))
			elif not object_types.has(ot):
				out.append(Problem.warn("resource node %s OBJECT_TYPE %s is not in the catalog (inert)" % [ctx, ot], ctx, it))
		_:
			pass


## A job_board Facility opens the board named by properties["job_board_id"]. The id must resolve to an
## authored board (job_boards/<board_id>.json), else the panel opens empty / the server errors when a
## player interacts — a runtime break, not a boot failure, so WARNING (mirrors the resource-node check).
static func _job_board(it: Interactable, job_board_ids: Dictionary, out: Array) -> void:
	var ctx := it.id if it.id != "" else it.kind
	var bid := str(it.properties.get("job_board_id", "")).strip_edges()
	if bid == "":
		out.append(Problem.warn("job board %s has no job_board_id set (it opens nothing)" % ctx, ctx, it))
	elif not job_board_ids.has(bid):
		out.append(Problem.warn("job board %s: job_board_id %s is not an authored board" % [ctx, bid], ctx, it))


## Validate a `scripted` object's interaction graph: structure (entry resolves, edges don't dangle)
## plus each node's references (the server would fail give/take_item / open_shop at runtime; an empty
## flag / qty is always a mistake).
static func _scripted_graph(it: Interactable, item_ids: Dictionary, shop_ids: Dictionary,
		encounters: Dictionary, out: Array) -> void:
	var ctx := it.id if it.id != "" else it.kind
	var nodes: Array = it.graph.get("nodes", [])
	if nodes.is_empty():
		out.append(Problem.warn("scripted %s has an empty interaction graph (it does nothing)" % ctx, ctx, it))
		return
	var ids := {}
	for node in nodes:
		ids[str((node as Dictionary).get("id", ""))] = true
	if not ids.has(str(it.graph.get("entry", ""))):
		out.append(Problem.err("scripted %s: graph entry node is missing" % ctx, ctx, it))
	for node in nodes:
		_graph_node(it, ctx, node, ids, item_ids, shop_ids, encounters, out)


static func _graph_node(it: Interactable, ctx: String, node: Dictionary, ids: Dictionary,
		item_ids: Dictionary, shop_ids: Dictionary, encounters: Dictionary, out: Array) -> void:
	var kind := str(node.get("kind", ""))
	var tag := "%s node %s (%s)" % [ctx, str(node.get("id", "?")), kind]
	# Edge targets must resolve to a real node.
	for edge in ["next", "if_true", "if_false"]:
		var dst := str(node.get(edge, ""))
		if dst != "" and not ids.has(dst):
			out.append(Problem.err("%s: %s points at a missing node '%s'" % [tag, edge, dst], ctx, it))
	match kind:
		"action":
			_action_refs(it, tag, node.get("action", {}), item_ids, shop_ids, encounters, out)
		"condition":
			var cond: Dictionary = node.get("cond", {})
			var ck := str(cond.get("kind", ""))
			if (ck == "flag_set" or ck == "flag_unset") and str(cond.get("key", "")).strip_edges() == "":
				out.append(Problem.err("%s: condition flag key is required" % tag, ctx, it))
			if ck == "has_item" and not item_ids.has(int(cond.get("item_id", -1))):
				out.append(Problem.err("%s: condition item does not resolve" % tag, ctx, it))
		"choice":
			var opts: Array = node.get("options", [])
			if opts.is_empty():
				out.append(Problem.err("%s: choice has no options" % tag, ctx, it))
			for o in opts:
				# Each option label is sent as a wire String in the Choice step → 255-byte cap.
				var olabel := str((o as Dictionary).get("label", ""))
				if olabel.strip_edges() == "":
					out.append(Problem.warn("%s: a choice option has no label" % tag, ctx, it))
				else:
					_check_len("%s option label" % tag, olabel, ctx, it, out)
				var dst := str((o as Dictionary).get("next", ""))
				if dst != "" and not ids.has(dst):
					out.append(Problem.err("%s: option points at a missing node '%s'" % [tag, dst], ctx, it))
		_:
			pass


## Reference checks for an Action node's nested ScriptAction.
static func _action_refs(it: Interactable, tag: String, a: Dictionary,
		item_ids: Dictionary, shop_ids: Dictionary, encounters: Dictionary, out: Array) -> void:
	var ctx := it.id if it.id != "" else it.kind
	match str(a.get("kind", "")):
		"give_item", "take_item":
			if not item_ids.has(int(a.get("item_id", -1))):
				out.append(Problem.err("%s: item does not resolve to a known item" % tag, ctx, it))
			if int(a.get("qty", 0)) < 1:
				out.append(Problem.err("%s: qty must be >= 1" % tag, ctx, it))
		"open_shop":
			if not shop_ids.has(str(a.get("shop_id", ""))):
				out.append(Problem.err("%s: shop is not a configured shop" % tag, ctx, it))
		"wild_battle":
			if not encounters.has(str(a.get("encounter_group", ""))):
				out.append(Problem.warn("%s: encounter group is not in the catalog" % tag, ctx, it))
		"say", "say_system":
			# Unlike inline simple_dialogue, a graph say sends its whole text as one wire step (no
			# newline split), so the entire string is bounded by the 255-byte limit.
			var text := str(a.get("text", ""))
			if text.strip_edges() == "":
				out.append(Problem.warn("%s: empty text" % tag, ctx, it))
			else:
				_check_len("%s text" % tag, text, ctx, it, out)
		"play_sound":
			_check_len("%s sound id" % tag, str(a.get("sound_id", "")), ctx, it, out)
		"play_animation":
			_check_len("%s animation id" % tag, str(a.get("animation_id", "")), ctx, it, out)
		"set_flag", "clear_flag":
			if str(a.get("key", "")).strip_edges() == "":
				out.append(Problem.err("%s: flag key is required" % tag, ctx, it))
		"give_badge":
			var b := int(a.get("badge_id", -1))
			if b < 0 or b > 7:
				out.append(Problem.err("%s: badge must be 0..7" % tag, ctx, it))
		"give_pokemon":
			if int(a.get("species_id", 0)) <= 0:
				out.append(Problem.err("%s: give_pokemon needs a species" % tag, ctx, it))
			var lvl := int(a.get("level", 0))
			if lvl < 1 or lvl > 100:
				out.append(Problem.err("%s: level must be 1..100" % tag, ctx, it))
		_:
			pass


static func _patrol(it: Interactable, is_blocked: Callable, out: Array) -> void:
	if str(it.behavior.get("kind", "")) != "patrol_path":
		return
	var ctx := it.id if it.id != "" else it.kind
	var wps: Array = it.waypoints
	if wps.size() < 2:
		out.append(Problem.err("patrol NPC %s needs at least 2 waypoints" % ctx, ctx, it))
		return
	if wps[0] != it.tile:
		out.append(Problem.err("patrol NPC %s: first waypoint must equal its own tile" % ctx, ctx, it))
	for i in range(1, wps.size()):
		var a: Vector2i = wps[i - 1]
		var b: Vector2i = wps[i]
		if (a.x != b.x) == (a.y != b.y):  # both differ (diagonal) or neither (zero-length)
			out.append(Problem.err("patrol NPC %s: leg (%d,%d)→(%d,%d) is not axis-aligned" % [ctx, a.x, a.y, b.x, b.y], ctx, it))
		if is_blocked.is_valid() and is_blocked.call(b):
			out.append(Problem.warn("patrol NPC %s: waypoint (%d,%d) is on a blocked tile" % [ctx, b.x, b.y], ctx, it))


static func _zone(z: Zone, object_types: Dictionary, encounters: Dictionary, out: Array) -> void:
	var ctx := z.name if z.name != "" else "%s zone" % z.category
	if z.name.strip_edges() == "":
		out.append(Problem.warn("%s zone has no name" % z.category, ctx, z))
	if z.polygon.size() < 3:
		out.append(Problem.warn("%s zone %s has fewer than 3 vertices (it never matches a tile)" % [z.category, ctx], ctx, z))
	match z.category:
		"Area":
			if not Zone.REGIONS.has(z.region):
				out.append(Problem.err("area zone %s has unknown region %s (expected one of %s)" \
					% [ctx, z.region, ", ".join(Zone.REGIONS)], ctx, z))
			if z.display_name.strip_edges() == "":
				out.append(Problem.warn("area zone %s has no display name (encounters placed in it " \
					% ctx + "cannot be attributed to a place)", ctx, z))
		"ResourceArea":
			if z.object_types.is_empty():
				out.append(Problem.err("resource area %s names no object types" % ctx, ctx, z))
			if z.max_active < 1:
				out.append(Problem.err("resource area %s needs max_active >= 1" % ctx, ctx, z))
			for ot in z.object_types:
				if not object_types.has(str(ot)):
					out.append(Problem.warn("resource area %s references uncatalogued object type %s" % [ctx, ot], ctx, z))
		"Gate":
			var has_pred := not z.requires_flag.is_empty() or not z.forbids_flag.is_empty() \
				or not z.requires_badge.is_empty() or not z.requires_item.is_empty() or z.requires_party_min >= 0
			if not has_pred:
				out.append(Problem.err("gate zone %s has no requirements (it gates nothing)" % ctx, ctx, z))
			# Each blocked message is shown to the player as a wire SystemDialogue step → 255-byte cap.
			for key in z.gate_messages:
				_check_len("gate message [%s]" % str(key), str(z.gate_messages[key]), ctx, z, out)
		"Encounter":
			if z.encounter_group != "" and not encounters.has(z.encounter_group):
				out.append(Problem.warn("encounter zone %s references unknown group %s" % [ctx, z.encounter_group], ctx, z))
			if z.fish_encounter_group != "" and not encounters.has(z.fish_encounter_group):
				out.append(Problem.warn("encounter zone %s references unknown fish group %s" % [ctx, z.fish_encounter_group], ctx, z))
		_:
			pass
