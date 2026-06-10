class_name Encounter
extends Resource

@export var encounter_id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var trigger_condition: String = ""
@export var min_morality: float = -100
@export var max_morality: float = 100
@export var min_reputation: float = 0
@export var min_qi: float = 0
@export var location_hint: String = ""
@export var options: Array = []
@export var rarity: float = 0.3
