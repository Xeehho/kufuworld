extends SceneTree
## P1-2 兼容桥接聚焦测试（headless）。
## 运行：godot --headless --path <项目根> --script res://tools/test_reputation_bridge.gd
## 覆盖：legacy 写转发（缺省/指定轨道/非法轨道回退）/兼容视图两种公式/
##       scale 放大/剧情效果钩子/组合存档往返/里程碑链路穿透。

const Bridge := preload("res://scripts/gameplay/reputation_bridge.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_legacy_write()
	_test_view_modes()
	_test_scale()
	_test_story_effect()
	_test_roundtrip()
	_test_milestone_chain()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[BridgeTest] FAIL: %s" % label)


func _test_legacy_write() -> void:
	var b := Bridge.new()
	_check(is_equal_approx(b.apply_legacy(50.0), 50.0), "缺省写民心+50")
	_check(is_equal_approx(b.rep.get_value("minxin"), 50.0), "民心轨=50")
	_check(is_equal_approx(b.apply_legacy(30.0, "chaogang"), 30.0), "指定朝纲+30")
	_check(is_equal_approx(b.rep.get_value("chaogang"), 30.0), "朝纲轨=30")
	# 非法轨道回退缺省轨（旧调用方误传不崩溃）
	_check(is_equal_approx(b.apply_legacy(10.0, "buxiao"), 10.0), "非法轨道回退民心")
	_check(is_equal_approx(b.rep.get_value("minxin"), 60.0), "回退后民心=60")
	# 负值穿透（REQ：放开旧钳制≥0）；apply_legacy 返回轨道变化量
	_check(is_equal_approx(b.apply_legacy(-100.0), -100.0), "负值写民心变化量-100")
	_check(is_equal_approx(b.rep.get_value("minxin"), -40.0), "民心终值-40")
	_check(b.rep.is_hostile("minxin"), "民心负=敌对（义军声讨线）")


func _test_view_modes() -> void:
	# TOTAL_NORMALIZED：旧值 = 总声望/42
	var b := Bridge.new()
	b.apply_legacy(1000.0, "minxin")
	b.apply_legacy(1000.0, "chaogang")
	b.apply_legacy(1000.0, "jungong")
	b.apply_legacy(1000.0, "wenming")
	_check(is_equal_approx(b.legacy_value(), 4200.0 / 42.0), "总归一视图=100")
	# MINXIN_SCALED：旧值 = 民心/100
	b.legacy_config["view_mode"] = Bridge.VIEW_MINXIN_SCALED
	_check(is_equal_approx(b.legacy_value(), 1000.0 / 100.0), "民心缩放视图=10")


func _test_scale() -> void:
	var b := Bridge.new()
	b.legacy_config["scale"] = 10.0
	b.apply_legacy(10.0)
	_check(is_equal_approx(b.rep.get_value("minxin"), 100.0), "scale×10放大写入")
	b.legacy_config["scale"] = 1.0


func _test_story_effect() -> void:
	var b := Bridge.new()
	b.apply_story_effect(10.0)
	_check(is_equal_approx(b.rep.get_value("minxin"), 10.0), "剧情效果缺省民心")
	b.apply_story_effect(10.0, "wenming")
	_check(is_equal_approx(b.rep.get_value("wenming"), 10.0), "剧情效果指定文名")


func _test_roundtrip() -> void:
	var b := Bridge.new()
	b.apply_legacy(300.0)  # 民心300：段位1（+300）；总300<600无舞台
	b.wallet.earn(123, "系统任务")
	var saved: Dictionary = b.to_dict()
	var b2 := Bridge.new()
	b2.from_dict(saved)
	_check(is_equal_approx(b2.rep.get_value("minxin"), 300.0), "往返：民心")
	_check(is_equal_approx(b2.legacy_value(), 300.0 / 42.0), "往返：兼容视图")
	_check(b2.wallet.points == 300 + 123, "往返：钱包含里程碑+任务")
	_check(b2.rep.claim_tier_milestone("minxin") == 0, "往返：水位防重复")


func _test_milestone_chain() -> void:
	# legacy 写入 → 段位晋升 → 钱包自动入账 全链路穿透
	var b := Bridge.new()
	b.apply_legacy(200.0)
	_check(b.wallet.points == 300, "legacy写200→段位1→自动+300")
	b.apply_legacy(700.0)  # 900：段位2（+800）；总900→舞台1（+500）
	_check(b.wallet.points == 300 + 800 + 500, "跨段+舞台链式入账")


func _report() -> void:
	print("[BridgeTest] ===== P1-2 桥接：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[BridgeTest] 失败项：%s" % f)
