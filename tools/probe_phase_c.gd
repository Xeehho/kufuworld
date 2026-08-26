extends Node
# 临时自动加载探针：Phase C 农场/敌人/站台全链路逻辑验证
# 用完必须把 ProbeAutoload 从 project.godot [autoload] 移除！日志: tools/probe_log.txt
const LOG := "C:/Learn/my-godot-project/tools/probe_log.txt"
var passes := 0
var fails := 0

func _log(msg: String):
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(msg)
		f.close()
	print(msg)

func check(name: String, cond: bool, extra: String = ""):
	if cond:
		passes += 1
		_log("[PASS] " + name)
	else:
		fails += 1
		_log("[FAIL] " + name + "  " + extra)

func _dump_inventory(inv):
	var parts := []
	for slot in inv.inventory:
		parts.append("%sx%d" % [slot["item"].item_id, slot["count"]])
	_log("[Probe] 背包: " + ", ".join(parts))

func _ready():
	for i in range(400):
		var fs = get_node_or_null("/root/Main/World/FarmSystem")
		var player = get_tree().get_first_node_in_group("player")
		if fs and player and get_node_or_null("/root/Main/World/MobSpawner"):
			break
		await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	await _run_tests()
	_log("[Probe] DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()

func _run_tests():
	var player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	var farm = get_node_or_null("/root/Main/World/FarmSystem")
	var inv = get_node_or_null("/root/Main/InventoryManager")
	var gen = get_node_or_null("/root/Main/World/WorldGenerator")
	var st_sys = get_node_or_null("/root/Main/World/StationSystem")
	var spawner = get_node_or_null("/root/Main/World/MobSpawner")
	check("systems_ready", farm != null and inv != null and gen != null and st_sys != null and spawner != null)
	var wc = get_node_or_null("/root/Main/World/WeatherController")
	if wc: wc.queue_free()
	var cm = get_node_or_null("/root/Main/World/CanvasModulate")
	if cm: cm.color = Color(1, 1, 1, 1)
	# 远离营地（营地锚定在出生点附近），避免仇恨污染后续判定
	var far_pos: Vector2 = gen.find_nearest_reachable(player.global_position + Vector2(520, 520))
	player.global_position = far_pos
	await get_tree().create_timer(0.5).timeout

	# ===== 农场链路 =====
	var origin := Vector2i(int(player.global_position.x / 16), int(player.global_position.y / 16))
	var target := Vector2i(-9999, -9999)
	for r in range(1, 30):
		var found := false
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := origin + Vector2i(dx, dy)
				var tid = gen.get_tile_id(c.x, c.y)
				if tid == 0 or tid == 18:
					target = c
					found = true
					break
			if found: break
		if found: break
	check("tillable_cell_found", target.x > -9000, str(target))
	var tpos := Vector2(target.x * 16.0 + 8.0, target.y * 16.0 + 8.0)
	var seeds_before: int = inv.get_item_count("vegetable_seeds")
	var r_till: Dictionary = farm.try_till(tpos)
	check("till_ok", bool(r_till["ok"]), str(r_till))
	check("ground_is_farmland", farm._ground_id(target) == 16)
	var r_plant: Dictionary = farm.try_plant(tpos)
	check("plant_ok", bool(r_plant["ok"]), str(r_plant))
	check("seed_consumed", inv.get_item_count("vegetable_seeds") == seeds_before - 1,
		"%d->%d" % [seeds_before, inv.get_item_count("vegetable_seeds")])
	var r_water: Dictionary = farm.try_water(tpos)
	check("water_ok", bool(r_water["ok"]), str(r_water))
	check("ground_is_wet", farm._ground_id(target) == 33)
	check("crop_watered_flag", farm.crops.has(target) and bool(farm.crops[target]["watered"]))
	# 未浇水的一天：不生长（设计验证）——第一次on_new_day消耗当前浇水，第二次应停滞
	farm.on_new_day()
	var days_after_first := int(farm.crops[target]["days"])
	farm.on_new_day()
	check("unwatered_day_stalls_growth", int(farm.crops[target]["days"]) == days_after_first,
		str(farm.crops.get(target, {})))
	# 每天浇水，3天后成熟
	for i in range(3):
		farm.try_water(tpos)
		farm.on_new_day()
	check("crop_mature_after_3_watered_days", farm.crops.has(target) and int(farm.crops[target]["stage"]) == 3,
		str(farm.crops.get(target, {})))
	var veggies_before: int = inv.get_item_count("veggie")
	var r_col: Dictionary = farm.try_collect(tpos)
	check("harvest_ok", bool(r_col["ok"]), str(r_col))
	check("veggie_gained", inv.get_item_count("veggie") > veggies_before)
	check("crop_removed", not farm.crops.has(target))
	farm.try_plant(tpos)
	var r_raw: Dictionary = farm.try_collect(tpos)
	check("unripe_rejected", not bool(r_raw["ok"]), str(r_raw))

	# ===== 浆果丛 =====
	if farm.bushes.size() > 0:
		var bcell: Vector2i = farm.bushes.keys()[0]
		var bpos := Vector2(bcell.x * 16.0 + 8.0, bcell.y * 16.0 + 8.0)
		var berries0: int = inv.get_item_count("berry")
		var rb: Dictionary = farm.try_collect(bpos)
		check("bush_harvest_ok", bool(rb["ok"]), str(rb))
		check("berry_gained", inv.get_item_count("berry") > berries0)
		check("bush_emptied", not bool(farm.bushes[bcell]["has_fruit"]))
	else:
		check("bushes_scattered", false, "no bushes scattered")

	# ===== 敌人系统：营地生成 =====
	var mobs_alive := get_tree().get_nodes_in_group("mobs").size()
	for m in get_tree().get_nodes_in_group("mobs"):
		_log("[Probe]   mob %s @ %s state=%d" % [m.name, str(m.global_position), int(m.state)])
	if spawner:
		for camp in spawner.camps_runtime:
			_log("[Probe]   camp[%s] alive=%d center=%s" % [camp["def"]["name"], camp["alive"], str(camp["center"])])
	check("camps_spawned", mobs_alive >= 4, "alive=%d" % mobs_alive)

	# ===== 玩家→mob 伤害闭环 =====
	var MobScript = load("res://scripts/mob.gd")
	var mob = CharacterBody2D.new()
	mob.set_script(MobScript)
	mob.position = player.global_position + Vector2(40, 0)
	player.get_parent().add_child(mob)
	mob.setup("orc_warrior")
	await get_tree().process_frame
	await get_tree().process_frame
	var hp0: float = mob.hp
	player.facing = 2   # Direction.RIGHT
	player.facing = player.facing
	var detected = player._find_mob_in_front()
	check("mob_in_front_detected", detected == mob, str(detected))
	mob.take_damage(12.0)
	check("mob_hp_reduced", mob.hp < hp0, "hp=%.1f" % mob.hp)
	check("mob_aggro_locked", float(mob.aggro_lock_timer) > 0.0)
	var ore0: int = inv.get_item_count("iron_ore")
	mob.take_damage(999.0)
	check("mob_dying_state", int(mob.state) == 4, "state=%d" % int(mob.state))
	await get_tree().create_timer(0.3).timeout
	_dump_inventory(inv)
	check("loot_dropped_on_death", inv.get_item_count("iron_ore") > ore0,
		"ore %d->%d" % [ore0, inv.get_item_count("iron_ore")])

	# ===== mob→玩家 伤害闭环 =====
	var mob2 = CharacterBody2D.new()
	mob2.set_script(MobScript)
	mob2.position = player.global_position + Vector2(20, 0)
	player.get_parent().add_child(mob2)
	mob2.setup("skeleton_warrior")
	await get_tree().process_frame
	GameManager.health = 80.0
	mob2._do_attack()
	check("mob_damages_player", GameManager.health < 80.0, "hp=%.1f" % GameManager.health)
	mob2.queue_free()

	# ===== 站台系统 =====
	var spos: Vector2 = player.global_position + Vector2(32, 0)
	var station = st_sys.place_station("熔炉", spos)
	check("furnace_placed", station != null and is_instance_valid(station))
	var near = st_sys.nearest_station(player, 99999.0)
	check("nearest_station_found", near == station, str(near))
	while inv.has_item("iron_ore"):
		inv.remove_item("iron_ore", inv.get_item_count("iron_ore"))
	var r_nomat: Dictionary = st_sys.try_craft(station)
	check("craft_no_material_fails", not bool(r_nomat["ok"]), str(r_nomat))
	var ItemFactory = load("res://scripts/item_factory.gd")
	ItemFactory.give("iron_ore", 2)
	_dump_inventory(inv)
	var ore_before: int = inv.get_item_count("iron_ore")
	var r_craft: Dictionary = st_sys.try_craft(station)
	check("craft_ok", bool(r_craft["ok"]), str(r_craft))
	check("ingot_produced", inv.get_item_count("iron_ingot") == 1)
	check("ore_consumed", inv.get_item_count("iron_ore") == ore_before - 2)
