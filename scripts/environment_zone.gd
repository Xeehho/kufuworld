extends Area2D

@export var environment_name: String = ""

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("player"):
		GameManager.current_environment = environment_name
		print("[Zone] Entered " + environment_name)

func _on_body_exited(body):
	if body.is_in_group("player"):
		GameManager.current_environment = ""
		print("[Zone] Left " + environment_name)
