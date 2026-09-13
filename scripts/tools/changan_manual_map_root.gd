@tool
extends Node2D

const GRID_SIZE := 16
const CITY_SIZE := Vector2i(168, 142)


func _ready() -> void:
	if not Engine.is_editor_hint():
		var guide := get_node_or_null("Guide") as CanvasItem
		if guide != null:
			guide.visible = false
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := Vector2(CITY_SIZE * GRID_SIZE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.13, 0.12, 0.06), true)
	for x in range(0, CITY_SIZE.x + 1):
		var strong := x % 3 == 0
		var color := Color(0.84, 0.68, 0.35, 0.24 if strong else 0.08)
		draw_line(Vector2(x * GRID_SIZE, 0), Vector2(x * GRID_SIZE, size.y), color,
				2.0 if strong else 1.0)
	for y in range(0, CITY_SIZE.y + 1):
		var strong := y % 3 == 0
		var color := Color(0.84, 0.68, 0.35, 0.24 if strong else 0.08)
		draw_line(Vector2(0, y * GRID_SIZE), Vector2(size.x, y * GRID_SIZE), color,
				2.0 if strong else 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.70, 0.24, 0.85), false, 4.0)
