extends SceneTree
## P1-2 兼容桥接聚焦测试（headless，公式A口径：视图=总/42、写入×42）。
## 运行：godot --headless --path <项目根> --script res://tools/test_reputation_bridge.gd
## 覆盖：legacy 增量写转发/绝对赋值 set_legacy_value 三写法（=x、+=x、=max*0.3）/
##       兼容视图公式/scale 可配/剧情效果钩子/组合存档往返/里程碑链路穿透。

const Bridge := preload("res://scripts/gameplay/reputation_bridge.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_legacy_write()
	_test_view_formula()
	_test_set_legacy_value()
	_test_scale_override()
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
	_check(is_equal_approx(b.apply_legacy(10.0), 420.0), "缺省写民心+10×42=420")
	_check(is_equal_approx(b.rep.get_value("minxin"), 420.0), "民心轨=420")
	_check(is_equal_approx(b.apply_legacy(5.0, "chaogang"), 210.0), "指定朝纲+5→210")
	_check(is_equal_approx(b.rep.get_value("chaogang"), 210.0), "朝纲轨=210")
	# 非法轨道回退缺省轨（旧调用方误传不崩溃）
	_check(is_equal_approx(b.apply_legacy(1.0, "buxiao"), 42.0), "非法轨道回退民心")
	_check(is_equal_approx(b.rep.get_value("minxin"), 462.0), "回退后民心=462")
	# 负值穿透（REQ：放开旧钳制≥0）；-12 旧点 = -504 轨道值
	_check(is_equal_approx(b.apply_legacy(-12.0), -504.0), "负值写民心变化量-504")
	_check(is_equal_approx(b.rep.get_value("minxin"), -42.0), "民心终值-42")
	_check(b.rep.is_hostile("minxin"), "民心负=敌对（义军声讨线）")


func _test_view_formula() -> void:
	# 公式A写读一致：写民心 +N 旧点（权重1.0）→ 视图恰好 +N
	var b := Bridge.new()
	b.apply_legacy(40.0)
	_check(is_equal_approx(b.legacy_value(), 40.0), "总归一视图写读一致（+40旧点→视图40）")
	# 备选公式保留：民心/100
	b.legacy_config["view_mode"] = Bridge.VIEW_MINXIN_SCALED
	_check(is_equal_approx(b.legacy_value(), 40.0 * 42.0 / 100.0), "民心缩放视图16.8")
	b.legacy_config["view_mode"] = Bridge.VIEW_TOTAL_NORMALIZED
	# 多轨加权可见：朝纲写入对视图贡献 ×1.2
	b.apply_legacy(10.0, "chaogang")
	_check(is_equal_approx(b.legacy_value(), 40.0 + 10.0 * 1.2), "朝纲贡献按权重1.2进视图")


func _test_set_legacy_value() -> void:
	# REQ 复查口径②：绝对赋值差额语义，覆盖旧代码三种写法
	var b := Bridge.new()
	# 写法1：reputation = x（death_system/oath 等直赋值）
	b.set_legacy_value(100.0)
	_check(is_equal_approx(b.legacy_value(), 100.0), "=x 绝对赋值视图到100")
	_check(is_equal_approx(b.rep.get_value("minxin"), 4200.0), "民心承担全额4200")
	# 写法2：reputation += x（npc_spawner/oath 直加）
	b.set_legacy_value(b.legacy_value() + 30.0)
	_check(is_equal_approx(b.legacy_value(), 130.0), "+=30 视图到130")
	# 写法3：reputation = max(reputation * 0.3, 0)（death_system:153 死亡惩罚）
	b.set_legacy_value(maxf(b.legacy_value() * 0.3, 0.0))
	_check(is_equal_approx(b.legacy_value(), 39.0), "死亡×0.3 视图到39（惩罚不反向）")
	# 回升到高位再压半，覆盖跨段位场景的绝对语义
	b.set_legacy_value(200.0)
	b.set_legacy_value(maxf(b.legacy_value() * 0.3, 0.0))
	_check(is_equal_approx(b.legacy_value(), 60.0), "高位压半视图60")
	# 指定轨道的绝对赋值（写文名视图到同值）
	var b2 := Bridge.new()
	b2.set_legacy_value(50.0, "wenming")
	_check(is_equal_approx(b2.legacy_value(), 50.0 * 0.8), "文名承担全额但视图按权重0.8")


func _test_scale_override() -> void:
	# scale 显式可配（回归期临时降回 1:1 排查用）
	var b := Bridge.new()
	b.legacy_config["scale"] = 1.0
	b.apply_legacy(10.0)
	_check(is_equal_approx(b.rep.get_value("minxin"), 10.0), "scale=1 时 1:1 写入")
	b.legacy_config["scale"] = 42.0


func _test_story_effect() -> void:
	var b := Bridge.new()
	b.apply_story_effect(10.0)
	_check(is_equal_approx(b.rep.get_value("minxin"), 420.0), "剧情效果缺省民心")
	b.apply_story_effect(10.0, "wenming")
	_check(is_equal_approx(b.rep.get_value("wenming"), 420.0), "剧情效果指定文名")


func _test_roundtrip() -> void:
	var b := Bridge.new()
	b.apply_legacy(100.0)  # 民心4200：段位3（+300+800+1500）；总4200→舞台2（+500+1200）
	b.wallet.earn(123, "系统任务")
	var saved: Dictionary = b.to_dict()
	var b2 := Bridge.new()
	b2.from_dict(saved)
	_check(is_equal_approx(b2.rep.get_value("minxin"), 4200.0), "往返：民心")
	_check(is_equal_approx(b2.legacy_value(), 100.0), "往返：兼容视图100")
	_check(b2.wallet.points == 300 + 800 + 1500 + 500 + 1200 + 123, "往返：钱包含里程碑+任务")
	_check(b2.rep.claim_tier_milestone("minxin") == 0, "往返：水位防重复")


func _test_milestone_chain() -> void:
	# legacy 写入 → 段位晋升 → 钱包自动入账 全链路穿透
	var b := Bridge.new()
	b.apply_legacy(10.0)  # 民心420：段位1（+300）；总420<600无舞台
	_check(b.wallet.points == 300, "legacy写420→段位1→自动+300")
	b.apply_legacy(10.0)  # 民心840：段位2（+800）；总840→舞台1（+500）
	_check(b.wallet.points == 300 + 800 + 500, "跨段+舞台链式入账")


func _report() -> void:
	print("[BridgeTest] ===== P1-2 桥接（公式A口径）：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[BridgeTest] 失败项：%s" % f)
