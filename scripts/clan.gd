class_name Clan
extends Resource

@export var clan_name: String = ""
@export_enum("正派", "邪派", "中立") var stance: String = "中立"
@export var territory: String = ""
@export var power: float = 50.0
@export var gold: int = 1000
@export var member_count: int = 20
@export var allies = []
@export var enemies = []
@export var description: String = ""
@export var join_condition_reputation: float = 0.0
@export var join_condition_morality: float = 0.0
@export var mastery_skills: Array = []
@export var location: Vector2 = Vector2.ZERO
