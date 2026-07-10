class_name DataRules
## Pure validators for the content/ datasets, mirroring the game-server catalogs
## (crates/pkmn-core/src/data/*) and the Python generator's fail-loud checks. Each function takes the
## in-memory parsed data (so live edits are validated before save) plus the content dir for cross-file
## reference sets, and returns Array[Problem]. ERROR = the server/generator would refuse to boot on it.

const RANKS := ["Novice", "Amateur", "Ace", "Pro", "Master", "Champion", "Elite"]
const NATURES := ["hardy", "lonely", "brave", "adamant", "naughty", "bold", "docile", "relaxed",
	"impish", "lax", "timid", "hasty", "serious", "jolly", "naive", "modest", "mild", "quiet",
	"bashful", "rash", "calm", "gentle", "sassy", "careful", "quirky"]
const GENDERS := ["male", "female", "genderless"]
const STATS := ["hp", "atk", "def", "spa", "spd", "spe"]
const CUSTOM_ITEM_TYPES := ["tool", "material", "equipment", "collectible", "key"]

const MAX_TEAM := 6
const MAX_MOVES := 4
const MAX_IV := 31
const MAX_EV_STAT := 252
const MAX_EV_TOTAL := 510
const MAX_BADGE_INDEX := 7
const MAX_MIN_BADGES := 8
const RESPAWN_MIN := 1000
const RESPAWN_MAX := 604800000  # 7 days in ms
const MAX_LEVEL := 99
const SWING_MIN := 200
const SWING_MAX := 30000

const CLOTHING_SLOT_RANGE := {
	"hair": [10000, 19999], "tops": [20000, 29999],
	"bottoms": [30000, 39999], "hats": [40000, 49999],
}


# -- trainers --------------------------------------------------------------------------------------

## by_path: { absolute_path: parsed_dict }. Cross-file: duplicate unique_name detection.
static func trainers(by_path: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var species := ValCheck.value_set(Catalog.species_slugs)
	var abilities := ValCheck.value_set(Catalog.ability_slugs)
	var moves := ValCheck.value_set(Catalog.move_slugs)
	var items := ValCheck.item_slug_set(content_dir)
	var seen_names := {}  # unique_name -> stem of the file that first claimed it
	for path in by_path:
		var t: Dictionary = by_path[path]
		var stem := str(path).get_file().get_basename()
		var loc := { "section": "Trainers", "path": path }
		var add := func(sev: int, msg: String) -> void:
			out.append(Problem.err(msg, stem, loc) if sev == Problem.Severity.ERROR else Problem.warn(msg, stem, loc))

		var uname := str(t.get("unique_name", ""))
		if uname != stem:
			add.call(Problem.Severity.ERROR, "unique_name %s doesn't match filename stem %s" % [uname, stem])
		elif seen_names.has(uname):
			add.call(Problem.Severity.ERROR, "duplicate unique_name %s (also in %s)" % [uname, seen_names[uname]])
		else:
			seen_names[uname] = stem
		if str(t.get("display_name", "")).strip_edges() == "":
			add.call(Problem.Severity.ERROR, "display_name is required")
		if t.has("rank") and not (str(t["rank"]) in RANKS):
			add.call(Problem.Severity.ERROR, "rank %s must be one of %s" % [t["rank"], ", ".join(RANKS)])
		var badge: Variant = t.get("badge_award", null)
		if badge != null and (int(badge) < 0 or int(badge) > MAX_BADGE_INDEX):
			add.call(Problem.Severity.ERROR, "badge_award %d must be null or 0..%d" % [int(badge), MAX_BADGE_INDEX])

		var seen_items := {}
		for entry in t.get("items", []):
			var slug := str((entry as Dictionary).get("item", ""))
			if not items.has(slug):
				add.call(Problem.Severity.ERROR, "bag item %s doesn't resolve to a known item" % slug)
			if int((entry as Dictionary).get("qty", 0)) < 1:
				add.call(Problem.Severity.ERROR, "bag item %s qty must be >= 1" % slug)
			if seen_items.has(slug):
				add.call(Problem.Severity.ERROR, "bag item %s is duplicated (one row per item)" % slug)
			seen_items[slug] = true

		var team: Array = t.get("team", [])
		if team.size() < 1 or team.size() > MAX_TEAM:
			add.call(Problem.Severity.ERROR, "team must have 1..%d members (got %d)" % [MAX_TEAM, team.size()])
		for i in team.size():
			_trainer_member(team[i], i, species, abilities, moves, items, add)
		_trainer_scaling_bounds(t, team, add)
	return out


## Mirrors trainer_catalog.rs::parse_scaling_bounds — the bounds clamp the scaling
## reference level and are dead data on a team with no level_offset member.
static func _trainer_scaling_bounds(t: Dictionary, team: Array, add: Callable) -> void:
	var minv: Variant = t.get("scaling_min_level", null)
	var maxv: Variant = t.get("scaling_max_level", null)
	if minv == null and maxv == null:
		return
	var has_scaled := false
	for m in team:
		if (m as Dictionary).get("level_offset", null) != null:
			has_scaled = true
			break
	if not has_scaled:
		add.call(Problem.Severity.ERROR, "scaling_min_level/scaling_max_level require at least one team member with level_offset")
	if minv != null and (int(minv) < 1 or int(minv) > 100):
		add.call(Problem.Severity.ERROR, "scaling_min_level=%d must be in 1..100" % int(minv))
	if maxv != null and (int(maxv) < 1 or int(maxv) > 100):
		add.call(Problem.Severity.ERROR, "scaling_max_level=%d must be in 1..100" % int(maxv))
	var lo := 1 if minv == null else int(minv)
	var hi := 100 if maxv == null else int(maxv)
	if lo > hi:
		add.call(Problem.Severity.ERROR, "scaling_min_level=%d exceeds scaling_max_level=%d" % [lo, hi])


static func _trainer_member(m: Dictionary, slot: int, species: Dictionary, abilities: Dictionary,
		moves: Dictionary, items: Dictionary, add: Callable) -> void:
	var tag := "team[%d]" % slot
	var sp := str(m.get("species", ""))
	if not species.has(sp):
		add.call(Problem.Severity.ERROR, "%s: species %s doesn't resolve to a known species" % [tag, sp])
	var ability := str(m.get("ability", ""))
	if ability != "" and not abilities.has(ability):
		add.call(Problem.Severity.ERROR, "%s: ability %s doesn't resolve to a known ability" % [tag, ability])
	var nature := str(m.get("nature", "serious")).to_lower()
	if not (nature in NATURES):
		add.call(Problem.Severity.ERROR, "%s: nature %s is not a valid nature" % [tag, m.get("nature", "")])
	var gender: Variant = m.get("gender", null)
	if gender != null and str(gender) != "" and not (str(gender).to_lower() in GENDERS):
		add.call(Problem.Severity.ERROR, "%s: gender %s must be male/female/genderless or empty" % [tag, gender])
	var held: Variant = m.get("held_item", null)
	if held != null and str(held) != "" and not items.has(str(held)):
		add.call(Problem.Severity.ERROR, "%s: held_item %s doesn't resolve to a known item" % [tag, held])

	var has_fixed := m.has("fixed_level") and m["fixed_level"] != null
	var has_offset := m.has("level_offset") and m["level_offset"] != null
	if has_fixed and has_offset:
		add.call(Problem.Severity.ERROR, "%s: fixed_level and level_offset are mutually exclusive" % tag)
	elif not has_fixed and not has_offset:
		add.call(Problem.Severity.ERROR, "%s: must set exactly one of fixed_level (1..100) or level_offset" % tag)
	elif has_fixed and (int(m["fixed_level"]) < 1 or int(m["fixed_level"]) > 100):
		add.call(Problem.Severity.ERROR, "%s: fixed_level %d must be in 1..100" % [tag, int(m["fixed_level"])])

	var ev_sum := 0
	for s in STATS:
		var iv := int(m.get("iv_" + s, 0))
		if iv < 0 or iv > MAX_IV:
			add.call(Problem.Severity.ERROR, "%s: iv_%s=%d must be in 0..%d" % [tag, s, iv, MAX_IV])
		var ev := int(m.get("ev_" + s, 0))
		if ev < 0 or ev > MAX_EV_STAT:
			add.call(Problem.Severity.ERROR, "%s: ev_%s=%d must be in 0..%d" % [tag, s, ev, MAX_EV_STAT])
		ev_sum += ev
	if ev_sum > MAX_EV_TOTAL:
		add.call(Problem.Severity.ERROR, "%s: EV sum %d exceeds the %d cap" % [tag, ev_sum, MAX_EV_TOTAL])

	var mv: Array = m.get("moves", [])
	if mv.size() > MAX_MOVES:
		add.call(Problem.Severity.ERROR, "%s: %d moves (max %d)" % [tag, mv.size(), MAX_MOVES])
	var seen_mv := {}
	for mname in mv:
		var ms := str(mname)
		if not moves.has(ms):
			add.call(Problem.Severity.ERROR, "%s: move %s doesn't resolve to a known move" % [tag, ms])
		if seen_mv.has(ms):
			add.call(Problem.Severity.ERROR, "%s: move %s is duplicated" % [tag, ms])
		seen_mv[ms] = true


# -- shops -----------------------------------------------------------------------------------------

static func shops(by_path: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var items := ValCheck.item_slug_set(content_dir)
	var seen_ids := {}
	for path in by_path:
		var raw: Dictionary = by_path[path]
		var stem := str(path).get_file().get_basename()
		var loc := { "section": "Shops", "path": path }
		var add := func(msg: String) -> void: out.append(Problem.err(msg, stem, loc))
		var sid := str(raw.get("shop_id", ""))
		if sid != stem:
			add.call("shop_id %s doesn't match filename stem %s" % [sid, stem])
		elif seen_ids.has(sid):
			add.call("duplicate shop_id %s (also in %s)" % [sid, seen_ids[sid]])
		else:
			seen_ids[sid] = stem
		var entries: Array = raw.get("entries", [])
		if entries.is_empty():
			add.call("entries must contain at least one item")
		var seen_item := {}
		for i in entries.size():
			var e: Dictionary = entries[i]
			var slug := str(e.get("item", ""))
			if not items.has(slug):
				add.call("entries[%d]: item %s doesn't resolve to a known item" % [i, slug])
			var mb := int(e.get("min_badges", 0))
			if mb < 0 or mb > MAX_MIN_BADGES:
				add.call("entries[%d]: min_badges %d must be in 0..%d" % [i, mb, MAX_MIN_BADGES])
			if seen_item.has(slug):
				add.call("entries[%d]: item %s duplicated (one entry per item)" % [i, slug])
			seen_item[slug] = true
	return out


# -- job boards ------------------------------------------------------------------------------------

const MAX_JOB_ID_BYTES := 64
const MAX_BOARD_NAME_BYTES := 48
const MAX_JOB_TITLE_BYTES := 80
const MAX_JOB_DESC_BYTES := 200
const MAX_JOB_REWARDS := 4
const JOB_OBJECTIVE_KINDS := ["defeat_species", "catch_pokemon", "gather_item", "win_battles", "defeat_trainer", "earn_skill_xp"]
const JOB_REWARD_KINDS := ["pokeyen", "item", "skill_xp"]

## by_path: { absolute_path: parsed board dict }. Mirrors crates/pkmn-core/src/data/job_catalog.rs.
## Cross-file: job_id is globally unique across ALL boards. Cross-catalog: species/items resolve against
## the working copy, skill against Catalog.skills, defeat_trainer against content/trainers (+ a rebattle
## WARNING the server can't give). Slot/pool agreement mirrors check_slots. See docs/game-server/JOBS.md.
static func job_boards(by_path: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var species := ValCheck.value_set(Catalog.species_slugs)
	var items := ValCheck.item_slug_set(content_dir)
	var skills := ValCheck.value_set(Catalog.skills)
	var trainers := ContentScan.trainer_rebattle()  # { unique_name: rebattle_policy }
	var seen_job_ids := {}  # job_id -> stem of the board that first claimed it (ids are global)
	for path in by_path:
		var board: Dictionary = by_path[path]
		var stem := str(path).get_file().get_basename()
		var loc := { "section": "Job boards", "path": path }
		var add := func(sev: int, msg: String) -> void:
			out.append(Problem.err(msg, stem, loc) if sev == Problem.Severity.ERROR else Problem.warn(msg, stem, loc))

		var bid := str(board.get("board_id", ""))
		if bid != stem:
			add.call(Problem.Severity.ERROR, "board_id %s doesn't match filename stem %s" % [bid, stem])
		var bname := str(board.get("name", ""))
		if bname.strip_edges() == "":
			add.call(Problem.Severity.ERROR, "name is required (the town shown as the turn-in location)")
		elif ValCheck.utf8_len(bname) > MAX_BOARD_NAME_BYTES:
			add.call(Problem.Severity.ERROR, "name is %d bytes (max %d)" % [ValCheck.utf8_len(bname), MAX_BOARD_NAME_BYTES])
		var jobs: Array = board.get("jobs", [])
		if jobs.is_empty():
			add.call(Problem.Severity.ERROR, "board has no jobs (needs at least one)")
		var pool := { "daily": 0, "weekly": 0 }
		var seen_here := {}
		for i in jobs.size():
			if typeof(jobs[i]) != TYPE_DICTIONARY:
				continue
			var cadence := _job(jobs[i], i, species, items, skills, trainers, seen_job_ids, seen_here, stem, add)
			if pool.has(cadence):
				pool[cadence] += 1
		_job_slots(board, "daily_slots", pool["daily"], add)
		_job_slots(board, "weekly_slots", pool["weekly"], add)
	return out


## Validate one job; returns its cadence ("daily"/"weekly"/"") for the caller's slot/pool check.
static func _job(job: Dictionary, idx: int, species: Dictionary, items: Dictionary, skills: Dictionary,
		trainers: Dictionary, seen_job_ids: Dictionary, seen_here: Dictionary, board_stem: String,
		add: Callable) -> String:
	var tag := "jobs[%d]" % idx
	var jid := str(job.get("job_id", ""))
	if jid.strip_edges() == "":
		add.call(Problem.Severity.ERROR, "%s: job_id is required" % tag)
	else:
		if ValCheck.utf8_len(jid) > MAX_JOB_ID_BYTES:
			add.call(Problem.Severity.ERROR, "%s: job_id is %d bytes (max %d)" % [tag, ValCheck.utf8_len(jid), MAX_JOB_ID_BYTES])
		if seen_here.has(jid):
			add.call(Problem.Severity.ERROR, "%s: duplicate job_id %s within this board" % [tag, jid])
		elif seen_job_ids.has(jid):
			add.call(Problem.Severity.ERROR, "%s: job_id %s is already used by board %s (ids are global)" % [tag, jid, seen_job_ids[jid]])
		else:
			seen_job_ids[jid] = board_stem
		seen_here[jid] = true
	_job_text(job, "title", tag, MAX_JOB_TITLE_BYTES, add)
	_job_text(job, "description", tag, MAX_JOB_DESC_BYTES, add)
	_job_objective(job.get("objective", null), tag, species, items, skills, trainers, add)
	_job_rewards(job.get("rewards", null), tag, items, skills, add)
	var cadence := str(job.get("cadence", ""))
	if not (cadence in ["daily", "weekly"]):
		add.call(Problem.Severity.ERROR, "%s: cadence %s must be daily or weekly" % [tag, cadence])
	return cadence


static func _job_text(job: Dictionary, key: String, tag: String, max_bytes: int, add: Callable) -> void:
	var v := str(job.get(key, ""))
	if v.strip_edges() == "":
		add.call(Problem.Severity.ERROR, "%s: %s is required" % [tag, key])
	elif ValCheck.utf8_len(v) > max_bytes:
		add.call(Problem.Severity.ERROR, "%s: %s is %d bytes (max %d — wire strings are u8-length)" % [tag, key, ValCheck.utf8_len(v), max_bytes])


static func _job_objective(obj: Variant, tag: String, species: Dictionary, items: Dictionary,
		skills: Dictionary, trainers: Dictionary, add: Callable) -> void:
	if typeof(obj) != TYPE_DICTIONARY:
		add.call(Problem.Severity.ERROR, "%s: objective is required" % tag)
		return
	var o: Dictionary = obj
	var kind := str(o.get("kind", ""))
	match kind:
		"defeat_species":
			_job_need_slug(o, "species", species, "%s: objective species" % tag, add)
			_job_need_pos(o, "count", "%s: objective count" % tag, add)
		"catch_pokemon":
			if o.has("species") and o["species"] != null and str(o["species"]).strip_edges() != "":
				_job_need_slug(o, "species", species, "%s: objective species" % tag, add)
			_job_need_pos(o, "count", "%s: objective count" % tag, add)
		"gather_item":
			_job_need_slug(o, "item", items, "%s: objective item" % tag, add)
			_job_need_pos(o, "count", "%s: objective count" % tag, add)
		"win_battles":
			_job_need_pos(o, "count", "%s: objective count" % tag, add)
		"defeat_trainer":
			var tname := str(o.get("trainer", "")).strip_edges()
			if tname == "":
				add.call(Problem.Severity.ERROR, "%s: objective defeat_trainer requires trainer" % tag)
			elif not trainers.has(tname):
				add.call(Problem.Severity.ERROR, "%s: objective trainer %s doesn't resolve to a known trainer" % [tag, tname])
			elif not (str(trainers[tname]) in ["daily", "weekly"]):
				add.call(Problem.Severity.WARNING, "%s: trainer %s is not daily/weekly-rebattlable — the job is uncompletable once it is beaten" % [tag, tname])
		"earn_skill_xp":
			_job_need_slug(o, "skill", skills, "%s: objective skill" % tag, add)
			_job_need_pos(o, "amount", "%s: objective amount" % tag, add)
		_:
			add.call(Problem.Severity.ERROR, "%s: objective kind %s must be one of %s" % [tag, kind, ", ".join(JOB_OBJECTIVE_KINDS)])


static func _job_rewards(raw: Variant, tag: String, items: Dictionary, skills: Dictionary, add: Callable) -> void:
	if typeof(raw) != TYPE_ARRAY:
		add.call(Problem.Severity.ERROR, "%s: rewards is required" % tag)
		return
	var rewards: Array = raw
	if rewards.is_empty() or rewards.size() > MAX_JOB_REWARDS:
		add.call(Problem.Severity.ERROR, "%s: rewards must have 1..%d entries (got %d)" % [tag, MAX_JOB_REWARDS, rewards.size()])
	for i in rewards.size():
		if typeof(rewards[i]) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = rewards[i]
		var rtag := "%s rewards[%d]" % [tag, i]
		match str(r.get("kind", "")):
			"pokeyen":
				_job_need_pos(r, "amount", "%s amount" % rtag, add)
			"item":
				_job_need_slug(r, "item", items, "%s item" % rtag, add)
				_job_need_pos(r, "qty", "%s qty" % rtag, add)
			"skill_xp":
				_job_need_slug(r, "skill", skills, "%s skill" % rtag, add)
				_job_need_pos(r, "amount", "%s amount" % rtag, add)
			_:
				add.call(Problem.Severity.ERROR, "%s: kind %s must be one of %s" % [rtag, r.get("kind", ""), ", ".join(JOB_REWARD_KINDS)])


## A pool and its slot count must agree (job_catalog.rs::check_slots): no slots for an empty pool, no
## empty rotation over a non-empty pool, never more slots than jobs of that cadence.
static func _job_slots(board: Dictionary, key: String, pool: int, add: Callable) -> void:
	var slots := int(board.get(key, 0))
	if (slots == 0) != (pool == 0):
		add.call(Problem.Severity.ERROR, "%s=%d with %d job(s) of that cadence — both must be zero or both non-zero" % [key, slots, pool])
	elif slots > pool:
		add.call(Problem.Severity.ERROR, "%s=%d exceeds the pool of %d job(s)" % [key, slots, pool])


static func _job_need_slug(d: Dictionary, key: String, known: Dictionary, label: String, add: Callable) -> void:
	var slug := str(d.get(key, "")).strip_edges()
	if slug == "":
		add.call(Problem.Severity.ERROR, "%s is required" % label)
	elif not known.has(slug):
		add.call(Problem.Severity.ERROR, "%s %s doesn't resolve" % [label, slug])


static func _job_need_pos(d: Dictionary, key: String, label: String, add: Callable) -> void:
	if int(d.get(key, 0)) < 1:
		add.call(Problem.Severity.ERROR, "%s must be set and >= 1" % label)


# -- resource defs / nodes / loot / tools ----------------------------------------------------------

static func resource_defs(defs: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var loot := ValCheck.loot_table_names(content_dir)
	var tool_ids := _tool_id_ranges(content_dir)
	var skills := ValCheck.value_set(Catalog.skills)
	for name in defs:
		var d: Dictionary = defs[name]
		var loc := { "section": "Resource defs", "key": name }
		var add := func(msg: String) -> void: out.append(Problem.err(msg, name, loc))
		if not skills.has(str(d.get("skill", ""))):
			add.call("skill %s must be one of %s" % [d.get("skill", ""), ", ".join(skills.keys())])
		var respawn := int(d.get("respawn_ms", 0))
		if respawn < RESPAWN_MIN or respawn > RESPAWN_MAX:
			add.call("respawn_ms %d out of range [%d, 7 days]" % [respawn, RESPAWN_MIN])
		var hp := int(d.get("hp_max", 1))
		if hp < 1 or hp > 1000:
			add.call("hp_max %d out of range [1, 1000]" % hp)
		var lvl := int(d.get("level_required", 1))
		if lvl < 1 or lvl > MAX_LEVEL:
			add.call("level_required %d out of range [1, %d]" % [lvl, MAX_LEVEL])
		if int(d.get("xp", 0)) > 1000000:
			add.call("xp %d implausibly large (> 1,000,000)" % int(d.get("xp", 0)))
		var lt: Variant = d.get("loot", null)
		if lt != null and str(lt) != "" and not loot.has(str(lt)):
			add.call("loot table %s does not exist" % lt)
		var tool: Variant = d.get("tool", null)
		if tool != null and not tool_ids.has(int(tool)):
			add.call("tool item_id %d is not in any registered tool tier range" % int(tool))
	return out


static func resource_nodes(groups: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var def_names := {}
	var rd: Variant = JsonIO.load_file(content_dir + "/resource_defs.json")
	if typeof(rd) == TYPE_DICTIONARY and rd.has("defs"):
		for n in rd["defs"]:
			def_names[str(n)] = true
	var ids_seen := {}  # variant id -> group that first claimed it
	for gname in groups:
		var g: Dictionary = groups[gname]
		var loc := { "section": "Resource nodes", "key": gname }
		var add := func(msg: String) -> void: out.append(Problem.err(msg, gname, loc))
		var variants: Array = g.get("variants", [])
		if variants.is_empty():
			add.call("group has no variants")
			continue
		var ref_count := 0
		for v in variants:
			if str((v as Dictionary).get("ref", "")) != "":
				ref_count += 1
		if ref_count != 0 and ref_count != variants.size():
			add.call("group mixes ref and non-ref variants — it is either def-backed (all ref) or inline (none)")
		var def_backed := ref_count == variants.size()
		var total_weight := 0
		for idx in variants.size():
			var v: Dictionary = variants[idx]
			var weight := int(v.get("weight", 100))
			total_weight += weight
			if weight == 0:
				add.call("variant id %d: weight is zero — it would never roll" % int(v.get("id", 0)))
			var vid := int(v.get("id", 0))
			if ids_seen.has(vid):
				add.call("duplicate variant id %d (also in group %s)" % [vid, ids_seen[vid]])
			else:
				ids_seen[vid] = gname
			var ref := str(v.get("ref", ""))
			if ref != "" and not def_names.has(ref):
				add.call("variant id %d: unknown resource def %s" % [vid, ref])
		if total_weight == 0:
			add.call("variant weights sum to zero")
		var swing := int(g.get("swing_duration_ms", 0))
		if swing < SWING_MIN or swing > SWING_MAX:
			add.call("swing_duration_ms %d out of range [%d, %d]" % [swing, SWING_MIN, SWING_MAX])
		if def_backed:
			if g.has("respawn_ms"):
				add.call("def-backed group must not set group-level respawn_ms (it lives on each ResourceDef)")
		else:
			if not g.has("respawn_ms"):
				add.call("inline-obstacle group requires respawn_ms (the depletion cooldown in ms)")
			else:
				var rms := int(g["respawn_ms"])
				if rms < RESPAWN_MIN or rms > RESPAWN_MAX:
					add.call("respawn_ms %d out of range [%d, 7 days]" % [rms, RESPAWN_MIN])
	return out


static func loot_tables(tables: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var items := ValCheck.item_id_set(content_dir)
	for tname in tables:
		var entries: Array = tables[tname]
		var loc := { "section": "Loot tables", "key": tname }
		var add := func(msg: String) -> void: out.append(Problem.err(msg, tname, loc))
		if entries.is_empty():
			add.call("loot table is empty")
		for idx in entries.size():
			var e: Dictionary = entries[idx]
			var qmin := int(e.get("qty_min", 0))
			var qmax := int(e.get("qty_max", 0))
			if qmin < 1 or qmax < 1 or qmin > qmax:
				add.call("entry %d: qty_min=%d qty_max=%d (must be 1..=qty_max)" % [idx, qmin, qmax])
			if int(e.get("weight", 0)) == 0:
				add.call("entry %d: weight is zero (would never roll)" % idx)
			var iid := int(e.get("item_id", 0))
			if not items.has(iid):
				add.call("entry %d: item_id %d is not in the item database" % [idx, iid])
	return out


static func tool_categories(cats: Dictionary, content_dir: String) -> Array:
	var out: Array = []
	var items := ValCheck.item_id_set(content_dir)
	var tier_end := {}  # item_id -> max_id of the category that claimed it
	for cname in cats:
		var c: Dictionary = cats[cname]
		var loc := { "section": "Tool categories", "key": cname }
		var add := func(msg: String) -> void: out.append(Problem.err(msg, cname, loc))
		var lo := int(c.get("min_id", 0))
		var hi := int(c.get("max_id", 0))
		if lo < 1 or hi < 1 or lo > hi:
			add.call("invalid range [%d, %d]" % [lo, hi])
			continue
		var dmg: Dictionary = c.get("damage", {})
		for iid in range(lo, hi + 1):
			var pair: Variant = dmg.get(str(iid), null)
			if pair == null:
				add.call("missing damage entry for item_id %d" % iid)
				continue
			var dmin := int(pair[0])
			var dmax := int(pair[1])
			if dmin < 1 or dmin > dmax:
				add.call("item_id %d: damage [%d, %d] invalid (need 1 <= min <= max)" % [iid, dmin, dmax])
			if not items.has(iid):
				add.call("item_id %d is not in the item database" % iid)
			if tier_end.has(iid) and tier_end[iid] != hi:
				add.call("item_id %d is in two categories with different max_id (%d and %d)" % [iid, tier_end[iid], hi])
			tier_end[iid] = hi
	return out


# -- items / clothing / encounters / tips ----------------------------------------------------------

static func custom_items(arr: Array) -> Array:
	var out: Array = []
	var seen := {}
	for it in arr:
		var iid := int((it as Dictionary).get("item_id", 0))
		var nm := str((it as Dictionary).get("name", ""))
		var loc := { "section": "Items", "item_id": iid }
		if iid < 1000 or iid > 9999:
			out.append(Problem.err("item_id %d (%s): custom ids must be in 1000..9999" % [iid, nm], nm, loc))
		var itype := str((it as Dictionary).get("item_type", ""))
		if not (itype in CUSTOM_ITEM_TYPES):
			out.append(Problem.err("%s: invalid item_type %s (must be one of %s)" % [nm, itype, ", ".join(CUSTOM_ITEM_TYPES)], nm, loc))
		if seen.has(iid):
			out.append(Problem.err("duplicate item_id %d (%s collides with %s)" % [iid, nm, seen[iid]], nm, loc))
		seen[iid] = nm
	return out


static func clothing(raw: Dictionary) -> Array:
	var out: Array = []
	var all_ids := {}  # item_id -> display name
	for slot in raw:
		if typeof(raw[slot]) != TYPE_ARRAY or not CLOTHING_SLOT_RANGE.has(slot):
			continue
		var lo: int = CLOTHING_SLOT_RANGE[slot][0]
		var hi: int = CLOTHING_SLOT_RANGE[slot][1]
		for v in raw[slot]:
			var vd: Dictionary = v
			var nm := str(vd.get("name", "?"))
			var loc := { "section": "Clothing", "slot": slot }
			var base := int(vd.get("id_start", 0))
			var colors: Array = vd.get("colors", [])
			var count: int = maxi(1, colors.size())
			for k in count:
				var iid := base + k
				if iid < lo or iid > hi:
					out.append(Problem.err("id %d (%s) is outside %s range [%d, %d]" % [iid, nm, slot, lo, hi], nm, loc))
				if all_ids.has(iid):
					out.append(Problem.err("duplicate clothing id %d (%s collides with %s)" % [iid, nm, all_ids[iid]], nm, loc))
				all_ids[iid] = nm
	return out


static func encounters(entries: Array, content_dir: String) -> Array:
	var out: Array = []
	var species := ValCheck.value_set(Catalog.species_slugs)
	var loot := ValCheck.loot_table_names(content_dir)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var group := str(e.get("encounter", "?"))
		var loc := { "section": "Encounters", "group": group }
		var sp := str(e.get("pokemon", ""))
		if not species.has(sp):
			out.append(Problem.err("group %s: pokemon %s doesn't resolve to a known species" % [group, sp], group, loc))
		var hg: Variant = e.get("held_item_groups", "")
		if hg != null and str(hg) != "" and not loot.has(str(hg)):
			out.append(Problem.warn("group %s: held_item_groups %s is not a known loot table (ignored)" % [group, hg], group, loc))
		if int(e.get("min_level", 1)) > int(e.get("max_level", 1)):
			out.append(Problem.warn("group %s (%s): min_level > max_level" % [group, sp], group, loc))
	return out


static func tips(raw: Dictionary) -> Array:
	var out: Array = []
	var arr: Array = raw.get("tips", [])
	for i in arr.size():
		if str(arr[i]).strip_edges() == "":
			out.append(Problem.err("tips[%d] is empty" % i, "tips", { "section": "Tips", "index": i }))
	return out


# -- helpers ---------------------------------------------------------------------------------------

## {item_id: true} for every id covered by a tool_categories range (server checks a def's tool is in one).
static func _tool_id_ranges(content_dir: String) -> Dictionary:
	var s := {}
	var tc: Variant = JsonIO.load_file(content_dir + "/tool_categories.json")
	if typeof(tc) == TYPE_DICTIONARY and tc.has("categories"):
		for cname in tc["categories"]:
			var c: Dictionary = tc["categories"][cname]
			for iid in range(int(c.get("min_id", 0)), int(c.get("max_id", -1)) + 1):
				s[iid] = true
	return s
