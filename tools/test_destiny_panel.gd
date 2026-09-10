extends SceneTree
## P1-3 天命面板+糖糖演出聚焦测试（headless，实例化 Control 断言结构与文本）。
## 运行：godot --headless --path <项目根> --script res://tools/test_destiny_panel.gd

const Core := preload("res://scripts/gameplay/destiny_core.gd")
const DPanel := preload("res://scripts/gameplay/destiny_panel.gd")
const Tangtang := preload("res://scripts/gameplay/tangtang.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_panel_render()
	_test_panel_states()
	_test_tangtang_levels()
	_test_tangtang_lines()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[PanelTest] FAIL: %s" % label)


func _test_panel_render() -> void:
	var c := Core.new()
	c.bridge.wallet.earn(777, "注资")
	c.bridge.apply_legacy(10.0)  # 民心420：段位1，里程碑+300
	var p := DPanel.new(c)
	_check(p._track_rows.size() == 4, "四轨行")
	_check(String(p._track_rows[0]["name"].text) == "民心", "首轨名民心")
	_check(String(p._track_rows[1]["name"].text) == "朝纲", "次轨名朝纲")
	_check(String(p._track_rows[0]["value"].text) == "420", "民心数值420")
	_check(String(p._track_rows[0]["tier"].text) == "小有名气", "民心段位名")
	_check(p._points_lbl.text == "天命点 1077", "天命点含里程碑1077")
	_check(p._tangtang_lbl.text.contains("Lv1") and p._tangtang_lbl.text.contains("青光雏鸟"), "糖糖Lv1雏鸟徽章")
	_check(p._stage_lbl.text.contains("默默无闻") and p._stage_unlock_lbl.text.contains("陈家村"), "舞台名与解锁地")
	_check(p._wheel_lbl.text.contains("未开放") and p._wheel_lbl.text.contains("未投保"), "轮盘锁定+未投保")
	_check(is_equal_approx(p._track_rows[0]["bar_fill"].scale.x, 0.042), "进度条比例420/10000")


func _test_panel_states() -> void:
	# 敌对轨：段位标签换「敌对」+DANGER 色+红条
	var c := Core.new()
	c.bridge.apply_legacy(-1.0)  # 民心-42
	var p := DPanel.new(c)
	_check(String(p._track_rows[0]["tier"].text) == "敌对", "敌对轨标签")
	var danger_color: Color = p._track_rows[0]["bar_fill"].color
	_check(is_equal_approx(danger_color.r, UITheme.DANGER.r) and is_equal_approx(danger_color.g, UITheme.DANGER.g), "敌对轨红条")
	# Godot 4.6 CanvasItem.scale 引擎最小值约1e-5（赋0读回1e-5，渲染不可见）
	_check(p._track_rows[0]["bar_fill"].scale.x <= 0.000011, "负值轨进度条归零（≤1e-5引擎底值）")
	# 轮盘解锁+投保态
	var c2 := Core.new()
	c2.bridge.wallet.earn(1000, "注资")
	c2.bridge.apply_legacy(100.0)  # 总4200≥3000
	c2.shop.buy_destiny("huixiang_baoxian", 1)
	var p2 := DPanel.new(c2)
	_check(p2._wheel_lbl.text.contains("已开放") and p2._wheel_lbl.text.contains("已投保"), "轮盘开放+已投保")
	_check(p2._tangtang_lbl.text.contains("Lv3") and p2._tangtang_lbl.text.contains("少年青鸾"), "总4200糖糖Lv3青鸾")
	# refresh 增量更新（数值变化后刷新）
	c2.bridge.apply_legacy(10.0)
	p2.refresh()
	_check(String(p2._track_rows[0]["value"].text) != "4200", "refresh更新数值")


func _test_tangtang_levels() -> void:
	_check(Tangtang.level_for(0.0)["form"] == "青光雏鸟", "Lv1门槛0")
	_check(Tangtang.level_for(499.0)["level"] == 1, "499仍Lv1")
	_check(Tangtang.level_for(500.0)["level"] == 2, "500启蒙")
	_check(Tangtang.level_for(3000.0)["level"] == 3, "3000成长")
	_check(Tangtang.level_for(12000.0)["level"] == 4, "12000振翅")
	_check(Tangtang.level_for(50000.0)["form"] == "凤凰虚影", "50000涅槃（设计矛盾值，待拍板）")
	_check(Tangtang.level_for(99999.0)["level"] == 5, "封顶Lv5")


func _test_tangtang_lines() -> void:
	for lv in [2, 3, 4, 5]:
		var line := Tangtang.level_up_line({"level": lv})
		_check(not line.is_empty(), "升级台词Lv%d非空" % lv)
	var b1 := Tangtang.bubble_line("milestone_tier", {"track_name": "民心", "tier_name": "小有名气", "amount": 300})
	_check(b1.contains("民心") and b1.contains("300"), "段位台词含轨道与数额")
	var b2 := Tangtang.bubble_line("echo", {"insured": false, "points_penalty": 100})
	_check(b2.contains("100"), "回响台词含扣点")
	var b3 := Tangtang.bubble_line("daily", {"amount": 4})
	_check(b3.contains("4"), "日结台词含数额")
	_check(not Tangtang.bubble_line("unknown_event").is_empty(), "未知事件兜底台词")


func _report() -> void:
	print("[PanelTest] ===== P1-3 面板+糖糖：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[PanelTest] 失败项：%s" % f)
