class_name InnerSkill
extends Resource

@export var skill_name: String = ""
@export_enum("阴", "阳", "调和") var yin_yang: String = "调和"
@export_enum("金", "木", "水", "火", "土") var element: String = "土"
@export var progress_per_tick: float = 1.0
@export var max_progress: float = 100.0
@export var required_location: String = ""
@export var qi_bonus: float = 0.0
@export var description: String = ""
