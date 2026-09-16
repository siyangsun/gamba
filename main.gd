extends Control

## Root: owns the 3D die world (in a SubViewport) and the three UI panels,
## and switches between them.

enum State { SHELF, EDITOR, ROLL }

const PRESET_DIR := "user://presets"

# roll view's side panel is docked on the right, so the arena is recentered
# left of world origin to read as centered in the space that's actually clear
const ARENA_CENTER := Vector3(-2.2, 0, 0)

# physics layers: arena and cupboard geometry are kept apart so an
# invisible-but-still-solid arena wall can't catch a shelf raycast (or vice versa)
const LAYER_SHELF := 1
const LAYER_ARENA := 2

# arena keeps its cool daylight-ish look; the shelf reads as a dim,
# candlelit room instead
const ARENA_BG_COLOR := Color(0.55, 0.60, 0.66)
const SHELF_BG_COLOR := Color8(46, 32, 22)
const SHELF_ZOOM := 1.0  # "zoomed out" from the tight framing
const SHELF_DIE_SCALE := 0.7  # dice shown ~30% smaller on the shelf
const SHELF_WIDTH_SCALE := 1.2  # shelves ~20% wider than the die grid needs

var _state: State = State.SHELF
var _shelf: ShelfPanel
var _editor: EditorPanel
var _roll: RollView
var _vpc: SubViewportContainer
var _world: Node3D
var _cam: Camera3D
var _env: Environment
var _die: Die
var _editing_path := ""  # resource_path of the preset being edited, "" when new
var _audio_controls: HBoxContainer

var _arena_root: Node3D
var _cupboard_root: Node3D
var _shelf_die_preset: Dictionary = {}  # Die -> DicePreset, for click-to-select


func _ready() -> void:
	randomize()
	theme = _build_theme()
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	_setup_audio_buses()
	_start_music()
	_build_3d()
	_build_cupboard()
	_build_panels()
	_build_audio_controls()
	_go_shelf()


## Music and SFX get their own buses so the mute buttons can toggle each
## independently without hunting down every AudioStreamPlayer's volume.
func _setup_audio_buses() -> void:
	for bus_name in ["Music", "Sfx"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


var _bgm: AudioStreamPlayer    # rule of the six, replayed once per loop
var _layer: AudioStreamPlayer  # companion track for this loop's residue mod 6
var _loop := 0                 # 0-indexed loop counter

# residue of loop % 6 -> companion track layered over rule of the six
const COMPANIONS := {
	1: "lord of one face",
	2: "snake eyes",
	3: "threes company",
	4: "quatrain",
	5: "i see a star",
}


func _start_music() -> void:
	_bgm = AudioStreamPlayer.new()
	_layer = AudioStreamPlayer.new()
	_bgm.bus = "Music"
	_layer.bus = "Music"
	add_child(_bgm)
	add_child(_layer)
	_bgm.volume_db = -6.0  # ~half loudness
	_layer.volume_db = -6.0
	# rule of the six doesn't self-loop; its finish is each loop boundary
	_bgm.finished.connect(func() -> void:
		_loop += 1
		_play_loop())
	_play_loop()


## Rule of the six always plays. On top, one companion for this loop's residue
## mod 6 (see COMPANIONS); residues with no entry play rule of the six alone.
func _play_loop() -> void:
	var base := load("res://assets/audio/bgm/rule of the six.mp3")
	base.loop = false  # so finished fires and drives the next loop
	_bgm.stream = base
	_bgm.play()
	var companion: String = COMPANIONS.get(_loop % 6, "")
	if companion != "":
		_layer.stream = load("res://assets/audio/bgm/%s.mp3" % companion)
		_layer.play()
	else:
		_layer.stop()


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

	_world = Node3D.new()
	vp.add_child(_world)

	_cam = Camera3D.new()
	_cam.fov = 45
	_world.add_child(_cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -40, 0)
	light.shadow_enabled = true
	_world.add_child(light)

	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = ARENA_BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.7, 0.7, 0.7)
	_env.ambient_light_energy = 0.6
	we.environment = _env
	_world.add_child(we)

	_arena_root = Node3D.new()
	_world.add_child(_arena_root)

	# rubber arena: floor + four walls to keep the die on screen. Wider than
	# deep and recentered left so it reads centered next to the side panel
	# docked on the right of the roll view.
	var hx := 4.5  # half-extent left/right
	var hz := 3.5  # half-extent near/far
	# arena geometry sits on its own collision layer so it can't intercept
	# raycasts aimed at the shelf while merely hidden (visible=false only
	# stops rendering, not physics) and vice versa
	_add_box(_arena_root, ARENA_CENTER + Vector3(0, -0.25, 0), Vector3(hx * 2, 0.5, hz * 2),
		Color(0.28, 0.34, 0.28), true, LAYER_ARENA)
	_add_box(_arena_root, ARENA_CENTER + Vector3(-hx, 1, 0), Vector3(0.3, 3, hz * 2), Color.BLACK, false, LAYER_ARENA)
	_add_box(_arena_root, ARENA_CENTER + Vector3(hx, 1, 0), Vector3(0.3, 3, hz * 2), Color.BLACK, false, LAYER_ARENA)
	_add_box(_arena_root, ARENA_CENTER + Vector3(0, 1, hz), Vector3(hx * 2, 3, 0.3), Color.BLACK, false, LAYER_ARENA)
	_add_box(_arena_root, ARENA_CENTER + Vector3(0, 1, -hz), Vector3(hx * 2, 3, 0.3), Color.BLACK, false, LAYER_ARENA)

	_die = Die.new()
	_arena_root.add_child(_die)
	_die.position = ARENA_CENTER + Vector3(0, 0.5, 0)
	_die.roll_center = Vector2(ARENA_CENTER.x, ARENA_CENTER.z)
	_die.landed.connect(_on_landed)
	_die.collision_layer = LAYER_ARENA
	_die.collision_mask = LAYER_ARENA


func _add_box(world: Node3D, pos: Vector3, size: Vector3, col: Color, visible: bool,
		collision_layer: int = LAYER_SHELF) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.collision_layer = collision_layer
	sb.collision_mask = collision_layer
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
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _state == State.ROLL:
		_roll.clear_result()
		_die.roll()
	elif _state == State.SHELF:
		_handle_shelf_click(event.position)


## Raycasts into the cupboard scene to find which die (if any) was clicked.
func _handle_shelf_click(screen_pos: Vector2) -> void:
	var space := _world.get_world_3d().direct_space_state
	var from := _cam.project_ray_origin(screen_pos)
	var to := from + _cam.project_ray_normal(screen_pos) * 50.0
	var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_SHELF)
	var hit := space.intersect_ray(query)
	var collider = hit.get("collider")
	if collider != null and _shelf_die_preset.has(collider):
		_go_roll(_shelf_die_preset[collider])


# --- cupboard shelf ---------------------------------------------------------
# The shelf screen is a real 3D cupboard in the same world as the roll arena;
# only one is visible (and gets the camera) at a time.

const TIER_COLS := 4
const DIE_SPACING := 1.7
const TIER_HEIGHT := 2.2
const PLANK_DEPTH := 1.15
const PLANK_THICKNESS := 0.15
const WOOD_COLOR := Color8(140, 100, 60)


func _build_cupboard() -> void:
	_cupboard_root = Node3D.new()
	_world.add_child(_cupboard_root)


## Rebuilds the cupboard frame, planks, and one real (frozen) Die per preset,
## sized to the current collection, then reframes the camera to fit it.
func _refresh_shelf_dice(presets: Array) -> void:
	for c in _cupboard_root.get_children():
		c.queue_free()
	_shelf_die_preset.clear()

	var tiers := maxi(3, ceili(float(presets.size()) / TIER_COLS))
	var half_w := (TIER_COLS * DIE_SPACING * 0.5 + 0.5) * SHELF_WIDTH_SCALE
	var base_y := 0.4
	var top_y := base_y + float(tiers - 1) * TIER_HEIGHT
	# frame spans from just under the bottom plank to well above the top
	# tier's dice, so the sides don't dangle below the lowest shelf
	var bottom_edge := base_y - 0.3
	var top_edge := top_y + 1.4
	var total_h := top_edge - bottom_edge
	var frame_y := (top_edge + bottom_edge) * 0.5

	_add_box(_cupboard_root, Vector3(0, frame_y, -PLANK_DEPTH * 0.5 - 0.05),
		Vector3(half_w * 2, total_h, 0.1), WOOD_COLOR, true)
	_add_box(_cupboard_root, Vector3(-half_w, frame_y, 0),
		Vector3(0.15, total_h, PLANK_DEPTH), WOOD_COLOR, true)
	_add_box(_cupboard_root, Vector3(half_w, frame_y, 0),
		Vector3(0.15, total_h, PLANK_DEPTH), WOOD_COLOR, true)

	for t in tiers:
		var plank_y := top_y - float(t) * TIER_HEIGHT
		_add_box(_cupboard_root, Vector3(0, plank_y, 0),
			Vector3(half_w * 2, PLANK_THICKNESS, PLANK_DEPTH), WOOD_COLOR, true)

	if presets.is_empty():
		_cupboard_root.add_child(
			_make_label3d("No dice yet — create one to start rolling.",
				Vector3(0, base_y + PLANK_THICKNESS * 0.5 + 0.5, PLANK_DEPTH * 0.5 - 0.1)))

	for i in presets.size():
		var t := i / TIER_COLS
		var cols_here := mini(TIER_COLS, presets.size() - t * TIER_COLS)
		var col_in_tier := i % TIER_COLS
		var x := (col_in_tier - float(cols_here - 1) * 0.5) * DIE_SPACING
		var plank_y := top_y - float(t) * TIER_HEIGHT
		var die_y := plank_y + PLANK_THICKNESS * 0.5 + 0.5 * SHELF_DIE_SCALE

		var p: DicePreset = presets[i]
		var d := Die.new()
		_cupboard_root.add_child(d)
		d.freeze = true
		d.position = Vector3(x, die_y, -0.15)
		d.rotation_degrees = Vector3(0, 25, 0)
		d.scale = Vector3.ONE * SHELF_DIE_SCALE
		d.set_skin(p.theme)
		_shelf_die_preset[d] = p
		# name placard sits on the plank's very front lip, clear of the die
		# in front of it (not dangling into the tier below either)
		_cupboard_root.add_child(_make_label3d(p.name,
			Vector3(x, plank_y + PLANK_THICKNESS * 0.5 + 0.12, PLANK_DEPTH * 0.5 - 0.03)))

	# pull the camera back/up as the collection grows so it still all fits;
	# SHELF_ZOOM scales the whole shot back further for breathing room
	_cam.fov = 32
	var target_y := top_y * 0.675 + 0.8
	var cam_dist := (8.0 + float(tiers - 1) * 2.8) * SHELF_ZOOM
	var cam_height := target_y + 3.4 * SHELF_ZOOM
	_cam.look_at_from_position(Vector3(0, cam_height, cam_dist), Vector3(0, target_y, 0), Vector3.UP)
	_env.background_color = SHELF_BG_COLOR


func _make_label3d(txt: String, pos: Vector3) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 40
	lbl.pixel_size = 0.0055
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 12
	return lbl


func _on_landed(value: int) -> void:
	if _state == State.ROLL:
		_roll.show_result(value)


# --- panels ---------------------------------------------------------------

func _build_panels() -> void:
	_shelf = ShelfPanel.new()
	_shelf.new_die_requested.connect(_go_editor_new)
	add_child(_shelf)

	_editor = EditorPanel.new()
	_editor.saved.connect(_on_saved)
	_editor.cancelled.connect(_go_shelf)
	add_child(_editor)

	_roll = RollView.new()
	_roll.back_requested.connect(_go_shelf)
	_roll.edit_requested.connect(_go_editor_edit)
	_roll.delete_requested.connect(_on_delete_preset)
	add_child(_roll)


## Persistent mute toggles, corner-docked, drawn above every screen except
## the editor (whose form fills the corner they'd otherwise sit in).
func _build_audio_controls() -> void:
	_audio_controls = HBoxContainer.new()
	_audio_controls.add_theme_constant_override("separation", 8)
	add_child(_audio_controls)

	_audio_controls.add_child(_make_mute_button("Music", "Music"))
	_audio_controls.add_child(_make_mute_button("SFX", "Sfx"))

	# set after children exist so the container's min-size (used to place a
	# non-full-rect anchor preset) reflects real content, not zero
	_audio_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)


func _make_mute_button(label: String, bus_name: String) -> Button:
	var b := Button.new()
	b.text = "%s: On" % label
	b.pressed.connect(func():
		var idx := AudioServer.get_bus_index(bus_name)
		var muted := not AudioServer.is_bus_mute(idx)
		AudioServer.set_bus_mute(idx, muted)
		b.text = "%s: %s" % [label, "Off" if muted else "On"])
	return b


func _go_shelf() -> void:
	_state = State.SHELF
	_refresh_shelf_dice(_load_presets())
	_set_visible(true, false, false)


func _go_editor_new() -> void:
	_state = State.EDITOR
	_editing_path = ""
	_editor.load_preset(DicePreset.new())
	_set_visible(false, true, false)


func _go_editor_edit(preset: DicePreset) -> void:
	_state = State.EDITOR
	_editing_path = preset.resource_path
	_editor.load_preset(preset)
	_set_visible(false, true, false)


func _go_roll(preset: DicePreset) -> void:
	_state = State.ROLL
	_die.set_skin(preset.theme)
	_roll.set_preset(preset)
	_cam.fov = 45
	_cam.look_at_from_position(Vector3(0, 7, 8), Vector3.ZERO, Vector3.UP)
	_env.background_color = ARENA_BG_COLOR
	_set_visible(false, false, true)


func _set_visible(shelf: bool, editor: bool, roll: bool) -> void:
	_shelf.visible = shelf
	_editor.visible = editor
	_roll.visible = roll
	_vpc.visible = shelf or roll
	_arena_root.visible = roll
	_cupboard_root.visible = shelf
	# tucked in the bottom-left corner; hidden in the editor since its form
	# fills nearly the whole screen and would sit right under the buttons
	_audio_controls.visible = not editor


func _on_saved(preset: DicePreset) -> void:
	var was_editing := _editing_path != ""
	# a rename during edit changes the slug; drop the old file so it isn't orphaned
	var new_path := "%s/%s.tres" % [PRESET_DIR, _slug(preset.name)]
	if _editing_path != "" and _editing_path != new_path:
		DirAccess.remove_absolute(_editing_path)
	_editing_path = ""
	_save_preset(preset)
	# editing an existing die returns to rolling it, not all the way back to
	# the shelf; only a brand-new die (made from the shelf) lands on the shelf
	if was_editing:
		_go_roll(preset)
	else:
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
			# CACHE_MODE_REPLACE: without it, re-saving a preset mid-session
			# (e.g. editing) still returns the stale pre-edit object here.
			var r = ResourceLoader.load(
				"%s/%s" % [PRESET_DIR, f], "", ResourceLoader.CACHE_MODE_REPLACE)
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


# --- theme (XP-ish grey/beige, slightly rounded corners) ------------------

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	# body font: warm old-style serif for everything except page titles
	t.default_font = load("res://fonts/EBGaramond-Regular.ttf")
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
	t.set_color("font_color", "LineEdit", Color8(30, 28, 20))

	t.set_color("font_color", "Label", Color8(30, 28, 20))

	t.set_stylebox("normal", "OptionButton", btn)
	t.set_stylebox("hover", "OptionButton", hov)
	t.set_stylebox("pressed", "OptionButton", prs)
	t.set_color("font_color", "OptionButton", Color8(20, 18, 10))
	t.set_color("font_color", "PopupMenu", Color8(20, 18, 10))

	# header font: ornate display serif for page titles only
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", load("res://fonts/CinzelDecorative-Bold.ttf"))

	return t


func _flat(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(bw)
	s.border_color = border
	s.set_corner_radius_all(3)
	s.set_content_margin_all(8)
	return s
