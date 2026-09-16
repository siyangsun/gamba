extends RigidBody3D
class_name Die

## A standard 6-sided die built entirely in code (no art assets).
## Real physics: roll() flings it; when it settles, `landed(value)` fires with
## the face pointing up. Pip textures are generated procedurally.

signal landed(value: int)

const SIZE := 1.0
const FACE_TEX := 128

# grid positions (col,row in 0..2) of pips for each face value
const PIP_LAYOUT := {
	1: [Vector2(1, 1)],
	2: [Vector2(0, 0), Vector2(2, 2)],
	3: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
	4: [Vector2(0, 0), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)],
	5: [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)],
	6: [Vector2(0, 0), Vector2(2, 0), Vector2(0, 1), Vector2(2, 1), Vector2(0, 2), Vector2(2, 2)],
}

# face outward-normal (local) -> value. Opposite faces sum to 7.
const FACE_DEFS := [
	{"n": Vector3(1, 0, 0), "v": 1, "rot": Vector3(0, 90, 0)},
	{"n": Vector3(-1, 0, 0), "v": 6, "rot": Vector3(0, -90, 0)},
	{"n": Vector3(0, 1, 0), "v": 2, "rot": Vector3(-90, 0, 0)},
	{"n": Vector3(0, -1, 0), "v": 5, "rot": Vector3(90, 0, 0)},
	{"n": Vector3(0, 0, 1), "v": 3, "rot": Vector3(0, 0, 0)},
	{"n": Vector3(0, 0, -1), "v": 4, "rot": Vector3(0, 180, 0)},
]

const HIT_SOUNDS := 5
const TUMBLE_SOUNDS := 6
const HIT_COOLDOWN := 0.12  # ignore the machine-gun of contacts within one bounce
const HIT_SPEED := 2.0  # below this a contact is a soft tumble, not a hit

var _faces: Array = []  # [{v:int, n:Vector3}]
var _rolling := false
var _settle := 0.0
var _timeout := 0.0
var _hit_player: AudioStreamPlayer
var _tumble_player: AudioStreamPlayer
var _last_hit := -1.0


func _ready() -> void:
	mass = 1.0
	can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.6
	physics_material_override = pm

	# collision sound: hard impacts thud then tumble; soft contacts just tumble
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_contact)
	_hit_player = AudioStreamPlayer.new()
	_tumble_player = AudioStreamPlayer.new()
	add_child(_hit_player)
	add_child(_tumble_player)
	_hit_player.finished.connect(_play_tumble)  # tumble once after each hit

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * SIZE
	col.shape = box
	add_child(col)

	# ivory body slightly inset behind the face quads
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * SIZE * 0.99
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.88, 0.84, 0.73)
	bmat.roughness = 0.85
	body.material_override = bmat
	add_child(body)

	_build_faces()
	_self_check()


func _build_faces() -> void:
	var half := 0.5 * SIZE
	for d in FACE_DEFS:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(SIZE, SIZE) * 0.99
		mi.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = make_face_texture(int(d.v), FACE_TEX)
		mat.roughness = 0.8
		mat.normal_enabled = true
		mat.normal_texture = make_face_normalmap(int(d.v), FACE_TEX)
		mi.material_override = mat
		mi.position = (d.n as Vector3) * (half + 0.002)
		var r: Vector3 = d.rot
		mi.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		add_child(mi)
		_faces.append({"v": int(d.v), "n": d.n})


## Renders one die face (ivory grain + pips) at the given texture size.
## Shared with ShelfPanel, which uses it at a smaller size for shelf icons.
static func make_face_texture(value: int, tex_size: int) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	var ivory := Color(0.90, 0.86, 0.75)
	# faux-physical grain
	for y in tex_size:
		for x in tex_size:
			var n := randf() * 0.06 - 0.03
			img.set_pixel(x, y, Color(
				clampf(ivory.r + n, 0, 1),
				clampf(ivory.g + n, 0, 1),
				clampf(ivory.b + n, 0, 1)))
	var pip := Color(0.09, 0.08, 0.07)
	var radius := tex_size / 9.0
	for g: Vector2 in PIP_LAYOUT[value]:
		var cx: float = tex_size * (0.25 + 0.25 * g.x)
		var cy: float = tex_size * (0.25 + 0.25 * g.y)
		_fill_circle(tex_size, img, cx, cy, radius, pip)
	return ImageTexture.create_from_image(img)


## Normal map giving each pip a shallow spherical dimple (concave dish).
static func make_face_normalmap(value: int, tex_size: int) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.5, 1.0))  # flat surface
	var radius := tex_size / 9.0
	var depth := 2.5  # larger = flatter dimple; smaller = deeper. "slight" concavity
	for g: Vector2 in PIP_LAYOUT[value]:
		var cx: float = tex_size * (0.25 + 0.25 * g.x)
		var cy: float = tex_size * (0.25 + 0.25 * g.y)
		var y0 := maxi(0, int(cy - radius - 1))
		var y1 := mini(tex_size, int(cy + radius + 2))
		var x0 := maxi(0, int(cx - radius - 1))
		var x1 := mini(tex_size, int(cx + radius + 2))
		for y in range(y0, y1):
			for x in range(x0, x1):
				var d := Vector2(x - cx, y - cy)
				if d.length() > radius:
					continue
				# concave: horizontal normal points toward the center.
				# green flipped for Godot's OpenGL (Y-up) normal convention.
				var n := Vector3(-d.x / radius, d.y / radius, depth).normalized()
				img.set_pixel(x, y, Color(
					n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return ImageTexture.create_from_image(img)


static func _fill_circle(tex_size: int, img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var y0 := maxi(0, int(cy - r - 1))
	var y1 := mini(tex_size, int(cy + r + 2))
	var x0 := maxi(0, int(cx - r - 1))
	var x1 := mini(tex_size, int(cx + r + 2))
	for y in range(y0, y1):
		for x in range(x0, x1):
			if Vector2(x - cx, y - cy).length() <= r:
				img.set_pixel(x, y, col)


func roll() -> void:
	sleeping = false
	var t := global_transform
	t.origin = Vector3(randf_range(-0.5, 0.5), 3.0, randf_range(-0.5, 0.5))
	t.basis = Basis.from_euler(Vector3(
		randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU)))
	global_transform = t
	linear_velocity = Vector3(randf_range(-2, 2), 1.0, randf_range(-2, 2))
	angular_velocity = Vector3(
		randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	_rolling = true
	_settle = 0.0
	_timeout = 0.0


func _physics_process(delta: float) -> void:
	if not _rolling:
		return
	_timeout += delta
	var still := (linear_velocity.length() < 0.08
		and angular_velocity.length() < 0.08) or sleeping
	if still:
		_settle += delta
		if _settle > 0.35:
			_finish()
	else:
		_settle = 0.0
	if _timeout > 8.0:  # safety net if it never quite settles
		_finish()


func _on_contact(_body: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hit < HIT_COOLDOWN:
		return
	_last_hit = now
	if linear_velocity.length() < HIT_SPEED:
		_play_tumble()
	else:
		_hit_player.stream = load("res://assets/audio/fx/hit%d.mp3" % (randi() % HIT_SOUNDS + 1))
		_hit_player.play()  # tumble follows via the finished signal


func _play_tumble() -> void:
	_tumble_player.stream = load("res://assets/audio/fx/tumble%d.mp3" % (randi() % TUMBLE_SOUNDS + 1))
	_tumble_player.play()


func _finish() -> void:
	_rolling = false
	landed.emit(read_up_face())


func read_up_face() -> int:
	return _up_value(global_transform.basis)


func _up_value(basis: Basis) -> int:
	var best_v := 1
	var best_d := -INF
	for f in _faces:
		var d := (basis * (f.n as Vector3)).dot(Vector3.UP)
		if d > best_d:
			best_d = d
			best_v = int(f.v)
	return best_v


# ponytail: cheap wiring check instead of a full test file.
func _self_check() -> void:
	var vals := {}
	for f in _faces:
		vals[int(f.v)] = f.n
	assert(vals.size() == 6, "die must have 6 distinct face values")
	for v in range(1, 7):
		assert(vals.has(v), "missing face value %d" % v)
	for f in _faces:
		for g in _faces:
			if (f.n as Vector3) == -(g.n as Vector3):
				assert(int(f.v) + int(g.v) == 7, "opposite faces must sum to 7")
	# at identity the +Y face (value 2) points up
	assert(_up_value(Basis()) == 2, "up-face read is wired wrong")
