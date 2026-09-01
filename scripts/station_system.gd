extends Node2D

# Phase C 制作站台系统：工作台/熔炉/炼丹台/篝火 摆放与交互合成
# 素材 download_assets Stations目录经 tools/make_phase_c_assets.py 裁剪烘焙到 sprites/stations/
# 运行时一律 TextureGen.load_png_texture 直读（无import数据）
# 挂载于 /root/Main/World/StationSystem

const TextureGen = preload("res://scripts/texture_generator.gd")
const ItemFactory = preload("res://scripts/item_factory.gd")

# type -> {名称, 贴图, 合成输入{id:数量}, 产出id}
const STATION_DEFS := {
	"工作台": {"tex": "res://sprites/stations/workbench.png", "frames": 1,
		"input": {"iron_ingot": 1}, "output": "iron_sword"},
	"熔炉": {"tex": "res://sprites/stations/furnace.png", "frames": 1,
		"input": {"iron_ore": 2}, "output": "iron_ingot"},
	"炼丹台": {"tex": "res://sprites/stations/alchemy_table.png", "frames": 1,
		"input": {"herb_material": 2}, "output": "gold_herb"},
	"篝火": {"tex": "res://sprites/stations/bonfire_f%d.png", "frames": 4,
		"input": {"berry": 1}, "output": "roasted_berry"},
}

func _ready():
	add_to_group("station_system")
	y_sort_enabled = true   # Phase G4：站台并入World递归Y-sort

# 建造模式放置入口（player._place_building 调用）
func place_station(type_str: String, pos: Vector2) -> Node2D:
	var def: Dictionary = STATION_DEFS.get(type_str, {})
	if def.is_empty():
		return null
	var node := Node2D.new()
	node.name = "Station_" + type_str + "_" + str(randi() % 10000)
	node.position = pos
	node.z_index = 2   # Phase G4：实体层统一z
	node.add_to_group("station")
	node.set_meta("station_type", type_str)
	if int(def["frames"]) > 1:
		# 多帧： AnimatedSprite2D 循环（篝火火焰）
		var sf := SpriteFrames.new()
		sf.add_animation("burn")
		sf.set_animation_speed("burn", 7.0)
		sf.set_animation_loop("burn", true)
		for i in range(int(def["frames"])):
			var t := TextureGen.load_png_texture(def["tex"] % i)
			if t:
				sf.add_frame("burn", t)
		var aspr := AnimatedSprite2D.new()
		aspr.sprite_frames = sf
		aspr.play("burn")
		aspr.offset = Vector2(0, -aspr.sprite_frames.get_frame_texture("burn", 0).get_height() * 0.5 + 5)
		node.add_child(aspr)
	else:
		var spr := Sprite2D.new()
		spr.texture = TextureGen.load_png_texture(String(def["tex"]))
		var h := spr.texture.get_height()
		spr.offset = Vector2(0, -h * 0.5 + 6)   # 底缘落在节点原点附近
		node.add_child(spr)
	# 画面改造P2.2：站台脚底软阴影（底缘+6对齐，影垫站台脚下）
	var shadow := TextureGen.make_shadow_sprite(26.0, 0.26)
	shadow.position = Vector2(0, 4)
	node.add_child(shadow)
	get_parent().add_child(node)
	print("[Station] 放置 %s @ %s" % [type_str, pos])
	return node

# F键交互入口：检查背包材料→消耗→产出。返回{ok,msg}供飘字
func try_craft(station_node: Node2D) -> Dictionary:
	var type_str := str(station_node.get_meta("station_type"))
	var def: Dictionary = STATION_DEFS.get(type_str, {})
	if def.is_empty():
		return {"ok": false, "msg": "未知站台"}
	var inv := get_node_or_null("/root/Main/InventoryManager")
	if inv == null:
		return {"ok": false, "msg": "背包系统未就绪"}
	# 材料校验
	var input: Dictionary = def["input"]
	for item_id in input.keys():
		var need := int(input[item_id])
		if not inv.has_item(item_id, need):
			var it = ItemFactory.create(item_id)
			var nm: String = it.item_name if it else item_id
			return {"ok": false, "msg": "缺材料：%sx%d" % [nm, need]}
	for item_id in input.keys():
		inv.remove_item(item_id, int(input[item_id]))
	var out_id := String(def["output"])
	ItemFactory.give(out_id, 1)
	var out_item = ItemFactory.create(out_id)
	var out_name: String = out_item.item_name if out_item else out_id
	print("[Station] %s 合成 %s" % [type_str, out_name])
	return {"ok": true, "msg": "%s：获得%s" % [type_str, out_name]}

# 供玩家查找最近可交互站台
static func nearest_station(from: Node, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for s in from.get_tree().get_nodes_in_group("station"):
		var d: float = from.global_position.distance_to((s as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = s
	return best
