class_name RomSetup
extends Control
## First-run screen: the designer supplies their FireRed, HGSS and Black/White ROMs (never shipped).
## When all three validate they're copied to user://roms/ and `setup_complete` fires. FireRed renders
## maps; HGSS supplies NPC sprites; B/W supplies Pokémon/item icons.

signal setup_complete

@onready var _firered_btn: Button = %FireredBtn
@onready var _hgss_btn: Button = %HgssBtn
@onready var _bw_btn: Button = %BwBtn
@onready var _firered_status: Label = %FireredStatus
@onready var _hgss_status: Label = %HgssStatus
@onready var _bw_status: Label = %BwStatus
@onready var _continue_btn: Button = %ContinueBtn
@onready var _firered_dialog: FileDialog = %FireredDialog
@onready var _hgss_dialog: FileDialog = %HgssDialog
@onready var _bw_dialog: FileDialog = %BwDialog

var _firered_path := ""
var _hgss_path := ""
var _bw_path := ""


func _ready() -> void:
	_firered_btn.pressed.connect(_firered_dialog.popup_centered)
	_hgss_btn.pressed.connect(_hgss_dialog.popup_centered)
	_bw_btn.pressed.connect(_bw_dialog.popup_centered)
	_firered_dialog.file_selected.connect(_on_firered)
	_hgss_dialog.file_selected.connect(_on_hgss)
	_bw_dialog.file_selected.connect(_on_bw)
	_continue_btn.pressed.connect(_on_continue)
	# Pre-fill anything already provisioned so a returning designer only supplies what's missing.
	if FileAccess.file_exists(RomManager.FIRERED_PATH):
		_firered_path = RomManager.FIRERED_PATH
		_firered_status.text = "firered.gba — already provisioned"
	if RomManager.is_hgss_loaded():
		_hgss_path = RomManager.HGSS_PATH
		_hgss_status.text = "hgss.nds — already provisioned"
	if RomManager.is_bw_loaded():
		_bw_path = RomManager.BW_PATH
		_bw_status.text = "bw.nds — already provisioned"
	_refresh_continue()


func _on_firered(path: String) -> void:
	var code := RomManager.try_load_firered(path)
	_firered_path = path if code != "" else ""
	_firered_status.text = "%s — valid (%s)" % [path.get_file(), code] if code != "" \
		else "%s — invalid or unrecognized ROM" % path.get_file()
	_refresh_continue()


func _on_hgss(path: String) -> void:
	var code := RomManager.try_load_hgss(path)
	_hgss_path = path if code != "" else ""
	_hgss_status.text = "%s — valid (%s)" % [path.get_file(), code] if code != "" \
		else "%s — invalid or unrecognized ROM" % path.get_file()
	_refresh_continue()


func _on_bw(path: String) -> void:
	var code := RomManager.try_load_bw(path)
	_bw_path = path if code != "" else ""
	_bw_status.text = "%s — valid (%s)" % [path.get_file(), code] if code != "" \
		else "%s — invalid or unrecognized ROM" % path.get_file()
	_refresh_continue()


func _refresh_continue() -> void:
	_continue_btn.disabled = _firered_path == "" or _hgss_path == "" or _bw_path == ""


func _on_continue() -> void:
	if RomManager.import_roms(_firered_path, _hgss_path, _bw_path):
		setup_complete.emit()
	else:
		_firered_status.text = "Failed to copy one or more ROM files"
