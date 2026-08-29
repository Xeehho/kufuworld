class_name NPCData
extends Resource

@export var npc_id: String = ""
@export var npc_name: String = ""
@export_enum("豪爽", "阴沉", "儒雅", "暴躁", "狡诈", "慈悲", "孤傲", "市侩") var personality: String = "豪爽"
@export var likes = []
@export var dislikes = []
@export var home_position: Vector2 = Vector2.ZERO
@export var work_position: Vector2 = Vector2.ZERO
@export var sleep_start_hour: int = 22
@export var work_start_hour: int = 8
@export var dialogue_id: String = ""
# 城池NPC固定日程（非空则覆盖自动生成）：腿={start,end,state,pos}，state∈work/leisure/wander/idle
@export var custom_schedule: Array = []
