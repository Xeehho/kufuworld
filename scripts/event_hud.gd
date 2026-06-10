extends Control

var event_labels: Array = []
var max_visible: int = 4

func _ready():
	set_position(Vector2(1620, 10))
	GameManager.world_event.connect(_on_world_event)

func _on_world_event(title: String, body: String, importance: int):
	var lbl = Label.new()
	lbl.text = "[门] " + title + ": " + body
	lbl.position = Vector2(0, event_labels.size() * 16)
	lbl.add_theme_font_size_override("font_size", 10)
	var c = Color.WHITE
	if importance >= 6:
		c = Color(1, 0.3, 0.3)
	elif importance >= 4:
		c = Color(1, 0.8, 0.2)
	lbl.add_theme_color_override("font_color", c)
	add_child(lbl)
	event_labels.append(lbl)

	while event_labels.size() > max_visible:
		var old = event_labels.pop_front()
		old.queue_free()
	for i in range(event_labels.size()):
		event_labels[i].position.y = i * 16
		event_labels[i].modulate.a = 1.0 - (event_labels.size() - 1 - i) * 0.2

	var timer = get_node_or_null("FadeTimer")
	if timer == null:
		timer = Timer.new()
		timer.name = "FadeTimer"
		timer.wait_time = 6.0
		timer.one_shot = true
		timer.timeout.connect(_fade_oldest)
		add_child(timer)
	else:
		timer.start()

func _fade_oldest():
	if event_labels.size() > 0:
		var old = event_labels.pop_front()
		old.queue_free()
		for i in range(event_labels.size()):
			event_labels[i].position.y = i * 16
