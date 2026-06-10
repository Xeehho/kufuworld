extends Node

# 架势系统 - 管理攻击/防御架势切换、破绽值、格挡反击

enum Stance { NEUTRAL, ATTACK, DEFENSE }

var current_stance: int = Stance.NEUTRAL
var vulnerability: float = 0.0        # 破绽值 0-100
var max_vulnerability: float = 100.0
var vulnerability_decay: float = 5.0  # 每秒自然衰减
var stance_switch_cooldown: float = 0.0
var stance_switch_cd_max: float = 0.5 # 切换冷却0.5秒
var block_counter_window: float = 0.0 # 格挡反击窗口
var block_counter_window_max: float = 0.4
var is_in_block_counter: bool = false
var hit_count: int = 0                # 连续命中计数
var hit_count_timer: float = 0.0      # 连击重置计时
var hit_count_timeout: float = 2.0    # 2秒无命中重置连击

# 架势伤害修正
const ATTACK_STANCE_DAMAGE_MULT: float = 1.4    # 攻击架势伤害+40%
const ATTACK_STANCE_DEFENSE_MULT: float = 0.6   # 攻击架势防御-40%
const DEFENSE_STANCE_DAMAGE_MULT: float = 0.7   # 防御架势伤害-30%
const DEFENSE_STANCE_DEFENSE_MULT: float = 1.5  # 防御架势防御+50%
const NEUTRAL_DAMAGE_MULT: float = 1.0
const NEUTRAL_DEFENSE_MULT: float = 1.0

# 破绽值参数
const VULN_ON_HIT_ATTACK_STANCE: float = 15.0   # 攻击架势被命中增加破绽
const VULN_ON_HIT_NEUTRAL: float = 8.0          # 中立架势被命中增加破绽
const VULN_ON_HIT_DEFENSE_STANCE: float = 4.0   # 防御架势被命中增加破绽
const VULN_ON_DEAL_HIT: float = 3.0             # 命中对手增加对手破绽
const VULN_STAGGER_THRESHOLD: float = 80.0      # 破绽值>=80时大硬直
const STAGGER_DURATION: float = 1.2             # 大硬直持续时间

# 格挡反击
const BLOCK_COUNTER_DAMAGE_MULT: float = 2.0    # 格挡反击伤害x2
const BLOCK_COUNTER_VULN_REDUCTION: float = 30.0 # 格挡反击减少自身破绽

signal stance_changed(new_stance)
signal vulnerability_changed(value)
signal stagger_triggered
signal block_counter_available
signal block_counter_executed

func _process(delta):
	# 破绽值自然衰减
	if vulnerability > 0:
		vulnerability = max(vulnerability - vulnerability_decay * delta, 0)
		vulnerability_changed.emit(vulnerability)
	
	# 切换冷却
	if stance_switch_cooldown > 0:
		stance_switch_cooldown -= delta
	
	# 连击计时
	if hit_count_timer > 0:
		hit_count_timer -= delta
		if hit_count_timer <= 0:
			hit_count = 0
	
	# 格挡反击窗口
	if block_counter_window > 0:
		block_counter_window -= delta
		if block_counter_window <= 0:
			is_in_block_counter = false

func switch_stance(new_stance: int) -> bool:
	if new_stance == current_stance:
		return false
	if stance_switch_cooldown > 0:
		return false
	current_stance = new_stance
	stance_switch_cooldown = stance_switch_cd_max
	stance_changed.emit(current_stance)
	var names = ["中立", "攻击", "防御"]
	print("[Stance] 切换为" + names[current_stance] + "架势")
	return true

func get_damage_multiplier() -> float:
	if current_stance == Stance.ATTACK:
		return ATTACK_STANCE_DAMAGE_MULT
	elif current_stance == Stance.DEFENSE:
		return DEFENSE_STANCE_DAMAGE_MULT
	return NEUTRAL_DAMAGE_MULT

func get_defense_multiplier() -> float:
	if current_stance == Stance.ATTACK:
		return ATTACK_STANCE_DEFENSE_MULT
	elif current_stance == Stance.DEFENSE:
		return DEFENSE_STANCE_DEFENSE_MULT
	return NEUTRAL_DEFENSE_MULT

func on_hit_dealt() -> float:
	# 命中对手，增加对手破绽，返回伤害修正
	hit_count += 1
	hit_count_timer = hit_count_timeout
	var vuln_increase = VULN_ON_DEAL_HIT + hit_count * 2.0  # 连击额外增加破绽
	var dmg_mult = get_damage_multiplier()
	# 连击加成
	if hit_count >= 3:
		dmg_mult += 0.1 * (hit_count - 2)  # 3连+10%, 4连+20%...
	print("[Combat] 命中! 连击x" + str(hit_count) + " 破绽+" + str(vuln_increase))
	return dmg_mult

func on_hit_received(damage: float) -> float:
	# 被命中，增加自身破绽，返回实际伤害
	var vuln_increase = 0.0
	if current_stance == Stance.ATTACK:
		vuln_increase = VULN_ON_HIT_ATTACK_STANCE
	elif current_stance == Stance.DEFENSE:
		vuln_increase = VULN_ON_HIT_DEFENSE_STANCE
	else:
		vuln_increase = VULN_ON_HIT_NEUTRAL
	
	vulnerability = min(vulnerability + vuln_increase, max_vulnerability)
	vulnerability_changed.emit(vulnerability)
	
	# 防御修正
	var actual_damage = damage * get_defense_multiplier()
	
	# 检查破绽值是否触发大硬直
	if vulnerability >= VULN_STAGGER_THRESHOLD:
		stagger_triggered.emit()
		print("[Combat] 破绽值满! 大硬直!")
	
	print("[Combat] 受击! 伤害" + str(actual_damage) + " 破绽+" + str(vuln_increase) + " 总破绽=" + str(vulnerability))
	return actual_damage

func on_block_hit():
	# 格挡成功，开启反击窗口
	block_counter_window = block_counter_window_max
	is_in_block_counter = true
	block_counter_available.emit()
	print("[Combat] 格挡成功! 反击窗口开启!")

func try_block_counter() -> bool:
	# 尝试格挡反击
	if not is_in_block_counter:
		return false
	is_in_block_counter = false
	block_counter_window = 0
	vulnerability = max(vulnerability - BLOCK_COUNTER_VULN_REDUCTION, 0)
	vulnerability_changed.emit(vulnerability)
	block_counter_executed.emit()
	print("[Combat] 格挡反击! 伤害x" + str(BLOCK_COUNTER_DAMAGE_MULT) + " 破绽-" + str(BLOCK_COUNTER_VULN_REDUCTION))
	return true

func get_block_counter_damage_mult() -> float:
	if is_in_block_counter:
		return BLOCK_COUNTER_DAMAGE_MULT
	return 1.0

func is_staggered() -> bool:
	return vulnerability >= VULN_STAGGER_THRESHOLD

func get_stance_name() -> String:
	var names = ["中立", "攻击", "防御"]
	return names[current_stance]

func reset():
	current_stance = Stance.NEUTRAL
	vulnerability = 0.0
	hit_count = 0
	hit_count_timer = 0.0
	is_in_block_counter = false
	block_counter_window = 0.0
