extends Node2D

@onready var world: Node2D = $World

func _ready():
	print("Godot Trae Project initialized!")
	print("MCP Server URL: http://127.0.0.1:8000/mcp")
	_ensure_textures()
	# 延迟一帧再初始化其他系统，确保纹理资源已就绪
	await get_tree().process_frame
	_setup_world_generator()
	_setup_weather()
	_setup_hud()
	_setup_clan_simulator()
	_setup_event_hud()
	_setup_quest_system()
	_setup_encounter_system()
	_setup_oath_system()
	_setup_quest_log()
	_setup_quick_menu()
	_setup_combat_stance()
	_setup_combat_hud()
	_setup_inventory()
	_setup_shop()
	_setup_shop_hud()
	_setup_death_system()
	_setup_death_hud()
	# NPC生成延迟到纹理和世界都就绪后
	_setup_npc_spawner()

func _ensure_textures():
	# 检查关键纹理是否存在，如果不存在则运行生成器
	var need_textures = not ResourceLoader.exists("res://sprites/tiles/grass.png") or not ResourceLoader.exists("res://sprites/player/idle_down_0.png") or not ResourceLoader.exists("res://sprites/npc/warrior_idle_down_0.png")
	if need_textures:
		var gen_script = load("res://scripts/texture_generator.gd")
		if gen_script:
			var gen = Node.new()
			gen.set_script(gen_script)
			add_child(gen)
			gen.generate_all()
			gen.queue_free()
			print("[Main] Textures generated on first run")
	# 检查帧资源是否存在，如果不存在则运行帧生成器
	if not ResourceLoader.exists("res://sprites/player/player_frames.tres"):
		var frame_gen_script = load("res://scripts/frames_generator.gd")
		if frame_gen_script:
			var frame_gen = Node.new()
			frame_gen.set_script(frame_gen_script)
			add_child(frame_gen)
			frame_gen.queue_free()
			print("[Main] Frame resources generated")
	# 检查瓦片集是否有效（文件存在、有瓦片源、有物理碰撞层）
	var need_tileset = true
	if ResourceLoader.exists("res://tilesets/ground_tiles.tres"):
		var existing_ts = load("res://tilesets/ground_tiles.tres") as TileSet
		if existing_ts and existing_ts.get_source_count() > 0 and existing_ts.get_physics_layers_count() > 0:
			need_tileset = false
	if need_tileset:
		var tileset_gen_script = load("res://scripts/tileset_generator.gd")
		if tileset_gen_script:
			var tileset_gen = Node.new()
			tileset_gen.set_script(tileset_gen_script)
			add_child(tileset_gen)
			tileset_gen.queue_free()
			print("[Main] TileSet resources generated")

func _setup_quest_system():
	var qs = Node.new()
	qs.name = "QuestSystem"
	qs.set_script(load("res://scripts/quest_system.gd"))
	add_child(qs)

func _setup_encounter_system():
	var es = Node.new()
	es.name = "EncounterSystem"
	es.set_script(load("res://scripts/encounter_system.gd"))
	add_child(es)

func _setup_oath_system():
	var os = Node.new()
	os.name = "OathSystem"
	os.set_script(load("res://scripts/oath_system.gd"))
	add_child(os)

func _setup_quest_log():
	var ql = Control.new()
	ql.name = "QuestLogHUD"
	ql.set_script(load("res://scripts/quest_log_hud.gd"))
	ql.position = Vector2(1640, 140)
	$World/UI.add_child(ql)

func _setup_quick_menu():
	var qm = Control.new()
	qm.name = "QuickMenu"
	qm.set_script(load("res://scripts/quick_menu.gd"))
	$World/UI.add_child(qm)

func _setup_clan_simulator():
	var sim = Node.new()
	sim.name = "ClanSimulator"
	sim.set_script(load("res://scripts/clan_simulator.gd"))
	add_child(sim)

func _setup_event_hud():
	var evt = Control.new()
	evt.name = "EventHUD"
	evt.set_script(load("res://scripts/event_hud.gd"))
	$World/UI.add_child(evt)

func _setup_hud():
	var hud = Control.new()
	hud.name = "SurvivalHUD"
	hud.set_script(load("res://scripts/survival_hud.gd"))
	$World/UI.add_child(hud)

func _setup_world_generator():
	if world == null:
		return
	var gen = Node2D.new()
	gen.name = "WorldGenerator"
	gen.set_script(load("res://scripts/world_generator.gd"))
	world.add_child(gen)
	# 确保WorldGenerator在TileMap之后，这样POI渲染在瓦片之上
	world.move_child(gen, world.get_child_count() - 1)

func _setup_weather():
	if world == null:
		return
	var wc = Node.new()
	wc.name = "WeatherController"
	wc.set_script(load("res://scripts/weather_controller.gd"))
	world.add_child(wc)

func _setup_combat_stance():
	var cs = Node.new()
	cs.name = "CombatStance"
	cs.set_script(load("res://scripts/combat_stance.gd"))
	add_child(cs)

func _setup_combat_hud():
	var ch = Control.new()
	ch.name = "CombatHUD"
	ch.set_script(load("res://scripts/combat_hud.gd"))
	$World/UI.add_child(ch)

func _setup_inventory():
	var inv = Node.new()
	inv.name = "InventoryManager"
	inv.set_script(load("res://scripts/inventory_manager.gd"))
	add_child(inv)

func _setup_shop():
	var shop = Node.new()
	shop.name = "ShopSystem"
	shop.set_script(load("res://scripts/shop_system.gd"))
	add_child(shop)

func _setup_shop_hud():
	var sh = Control.new()
	sh.name = "ShopHUD"
	sh.set_script(load("res://scripts/shop_hud.gd"))
	$World/UI.add_child(sh)

func _setup_death_system():
	var ds = Node.new()
	ds.name = "DeathSystem"
	ds.set_script(load("res://scripts/death_system.gd"))
	add_child(ds)

func _setup_death_hud():
	var dh = Control.new()
	dh.name = "DeathHUD"
	dh.set_script(load("res://scripts/death_hud.gd"))
	$World/UI.add_child(dh)

func _setup_npc_spawner():
	# 移除场景中的自动NPCSpawner（如果有），改为代码控制延迟生成
	var old_spawner = world.get_node_or_null("NPCSpawner")
	if old_spawner:
		old_spawner.queue_free()
	# 等待旧spawner清理完
	await get_tree().process_frame
	var spawner = Node2D.new()
	spawner.name = "NPCSpawner"
	spawner.set_script(load("res://scripts/npc_spawner.gd"))
	world.add_child(spawner)
	print("[Main] NPCSpawner created after textures ready")
