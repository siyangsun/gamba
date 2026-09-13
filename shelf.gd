extends Control
class_name ShelfPanel

## Home screen: browse saved dice presets, or make a new one.

signal new_die_requested
signal preset_chosen(preset: DicePreset)

var _grid: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	title.add_theme_font_size_override("font_size", 30)
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_grid = VBoxContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("separation", 6)
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
	for p in presets:
		var b := Button.new()
		b.text = p.name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): preset_chosen.emit(p))
		_grid.add_child(b)
