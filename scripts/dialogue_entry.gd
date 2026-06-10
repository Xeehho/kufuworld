class_name DialogueEntry
extends Resource

@export var entry_id: String = ""
@export var text: String = ""
@export var responses: Array[DialogueResponse] = []
@export var condition_min_favor: float = -100
@export var condition_max_favor: float = 100
