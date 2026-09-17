extends RigidBody3D
class_name Die

## A standard 6-sided die built entirely in code (no art assets).
## Real physics: roll() flings it; when it settles, `landed(value)` fires with
## the face pointing up. Pip textures are generated procedurally.

signal landed(value: int)

const SIZE := 1.0
const FACE_TEX := 128

# selectable die skins: body tint, face (grain base), pip color, and material type.
# material types: "ivory" (warm tint near edges), "stone" (spiral-veined, monochrome),
# "gem" (multi-shade marbling + cracks), "metal" (shiny, brushed),
# "acrylic" (smooth glossy plastic, no marbling/tint).
const SKINS := {
	"ivory": {"body": Color(0.88, 0.84, 0.73), "face": Color(0.90, 0.86, 0.75), "pip": Color(0.09, 0.08, 0.07), "material": "ivory"},
	"onyx": {"body": Color(0.12, 0.12, 0.13), "face": Color(0.16, 0.16, 0.17), "pip": Color(0.90, 0.90, 0.92), "material": "gem"},
	"graphite": {"body": Color(0.26, 0.26, 0.28), "face": Color(0.31, 0.31, 0.33), "pip": Color(0.88, 0.88, 0.90), "material": "stone"},
	"ruby": {"body": Color(0.50, 0.05, 0.08), "face": Color(0.60, 0.08, 0.11), "pip": Color(0.85, 0.68, 0.25), "material": "gem"},
	"jade": {"body": Color(0.05, 0.35, 0.22), "face": Color(0.08, 0.42, 0.28), "pip": Color(0.95, 0.89, 0.70), "material": "gem"},
	"gold": {"body": Color(0.60, 0.47, 0.12), "face": Color(0.72, 0.57, 0.16), "pip": Color(0.10, 0.08, 0.04), "material": "metal"},
	"sapphire": {"body": Color(0.08, 0.15, 0.50), "face": Color(0.10, 0.20, 0.62), "pip": Color(0.85, 0.89, 0.97), "material": "gem"},
	"acrylic": {"body": Color(0.93, 0.93, 0.95), "face": Color(0.96, 0.96, 0.98), "pip": Color(0.05, 0.05, 0.06), "material": "acrylic"},
}

# grid positions (col,row in 0..2) of pips for each face value
const PIP_LAYOUT := {
	1: [Vector2(1, 1)],
	2: [Vector2(0, 0), Vector2(2, 2)],
	3: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 2)],
	4: [Vector2(0, 0), Vector2(2, 0), Vector2(0, 2), Vector2(2, 2)],
	5: [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)],
	6: [Vector2(0, 0), Vector2(2, 0), Vector2(0, 1), Vector2(2, 1), Vector2(0, 2), Vector2(2, 2)],
}

# selectable face-marking styles: dots (pips), arabic numbers, roman numerals
const NUMBERING_STYLES := ["dots", "numbers", "numerals"]

# 5x7 bitmap glyphs for the "numbers" style
const DIGIT_GLYPHS := {
	1: ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	2: [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	3: [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
	4: ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	5: ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	6: [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
}

# bitmap glyphs for the "numerals" style, composed as sequences of I/V below
const ROMAN_GLYPHS := {
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"V": ["#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
}
const ROMAN_SEQUENCE := {
	1: ["I"], 2: ["I", "I"], 3: ["I", "I", "I"],
	4: ["I", "V"], 5: ["V"], 6: ["V", "I"],
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

var skin_name := "ivory"
var numbering_style := "dots"
var roll_center := Vector2.ZERO  # world x/z the die is tossed above and settles near
var _faces: Array = []  # [{v:int, n:Vector3, mi:MeshInstance3D}]
var _body: MeshInstance3D
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
	_hit_player.bus = "Sfx"
	_tumble_player.bus = "Sfx"
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
	bmat.albedo_color = SKINS[skin_name].body
	_apply_material_type(bmat, skin_name)
	body.material_override = bmat
	add_child(body)
	_body = body

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
		mat.albedo_texture = make_face_texture(int(d.v), FACE_TEX, skin_name, numbering_style)
		_apply_material_type(mat, skin_name)
		_apply_pip_matte(mat, int(d.v), skin_name, numbering_style)
		mat.normal_enabled = true
		mat.normal_texture = make_face_normalmap(int(d.v), FACE_TEX, numbering_style)
		mat.normal_scale = 1.4
		mi.material_override = mat
		mi.position = (d.n as Vector3) * (half + 0.002)
		var r: Vector3 = d.rot
		mi.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))
		add_child(mi)
		_faces.append({"v": int(d.v), "n": d.n, "mi": mi})


## Re-tint body + face art to the named skin (falls back to ivory).
func set_skin(name: String) -> void:
	skin_name = name if SKINS.has(name) else "ivory"
	_refresh_faces()


## Re-renders face art in the named marking style (falls back to dots).
func set_numbering(name: String) -> void:
	numbering_style = name if NUMBERING_STYLES.has(name) else "dots"
	_refresh_faces()


func _refresh_faces() -> void:
	if _body == null:
		return  # not built yet; _ready() will use current skin_name/numbering_style
	var bmat := _body.material_override as StandardMaterial3D
	bmat.albedo_color = SKINS[skin_name].body
	_apply_material_type(bmat, skin_name)
	for f in _faces:
		var mat := (f.mi as MeshInstance3D).material_override as StandardMaterial3D
		mat.albedo_texture = make_face_texture(int(f.v), FACE_TEX, skin_name, numbering_style)
		_apply_material_type(mat, skin_name)
		_apply_pip_matte(mat, int(f.v), skin_name, numbering_style)
		mat.normal_texture = make_face_normalmap(int(f.v), FACE_TEX, numbering_style)


## Base (non-pip) surface roughness for each material type. Single source of
## truth shared between the material scalar and the per-face roughness map.
static func _base_roughness(mat_type: String) -> float:
	match mat_type:
		"metal": return 0.1
		"stone": return 0.25
		"gem": return 0.12
		"acrylic": return 0.12
		_: return 0.8


## Applies per-material-type shading (shiny metal, glossy stone/gem, or
## matte ivory) to a face or body material. Leaves albedo_color/texture alone
## except for gems, which also get a translucent alpha.
static func _apply_material_type(mat: StandardMaterial3D, skin_name: String) -> void:
	var skin: Dictionary = SKINS.get(skin_name, SKINS["ivory"])
	var mat_type: String = skin.get("material", "ivory")
	mat.roughness = _base_roughness(mat_type)
	match mat_type:
		"metal":
			# environment has no reflection probe, so a fully metallic BRDF
			# would render near-black; lean on a tight specular highlight instead.
			mat.metallic = 0.35
			mat.metallic_specular = 1.0
		"stone":
			mat.metallic = 0.05
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.5
		"gem":
			mat.metallic = 0.02
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.8
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.82
			# bend what's behind instead of just fading it, so it reads as a
			# gem catching/refracting light rather than plain see-through
			mat.refraction_enabled = true
			mat.refraction_scale = 0.09
		"acrylic":
			mat.metallic = 0.0
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.4
		_:
			mat.metallic = 0.0


## Kills the shiny highlight/clearcoat over the markings specifically, so
## dots/digits/numerals read as matte rather than catching the same polish
## as the surrounding face. clearcoat_texture has a fixed R=strength/
## G=glossiness convention (no channel selector), so roughness is packed
## into blue instead.
static func _apply_pip_matte(mat: StandardMaterial3D, value: int, skin_name: String, numbering_style: String) -> void:
	var skin: Dictionary = SKINS.get(skin_name, SKINS["ivory"])
	var mat_type: String = skin.get("material", "ivory")
	var detail := make_face_detail_texture(value, FACE_TEX, _base_roughness(mat_type), numbering_style)
	mat.roughness = 1.0  # texture now fully controls roughness, per pixel
	mat.roughness_texture = detail
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	if mat.clearcoat_enabled:
		mat.clearcoat_texture = detail


## R = clearcoat strength (1 = configured amount, 0 = none at the markings).
## G = clearcoat glossiness (left at full everywhere).
## B = absolute roughness (base_roughness, or matte at the markings).
static func make_face_detail_texture(value: int, tex_size: int, base_roughness: float, numbering_style: String) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 1.0, base_roughness))
	_paint_markings(img, value, numbering_style, tex_size, Color(0.0, 1.0, 0.92))
	return ImageTexture.create_from_image(img)


## Draws the face marking (dot pips, a digit, or a roman numeral) in the
## given color. Shared by the albedo pass (pip color) and the matte-mask
## pass (roughness/clearcoat override), so both stay perfectly aligned.
static func _paint_markings(img: Image, value: int, numbering_style: String, tex_size: int, col: Color) -> void:
	match numbering_style:
		"numbers":
			var rows: Array = DIGIT_GLYPHS[value]
			var cell := maxi(1, tex_size / 14)
			var w := 5 * cell
			var h := 7 * cell
			_draw_bitmap_glyph(img, rows, (tex_size - w) / 2, (tex_size - h) / 2, cell, col)
		"numerals":
			var glyphs: Array = ROMAN_SEQUENCE[value]
			var cell := maxi(1, tex_size / 16)
			var total_cols := 0
			for gk in glyphs:
				total_cols += String(ROMAN_GLYPHS[gk][0]).length()
			total_cols += glyphs.size() - 1  # 1-col gap between glyphs
			var h := 7 * cell
			var ox := (tex_size - total_cols * cell) / 2
			var oy := (tex_size - h) / 2
			for gk in glyphs:
				_draw_bitmap_glyph(img, ROMAN_GLYPHS[gk], ox, oy, cell, col)
				ox += (String(ROMAN_GLYPHS[gk][0]).length() + 1) * cell
		_:
			var radius := tex_size / 9.0
			for g: Vector2 in PIP_LAYOUT[value]:
				var cx: float = tex_size * (0.25 + 0.25 * g.x)
				var cy: float = tex_size * (0.25 + 0.25 * g.y)
				_fill_circle(tex_size, img, cx, cy, radius, col)


## Blits a bitmap glyph (an array of '#'/'.' row strings) at cell resolution.
static func _draw_bitmap_glyph(img: Image, rows: Array, ox: int, oy: int, cell: int, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			if row[rx] != "#":
				continue
			for py in cell:
				for px in cell:
					var x := ox + rx * cell + px
					var y := oy + ry * cell + py
					if x >= 0 and x < w and y >= 0 and y < h:
						img.set_pixel(x, y, col)


## Renders one die face (grain/marbling/brushing + markings) at the given
## texture size. Shared with EditorPanel's preview, which uses it smaller.
static func make_face_texture(value: int, tex_size: int, skin_name := "ivory", numbering_style := "dots") -> ImageTexture:
	var skin: Dictionary = SKINS.get(skin_name, SKINS["ivory"])
	var face: Color = skin.face
	var mat_type: String = skin.get("material", "ivory")
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	for y in tex_size:
		for x in tex_size:
			var col := face
			match mat_type:
				"stone":
					# spiral veining: a few overlapping sine veins, lighter than the base
					var u := float(x) / tex_size
					var v := float(y) / tex_size
					var vein := sin((u * 6.0 + v * 3.0 + sin(v * 9.0) * 1.5) * PI)
					var streak := clampf(absf(vein), 0.0, 1.0)
					streak = pow(1.0 - streak, 6.0)  # narrow bright veins
					col = face.lerp(Color(1, 1, 1), streak * 0.35)
					var grain := randf() * 0.03 - 0.015
					col = Color(col.r + grain, col.g + grain, col.b + grain)
				"gem":
					# smoky depth marbling: layered turbulence blends the base color
					# toward near-black in cloudy bands, unlike the stone spiral veins
					var u := float(x) / tex_size
					var v := float(y) / tex_size
					var n1 := sin((u * 4.0 + v * 5.5) * PI + sin(v * 7.0) * 2.0)
					var n2 := sin((u * 9.5 - v * 3.0) * PI + sin(u * 6.0) * 1.5)
					var depth := clampf((n1 * 0.6 + n2 * 0.4) * 0.5 + 0.5, 0.0, 1.0)
					col = face.lerp(Color(0.03, 0.03, 0.05), pow(depth, 2.2) * 0.6)
					var grain := randf() * 0.02 - 0.01
					col = Color(col.r + grain, col.g + grain, col.b + grain)
				"metal":
					# brushed metal: fine directional streaks, low noise
					var streak := sin(float(x) * 1.3 + float(y) * 0.05) * 0.04
					col = Color(
						clampf(face.r + streak, 0, 1),
						clampf(face.g + streak, 0, 1),
						clampf(face.b + streak, 0, 1))
				"acrylic":
					# smooth injection-molded plastic: almost no grain
					var n := randf() * 0.012 - 0.006
					col = Color(
						clampf(face.r + n, 0, 1),
						clampf(face.g + n, 0, 1),
						clampf(face.b + n, 0, 1))
				_:
					# ivory: faint grain plus a warm yellow tint that builds near the edges
					var edge_u := 1.0 - 2.0 * absf(float(x) / tex_size - 0.5)
					var edge_v := 1.0 - 2.0 * absf(float(y) / tex_size - 0.5)
					var edge := 1.0 - minf(edge_u, edge_v)  # 0 center -> 1 at border
					var n := randf() * 0.06 - 0.03
					col = Color(
						clampf(face.r + n, 0, 1),
						clampf(face.g + n + edge * 0.08, 0, 1),
						clampf(face.b + n - edge * 0.05, 0, 1))
			img.set_pixel(x, y, col)
	if mat_type == "gem":
		_draw_cracks(tex_size, img, 2 + (randi() % 2))
	_paint_markings(img, value, numbering_style, tex_size, skin.pip)
	return ImageTexture.create_from_image(img)


## Scratches a couple of jagged fracture lines into a gem face texture,
## darkening whatever marbling is already there rather than painting flat lines.
static func _draw_cracks(tex_size: int, img: Image, count: int) -> void:
	for _i in count:
		var x := randf() * tex_size
		var y := randf() * tex_size
		var angle := randf() * TAU
		var steps := int(tex_size * randf_range(0.7, 1.3))
		for _s in steps:
			angle += randf_range(-0.4, 0.4)
			x += cos(angle) * 1.5
			y += sin(angle) * 1.5
			var ix := int(x)
			var iy := int(y)
			if ix < 0 or ix >= tex_size or iy < 0 or iy >= tex_size:
				break
			img.set_pixel(ix, iy, img.get_pixel(ix, iy).darkened(0.6))
			if ix + 1 < tex_size:
				img.set_pixel(ix + 1, iy, img.get_pixel(ix + 1, iy).darkened(0.3))


## Normal map giving each pip a deep spherical dimple (concave dish).
## Numbers/numerals stay flat -- glyph-shaped dimples aren't worth the
## complexity, so those styles print flush with the face.
static func make_face_normalmap(value: int, tex_size: int, numbering_style := "dots") -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.5, 1.0))  # flat surface
	if numbering_style != "dots":
		return ImageTexture.create_from_image(img)
	var radius := tex_size / 9.0
	var depth := 1.8  # larger = flatter dimple; smaller = deeper
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
	t.origin = Vector3(roll_center.x + randf_range(-0.5, 0.5), 3.0,
		roll_center.y + randf_range(-0.5, 0.5))
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
