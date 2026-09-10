class_name ReputationBridge
extends RefCounted
## P1-2 兼容桥接：旧单轨 reputation ↔ 新四轨声望系统的翻译层。
## 接入方式见 AI_COLLABORATION.md REQ-20260910-01：`game_manager.gd` 的
## `var reputation` 改 computed property 后，get/set 都走本模块——
## 旧调用方（任务/奇遇/誓约/商店/NPC/死亡）零改动自动进新系统。
## REQ 评估通过前本模块独立存在，不改任何现有文件。
##
## 兼容视图公式（REQ-20260910-01 复查口径①拍板）：
## - TOTAL_NORMALIZED（默认）：旧值 = 总声望/42、写入 ×42 进默认轨——
##   旧门槛 10/30/50、誓约 500、商店折扣 600 均落在合理全局舞台
## - MINXIN_SCALED（备选保留）：旧值 = 民心/100——誓约 500 与折扣 600 不可达，勿用于生产

const RepSysScript := preload("res://scripts/gameplay/reputation_system.gd")
const DWalletScript := preload("res://scripts/gameplay/destiny_wallet.gd")

const VIEW_TOTAL_NORMALIZED := "total_normalized"
const VIEW_MINXIN_SCALED := "minxin_scaled"

## 总声望理论满值 10000×(1.0+1.2+1.2+0.8)=42000，归一到旧值域 0~1000。
const TOTAL_NORMALIZE_DIVISOR := 42.0
## 民心 0~10000 → 旧值域 0~100。
const MINXIN_SCALE_DIVISOR := 100.0

var rep: RepSysScript
var wallet: DWalletScript
var legacy_config: Dictionary = {
	"view_mode": VIEW_TOTAL_NORMALIZED,
	"scale": 42.0,  # 写入放大系数：与视图公式联动（总/42 ↔ 写×42，写读一致）
	"default_track": "minxin",
}


func _init(config_path: String = RepSysScript.CONFIG_PATH) -> void:
	rep = RepSysScript.new(config_path)
	wallet = DWalletScript.new()
	wallet.bind_reputation_system(rep)
	_load_legacy_config(config_path)


## JSON 顶层 "legacy" 节（可选）覆盖桥接默认配置；缺失用内置默认。
func _load_legacy_config(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("legacy") is Dictionary:
		for key in parsed["legacy"].keys():
			if legacy_config.has(key):
				legacy_config[key] = parsed["legacy"][key]


## 旧写入口（增量语义）：modify_reputation 与 += 形态的转发目标。
## 返回实际轨道变化量。缺省轨道=民心（设计§5.1）。
func apply_legacy(amount: float, track: String = "", reason: String = "legacy") -> float:
	var target := track if rep.is_valid_track(track) else String(legacy_config["default_track"])
	var scaled := amount * float(legacy_config["scale"])
	return rep.add_reputation(target, scaled, reason)


## 旧写入口（绝对赋值语义，REQ 二次复验口径）：面向"目标总兼容值"的可达求解。
## 旧代码三种写法 `reputation = x` / `reputation += x` / `reputation = max(*0.3, 0)`
## 都是把旧值设到绝对目标；本函数把兼容视图精确设到 value（目标总声望 = value×scale）：
## 1. 差额优先压默认轨（权重 1.0，Δ轨 = Δ总）；
## 2. 默认轨触 [-1000,10000] 边界后，按各轨权重换算依次溢出（朝纲→军功→文名）；
## 3. 目标超出全局可达界 [Σmin×w, Σmax×w] = [-4200, 42000] 时钳制到最近可达值；
## 4. track 参数已移除——旧代码绝对赋值从不指定轨道，轨道定向属增量语义（apply_legacy）。
## 返回视图实际到达值（调用方据此断言）。仅公式A（total_normalized）口径下有意义。
func set_legacy_value(value: float, reason: String = "legacy_set") -> float:
	var scale := float(legacy_config["scale"])
	var target_total := value * scale
	var lo := 0.0
	var hi := 0.0
	for t in RepSysScript.TRACKS:
		var w := float(rep.config["track_weights"].get(t, 1.0))
		lo += float(rep.config["value_min"]) * w
		hi += float(rep.config["value_max"]) * w
	target_total = clampf(target_total, lo, hi)
	var remaining := target_total - rep.get_total()
	remaining -= rep.add_reputation(String(legacy_config["default_track"]), remaining, reason)
	for t in RepSysScript.TRACKS:
		if is_equal_approx(remaining, 0.0):
			break
		if t == String(legacy_config["default_track"]):
			continue
		var w := float(rep.config["track_weights"].get(t, 1.0))
		var applied := rep.add_reputation(t, remaining / w, reason)
		remaining -= applied * w
	return legacy_value()


## 旧读入口：reputation getter 的兼容视图。负值轨同样参与（透支可见）。
func legacy_value() -> float:
	match String(legacy_config["view_mode"]):
		VIEW_MINXIN_SCALED:
			return rep.get_value("minxin") / MINXIN_SCALE_DIVISOR
		_:
			return rep.get_total() / TOTAL_NORMALIZE_DIVISOR


## 剧情效果钩子（apply_story_effects 的 "reputation" 键）：
## amount 直写，track 缺省民心；后续剧情数据可带 "track" 字段分流。
func apply_story_effect(amount: float, track: String = "") -> float:
	return apply_legacy(amount, track, "story")


## 组合存档：声望水位 + 钱包 + 桥接配置快照，一次序列化。
func to_dict() -> Dictionary:
	return {
		"reputation": rep.to_dict(),
		"wallet": wallet.to_dict(),
		"legacy_config": legacy_config.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	if data.has("reputation"):
		rep.from_dict(data["reputation"])
	if data.has("wallet"):
		wallet.from_dict(data["wallet"])
	if data.get("legacy_config") is Dictionary:
		for key in data["legacy_config"].keys():
			if legacy_config.has(key):
				legacy_config[key] = data["legacy_config"][key]
