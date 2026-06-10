class_name BuildingTemplate
extends Resource

@export var building_name: String = ""
@export_enum("茅屋", "练功房", "炼丹房", "农田", "仓库", "围墙") var building_type: String = "茅屋"
@export var wood_cost: int = 10
@export var stone_cost: int = 5
@export var size_x: int = 3
@export var size_y: int = 3
@export var tile_id: int = 2
@export var description: String = ""
@export var capacity: int = 0
@export var provides: String = ""
