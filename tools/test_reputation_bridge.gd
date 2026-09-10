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
	# REQ 二次复验口径：面向"目标总兼容值"的可达求解，任何场景视图精确到达
	# 基础三写法（=x / +=x / =max(*0.3,0)）
	var b := Bridge.new()
	b.set_legacy_value(100.0)
	_check(is_equal_approx(b.legacy_value(), 100.0), "=x 绝对赋值视图到100")
	_check(is_equal_approx(b.rep.get_value("minxin"), 4200.0), "民心承担全额4200")
	b.set_legacy_value(b.legacy_value() + 30.0)
	_check(is_equal_approx(b.legacy_value(), 130.0), "+=30 视图到130")
	b.set_legacy_value(maxf(b.legacy_value() * 0.3, 0.0))
	_check(is_equal_approx(b.legacy_value(), 39.0), "死亡×0.3 视图到39（惩罚不反向）")
	# 组1：多轨降值——民心余量足额承担，其余轨不动
	var b1 := Bridge.new()
	b1.apply_legacy(200.0, "minxin")
	b1.apply_legacy(100.0, "chaogang")
	b1.apply_legacy(100.0, "jungong")
	b1.apply_legacy(100.0, "wenming")
	# 总 = 8400 + 5040 + 5040 + 3360 = 21840 → 视图 520
	_check(is_equal_approx(b1.legacy_value(), 520.0), "多轨基准视图520")
	b1.set_legacy_value(300.0)
	_check(is_equal_approx(b1.legacy_value(), 300.0), "组1 多轨降值精确到达300")
	_check(is_equal_approx(b1.rep.get_value("minxin"), -840.0), "组1 民心降9240至-840（下界内）")
	_check(is_equal_approx(b1.rep.get_value("chaogang"), 4200.0), "组1 其余轨不动（朝纲）")
	# 组2：民心触顶后继续 +=——溢出按权重换算到其余轨
	var b2 := Bridge.new()
	b2.rep.add_reputation("minxin", 10000.0)
	var before := b2.legacy_value()
	b2.set_legacy_value(before + 10.0)
	_check(is_equal_approx(b2.legacy_value(), before + 10.0), "组2 民心触顶后+=仍精确到达")
	_check(is_equal_approx(b2.rep.get_value("minxin"), 10000.0), "组2 民心保持10000")
	_check(b2.rep.get_value("chaogang") > 0.0, "组2 差额溢出至朝纲（÷1.2换算）")
	# 组3：满总声望 = current*0.3（跨多轨降值，死亡高惩罚场景）
	var b3 := Bridge.new()
	for t in b3.rep.TRACKS:
		b3.rep.add_reputation(t, 10000.0)
	var v := b3.legacy_value()
	_check(is_equal_approx(v, 1000.0), "组3 满轨视图1000")
	b3.set_legacy_value(maxf(v * 0.3, 0.0))
	_check(is_equal_approx(b3.legacy_value(), 300.0), "组3 满轨压0.3跨多轨精确到达300")
	_check(is_equal_approx(b3.rep.get_value("minxin"), -1000.0), "组3 民心触下限-1000")
	_check(is_equal_approx(b3.rep.get_value("chaogang"), -1000.0), "组3 朝纲触下限-1000")
	_check(is_equal_approx(b3.rep.get_value("jungong"), 10000.0 - 5200.0 / 1.2), "组3 军功承担尾差5666.67")
	_check(is_equal_approx(b3.rep.get_value("wenming"), 10000.0), "组3 文名不动")
	# 组4：非1权重轨——track 参数已移除（绝对赋值面向总兼容值，轨道定向属增量语义）
	var b4 := Bridge.new()
	b4.apply_legacy(50.0, "wenming")
	_check(is_equal_approx(b4.legacy_value(), 50.0 * 0.8), "组4 增量语义文名贡献×0.8（视图40）")
	b4.set_legacy_value(50.0)
	_check(is_equal_approx(b4.legacy_value(), 50.0), "组4 绝对赋值面向总视图精确到50（不再受权重缩放）")
	# 组5：全局不可达目标钳制（视图可达界 [-100, 1000]）
	var b5 := Bridge.new()
	b5.set_legacy_value(2000.0)
	_check(is_equal_approx(b5.legacy_value(), 1000.0), "组5 超上限钳制到1000")
	b5.set_legacy_value(-500.0)
	_check(is_equal_approx(b5.legacy_value(), -100.0), "组5 低于下限钳制到-100")


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
