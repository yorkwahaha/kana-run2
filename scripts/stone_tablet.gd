extends RefCounted
## Shared, opaque chipped-stone geometry. Local origin is the centre of the rock.
const WIDTH := 1.68
const HEIGHT := 1.90
const FRONT := 0.28
const SHADER = preload("res://shaders/stone_tablet.gdshader")

static func make_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Uneven corners and a broad face leave space for the live kana label.
	var outline := PackedVector2Array([
		Vector2(-0.39, -0.5), Vector2(0.38, -0.5), Vector2(0.5, -0.39),
		Vector2(0.47, 0.34), Vector2(0.32, 0.5), Vector2(-0.31, 0.47),
		Vector2(-0.5, 0.32), Vector2(-0.49, -0.37),
	])
	for i in outline.size():
		var p := outline[i] * Vector2(WIDTH, HEIGHT)
		var q := outline[(i + 1) % outline.size()] * Vector2(WIDTH, HEIGHT)
		var a := Vector3(p.x * 0.86, p.y * 0.91, FRONT)
		var b := Vector3(q.x * 0.86, q.y * 0.91, FRONT)
		var c := Vector3(p.x, p.y, 0.04)
		var d := Vector3(q.x, q.y, 0.04)
		var e := Vector3(p.x * 0.94, p.y * 0.98, -0.30)
		var f := Vector3(q.x * 0.94, q.y * 0.98, -0.30)
		_triangle(surface, Vector3(0, 0, FRONT), a, b)
		_triangle(surface, a, c, d); _triangle(surface, a, d, b)
		_triangle(surface, c, e, f); _triangle(surface, c, f, d)
		_triangle(surface, Vector3(0, 0, -0.30), f, e)
	return surface.commit()

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	surface.set_normal(normal)
	for vertex in [a, b, c]:
		surface.add_vertex(vertex)
