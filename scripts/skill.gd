class_name Skill
extends Resource

@export var skill_name: String = ""
@export_enum("拳掌", "剑法", "刀法", "棍法", "暗器", "内功") var category: String = "拳掌"
@export var damage: float = 10.0
@export var cost: float = 5.0
@export var startup_frames: int = 5
@export var active_frames: int = 8
@export var recovery_frames: int = 10
@export_enum("起手", "连击", "终结", "无") var combo_tag: String = "无"
@export var is_light: bool = true
@export var description: String = ""
