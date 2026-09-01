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
	_setup_minimap()	# Phase G: 小地图（M键开关）
	_setup_clan_simulator()
	_setup_event_hud()
	_setup_quest_system()
	_setup_encounter_system()
	_setup_oath_system()
	_setup_quick_menu()
	_setup_pause_hud()
	_setup_combat_stance()
	_setup_combat_hud()
	_setup_inventory()
	_setup_shop()
	_setup_shop_hud()
	_setup_audio()   # Phase D：音效/BGM占位（早于玩法系统装配，便于各处接线）
	_setup_death_system()
	_setup_death_hud()
	# NPC生成延迟到纹理和世界都就绪后
	_setup_npc_spawner()
	_setup_npc_info_hud()
	_setup_building_info_hud()	# Phase G: 建筑信息面板（点击古堡查看势力）
	_setup_quest_log_hud()	# Phase F7: 游戏化任务日志
	_setup_quest_tracker_hud()	# Phase H: 左轨任务追踪器（对标巫师3/原神objective tracker）
	_setup_character_panel()	# 统一角色面板（替代旧CharacterSheet+InventoryHUD：V/I键+头像点击）
	# Phase C 星露谷交互玩法（依赖WorldGenerator/InventoryManager就绪）
	_setup_farm_system()
	_setup_station_system()
	_setup_mob_spawner()
	_setup_tree_chop_system()   # 树木采伐（依赖WorldGenerator树精灵就绪，自身懒判安全）
	_setup_main_story()   # 主线剧情驱动器：依赖Quest/Mob/Farm/Oath等系统就绪

func _setup_tree_chop_system():
	var tc = Node2D.new()
	tc.name = "TreeChopSystem"
	tc.set_script(load("res://scripts/tree_chop_system.gd"))
	world.add_child(tc)

func _setup_main_story():
	var st = Node.new()
	st.name = "MainStory"
	st.set_script(load("res://scripts/main_story.gd"))
	add_child(st)

func _setup_audio():
	var ac = Node.new()
	ac.name = "AudioController"
	ac.set_script(load("res://scripts/audio_controller.gd"))
	world.add_child(ac)

func _setup_farm_system():
	var fs = Node2D.new()
	fs.name = "FarmSystem"
	fs.set_script(load("res://scripts/farm_system.gd"))
	world.add_child(fs)

func _setup_station_system():
	var ss = Node2D.new()
	ss.name = "StationSystem"
	ss.set_script(load("res://scripts/station_system.gd"))
	world.add_child(ss)

func _setup_mob_spawner():
	var ms = Node2D.new()
	ms.name = "MobSpawner"
	ms.set_script(load("res://scripts/mob_spawner.gd"))
	world.add_child(ms)

func _ensure_textures():
	# 检查关键纹理是否存在，如果不存在则运行生成器
	# 注意：必须用 FileAccess 而非 ResourceLoader.exists —— 运行时生成的PNG没有import数据
	# Phase G重构：全部瓦片（含terrain五件套）由 texture_generator 从素材包直接裁切
	var tile_files = [
		"grass", "grass_dark", "path", "water", "sand", "snow", "stone",
		"farmland", "farmland_wet", "mountain", "mountain_snow",
		"house_town", "house_cottage", "house_temple", "house_cave",
		"flower", "daisy", "mushroom", "rock", "fence", "bridge", "city_wall",
		"snow_farmland", "snow_path",
		"ward_wall",
	]
	var need_textures = false
	for t in tile_files:
		if not FileAccess.file_exists("res://sprites/tiles/" + t + ".png"):
			need_textures = true
			break
	if need_textures:
		var gen_script = load("res://scripts/texture_generator.gd")
		if gen_script:
			var gen = Node.new()
			gen.set_script(gen_script)
			add_child(gen)
			gen.generate_tiles()  # Phase B陷阱修复：严禁generate_all——那会用程序画法覆盖素材包玩家/NPC帧
			gen.queue_free()
			print("[Main] Generator tiles regenerated")
	# Phase F5: 大型建筑贴图（sprites/buildings/*.png 缺失时生成；逐kind校验防止增量缺失）
	var big_missing := false
	for kind in ["hut", "house", "manor", "temple", "castle",
			"yamen", "tavern", "apothecary", "shop_a", "shop_b",
			"stall_red", "stall_teal", "well", "gate_tower"]:
		if not FileAccess.file_exists("res://sprites/buildings/%s.png" % kind):
			big_missing = true
			break
	if big_missing:
		var gen_script2 = load("res://scripts/texture_generator.gd")
		if gen_script2:
			var gen2 = Node.new()
			gen2.set_script(gen_script2)
			add_child(gen2)
			gen2.generate_big_buildings()
			gen2.generate_city_props()
			gen2.queue_free()
			print("[Main] Big buildings regenerated")
	# 打坐专用坐姿帧（meditate_down_0/1，程序化生成；素材包无坐姿）
	if not FileAccess.file_exists("res://sprites/player/meditate_down_0.png"):
		var gen_script3 = load("res://scripts/texture_generator.gd")
		if gen_script3:
			var gen3 = Node.new()
			gen3.set_script(gen_script3)
			add_child(gen3)
			gen3.generate_meditate_frames()
			gen3.queue_free()
			print("[Main] Meditate frames regenerated")
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

func _setup_pause_hud():
	var ph = Control.new()
	ph.name = "PauseHUD"
	ph.set_script(load("res://scripts/pause_hud.gd"))
	$World/UI.add_child(ph)   # ESC无面板时呼出全局暂停（暂停时世界冻结）

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

func _setup_minimap():
	var mm = Control.new()
	mm.name = "MinimapHUD"
	mm.set_script(load("res://scripts/minimap_hud.gd"))
	$World/UI.add_child(mm)

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

func _setup_character_panel():
	# 统一角色面板：左人物信息/中装备三槽/右行囊45格（V/I键+左上头像点击打开）
	var cp = Control.new()
	cp.name = "CharacterPanel"
	cp.set_script(load("res://scripts/character_panel.gd"))
	$World/UI.add_child(cp)

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

func _setup_building_info_hud():
	var bih = Control.new()
	bih.name = "BuildingInfoHUD"
	bih.set_script(load("res://scripts/building_info_hud.gd"))
	$World/UI.add_child(bih)

func _setup_quest_log_hud():
	var ql = Control.new()
	ql.name = "QuestLogHUD"
	ql.set_script(load("res://scripts/quest_log_hud.gd"))
	$World/UI.add_child(ql)

func _setup_quest_tracker_hud():
	# Phase H: 常驻任务追踪器——实时显示追踪中任务的进度条，无需打开日志面板
	var qt = Control.new()
	qt.name = "QuestTrackerHUD"
	qt.set_script(load("res://scripts/quest_tracker_hud.gd"))
	$World/UI.add_child(qt)

func _setup_character_sheet():
	# 已由 _setup_character_panel（统一角色面板）替代，保留空函数防外部引用报错
	pass