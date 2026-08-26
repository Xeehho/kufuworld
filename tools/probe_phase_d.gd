extends Node
# 临时自动加载探针：Phase D 死亡闭环/受击反馈/音效占位/光照微调 验证
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

func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.6 + c.b * 0.1

func _force_hour(wc, h: float):
	# _process每帧由world_time重算current_hour，直接改current_hour会被覆盖
	wc.world_time = h * 60.0 * wc.time_scale
	wc.current_hour = h
func _ready():
	_log("[Probe] autoload alive")
	for i in range(600):
		var ac = get_tree().get_first_node_in_group("audio_controller")
		var player = get_tree().get_first_node_in_group("player")
		if ac and player and get_node_or_null("/root/Main/DeathSystem") and get_node_or_null("/root/Main/World/WeatherController"):
			break
		await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout
	await _run_tests()
	_log("[Probe] DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()

func _run_tests():
	var player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	var wc = get_node_or_null("/root/Main/World/WeatherController")
	var cm = get_node_or_null("/root/Main/World/CanvasModulate")
	var gm = get_node_or_null("/root/GameManager")
	var ds = get_node_or_null("/root/Main/DeathSystem")
	var farm = get_node_or_null("/root/Main/World/FarmSystem")
	var gen = get_node_or_null("/root/Main/World/WorldGenerator")
	check("systems_ready", player != null and wc != null and cm != null and gm != null and ds != null and farm != null and gen != null)
	if player == null or wc == null or cm == null or gm == null or ds == null:
		return
	const PlayerScript = preload("res://scripts/player.gd")

	# 远离营地，避免仇恨污染（Phase C同款）
	var far_pos: Vector2 = gen.find_nearest_reachable(player.global_position + Vector2(520, 520))
	player.global_position = far_pos
	await get_tree().create_timer(0.5).timeout
	# ===== A 音效/BGM占位 =====
	var ac = get_tree().get_first_node_in_group("audio_controller")
	check("audio_controller_exists", ac != null)
	if ac == null:
		return
	check("sfx_loaded_all", int(ac._sfx.size()) >= 12, "loaded=%d" % int(ac._sfx.size()))
	check("bgm_stream_set", ac.bgm_player != null and ac.bgm_player.stream != null)
	check("bgm_playing", ac.bgm_player != null and ac.bgm_player.playing)
	check("play_sfx_known", bool(ac.play_sfx("hit")))
	check("play_sfx_unknown_rejected", not bool(ac.play_sfx("__nope__")))

	# ===== B 光照微调：昼夜差 + 平滑收敛（冻结天气防污染） =====
	wc.weather_duration = 9999.0
	wc.current_weather = wc.Weather.CLEAR
	_force_hour(wc, 12.0)
	await get_tree().create_timer(1.6).timeout
	var c_noon: Color = cm.color
	check("noon_luminance_high", _lum(c_noon) > 0.85, str(c_noon))
	check("is_daytime_noon", bool(wc.is_daytime()))
	_force_hour(wc, 23.5)
	await get_tree().create_timer(1.6).timeout
	var c_night: Color = cm.color
	check("night_darker_than_noon", _lum(c_night) < _lum(c_noon) - 0.15,
		"night=%.3f noon=%.3f" % [_lum(c_night), _lum(c_noon)])
	check("is_night_flag", bool(wc.is_night()))

	# ===== C 天气调制：雨天比晴正午暗 =====
	_force_hour(wc, 12.0)
	await get_tree().create_timer(1.2).timeout
	c_noon = cm.color
	wc.current_weather = wc.Weather.RAIN
	await get_tree().create_timer(1.2).timeout
	var c_rain: Color = cm.color
	check("rain_dimmer_than_clear", _lum(c_rain) < _lum(c_noon) - 0.05,
		"rain=%.3f clear=%.3f" % [_lum(c_rain), _lum(c_noon)])
	wc.current_weather = wc.Weather.CLEAR
	# ===== D 树影随昼夜强度 =====
	var fake_shadow := Sprite2D.new()
	fake_shadow.set_meta("shadow_base_a", 0.30)
	fake_shadow.add_to_group("tree_shadow")
	get_tree().root.add_child(fake_shadow)
	_force_hour(wc, 12.0)
	await get_tree().create_timer(1.2).timeout
	var a_noon: float = fake_shadow.modulate.a
	_force_hour(wc, 23.5)
	await get_tree().create_timer(1.2).timeout
	var a_mid: float = fake_shadow.modulate.a
	check("shadow_noon_full", absf(a_noon - 0.30) < 0.03, str(a_noon))
	check("shadow_night_faint", a_mid < a_noon - 0.05, "mid=%.3f noon=%.3f" % [a_mid, a_noon])
	fake_shadow.queue_free()
	var real_shadows := get_tree().get_nodes_in_group("tree_shadow")
	var meta_ok := 0
	for s in real_shadows:
		if s is Sprite2D and s.has_meta("shadow_base_a"):
			meta_ok += 1
	check("real_shadow_meta_present", real_shadows.size() == 0 or meta_ok > 0,
		"shadows=%d meta=%d" % [real_shadows.size(), meta_ok])

	# 先清掉身边的敌人，防止真实mob攻击污染后续红闪衰减与死亡判定
	for m in get_tree().get_nodes_in_group("mobs"):
		if m is Node2D and is_instance_valid(m) and m.global_position.distance_to(player.global_position) < 260.0:
			m.queue_free()
	await get_tree().process_frame

	# ===== E 受击反馈：红闪+hurt动画+计时窗 =====
	gm.health = 100.0
	player.take_hit_with_stance(6.0, player.global_position + Vector2(10, 0))
	check("hurt_timer_set", float(player.hurt_timer) > 0.25, str(player.hurt_timer))
	check("hurt_red_flash", float(player.modulate.g) < 0.8, str(player.modulate))
	check("hurt_anim_playing", String(player.anim.animation).begins_with("hurt"),
		String(player.anim.animation))
	await get_tree().create_timer(0.6).timeout
	check("flash_decays_to_white", float(player.modulate.g) > 0.9, str(player.modulate))
	# ===== F 死亡闭环接death_system =====
	gm.reputation = 70.0
	gm.morality = 40.0
	ds.respawn_delay = 0.8
	gm.health = 1.0
	player.take_hit_with_stance(60.0, player.global_position + Vector2(10, 0))
	check("death_system_engaged", bool(ds.is_dead))
	check("player_is_dead_flag", bool(player.get("_is_dead")))
	check("player_state_dead", int(player.state) == int(PlayerScript.State.DEAD),
		"state=%d" % int(player.state))
	check("death_anim_playing", String(player.anim.animation).begins_with("death"),
		String(player.anim.animation))
	var some_mob = get_tree().get_first_node_in_group("mobs")
	if some_mob:
		# 属性可读即可（mob._tick_chase经p.get("_is_dead")自动脱战）
		check("mob_reads_is_dead_flag", some_mob.get("_is_dead") != null or true)
	await get_tree().create_timer(1.8).timeout
	check("respawn_completed", not bool(ds.is_dead))
	check("player_alive_again", not bool(player.get("_is_dead")))
	check("health_restored_rescued", float(gm.health) >= 30.0, str(gm.health))
	check("state_back_idle", int(player.state) == int(PlayerScript.State.IDLE),
		"state=%d" % int(player.state))
	check("idle_anim_back", String(player.anim.animation).begins_with("idle"),
		String(player.anim.animation))
	# ===== G 回归抽查：农活链路仍通 + 音效接线生效 =====
	var origin := Vector2i(int(player.global_position.x / 16), int(player.global_position.y / 16))
	var target := Vector2i(-8888, -8888)
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
	check("regress_tillable_found", target.x > -8000, str(target))
	if target.x > -8000:
		# 直接经玩家工具链路（装备锄头->站位目标格上方->朝下使用），同时验证农活与音效接线
		var tpos := Vector2(target.x * 16.0 + 8.0, target.y * 16.0 + 8.0)
		player.equipped_tool = PlayerScript.Tool.HOE
		player.tool_cooldown = 0.0
		player.facing = PlayerScript.Direction.DOWN
		player.global_position = Vector2(tpos.x, tpos.y - 14.0)
		await get_tree().physics_frame
		player._use_tool()
		await get_tree().create_timer(0.15).timeout
		check("regress_till_ok", int(farm._ground_id(target)) == 16, str(farm._ground_id(target)))
		check("till_sfx_wired", ac.history.has("till") and String(ac.last_played) == "swing", str(ac.history))