class_name POITemplate
extends Resource

@export var poi_name: String = ""
@export_enum("城镇", "门派", "洞穴", "修炼场", "遗迹", "集市") var poi_type: String = "城镇"
@export var min_height: float = -1.0
@export var max_height: float = 1.0
@export var min_humidity: float = -1.0
@export var max_humidity: float = 1.0
@export var min_distance: float = 10.0
@export var spawn_weight: float = 1.0
@export var icon_color: Color = Color.WHITE
@export var spawn_npcs: int = 0
@export var description: String = ""
