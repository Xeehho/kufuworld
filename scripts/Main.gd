extends Node2D

@onready var world: Node2D = $World

func _ready():
	print("Godot Trae Project initialized!")
	print("MCP Server URL: http://127.0.0.1:8000/mcp")
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
	world.move_child(gen, 0)

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
