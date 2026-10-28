extends Control

const BlockArt := preload("res://scripts/ui/block_art.gd")
const L10n := preload("res://scripts/localization/game_locale.gd")
const COLORS := [Color("#ffd154"), Color("#59e871"), Color("#bd76ff"), Color("#57c9ff"), Color("#ff7583"), Color("#ffae42")]
const NAMES := {
	"zh_CN": ["黄色方块", "绿色方块", "紫色星星", "青色菱形", "红色方块", "橙色小熊"],
	"en": ["Yellow block", "Green block", "Purple star", "Cyan diamond", "Red block", "Orange bear"],
	"fr": ["Bloc jaune", "Bloc vert", "Étoile violette", "Losange cyan", "Bloc rouge", "Ours orange"],
}

var avatar: int = 0:
	set(value):
		avatar = posmod(value, COLORS.size())
		accessibility_name = display_name(avatar)
		queue_redraw()
var crowned := false:
	set(value):
		crowned = value
		queue_redraw()

static func display_name(id: int) -> String:
	return NAMES[L10n.language()][posmod(id, COLORS.size())]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	accessibility_name = display_name(avatar)
	resized.connect(queue_redraw)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		accessibility_name = display_name(avatar)

func _draw() -> void:
	var side := minf(size.x, size.y) * 0.78
	var origin := (size - Vector2.ONE * side) * 0.5
	if crowned:
		side *= 0.8
		origin = Vector2((size.x - side) * 0.5, size.y - side - 2.0)
	var color: Color = COLORS[avatar]
	var face := Rect2(origin, Vector2.ONE * side)
	if avatar == 2 or avatar == 3:
		var points := PackedVector2Array()
		var count := 10 if avatar == 2 else 4
		for i in range(count):
			var radius := side * (0.5 if avatar == 3 or i % 2 == 0 else 0.29)
			points.append(face.get_center() + Vector2.from_angle(-PI / 2.0 + TAU * i / count) * radius)
		draw_colored_polygon(points, color.darkened(0.3))
		for i in range(points.size()):
			points[i] = face.get_center() + (points[i] - face.get_center()) * 0.91 - Vector2(0, side * 0.035)
		draw_colored_polygon(points, color)
		draw_line(points[0], points[1], color.lightened(0.55), maxf(1.0, side * 0.045), true)
	else:
		if avatar == 5:
			for x in [0.19, 0.81]:
				draw_circle(origin + Vector2(x, 0.05) * side, side * 0.16, color.darkened(0.1), true, -1, true)
				draw_circle(origin + Vector2(x, 0.05) * side, side * 0.09, color.lightened(0.4), true, -1, true)
		BlockArt.draw_block(self, face, color)
	var ink := Color("#18294a")
	for x in [0.36, 0.64]:
		draw_line(origin + Vector2(x, 0.42) * side, origin + Vector2(x, 0.52) * side, ink, maxf(2.0, side * 0.07), true)
	draw_arc(origin + Vector2(0.5, 0.56) * side, side * 0.11, 0.12, PI - 0.12, 12, ink, maxf(1.4, side * 0.045), true)
	if crowned:
		BlockArt.draw_icon(self, "crown", Rect2(Vector2((size.x - side * 0.65) * 0.5, 0), Vector2.ONE * side * 0.65), BlockArt.GOLD)
