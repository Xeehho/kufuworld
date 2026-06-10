class_name Quest
extends Resource

@export var quest_id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var category: String = ""
@export var target_count: int = 1
@export var current_count: int = 0
@export var reward_gold: int = 0
@export var reward_reputation: float = 0
@export var reward_morality: float = 0
@export var reward_contribution: int = 0
@export var difficulty: int = 1
@export var is_completed: bool = false
@export var is_active: bool = false

func completion_ratio() -> float:
	if target_count <= 0:
		return 0.0
	return float(current_count) / float(target_count)
