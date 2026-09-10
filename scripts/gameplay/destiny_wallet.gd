class_name DestinyWallet
extends RefCounted
## 天命点钱包（P1-1 自包含实现，暂不接入 GameManager/UI）。
## 设计依据：docs/大唐穿越重构-剧情与玩法设计-2026-09-04.md §6.1。
## 天命点是系统货币，与游戏内铜钱完全隔离（禁止双向兑换，防刷钱破坏经营系统）。
## 收入来源：声望里程碑（大头）、系统任务/成就（外部调 earn）、声望日结（细水长流）。
## 支出：商城、天命轮盘、回响保险（死亡保护）——全部走 spend，不足即拒绝。

signal points_changed(old_points: int, new_points: int, reason: String)
signal milestone_paid(amount: int, reason: String)

## 用 preload 而非裸 class_name 引用：headless --script 场景读不到新类的全局缓存。
const RepSysScript := preload("res://scripts/gameplay/reputation_system.gd")

var points: int = 0
var lifetime_earned: int = 0
var lifetime_spent: int = 0

var _rep: RepSysScript = null


## 绑定声望系统：段位/舞台晋升自动入账里程碑，日结按绑定系统总声望结算。
## 幂等：重复绑定同一实例直接返回。
func bind_reputation_system(rep: RepSysScript) -> void:
	if rep == null or rep == _rep:
		return
	_rep = rep
	_rep.tier_changed.connect(_on_tier_changed)
	_rep.stage_changed.connect(_on_stage_changed)


func unbind_reputation_system() -> void:
	if _rep == null:
		return
	if _rep.tier_changed.is_connected(_on_tier_changed):
		_rep.tier_changed.disconnect(_on_tier_changed)
	if _rep.stage_changed.is_connected(_on_stage_changed):
		_rep.stage_changed.disconnect(_on_stage_changed)
	_rep = null


## 入账（amount ≤ 0 拒绝，防误传符号）。系统任务/成就/剧情奖励走这里。
func earn(amount: int, reason: String = "") -> bool:
	if amount <= 0:
		push_warning("[Destiny] 非法入账数额：%d（reason=%s）" % [amount, reason])
		return false
	var old := points
	points += amount
	lifetime_earned += amount
	points_changed.emit(old, points, reason)
	return true


## 支出（商城/轮盘/回响）。余额不足返回 false 且不产生任何变化。
func spend(amount: int, reason: String = "") -> bool:
	if amount <= 0:
		push_warning("[Destiny] 非法支出数额：%d（reason=%s）" % [amount, reason])
		return false
	if points < amount:
		return false
	var old := points
	points -= amount
	lifetime_spent += amount
	points_changed.emit(old, points, reason)
	return true


## 声望日结：每日按总声望 0.1% 结算（挂机保底）。返回当日入账数额。
func settle_daily(total_reputation: float = -1.0) -> int:
	var total := total_reputation
	if total < 0.0 and _rep != null:
		total = _rep.get_total()
	var rate := float(_rate_config().get("daily_income_rate", 0.001))
	var amount := maxi(0, int(total * rate))
	if amount > 0:
		earn(amount, "声望日结")
	return amount


## 存档序列化（P2 存档系统接线用）。
func to_dict() -> Dictionary:
	return {
		"points": points,
		"lifetime_earned": lifetime_earned,
		"lifetime_spent": lifetime_spent,
	}


func from_dict(data: Dictionary) -> void:
	points = int(data.get("points", 0))
	lifetime_earned = int(data.get("lifetime_earned", 0))
	lifetime_spent = int(data.get("lifetime_spent", 0))


func _on_tier_changed(track: String, _old_tier: int, _new_tier: int) -> void:
	# 发放决策在 ReputationSystem（规则层，水位制防重复），钱包只负责入账
	if _rep == null:
		return
	var amount := _rep.claim_tier_milestone(track)
	if amount > 0:
		earn(amount, "声望里程碑·%s%s" % [_rep.track_name(track), _rep.get_tier_name(track)])
		milestone_paid.emit(amount, "tier:%s" % track)


func _on_stage_changed(_old_stage: int, _new_stage: int) -> void:
	if _rep == null:
		return
	var amount := _rep.claim_stage_milestone()
	if amount > 0:
		earn(amount, "声望舞台·%s" % _rep.get_stage_name())
		milestone_paid.emit(amount, "stage")


func _rate_config() -> Dictionary:
	if _rep != null:
		return _rep.config
	return RepSysScript.DEFAULT_CONFIG
