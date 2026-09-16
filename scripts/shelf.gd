extends Control
class_name ShelfPanel

## Home screen overlay. The actual shelf is a 3D cupboard rendered behind
## this (see main.gd) with real dice on it, clicked directly to roll one;
## this Control is just the title bar and the button to make a new one.

signal new_die_requested


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks fall through to the cupboard

	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	bar.add_child(margin)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	margin.add_child(hb)

	var title := Label.new()
	title.text = "The Dice Shelf"
	title.theme_type_variation = "Header"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(title)

	var hint := Label.new()
	hint.text = "Click a die to roll it."
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(hint)

	var new_btn := Button.new()
	new_btn.text = "+  New Die"
	new_btn.pressed.connect(func(): new_die_requested.emit())
	hb.add_child(new_btn)
