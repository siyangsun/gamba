extends Control
class_name EditorPanel

## Assign a meaning to each of the 6 faces, name the die, save it.

signal saved(preset: DicePreset)
signal cancelled

var _name: LineEdit
var _faces: Array[LineEdit] = []
var _skin_opt: OptionButton
var _skin_keys: Array = []
var _numbering_opt: OptionButton
var _numbering_keys: Array = []
var _preview: TextureRect


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

	vb.add_child(_skin_row())
	vb.add_child(_numbering_row())

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


func _skin_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "Skin"
	l.custom_minimum_size.x = 90
	row.add_child(l)
	# SKINS is pre-ordered by category, so a run of same-category entries
	# becomes one section; _skin_keys gets a "" placeholder per separator so
	# its indices still line up with the OptionButton's (separators occupy
	# a slot but are never selectable).
	_skin_keys = []
	_skin_opt = OptionButton.new()
	var last_category := ""
	for key in Die.SKINS.keys():
		var skin: Dictionary = Die.SKINS[key]
		var category: String = skin.get("category", "")
		if category != last_category:
			_skin_opt.add_separator(Die.CATEGORIES.get(category, String(category).capitalize()))
			_skin_keys.append("")
			last_category = category
		_skin_opt.add_item(skin.get("label", String(key).capitalize()))
		_skin_keys.append(key)
	_skin_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_opt.item_selected.connect(func(_i): _update_preview())
	row.add_child(_skin_opt)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(48, 48)
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_preview)
	return row


func _numbering_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "Numbering"
	l.custom_minimum_size.x = 90
	row.add_child(l)
	_numbering_keys = Die.NUMBERING_STYLES
	_numbering_opt = OptionButton.new()
	for key in _numbering_keys:
		_numbering_opt.add_item(String(key).capitalize())
	_numbering_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_numbering_opt.item_selected.connect(func(_i): _update_preview())
	row.add_child(_numbering_opt)
	return row


func _current_skin() -> String:
	return _skin_keys[maxi(0, _skin_opt.selected)]


func _current_numbering() -> String:
	return _numbering_keys[maxi(0, _numbering_opt.selected)]


func _update_preview() -> void:
	_preview.texture = Die.make_face_texture(5, 48, _current_skin(), _current_numbering())


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
	var si := _skin_keys.find(p.theme)
	_skin_opt.select(si if si >= 0 else 0)
	var ni := _numbering_keys.find(p.numbering)
	_numbering_opt.select(ni if ni >= 0 else 0)
	_update_preview()


func _on_save() -> void:
	var p := DicePreset.new()
	var n := _name.text.strip_edges()
	p.name = n if n != "" else "Untitled Die"
	var arr: Array[String] = []
	for le in _faces:
		arr.append(le.text.strip_edges())
	p.faces = arr
	p.theme = _current_skin()
	p.numbering = _current_numbering()
	saved.emit(p)
