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
	_setup_npc_info_hud()

func _ensure_textures():
	# 检查关键纹理是否存在，如果不存在则运行生成器
	# 注意：必须用 FileAccess 而非 ResourceLoader.exists —— 运行时生成的PNG没有import数据
	# 校验全部瓦片PNG（曾只查grass等几个代表文件，单独删除mountain/sand后不会触发重生成，瓦片隐形）
	var tile_files = [
		"grass", "grass_dark", "path", "water", "sand", "mountain", "mountain_snow",
		"tree_pine", "tree_oak", "tree_bamboo", "house_town", "house_cottage",
		"house_temple", "house_cave", "flower", "rock", "fence", "farmland", "bridge",
		"house2_l", "house2_r", "house3_l", "house3_m", "house3_r",
		"house4_l", "house4_lm", "house4_rm", "house4_r",
		"house5_l", "house5_lm", "house5_m", "house5_rm", "house5_r",
	]
	var need_textures = false
	for t in tile_files:
		if not FileAccess.file_exists("res://sprites/tiles/" + t + ".png"):
			need_textures = true
			break
	if not need_textures:
		need_textures = not FileAccess.file_exists("res://sprites/player/idle_down_0.png") or not FileAccess.file_exists("res://sprites/npc/warrior_idle_down_0.png")
	if need_textures:
		var gen_script = load("res://scripts/texture_generator.gd")
		if gen_script:
			var gen = Node.new()
			gen.set_script(gen_script)
			add_child(gen)
			gen.generate_all()
			gen.queue_free()
			print("[Main] Textures generated on first run")
	# 玩家/NPC帧动画与TileSet均在运行时从PNG直接构建（player.gd / npc_character.gd / world_generator.gd），
	# 不再依赖 player_frames.tres / ground_tiles.tres，避免运行时生成资源无import数据导致的加载失败

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

func _setup_npc_info_hud():
	var nih = Control.new()
	nih.name = "NPCInfoHUD"
	nih.set_script(load("res://scripts/npc_info_hud.gd"))
	$World/UI.add_child(nih)
