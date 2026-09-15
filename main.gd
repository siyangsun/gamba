extends Control

## Root: owns the 3D die world (in a SubViewport) and the three UI panels,
## and switches between them.

enum State { SHELF, EDITOR, ROLL }

const PRESET_DIR := "user://presets"

var _state: State = State.SHELF
var _shelf: ShelfPanel
var _editor: EditorPanel
var _roll: RollView
var _vpc: SubViewportContainer
var _die: Die


func _ready() -> void:
	randomize()
	theme = _build_theme()
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	_build_3d()
	_build_panels()
	_go_shelf()


# --- 3D world -------------------------------------------------------------

func _build_3d() -> void:
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	_vpc.gui_input.connect(_on_view_input)
	add_child(_vpc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	_vpc.add_child(vp)

	var world := Node3D.new()
	vp.add_child(world)

	var cam := Camera3D.new()
	cam.fov = 45
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 7, 8), Vector3.ZERO, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -40, 0)
	light.shadow_enabled = true
	world.add_child(light)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.60, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.ambient_light_energy = 0.6
	we.environment = env
	world.add_child(we)

	# felt arena: floor + four walls to keep the die on screen
	var ah := 3.5
	_add_box(world, Vector3(0, -0.25, 0), Vector3(ah * 2, 0.5, ah * 2),
		Color(0.28, 0.34, 0.28), true)
	_add_box(world, Vector3(-ah, 1, 0), Vector3(0.3, 3, ah * 2), Color.BLACK, false)
	_add_box(world, Vector3(ah, 1, 0), Vector3(0.3, 3, ah * 2), Color.BLACK, false)
	_add_box(world, Vector3(0, 1, ah), Vector3(ah * 2, 3, 0.3), Color.BLACK, false)
	_add_box(world, Vector3(0, 1, -ah), Vector3(ah * 2, 3, 0.3), Color.BLACK, false)

	_die = Die.new()
	world.add_child(_die)
	_die.position = Vector3(0, 0.5, 0)
	_die.landed.connect(_on_landed)


func _add_box(world: Node3D, pos: Vector3, size: Vector3, col: Color, visible: bool) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	if visible:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.55
		m.normal_enabled = true
		m.normal_texture = _pleather_normal_map()
		m.normal_scale = 1.4
		m.uv1_scale = Vector3(size.x, size.z, 1.0)
		mi.material_override = m
		sb.add_child(mi)
	world.add_child(sb)


## Procedural bump map (grainy, pock-marked) so the board reads as
## rubber/pleather instead of a flat color, with no texture asset needed.
func _pleather_normal_map() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.15
	noise.cellular_jitter = 1.0
	noise.fractal_octaves = 2

	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 3.0
	tex.noise = noise
	return tex


func _on_view_input(event: InputEvent) -> void:
	if _state != State.ROLL:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_roll.clear_result()
		_die.roll()


func _on_landed(value: int) -> void:
	if _state == State.ROLL:
		_roll.show_result(value)


# --- panels ---------------------------------------------------------------

func _build_panels() -> void:
	_shelf = ShelfPanel.new()
	_shelf.new_die_requested.connect(_go_editor_new)
	_shelf.preset_chosen.connect(_go_roll)
	_shelf.preset_delete_requested.connect(_on_delete_preset)
	add_child(_shelf)

	_editor = EditorPanel.new()
	_editor.saved.connect(_on_saved)
	_editor.cancelled.connect(_go_shelf)
	add_child(_editor)

	_roll = RollView.new()
	_roll.back_requested.connect(_go_shelf)
	_roll.delete_requested.connect(_on_delete_preset)
	add_child(_roll)


func _go_shelf() -> void:
	_state = State.SHELF
	_shelf.refresh(_load_presets())
	_set_visible(true, false, false)


func _go_editor_new() -> void:
	_state = State.EDITOR
	_editor.load_preset(DicePreset.new())
	_set_visible(false, true, false)


func _go_roll(preset: DicePreset) -> void:
	_state = State.ROLL
	_roll.set_preset(preset)
	_set_visible(false, false, true)


func _set_visible(shelf: bool, editor: bool, roll: bool) -> void:
	_shelf.visible = shelf
	_editor.visible = editor
	_roll.visible = roll
	_vpc.visible = roll


func _on_saved(preset: DicePreset) -> void:
	_save_preset(preset)
	_go_shelf()


func _on_delete_preset(preset: DicePreset) -> void:
	if preset.resource_path != "":
		DirAccess.remove_absolute(preset.resource_path)
	_go_shelf()


# --- persistence ----------------------------------------------------------

func _save_preset(preset: DicePreset) -> void:
	# ponytail: slug collisions overwrite; add unique suffix if renaming matters.
	var path := "%s/%s.tres" % [PRESET_DIR, _slug(preset.name)]
	ResourceSaver.save(preset, path)


func _load_presets() -> Array:
	var out: Array = []
	var d := DirAccess.open(PRESET_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tres"):
			var r = ResourceLoader.load("%s/%s" % [PRESET_DIR, f])
			if r is DicePreset:
				out.append(r)
	return out


func _slug(s: String) -> String:
	var out := ""
	var has_alnum := false
	for c in s.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			has_alnum = true
		else:
			out += "_"
	return out if has_alnum else "die"


# --- theme (XP-ish grey/beige, square corners) ----------------------------

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var beige := Color8(236, 233, 216)
	var dark := Color8(113, 111, 100)

	var panel := _flat(beige, dark, 2)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)

	var btn := _flat(Color8(225, 223, 205), dark, 2)
	t.set_stylebox("normal", "Button", btn)
	var hov := _flat(Color8(238, 236, 222), dark, 2)
	t.set_stylebox("hover", "Button", hov)
	var prs := _flat(Color8(200, 198, 182), dark, 2)
	t.set_stylebox("pressed", "Button", prs)
	t.set_color("font_color", "Button", Color8(20, 18, 10))

	var le := _flat(Color.WHITE, dark, 2)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _flat(Color.WHITE, Color8(0, 84, 227), 2))

	t.set_color("font_color", "Label", Color8(30, 28, 20))

	# header font: ornate display serif for page titles only
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", load("res://fonts/CinzelDecorative-Bold.ttf"))

	return t


func _flat(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(0)
	s.set_content_margin_all(8)
	return s
