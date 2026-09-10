class_name Tangtang
extends RefCounted
## 系统之灵「糖糖」演出核心（P1-3，设计§4.1）。
## 职责：①系统等级（糖糖形态）计算——Lv1~Lv5 随总声望成长（青光雏鸟→凤凰虚影）；
## ②系统提示的气泡台词调度——默认糖糖头顶气泡吐槽播报（嘴毒、贪吃、爱记账人设），
##   重大奖励才弹正式面板（辨识度卖点）。
## 可见性铁律（接线期约束，本模块不含 NPC 交互）：糖糖全程仅主角可见——
## NPC 台词永不提及糖糖；打开面板=主角入定发呆（复用模态锁输入）。
## 气泡渲染复用 NPC 名牌气泡管线（接线期接）；本模块只产出台词文本与等级数据。

const LEVELS: Array = [
	{"level": 1, "name": "唤醒", "threshold": 0.0, "form": "青光雏鸟"},
	{"level": 2, "name": "启蒙", "threshold": 500.0, "form": "幼鸟"},
	{"level": 3, "name": "成长", "threshold": 3000.0, "form": "少年青鸾"},
	{"level": 4, "name": "振翅", "threshold": 12000.0, "form": "成年青鸾"},
	# ⚠️ 设计稿内部矛盾：Lv5 门槛 50000 > 总声望理论上限 42000（权重 1.0/1.2/1.2/0.8 满值）。
	# 照设计原值配置，达到途径待拍板（隐藏结局钥匙或另有剧情加成）。
	{"level": 5, "name": "涅槃", "threshold": 50000.0, "form": "凤凰虚影"},
]


## 总声望 → 糖糖等级档（{level, name, threshold, form}）。
static func level_for(total_reputation: float) -> Dictionary:
	var picked: Dictionary = LEVELS[0]
	for lv in LEVELS:
		if total_reputation >= float(lv["threshold"]):
			picked = lv
	return picked


## 升级台词（等级变化播报；old_level < new_level 时由调用方触发）。
static func level_up_line(new_level: Dictionary) -> String:
	match int(new_level["level"]):
		2:
			return "叽叽——本座启蒙了！商城开张，快来上供。（说是契约，其实就是投喂）"
		3:
			return "长成少年青鸾啦～轮盘开转。天命点攒够了吗？不够就去赚声望，本座饿了。"
		4:
			return "振翅！仓界扩到二十格，图纸全解锁。账本我都记着呢，一笔不少。"
		5:
			return "凤凰虚影……原来这就是涅槃。小拾安，终局的棋盘要你自己落子了。"
		_:
			return "咕？本座好像又长大了一点。（这是系统升级的官方说法）"


## 事件气泡台词调度：系统提示默认走糖糖吐槽，替代干巴巴弹窗（§4.1 演出职责）。
## event: milestone_tier / milestone_stage / echo / daily / milestone_wheel 等。
static func bubble_line(event: String, data: Dictionary = {}) -> String:
	match event:
		"milestone_tier":
			return "%s涨到「%s」——记账：天命点 +%d。味道不错，继续。" % [
				String(data.get("track_name", "")), String(data.get("tier_name", "")), int(data.get("amount", 0))]
		"milestone_stage":
			return "舞台升到「%s」了。天命点 +%d，本座收下了。别飘，下一级还远着呢。" % [
				String(data.get("stage_name", "")), int(data.get("amount", 0))]
		"echo":
			if bool(data.get("insured", false)):
				return "吓死本座了……保险生效，只扣一半。下回记得看路，痴儿。"
			return "天道回响，命数未绝。天命点 -%d，肉疼的是你，饿的是我。" % int(data.get("points_penalty", 0))
		"daily":
			return "今日声望结余：天命点 +%d。细水长流，勉强够塞牙缝。" % int(data.get("amount", 0))
		"wheel":
			return "轮盘开转！%s——绑定不可交易，别想倒卖，本座盯着呢。" % String(data.get("result", ""))
		_:
			return "咕？（系统提示：有新事件，详见天命面板）"
