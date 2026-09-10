extends SceneTree
## P1-3 组装根+死亡回响聚焦测试（headless）。
## 运行：godot --headless --path <项目根> --script res://tools/test_destiny_core.gd
## 覆盖：组装根四系统实例与联动/直通查询/面板快照/日结周衰减调度/
##       组合存档往返/死亡回响数值结算（保险前后/不足清零/负值轨不动/信号联动）。

const Core := preload("res://scripts/gameplay/destiny_core.gd")
const Echo := preload("res://scripts/gameplay/echo_revive.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_assembly()
	_test_panel_snapshot()
	_test_ticks()
	_test_roundtrip()
	_test_echo_revive()
	_test_echo_insured()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[CoreTest] FAIL: %s" % label)


func _core_with_points(points: int) -> Core:
	var c := Core.new()
	c.bridge.wallet.earn(points, "测试注资")
	return c


func _test_assembly() -> void:
	var c := Core.new()
	_check(c.bridge != null and c.shop != null and c.wheel != null, "四系统实例组装")
	_check(c.rep == c.bridge.rep and c.wallet == c.bridge.wallet, "直通引用同一实例")
	# 商城购买扣的钱与声望里程碑入的是同一个钱包（组装正确性）
	c.bridge.wallet.earn(1000, "注资")
	var r := c.shop.buy_destiny("quyuanli_tuzhi", 0)
	_check(bool(r["ok"]) and c.wallet.points == 1000 - 800, "商城走组装钱包扣800")
	# 声望写入→段位晋升→钱包入账（bridge 内链路在组装根下仍通）
	c.bridge.apply_legacy(10.0)
	_check(c.wallet.points == 1000 - 800 + 300, "里程碑链路在组装根下穿透")


func _test_panel_snapshot() -> void:
	var c := _core_with_points(500)
	c.bridge.apply_legacy(10.0)  # 民心420：段位1
	var snap := c.panel_snapshot()
	_check(snap["tracks"].size() == 4, "快照四轨")
	_check(snap["tracks"][0]["name"] == "民心" and snap["tracks"][0]["tier"] == 1, "民心段位1")
	_check(is_equal_approx(float(snap["total"]), 420.0), "快照总声望")
	_check(int(snap["destiny_points"]) == 500 + 300, "快照天命点含里程碑")
	_check(snap["stage_name"] == "默默无闻", "快照舞台名")
	_check(bool(snap["wheel_unlocked"]) == false, "420<3000轮盘未解锁")
	_check(bool(snap["echo_insured"]) == false, "快照无保险")


func _test_ticks() -> void:
	var c := _core_with_points(0)
	c.bridge.apply_legacy(100.0)  # 民心4200：里程碑入账 2600(段位1-3)+1700(舞台1-2)
	var before_points := c.wallet.points
	var gained := c.tick_daily()
	_check(gained == 4 and c.wallet.points == before_points + 4, "日结4入账（总4200×0.001）")
	var before := c.rep.get_value("minxin")
	c.tick_weekly()
	_check(c.rep.get_value("minxin") < before, "周衰减生效")


func _test_roundtrip() -> void:
	var c := _core_with_points(1000)
	c.bridge.apply_legacy(10.0)
	c.shop.buy_destiny("quyuanli_tuzhi", 0)
	c.shop.buy_destiny("huixiang_baoxian", 1)
	var saved: Dictionary = c.to_dict()
	var c2 := Core.new()
	c2.from_dict(saved)
	_check(is_equal_approx(c2.rep.get_value("minxin"), 420.0), "往返：民心")
	_check(c2.wallet.points == 1000 - 800 - 500 + 300, "往返：钱包（购买+里程碑）")
	_check(String(c2.shop.buy_destiny("quyuanli_tuzhi", 0)["reason"]) == "sold_out", "往返：商城限购")
	_check(c2.shop.has_echo_insurance(), "往返：保险标志")


func _test_echo_revive() -> void:
	var c := _core_with_points(600)
	c.bridge.apply_legacy(100.0)  # 民心4200
	c.wheel.pity_juepin_count = 33  # 轮盘保底计数也入档（组合存档覆盖）
	var result := Echo.apply(c)
	# 无保险：扣100天命点（points_before 含里程碑入账，用相对断言）
	_check(int(result["points_penalty"]) == 100, "无保险扣天命点100")
	_check(int(result["points_after"]) == int(result["points_before"]) - 100, "扣后余额=结算前-100")
	# 正值轨 -5%：民心 4200→3990
	var tc: Dictionary = result["track_changes"]
	_check(is_equal_approx(float(tc["minxin"]["after"]), 4200.0 * 0.95), "民心-5%至3990")
	_check(is_equal_approx(c.rep.get_value("minxin"), 3990.0), "衰减写入系统")
	# 负值轨不动
	var c2 := _core_with_points(600)
	c2.bridge.apply_legacy(-1.0)  # 民心-42 敌对
	var r2 := Echo.apply(c2)
	_check(is_equal_approx(float(r2["track_changes"]["minxin"]["after"]), -42.0), "负值轨不衰减")
	# 天命点不足→清零
	var c3 := _core_with_points(60)
	var r3 := Echo.apply(c3)
	_check(int(r3["points_penalty"]) == 60 and int(r3["points_after"]) == 0, "不足60清零")
	# 文案
	var text := Echo.describe(result, {"minxin": "民心"})
	_check(text.contains("天道回响") and text.contains("-100"), "reskin文案")


func _test_echo_insured() -> void:
	var c := _core_with_points(600)
	c.wallet.earn(500, "保险金")
	c.shop.buy_destiny("huixiang_baoxian", 1)  # 500点，限购1
	c.bridge.apply_legacy(100.0)
	var result := Echo.apply(c)
	_check(bool(result["insured"]), "保险生效标志")
	_check(int(result["points_penalty"]) == 50, "保险后天命点惩罚减半50")
	var tc: Dictionary = result["track_changes"]
	_check(is_equal_approx(float(tc["minxin"]["after"]), 4200.0 * 0.975), "保险后声望衰减减半2.5%")


func _report() -> void:
	print("[CoreTest] ===== P1-3 组装根+回响：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[CoreTest] 失败项：%s" % f)
