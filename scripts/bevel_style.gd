class_name BevelStyle
extends StyleBox

## Chunky two-tier 3D bevel in the Windows 95/2000 style: an outer ring of
## pure highlight/dark-shadow, then a second inner ring one pixel in, framing
## a flat face. `sunken` swaps which corner reads "lit" to fake a pressed
## button or an inset text field instead of a raised button.

@export var bg_color: Color = Color8(196, 188, 168)
@export var highlight: Color = Color8(250, 246, 234)
@export var light: Color = Color8(220, 210, 184)
@export var shadow: Color = Color8(138, 124, 98)
@export var dark_shadow: Color = Color8(76, 64, 46)
@export var sunken: bool = false
@export var bevel_width: int = 2  # 1 = thin single ring, 2 = classic chunky double ring


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	RenderingServer.canvas_item_add_rect(to_canvas_item, rect, bg_color)

	var outer_tl := dark_shadow if sunken else highlight
	var outer_br := highlight if sunken else dark_shadow
	_ring(to_canvas_item, rect, outer_tl, outer_br)

	if bevel_width >= 2 and rect.size.x > 2 and rect.size.y > 2:
		var inner_tl := shadow if sunken else light
		var inner_br := light if sunken else shadow
		_ring(to_canvas_item, rect.grow(-1), inner_tl, inner_br)


func _ring(to_canvas_item: RID, rect: Rect2, top_left: Color, bottom_right: Color) -> void:
	var p := rect.position
	var s := rect.size
	RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p, Vector2(s.x, 1)), top_left)
	RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p, Vector2(1, s.y)), top_left)
	RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p.x, p.y + s.y - 1, s.x, 1), bottom_right)
	RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(p.x + s.x - 1, p.y, 1, s.y), bottom_right)
