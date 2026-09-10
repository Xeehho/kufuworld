class_name EchoRevive
extends RefCounted
## 死亡回响核心（P1-3，REQ-20260910-01 复查口径③）。
## 设计依据：§4.2 第 6 条 + §6.2 服务类——「死亡不清档：扣天命点 + 当幕声望 -5%，
## 原地/村落复活，文案 reskin『天道回响，命数未绝』」。
## 结算规则（口径细化）：
## - 天命点惩罚：扣 100 点，不足则清零；
## - 声望惩罚：各**正值**声望轨各衰减 5%（负值轨不自动变化——敌对记忆不消散）；
## - 回响保险（商城服务，echo_insured）：两项惩罚各减半（扣 50 点 / 各轨 -2.5%）；
## - 复活位置（原地/村落）由死亡系统决定，本模块只管数值结算并返回明细。
## 本模块自包含：输入 core（或 wallet+rep+insured），输出结算 Dictionary；
## death_system.gd 的实际接线（含 DeathHUD 文案 reskin）待 REQ 通过后进行。

const DestinyCoreScript := preload("res://scripts/gameplay/destiny_core.gd")

const POINT_PENALTY := 100
const TRACK_DECAY := 0.05
const INSURED_POINT_PENALTY := 50
const INSURED_TRACK_DECAY := 0.025


## 执行死亡回响结算。返回明细供 DeathHUD 展示与测试断言：
## {points_before, points_after, points_penalty, track_changes: {id: {before, after}}, insured}
static func apply(core: DestinyCoreScript) -> Dictionary:
	var wallet = core.bridge.wallet
	var rep = core.bridge.rep
	var insured: bool = core.shop.has_echo_insurance()
	var point_penalty := INSURED_POINT_PENALTY if insured else POINT_PENALTY
	var decay := INSURED_TRACK_DECAY if insured else TRACK_DECAY
	var points_before := wallet.points
	var points_after := maxi(0, points_before - point_penalty)
	if points_after != points_before:
		wallet.spend(points_before - points_after, "天道回响·天命点惩罚")
	var track_changes := {}
	for t in rep.TRACKS:
		var before := rep.get_value(t)
		var after := before
		if before > 0.0:
			# 正值轨按 5%（保险 2.5%）衰减；衰减走 add_reputation 保持信号/段位联动
			after = before * (1.0 - decay)
			rep.add_reputation(t, after - before, "天道回响·声望衰减")
		track_changes[t] = {"before": before, "after": rep.get_value(t)}
	return {
		"insured": insured,
		"points_before": points_before,
		"points_after": wallet.points,
		"points_penalty": points_before - wallet.points,
		"track_changes": track_changes,
	}


## 结算文案（DeathHUD reskin 用；先备好，接线时直接取）。
static func describe(result: Dictionary, track_names: Dictionary = {}) -> String:
	var lines := ["天道回响，命数未绝"]
	if bool(result["insured"]):
		lines.append("（回响保险生效：惩罚减半）")
	lines.append("天命点 -%d（余 %d）" % [int(result["points_penalty"]), int(result["points_after"])])
	for t in result["track_changes"]:
		var change: Dictionary = result["track_changes"][t]
		var lost := float(change["before"]) - float(change["after"])
		if lost > 0.0:
			lines.append("%s %.0f → %.0f" % [String(track_names.get(t, t)), change["before"], change["after"]])
	return "\n".join(lines)
