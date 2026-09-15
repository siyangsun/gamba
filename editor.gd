extends Control
class_name EditorPanel

## Assign a meaning to each of the 6 faces, name the die, save it.

signal saved(preset: DicePreset)
signal cancelled

var _name: LineEdit
var _faces: Array[LineEdit] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var inner := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(inner)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	inner.add_child(vb)

	var title := Label.new()
	title.text = "Assign the Faces"
	title.theme_type_variation = "Header"
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)

	vb.add_child(_row("Name", func(le): _name = le))

	for i in 6:
		var idx := i
		vb.add_child(_row("Face %d" % (idx + 1), func(le): _faces.append(le)))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	vb.add_child(buttons)
	var save := Button.new()
	save.text = "Save Die"
	save.pressed.connect(_on_save)
	buttons.add_child(save)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): cancelled.emit())
	buttons.add_child(cancel)


func _row(label_text: String, register: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 90
	row.add_child(l)
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(le)
	register.call(le)
	return row


func load_preset(p: DicePreset) -> void:
	while p.faces.size() < 6:
		p.faces.append("")
	_name.text = p.name if p.name != "Untitled Die" else ""
	for i in 6:
		_faces[i].text = p.faces[i]


func _on_save() -> void:
	var p := DicePreset.new()
	var n := _name.text.strip_edges()
	p.name = n if n != "" else "Untitled Die"
	var arr: Array[String] = []
	for le in _faces:
		arr.append(le.text.strip_edges())
	p.faces = arr
	saved.emit(p)
