extends Node2D

# 树木采伐系统 v1 —— 左键攻击命中树可累计砍伐，3刀放倒掉落木材
# 复用 world_generator 生成的 tree_prop 组精灵（节点原点=树干脚底，纹理经offset上移半高，
# 因此旋转即绕根倒下）；掉落走 GameManager.wood 口径（与建造消耗一致，不入背包45格）
# 挂载于 /root/Main/World/TreeChopSystem

const CHOP_HITS := 3        # 放倒所需刀数
const CHOP_REACH := 56.0    # 与攻击扇形判定一致
const CHIP_COUNT := 5       # 每击木屑粒子数
const WOOD_MIN := 2
const WOOD_MAX := 3

func try_chop_front(player: Node2D) -> Dictionary:
	# 几何与 player._find_mob_in_front 同源：距离56px内+朝向夹角余弦>0.25，取最近树
	var fwd: Vector2 = Vector2.DOWN
	if player != null and player.has_method("_facing_vector"):
		fwd = player._facing_vector()
	var best: Sprite2D = null
	var best_d := CHOP_REACH
	for t in get_tree().get_nodes_in_group("tree_prop"):
		var sp := t as Sprite2D
		if sp == null or not is_instance_valid(sp):
			continue
		if sp.has_meta("fell_started"):
			continue   # 正在倒下的树不再响应
		var to_t: Vector2 = sp.global_position - player.global_position
		if to_t.length() > best_d:
			continue
		if to_t.length() > 4.0 and fwd.dot(to_t.normalized()) < 0.25:
			continue
		best_d = to_t.length()
		best = sp
	if best == null:
		return {"ok": false}
	var hits := int(best.get_meta("chop_hits", 0)) + 1
	best.set_meta("chop_hits", hits)
	if hits >= CHOP_HITS:
		_fell_tree(best, signf(best.global_position.x - player.global_position.x))
		return {"ok": true, "felled": true}
	# 未放倒：木屑轻反馈
	_sfx("till", -12.0)
	_wood_chip_fx(best.global_position + Vector2(0, -14))
	return {"ok": true, "felled": false}

func _fell_tree(sp: Sprite2D, dir_x: float):
	sp.set_meta("fell_started", true)
	var dir_sign: float = dir_x if absf(dir_x) > 0.1 else (1.0 if randf() > 0.5 else -1.0)
	var gain := randi_range(WOOD_MIN, WOOD_MAX)
	GameManager.wood += gain
	GameManager.world_state_changed.emit()
	GameManager.emit_event("伐木拾柴", "你放倒了一棵树，获得%d单位木料" % gain, 1)
	print("[Tree] 一棵树被放倒，木材+%d" % gain)
	# 影子独立淡出（不随树体旋转）
	for c in sp.get_children():
		if c is Sprite2D and c.is_in_group("tree_shadow"):
			var stw := c.create_tween()
			stw.tween_property(c, "modulate:a", 0.0, 0.45)
	_sfx("harvest")
	_float_text(sp.global_position + Vector2(-24, -34), "+%d 木材" % gain, Color(0.9, 0.72, 0.4))
	# 绕脚底旋转倒下（offset已使锚点=树根），随后淡出移除；不重生
	var tw := sp.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "rotation_degrees", 88.0 * dir_sign, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(sp, "modulate:a", 0.0, 0.32).set_delay(0.30)
	tw.chain().tween_callback(sp.queue_free)

func _wood_chip_fx(pos: Vector2):
	for i in range(CHIP_COUNT):
		var chip := Polygon2D.new()
		chip.polygon = PackedVector2Array([
			Vector2(-1.5, -1), Vector2(1.5, -1), Vector2(1.5, 1), Vector2(-1.5, 1)])
		chip.color = Color(0.55, 0.38, 0.22)
		chip.position = pos
		chip.z_index = 8
		add_child(chip)
		var ang := randf() * TAU
		var dist := randf_range(8.0, 18.0)
		var tw := chip.create_tween().set_parallel(true)
		tw.tween_property(chip, "position",
			pos + Vector2(cos(ang) * dist, sin(ang) * dist * 0.6 - 6.0), 0.4)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(chip, "modulate:a", 0.0, 0.45)
		tw.chain().tween_callback(chip.queue_free)

func _float_text(pos: Vector2, txt: String, color: Color):
	var lbl = Label.new()
	lbl.text = txt
	lbl.z_index = 20
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.08))
	lbl.add_theme_constant_override("outline_size", 3)
	get_parent().add_child(lbl)
	lbl.global_position = pos
	var tw = lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "global_position:y", pos.y - 26, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.15)
	tw.chain().tween_callback(lbl.queue_free)

func _sfx(sfx_name: String, volume_db: float = -6.0):
	var ac = get_tree().get_first_node_in_group("audio_controller")
	if ac and ac.has_method("play_sfx"):
		ac.play_sfx(sfx_name, volume_db)
