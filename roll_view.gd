extends Control
class_name RollView

## Overlays the 3D die view. Left area is transparent so clicks reach the die;
## a side panel shows the result and the full face legend.

signal back_requested
signal edit_requested(preset: DicePreset)
signal delete_requested(preset: DicePreset)

var _preset: DicePreset
var _title: Label
var _result: Label
var _legend: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks fall through to the die

	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_top = 0.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -340
	side.offset_right = -12
	side.offset_top = 12
	side.offset_bottom = -12
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(side)

	var inner := MarginContainer.new()
	for s in ["left", "top", "right", "bottom"]:
		inner.add_theme_constant_override("margin_" + s, 16)
	side.add_child(inner)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	inner.add_child(vb)

	var back := Button.new()
	back.text = "< Back to Shelf"
	back.pressed.connect(func(): back_requested.emit())
	vb.add_child(back)

	_title = Label.new()
	_title.theme_type_variation = "Header"
	_title.add_theme_font_size_override("font_size", 24)
	vb.add_child(_title)

	var hint := Label.new()
	hint.text = "Click the die to roll."
	vb.add_child(hint)

	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 20)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_result)

	vb.add_child(HSeparator.new())

	var legend_title := Label.new()
	legend_title.text = "Faces"
	vb.add_child(legend_title)

	_legend = VBoxContainer.new()
	vb.add_child(_legend)

	vb.add_child(HSeparator.new())

	var edit_btn := Button.new()
	edit_btn.text = "Edit Die"
	edit_btn.pressed.connect(func(): edit_requested.emit(_preset))
	vb.add_child(edit_btn)

	var delete_btn := Button.new()
	delete_btn.text = "Delete Die"
	delete_btn.pressed.connect(_confirm_delete)
	vb.add_child(delete_btn)


func set_preset(p: DicePreset) -> void:
	_preset = p
	_title.text = p.name
	clear_result()
	for c in _legend.get_children():
		c.queue_free()
	for i in 6:
		var l := Label.new()
		l.text = "%d  —  %s" % [i + 1, _face_text(i + 1)]
		_legend.add_child(l)


func _confirm_delete() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete \"%s\"? This can't be undone." % _preset.name
	dlg.confirmed.connect(func(): delete_requested.emit(_preset))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func clear_result() -> void:
	_result.text = "Roll the die…"


func show_result(value: int) -> void:
	_result.text = "Result: %d\n%s" % [value, _face_text(value)]


func _face_text(value: int) -> String:
	if _preset == null or value < 1 or value > _preset.faces.size():
		return "(blank)"
	var t: String = _preset.faces[value - 1]
	return t if t != "" else "(blank)"
