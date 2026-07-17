class_name Problem
extends RefCounted
## One validation finding. ERROR means the game-server/generator would fail-loud on this data (so the
## editor blocks Save on it); WARNING means the data loads but is silently broken at runtime (unresolved
## warp target, uncatalogued resource node, degenerate zone polygon, …). `context` is a short human
## locator string shown in the panel; `locator` is an opaque payload the shell uses to navigate to the
## offending thing (a map model object, or a {section, key/index} for a dataset record).

enum Severity { ERROR, WARNING }

var severity: Severity
var message: String
var context: String
var locator: Variant


static func err(message: String, context := "", locator: Variant = null) -> Problem:
	return _make(Severity.ERROR, message, context, locator)


static func warn(message: String, context := "", locator: Variant = null) -> Problem:
	return _make(Severity.WARNING, message, context, locator)


static func _make(sev: Severity, message: String, context: String, locator: Variant) -> Problem:
	var p := Problem.new()
	p.severity = sev
	p.message = message
	p.context = context
	p.locator = locator
	return p


## Number of ERROR-severity problems in a list (Save is blocked when this is > 0).
static func error_count(problems: Array) -> int:
	var n := 0
	for p in problems:
		if (p as Problem).severity == Severity.ERROR:
			n += 1
	return n
