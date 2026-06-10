extends Area2D

signal collected

var fall_speed = 200

func _ready():
    body_entered.connect(_on_body_entered)

func _process(delta):
    position.y += fall_speed * delta
    if position.y > 700:
        queue_free()

func _on_body_entered(body):
    if body.name == "Player" or body is CharacterBody2D:
        emit_signal("collected")
        queue_free()