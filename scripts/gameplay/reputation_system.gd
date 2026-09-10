class_name ReputationSystem
extends RefCounted
## 四轨声望核心（P1-1 自包含实现，暂不接入 GameManager/Autoload/UI）。
## 设计依据：docs/大唐穿越重构-剧情与玩法设计-2026-09-04.md §5。
## 四轨：民心/朝纲/军功/文名，各轨取值 [value_min, value_max]，跌破敌对阈值即对应势力敌对
## （允许负值——与旧 GameManager.reputation 钳制 ≥0 的关键差异，P1-2 桥接时处理兼容）。
## 总声望 = 加权和（朝纲/军功 1.2，民心 1.0，文名 0.8）；单轨段位与总声望舞台
## 均由 data/reputation_config.json 配置驱动；段位里程碑采用"发放水位"制：
## 只对超过历史最高段位的部分发放天命点，衰减降级后回升不重复领取。

signal reputation_changed(track: String, old_value: float, new_value: float, reason: String)
signal tier_changed(track: String, old_tier: int, new_tier: int)
signal hostility_changed(track: String, hostile: bool)
signal total_changed(old_total: float, new_total: float)
signal stage_changed(old_stage: int, new_stage: int)

const CONFIG_PATH := "res://data/reputation_config.json"

## 轨道顺序固定：民心→朝纲→军功→文名（UI 展示与存档序列化共用）。
const TRACKS: PackedStringArray = ["minxin", "chaogang", "jungong", "wenming"]

## 内置默认配置：JSON 缺失/损坏时回退，保证核心永远可实例化（数值与 JSON 同源维护）。
const DEFAULT_CONFIG: Dictionary = {
	"track_names": {"minxin": "民心", "chaogang": "朝纲", "jungong": "军功", "wenming": "文名"},
	"track_weights": {"minxin": 1.0, "chaogang": 1.2, "jungong": 1.2, "wenming": 0.8},
	"value_max": 10000.0,
	"value_min": -1000.0,
	"hostility_threshold": 0.0,
	"weekly_decay_rate": 0.001,
	"daily_income_rate": 0.001,
	"tiers": [
		{"name": "默默无闻", "threshold": 0.0},
		{"name": "小有名气", "threshold": 200.0},
		{"name": "声名鹊起", "threshold": 800.0},
		{"name": "名动京师", "threshold": 2000.0},
		{"name": "国之柱石", "threshold": 5000.0},
		{"name": "青史留名", "threshold": 10000.0},
	],
	"milestone_rewards": [0, 300, 800, 1500, 3000, 6000],
	"stages": [
		{"name": "默默无闻", "threshold": 0.0, "unlock": "陈家村、灞桥集"},
		{"name": "小有名气", "threshold": 600.0, "unlock": "万年县衙"},
		{"name": "声名鹊起", "threshold": 2400.0, "unlock": "长安城（西市/坊间）"},
		{"name": "名动京师", "threshold": 8000.0, "unlock": "太极宫朝堂"},
		{"name": "国之柱石", "threshold": 20000.0, "unlock": "天可汗体系、十六卫"},
		{"name": "青史留名", "threshold": 40000.0, "unlock": "终幕抉择"},
	],
	"stage_rewards": [0, 500, 1200, 2500, 5000, 10000],
}

var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
var values: Dictionary = {}          # track -> float 当前声望
var max_tier_reached: Dictionary = {}  # track -> int 已发放里程碑的最高段位水位
var max_stage_reached: int = 0


func _init(config_path: String = CONFIG_PATH) -> void:
	for track in TRACKS:
		values[track] = 0.0
		max_tier_reached[track] = 0
	_load_config(config_path)


## 从 JSON 加载配置；失败时保留内置默认值并告警（不中断——声望核心不允许因配置问题不可用）。
func _load_config(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_warning("[RepSys] 配置缺失，使用内置默认：%s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_warning("[RepSys] 配置解析失败，使用内置默认：%s" % path)
		return
	for key in parsed.keys():
		if DEFAULT_CONFIG.has(key):
			config[key] = parsed[key]


func is_valid_track(track: String) -> bool:
	return TRACKS.has(track)


func track_name(track: String) -> String:
	return String(config["track_names"].get(track, track))


func get_value(track: String) -> float:
	return float(values.get(track, 0.0))


## 增减声望（amount 可为负=透支/惩罚）。返回实际变化量；未知道轨拒绝并返回 0。
func add_reputation(track: String, amount: float, reason: String = "") -> float:
	if not is_valid_track(track):
		push_warning("[RepSys] 未知道轨：%s" % track)
		return 0.0
	var old_value := get_value(track)
	var new_value := clampf(old_value + amount, config["value_min"], config["value_max"])
	if is_equal_approx(old_value, new_value):
		return 0.0
	var old_total := get_total()
	values[track] = new_value
	reputation_changed.emit(track, old_value, new_value, reason)
	_refresh_tier(track, old_value)
	_refresh_hostility(track, old_value)
	_refresh_total(old_total)
	return new_value - old_value


## 总声望 = Σ(轨道 × 权重)。负轨参与加权（透支同样拉低总声望）。
func get_total() -> float:
	var total := 0.0
	for track in TRACKS:
		total += get_value(track) * config["track_weights"].get(track, 1.0)
	return total


## 单轨段位索引（0 起）。负值轨恒为 0 段（默默无闻），敌对状态另行查询。
func get_tier(track: String) -> int:
	return _tier_for_value(get_value(track), config["tiers"])


func get_tier_name(track: String) -> String:
	var tiers: Array = config["tiers"]
	return String(tiers[get_tier(track)]["name"])


## 总声望舞台索引（0 起），对应设计 §5.2 剧情舞台门槛（不可跳级）。
func get_stage() -> int:
	return _tier_for_value(get_total(), config["stages"])


func get_stage_name() -> String:
	var stages: Array = config["stages"]
	return String(stages[get_stage()]["name"])


func get_stage_unlock() -> String:
	var stages: Array = config["stages"]
	return String(stages[get_stage()].get("unlock", ""))


## 该轨是否敌对（跌破敌对阈值，设计红线：民心负=义军声讨、朝纲负=下狱事件）。
func is_hostile(track: String) -> bool:
	return get_value(track) < float(config["hostility_threshold"])


## 周衰减「人走茶凉」：每轨每周 -weekly_decay_rate（复利）。仅正值衰减——
## 敌对记忆不会自动消散（负值不自动恢复也不加深），赎罪须走显式声望事件。
func apply_weekly_decay(weeks: float = 1.0) -> void:
	if weeks <= 0.0:
		return
	var factor := 1.0 - float(config["weekly_decay_rate"]) * weeks
	for track in TRACKS:
		var v := get_value(track)
		if v > float(config["hostility_threshold"]):
			add_reputation(track, v * factor - v, "周衰减")


## 领取单轨段位里程碑：返回自发放水位至当前段位的累计天命点，并推进水位。
## 由 DestinyWallet 在 tier_changed 信号里调用；衰减降级后再回升不会重复领取。
func claim_tier_milestone(track: String) -> int:
	if not is_valid_track(track):
		return 0
	var rewards: Array = config["milestone_rewards"]
	var tier := get_tier(track)
	var paid_tier := int(max_tier_reached.get(track, 0))
	var amount := 0
	for i in range(paid_tier + 1, tier + 1):
		amount += int(rewards[i]) if i < rewards.size() else 0
	if amount > 0:
		max_tier_reached[track] = tier
	return amount


## 领取总声望舞台里程碑（同理水位制）。
func claim_stage_milestone() -> int:
	var rewards: Array = config["stage_rewards"]
	var stage := get_stage()
	var amount := 0
	for i in range(max_stage_reached + 1, stage + 1):
		amount += int(rewards[i]) if i < rewards.size() else 0
	if amount > 0:
		max_stage_reached = stage
	return amount


## 日结天命点基数：按总声望 0.1%/日（挂机保底）。负总声望不发钱。
func daily_income() -> int:
	return maxi(0, int(get_total() * float(config["daily_income_rate"])))


func _tier_for_value(value: float, ladder: Array) -> int:
	var tier := 0
	for i in ladder.size():
		if value >= float(ladder[i]["threshold"]):
			tier = i
		else:
			break
	return tier


func _refresh_tier(track: String, old_value: float) -> void:
	var old_tier := _tier_for_value(old_value, config["tiers"])
	var new_tier := get_tier(track)
	if new_tier != old_tier:
		tier_changed.emit(track, old_tier, new_tier)


func _refresh_hostility(track: String, old_value: float) -> void:
	var threshold := float(config["hostility_threshold"])
	var was := old_value < threshold
	var now := get_value(track) < threshold
	if now != was:
		hostility_changed.emit(track, now)


func _refresh_total(old_total: float) -> void:
	var new_total := get_total()
	total_changed.emit(old_total, new_total)
	var old_stage := _tier_for_value(old_total, config["stages"])
	var new_stage := _tier_for_value(new_total, config["stages"])
	if new_stage != old_stage:
		stage_changed.emit(old_stage, new_stage)


## 存档序列化（P2 存档系统接线用）。
func to_dict() -> Dictionary:
	var out := {"values": {}, "max_tier_reached": {}, "max_stage_reached": max_stage_reached}
	for track in TRACKS:
		out["values"][track] = get_value(track)
		out["max_tier_reached"][track] = int(max_tier_reached.get(track, 0))
	return out


func from_dict(data: Dictionary) -> void:
	for track in TRACKS:
		if data.get("values", {}).has(track):
			values[track] = clampf(float(data["values"][track]), config["value_min"], config["value_max"])
		if data.get("max_tier_reached", {}).has(track):
			max_tier_reached[track] = int(data["max_tier_reached"][track])
	max_stage_reached = int(data.get("max_stage_reached", 0))
