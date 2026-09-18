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
# "acrylic" (smooth glossy plastic, no marbling/tint),
# "anodized" (gold: view-angle shader, one flat color per face that shifts
# white->yellow->orange->black with angle -- no baked texture, see _make_anodized_material),
# "tigerseye" (translucent gem with flowing golden-brown chatoyant bands).
const SKINS := {
	"ivory": {"body": Color(0.88, 0.84, 0.73), "face": Color(0.90, 0.86, 0.75), "pip": Color(0.09, 0.08, 0.07), "material": "ivory"},
	"onyx": {"body": Color(0.12, 0.12, 0.13), "face": Color(0.16, 0.16, 0.17), "pip": Color(0.90, 0.90, 0.92), "material": "gem"},
	"graphite": {"body": Color(0.26, 0.26, 0.28), "face": Color(0.31, 0.31, 0.33), "pip": Color(0.88, 0.88, 0.90), "material": "stone"},
	"ruby": {"body": Color(0.50, 0.05, 0.08), "face": Color(0.60, 0.08, 0.11), "pip": Color(0.85, 0.68, 0.25), "material": "gem"},
	"jade": {"body": Color(0.05, 0.35, 0.22), "face": Color(0.08, 0.42, 0.28), "pip": Color(0.95, 0.89, 0.70), "material": "gem"},
	"gold": {"body": Color(0.60, 0.47, 0.12), "face": Color(0.72, 0.57, 0.16), "pip": Color(0.10, 0.08, 0.04), "material": "anodized"},
	"tigers_eye": {"body": Color(0.45, 0.27, 0.07), "face": Color(0.75, 0.50, 0.15), "pip": Color(0.98, 0.86, 0.30), "material": "tigerseye"},
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
const ROMAN_TEXT := {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI"}
const NUMERAL_FONT_PATH := "res://fonts/EBGaramond-Regular.ttf"

static var _numeral_font: Font

# generated face textures are pure functions of (skin, numbering, value,
# tex_size) -- cache them so the same combination (e.g. many dice sharing a
# skin, or just re-opening the shelf) doesn't re-run the pixel loops every time.
static var _albedo_cache: Dictionary = {}
static var _detail_cache: Dictionary = {}
static var _normal_cache: Dictionary = {}

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

	# body slightly inset behind the face quads
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * SIZE * 0.99
	body.mesh = bm
	body.material_override = _make_body_material()
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
		mi.material_override = _make_face_material(int(d.v))
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
	# rebuild materials fresh rather than mutate in place: the material class
	# itself changes between skins (gold is a ShaderMaterial, the rest are
	# StandardMaterial3D), and textures are cached so this is cheap
	_body.material_override = _make_body_material()
	for f in _faces:
		(f.mi as MeshInstance3D).material_override = _make_face_material(int(f.v))


## Face material for the current skin: gold gets the view-angle anodized shader,
## every other skin gets a StandardMaterial3D with baked grain + pips.
func _make_face_material(value: int) -> Material:
	if skin_name == "gold":
		return _make_anodized_material(value)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = make_face_texture(value, FACE_TEX, skin_name, numbering_style)
	_apply_material_type(mat, skin_name)
	_apply_pip_matte(mat, value, skin_name, numbering_style)
	mat.normal_enabled = true
	mat.normal_texture = make_face_normalmap(value, FACE_TEX, numbering_style)
	mat.normal_scale = 1.4
	return mat


## Body (inset box behind the faces) material. Value -1 = no markings.
func _make_body_material() -> Material:
	if skin_name == "gold":
		return _make_anodized_material(-1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SKINS[skin_name].body
	_apply_material_type(mat, skin_name)
	return mat


## Gold: a ShaderMaterial whose base color is a single flat tone per face that
## slides white->yellow->orange->black with the viewing angle (thin-film /
## anodized look), with the pips composited on top from the shared detail mask.
func _make_anodized_material(value: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _anodized_shader()
	if value >= 1:
		var pip: Color = SKINS["gold"].pip
		m.set_shader_parameter("has_markings", true)
		m.set_shader_parameter("pip_color", Vector3(pip.r, pip.g, pip.b))
		m.set_shader_parameter("detail_tex",
			make_face_detail_texture(value, FACE_TEX, 0.3, numbering_style))
		m.set_shader_parameter("normal_tex",
			make_face_normalmap(value, FACE_TEX, numbering_style))
	else:
		m.set_shader_parameter("has_markings", false)
	return m


static var _anodized_shader_res: Shader

static func _anodized_shader() -> Shader:
	if _anodized_shader_res == null:
		_anodized_shader_res = Shader.new()
		_anodized_shader_res.code = ANODIZED_SHADER
	return _anodized_shader_res


# View-angle anodized shader. The face quad's normal is constant, so dot(N,V)
# is near-uniform across a face -> one flat color at a time that changes as the
# die turns. detail_tex.r is the marking mask (0 on markings), .b is roughness.
const ANODIZED_SHADER := "shader_type spatial;
uniform sampler2D detail_tex : filter_linear;
uniform sampler2D normal_tex : hint_normal;
uniform vec3 pip_color = vec3(0.1, 0.08, 0.04);
uniform bool has_markings = false;
uniform float angle_gamma = 0.8; // <1 spreads more of the ramp into view
uniform float white_boost = 0.5; // extra white on the most head-on facets

vec3 anodized(float t) {
	vec3 c0 = vec3(1.0, 1.0, 1.0);
	vec3 c1 = vec3(0.92, 0.82, 0.42);
	vec3 c2 = vec3(0.58, 0.42, 0.09);
	vec3 c3 = vec3(0.42, 0.17, 0.03);
	vec3 c4 = vec3(0.02, 0.02, 0.02);
	t = clamp(t, 0.0, 1.0) * 4.0;
	if (t < 1.0) return mix(c0, c1, t);
	if (t < 2.0) return mix(c1, c2, t - 1.0);
	if (t < 3.0) return mix(c2, c3, t - 2.0);
	return mix(c3, c4, t - 3.0);
}

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float t = pow(1.0 - ndv, angle_gamma);
	vec3 base = anodized(t);
	// extra white flash on the most head-on facets
	base = mix(base, vec3(1.0), white_boost * smoothstep(0.82, 1.0, ndv));
	ALBEDO = base;
	METALLIC = 0.1;
	ROUGHNESS = 0.5;
	if (has_markings) {
		vec4 d = texture(detail_tex, UV);
		float mask = 1.0 - d.r;
		ALBEDO = mix(base, pip_color, mask);
		ROUGHNESS = mix(0.5, 1.0, mask);
		METALLIC = mix(0.1, 0.0, mask);
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
"


## Base (non-pip) surface roughness for each material type. Single source of
## truth shared between the material scalar and the per-face roughness map.
static func _base_roughness(mat_type: String) -> float:
	match mat_type:
		"metal": return 0.1
		"stone": return 0.25
		"tigerseye": return 0.15
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
	# reset gem/clearcoat-only state so a reused material (the arena die switches
	# skins in place) doesn't keep a previous gem's translucency/refraction
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = 1.0
	mat.refraction_enabled = false
	mat.clearcoat_enabled = false
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
		"tigerseye":
			# translucent chatoyant gem: like gem but a touch more opaque and
			# glossier so the golden banding still reads through it
			mat.metallic = 0.05
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.7
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.9
			mat.refraction_enabled = true
			mat.refraction_scale = 0.06
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
	var key := "%s|%d|%d|%.3f" % [numbering_style, value, tex_size, base_roughness]
	if _detail_cache.has(key):
		return _detail_cache[key]
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 1.0, base_roughness))
	_paint_markings(img, value, numbering_style, tex_size, Color(0.0, 1.0, 0.92))
	var tex := ImageTexture.create_from_image(img)
	_detail_cache[key] = tex
	return tex


## Draws the face marking (dot pips, a digit, or a roman numeral) in the
## given color. Shared by the albedo pass (pip color) and the matte-mask
## pass (roughness/clearcoat override), so both stay perfectly aligned.
static func _paint_markings(img: Image, value: int, numbering_style: String, tex_size: int, col: Color) -> void:
	match numbering_style:
		"numbers":
			_paint_text(img, str(value), tex_size, col)
		"numerals":
			_paint_text(img, ROMAN_TEXT[value], tex_size, col)
		_:
			var radius := tex_size / 9.0
			for g: Vector2 in PIP_LAYOUT[value]:
				var cx: float = tex_size * (0.25 + 0.25 * g.x)
				var cy: float = tex_size * (0.25 + 0.25 * g.y)
				_fill_circle(tex_size, img, cx, cy, radius, col)


static func _get_numeral_font() -> Font:
	if _numeral_font == null:
		# faux-bold the serif via a FontVariation; no bold weight ships in fonts/
		var fv := FontVariation.new()
		fv.base_font = load(NUMERAL_FONT_PATH)
		fv.variation_embolden = 0.6
		_numeral_font = fv
	return _numeral_font


## Rasterizes `text` in the die's serif font and blits it centered onto
## `img`, alpha-blended per pixel so glyph edges stay antialiased instead
## of pixelated. Uses TextServer's glyph atlas directly (synchronous, no
## viewport/frame wait) so this works headless too.
static func _paint_text(img: Image, text: String, tex_size: int, col: Color) -> void:
	var rid: RID = _get_numeral_font().get_rids()[0]
	var ts := TextServerManager.get_primary_interface()
	# pin rasterization: global oversampling tracks DPI/UI scale and changes as
	# the app runs, which would render glyphs oversized/off-center into our 1:1
	# blit -- and that wrong size gets cached per skin. Force 1.0 + no subpixel
	# so the marking is centered and deterministic regardless of global state.
	ts.font_set_oversampling(rid, 1.0)
	ts.font_set_subpixel_positioning(rid, TextServer.SUBPIXEL_POSITIONING_DISABLED)
	var px_size := int(tex_size * 0.62)

	var glyphs: Array = []
	var total_w := 0.0
	for i in text.length():
		var glyph_index := ts.font_get_glyph_index(rid, px_size, text.unicode_at(i), 0)
		ts.font_render_glyph(rid, Vector2i(px_size, 0), glyph_index)
		var tex_idx := ts.font_get_glyph_texture_idx(rid, Vector2i(px_size, 0), glyph_index)
		var advance: Vector2 = ts.font_get_glyph_advance(rid, px_size, glyph_index)
		glyphs.append({
			"atlas": ts.font_get_texture_image(rid, Vector2i(px_size, 0), tex_idx),
			"uv": ts.font_get_glyph_uv_rect(rid, Vector2i(px_size, 0), glyph_index),
			"offset": ts.font_get_glyph_offset(rid, Vector2i(px_size, 0), glyph_index),
			"advance": advance,
		})
		total_w += advance.x

	var ascent: float = ts.font_get_ascent(rid, px_size)
	var descent: float = ts.font_get_descent(rid, px_size)
	var pen_x := (tex_size - total_w) * 0.5
	var pen_y := (tex_size - (ascent + descent)) * 0.5 + ascent

	for g in glyphs:
		_blit_glyph(img, g, pen_x, pen_y, col)
		pen_x += (g.advance as Vector2).x


static func _blit_glyph(img: Image, glyph: Dictionary, pen_x: float, pen_y: float, col: Color) -> void:
	var atlas: Image = glyph.atlas
	var uv: Rect2 = glyph.uv
	var offset: Vector2 = glyph.offset
	var w := img.get_width()
	var h := img.get_height()
	var ax := int(uv.position.x)
	var ay := int(uv.position.y)
	for gy in int(uv.size.y):
		for gx in int(uv.size.x):
			var a := atlas.get_pixel(ax + gx, ay + gy).a
			if a <= 0.01:
				continue
			var dx := int(pen_x + offset.x + gx)
			var dy := int(pen_y + offset.y + gy)
			if dx < 0 or dx >= w or dy < 0 or dy >= h:
				continue
			img.set_pixel(dx, dy, img.get_pixel(dx, dy).lerp(col, a))


## Renders one die face (grain/marbling/brushing + markings) at the given
## texture size. Shared with EditorPanel's preview, which uses it smaller.
static func make_face_texture(value: int, tex_size: int, skin_name := "ivory", numbering_style := "dots") -> ImageTexture:
	var key := "%s|%s|%d|%d" % [skin_name, numbering_style, value, tex_size]
	if _albedo_cache.has(key):
		return _albedo_cache[key]
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
				"anodized":
					# flat swatch for the 2D editor preview only; the real 3D gold
					# is a ShaderMaterial whose color shifts with view angle and
					# never samples this texture (see _make_anodized_material)
					var g := randf() * 0.03 - 0.015
					col = Color(clampf(0.86 + g, 0, 1), clampf(0.66 + g, 0, 1), clampf(0.14 + g, 0, 1))
				"tigerseye":
					# chatoyant silk: long wavy bands running down the face (varies
					# mostly across u, gently wavers along v) rather than isotropic
					# blotches, sampled through the golden-brown ramp
					var u := float(x) / tex_size
					var v := float(y) / tex_size
					var wobble := sin(v * 2.2) * 0.28 + sin(v * 5.3) * 0.08
					var t := clampf(sin((u * 4.5 + wobble) * PI) * 0.5 + 0.5, 0.0, 1.0)
					t = pow(t, 1.7)  # skew toward dark so the deep bands dominate
					col = _tigerseye(t)
					var grain := randf() * 0.02 - 0.01
					col = Color(col.r + grain, col.g + grain, col.b + grain)
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
	var tex := ImageTexture.create_from_image(img)
	_albedo_cache[key] = tex
	return tex


## Tiger's-eye ramp: near-black brown -> deep brown -> bronze -> amber, at
## t in [0,1]. No pale/beige top stop; dark end is weighted by the caller.
static func _tigerseye(t: float) -> Color:
	const STOPS := [
		Color(0.09, 0.04, 0.01),
		Color(0.30, 0.16, 0.03),
		Color(0.60, 0.37, 0.09),
		Color(0.90, 0.64, 0.20),
	]
	t = clampf(t, 0.0, 1.0) * (STOPS.size() - 1)
	var i := int(t)
	if i >= STOPS.size() - 1:
		return STOPS[STOPS.size() - 1]
	return STOPS[i].lerp(STOPS[i + 1], t - i)


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
	var key := "%s|%d|%d" % [numbering_style, value, tex_size]
	if _normal_cache.has(key):
		return _normal_cache[key]
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.5, 1.0))  # flat surface
	if numbering_style != "dots":
		var flat := ImageTexture.create_from_image(img)
		_normal_cache[key] = flat
		return flat
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
	var tex := ImageTexture.create_from_image(img)
	_normal_cache[key] = tex
	return tex


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
