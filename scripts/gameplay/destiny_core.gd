class_name DestinyCore
extends RefCounted
## 玩法核心组装根（P1-3）：统一持有并组装四个子系统——
## ReputationSystem（经 ReputationBridge）+ DestinyWallet + DestinyShop + DestinyWheel。
## 是未来 `game_manager.gd` 接线的单一挂点（REQ-20260910-01 通过后）：
## 挂载 = GameManager 实例化本类 + reputation 读写转发 bridge；UI/死亡/剧情全部从本类取数。
## 自包含零接线：当前仅供测试与未来接线使用，不改任何现有文件。
##
## 时序调度：本类不持有时钟——游戏日/周的推进由调用方（GameManager 时间系统）
## 在切日/切周时调 tick_daily()/tick_weekly()；测试与离线结算也可直接调。

const BridgeScript := preload("res://scripts/gameplay/reputation_bridge.gd")
const RepSysScript := preload("res://scripts/gameplay/reputation_system.gd")
const DWalletScript := preload("res://scripts/gameplay/destiny_wallet.gd")
const ShopScript := preload("res://scripts/gameplay/destiny_shop.gd")
const WheelScript := preload("res://scripts/gameplay/destiny_wheel.gd")

var bridge: BridgeScript
var shop: ShopScript
var wheel: WheelScript

## 声望与钱包经 bridge 组装（里程碑自动入账链已在 bridge 内连接）；
## 以下为直通快捷引用。
var rep: RepSysScript:
	get: return bridge.rep
var wallet: DWalletScript:
	get: return bridge.wallet


func _init(config_path: String = BridgeScript.RepSysScript.CONFIG_PATH) -> void:
	bridge = BridgeScript.new(config_path)
	shop = ShopScript.new(bridge.wallet, "res://data/destiny_shop_config.json")
	wheel = WheelScript.new(bridge.wallet, "res://data/destiny_wheel_config.json")


## ---- 直通查询（UI/死亡/剧情常用） ----

func total_reputation() -> float:
	return bridge.rep.get_total()


func stage() -> int:
	return bridge.rep.get_stage()


func destiny_points() -> int:
	return bridge.wallet.points


func is_wheel_unlocked() -> bool:
	return wheel.is_wheel_unlocked(total_reputation())


## 面板数据快照：天命面板（V键 CharacterSheet 天命页签）单次取数入口，
## 避免 UI 层逐节点查询四个系统。
func panel_snapshot() -> Dictionary:
	var tracks: Array = []
	for t in bridge.rep.TRACKS:
		tracks.append({
			"id": t,
			"name": bridge.rep.track_name(t),
			"value": bridge.rep.get_value(t),
			"tier": bridge.rep.get_tier(t),
			"tier_name": bridge.rep.get_tier_name(t),
			"hostile": bridge.rep.is_hostile(t),
		})
	return {
		"tracks": tracks,
		"total": bridge.rep.get_total(),
		"stage": bridge.rep.get_stage(),
		"stage_name": bridge.rep.get_stage_name(),
		"stage_unlock": bridge.rep.get_stage_unlock(),
		"destiny_points": bridge.wallet.points,
		"lifetime_earned": bridge.wallet.lifetime_earned,
		"lifetime_spent": bridge.wallet.lifetime_spent,
		"wheel_unlocked": is_wheel_unlocked(),
		"echo_insured": shop.has_echo_insurance(),
	}


## ---- 时序调度（由 GameManager 时间系统在切日/切周时调用） ----

## 游戏日切：天命点日结（总声望×daily_income_rate，挂机保底）。
func tick_daily() -> int:
	return bridge.wallet.settle_daily()


## 游戏周切：声望周衰减（仅正值轨，0.1%/周，「人走茶凉」）。
func tick_weekly() -> void:
	bridge.rep.apply_weekly_decay()


## ---- 组合存档：一次序列化全部玩法核心状态 ----

func to_dict() -> Dictionary:
	return {
		"bridge": bridge.to_dict(),
		"shop": shop.to_dict(),
		"wheel": wheel.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	if data.has("bridge"):
		bridge.from_dict(data["bridge"])
	if data.has("shop"):
		shop.from_dict(data["shop"])
	if data.has("wheel"):
		wheel.from_dict(data["wheel"])
