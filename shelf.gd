extends Control
class_name ShelfPanel

## Home screen: a scrollable wooden bookshelf of saved dice, each shown as a
## small icon of its own face art, or a button to make a new one.

signal new_die_requested
signal preset_chosen(preset: DicePreset)
signal preset_delete_requested(preset: DicePreset)

const COLS := 6
const ICON_TEX := 56
const TILE_SIZE := Vector2(90, 116)

var _grid: VBoxContainer


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
	vb.add_theme_constant_override("separation", 12)
	inner.add_child(vb)

	var title := Label.new()
	title.text = "The Dice Shelf"
	title.theme_type_variation = "Header"
	title.add_theme_font_size_override("font_size", 30)
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_grid = VBoxContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("separation", 14)
	scroll.add_child(_grid)

	var new_btn := Button.new()
	new_btn.text = "+  New Die"
	new_btn.pressed.connect(func(): new_die_requested.emit())
	vb.add_child(new_btn)


func refresh(presets: Array) -> void:
	for c in _grid.get_children():
		c.queue_free()
	if presets.is_empty():
		var empty := Label.new()
		empty.text = "No dice yet — create one to start rolling."
		_grid.add_child(empty)
		return
	var i := 0
	while i < presets.size():
		_grid.add_child(_make_shelf_row(presets.slice(i, mini(i + COLS, presets.size()))))
		i += COLS


func _make_shelf_row(row_presets: Array) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _wood_style())
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	for p in row_presets:
		hb.add_child(_make_tile(p))
	return row


func _make_tile(p: DicePreset) -> Control:
	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.flat = true
	tile.pressed.connect(func(): preset_chosen.emit(p))
	tile.tooltip_text = p.name

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	tile.add_child(vb)

	var icon := TextureRect.new()
	icon.texture = Die.make_face_texture(_icon_face(p), ICON_TEX, p.theme)
	icon.custom_minimum_size = Vector2(ICON_TEX, ICON_TEX)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(icon)

	var label := Label.new()
	label.text = p.name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TILE_SIZE.x - 10
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(label)

	var del := Button.new()
	del.text = "×"
	del.custom_minimum_size = Vector2(22, 22)
	del.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	del.pressed.connect(_confirm_delete.bind(p))
	tile.add_child(del)

	return tile


# a die always shows the same face on the shelf, picked from its name so it
# doesn't flicker between different pip counts on every refresh
func _icon_face(p: DicePreset) -> int:
	return (absi(p.name.hash()) % 6) + 1


func _wood_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color8(176, 141, 87)
	s.border_color = Color8(110, 82, 48)
	s.set_border_width_all(2)
	s.border_width_bottom = 8
	s.set_corner_radius_all(2)
	s.set_content_margin_all(10)
	return s


func _confirm_delete(p: DicePreset) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete \"%s\"? This can't be undone." % p.name
	dlg.confirmed.connect(func(): preset_delete_requested.emit(p))
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
