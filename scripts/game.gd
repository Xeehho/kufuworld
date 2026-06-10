extends Node2D

var score = 0
var StarScene = preload("res://scenes/star.tscn")

func _ready():
	print("_ready called")

func spawn_star():
	var star = StarScene.instantiate()
	var pos_x = randf_range(50, 1100)
	var pos_y = -20
	star.position = Vector2(pos_x, pos_y)
	print("spawn star at ", star.position)
	star.collected.connect(_on_star_collected)
	$StarContainer.add_child(star)

func _on_star_collected():
	score += 1
	$ScoreLabel.text = "Score: " + str(score)
	print("star collected, score: ", score)
