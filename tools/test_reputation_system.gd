extends SceneTree
## P1-1 四轨声望+天命点聚焦测试（headless）。
## 运行：godot --headless --path <项目根> --script res://tools/test_reputation_system.gd
## 覆盖：初始态/配置加载回退/加减与钳制/加权总声望/段位与舞台/负值敌对/
##       周衰减/里程碑水位防重复/钱包收支与日结/绑定自动入账/存档往返。
## 注意：--script 模式读不到新 class_name 的全局类缓存，统一走 preload。

const RepSys := preload("res://scripts/gameplay/reputation_system.gd")
const DWallet := preload("res://scripts/gameplay/destiny_wallet.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_initial_state()
	_test_config_load_and_fallback()
	_test_add_and_clamp()
	_test_weighted_total()
	_test_tier_and_signals()
	_test_negative_and_hostility()
	_test_weekly_decay()
	_test_milestone_watermark()
	_test_wallet_basics()
	_test_wallet_binding()
	_test_daily_settle()
	_test_save_roundtrip()
	_test_invalid_track()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[RepTest] FAIL: %s" % label)


func _test_initial_state() -> void:
	var rep := RepSys.new()
	_check(rep.get_value("minxin") == 0.0, "初始民心=0")
	_check(rep.get_total() == 0.0, "初始总声望=0")
	_check(rep.get_tier("chaogang") == 0, "初始段位=0")
	_check(rep.get_stage() == 0, "初始舞台=0")
	_check(rep.get_tier_name("minxin") == "默默无闻", "初始段位名")
	for t in RepSys.TRACKS:
		_check(not rep.is_hostile(t), "初始非敌对:%s" % t)


func _test_config_load_and_fallback() -> void:
	var rep := RepSys.new()  # 正常加载 res://data/reputation_config.json
	_check(is_equal_approx(rep.config["track_weights"]["chaogang"], 1.2), "JSON权重朝纲1.2")
	_check(rep.config["tiers"].size() == 6, "六段位")
	_check(rep.config["stages"][5]["threshold"] == 40000.0, "青史留名舞台40000")
	var fallback := RepSys.new("res://data/不存在的配置.json")
	_check(is_equal_approx(fallback.config["track_weights"]["wenming"], 0.8), "缺失JSON回退默认文名0.8")


func _test_add_and_clamp() -> void:
	var rep := RepSys.new()
	var delta := rep.add_reputation("minxin", 150.0, "赈灾施粥")
	_check(is_equal_approx(delta, 150.0), "加声望返回变化量150")
	_check(is_equal_approx(rep.get_value("minxin"), 150.0), "民心=150")
	rep.add_reputation("minxin", 999999.0, "溢出")
	_check(is_equal_approx(rep.get_value("minxin"), 10000.0), "上限钳制10000")


func _test_weighted_total() -> void:
	var rep := RepSys.new()
	for t in RepSys.TRACKS:
		rep.add_reputation(t, 1000.0, "测试基准")
	# 1000×(1.0+1.2+1.2+0.8) = 4200
	_check(is_equal_approx(rep.get_total(), 4200.0), "加权总声望4200")


func _test_tier_and_signals() -> void:
	var rep := RepSys.new()
	var events: Array = []
	rep.tier_changed.connect(func(track, old_t, new_t): events.append([track, old_t, new_t]))
	rep.add_reputation("minxin", 200.0, "平价售粮")
	_check(rep.get_tier("minxin") == 1, "民心200→段位1小有名气")
	_check(rep.get_tier_name("minxin") == "小有名气", "段位名小有名气")
	_check(events.size() == 1 and events[0] == ["minxin", 0, 1], "tier_changed信号载荷")
	# 满轨=青史留名（结局条件之一）
	rep.add_reputation("minxin", 9800.0, "满轨")
	_check(rep.get_tier("minxin") == 5 and rep.get_tier_name("minxin") == "青史留名", "满轨10000=青史留名")


func _test_negative_and_hostility() -> void:
	var rep := RepSys.new()
	var hostile_events: Array = []
	rep.hostility_changed.connect(func(track, hostile): hostile_events.append([track, hostile]))
	# 关键差异：新核心允许负值（旧 GameManager.modify_reputation 钳制≥0）
	var delta := rep.add_reputation("chaogang", -50.0, "朝堂失仪")
	_check(is_equal_approx(delta, -50.0), "负值允许且返回-50")
	_check(is_equal_approx(rep.get_value("chaogang"), -50.0), "朝纲=-50（敌对区间）")
	_check(rep.is_hostile("chaogang"), "朝纲负=敌对（下狱事件线）")
	_check(hostile_events.size() == 1 and hostile_events[0] == ["chaogang", true], "hostility_changed信号")
	# 负值下限钳制
	rep.add_reputation("chaogang", -99999.0, "深负")
	_check(is_equal_approx(rep.get_value("chaogang"), -1000.0), "负值下限-1000")
	# 回正解除敌对
	rep.add_reputation("chaogang", 1100.0, "戴罪立功")
	_check(not rep.is_hostile("chaogang") and hostile_events.back() == ["chaogang", false], "回正解除敌对")
	# 负轨拉低总声望（透支也是代价）
	var rep2 := RepSys.new()
	rep2.add_reputation("minxin", 100.0)
	rep2.add_reputation("wenming", -100.0)
	_check(is_equal_approx(rep2.get_total(), 100.0 * 1.0 - 100.0 * 0.8), "负轨参与加权")


func _test_weekly_decay() -> void:
	var rep := RepSys.new()
	rep.add_reputation("jungong", 10000.0)
	rep.apply_weekly_decay(1.0)
	_check(is_equal_approx(rep.get_value("jungong"), 9990.0), "周衰减0.1%：10000→9990")
	# 负值不衰减（敌对记忆不自动消散）
	var rep2 := RepSys.new()
	rep2.add_reputation("minxin", -100.0)
	rep2.apply_weekly_decay(10.0)
	_check(is_equal_approx(rep2.get_value("minxin"), -100.0), "负值周衰减不动")
	# 衰减可致段位降级（人走茶凉）
	var rep3 := RepSys.new()
	rep3.add_reputation("minxin", 200.0)
	rep3.add_reputation("minxin", -110.0, "剧情透支")
	_check(rep3.get_tier("minxin") == 0, "衰减/透支降级回段位0")


func _test_milestone_watermark() -> void:
	# 水位制：只对超过历史最高段位的部分发放；降级回升不重复领
	var rep := RepSys.new()
	rep.add_reputation("minxin", 200.0)
	_check(rep.claim_tier_milestone("minxin") == 300, "首升段位1领300")
	_check(rep.claim_tier_milestone("minxin") == 0, "重复领取返回0")
	rep.add_reputation("minxin", -110.0, "透支")
	rep.add_reputation("minxin", 120.0, "回升")
	_check(rep.claim_tier_milestone("minxin") == 0, "降级后回升不重复领")
	rep.add_reputation("minxin", 600.0, "跳段")  # 810 → 段位2
	_check(rep.claim_tier_milestone("minxin") == 800, "跳段只领新跨段800")
	# 舞台同理
	var rep2 := RepSys.new()
	rep2.add_reputation("chaogang", 500.0)  # 总=600 → 舞台1
	_check(rep2.claim_stage_milestone() == 500, "舞台1领500")
	_check(rep2.claim_stage_milestone() == 0, "舞台重复领取0")


func _test_wallet_basics() -> void:
	var w := DWallet.new()
	_check(w.earn(1000, "声望里程碑"), "入账1000")
	_check(w.points == 1000 and w.lifetime_earned == 1000, "余额与累计入账")
	_check(w.spend(300, "商城·格物图纸"), "支出300")
	_check(w.points == 700 and w.lifetime_spent == 300, "扣减与累计支出")
	_check(not w.spend(99999, "轮盘"), "余额不足拒绝")
	_check(w.points == 700, "拒绝后余额不变")
	_check(not w.earn(-5, "负数入账"), "负数入账拒绝")


func _test_wallet_binding() -> void:
	var rep := RepSys.new()
	var w := DWallet.new()
	w.bind_reputation_system(rep)
	rep.add_reputation("minxin", 200.0)  # 民心段位0→1
	_check(w.points == 300, "绑定后段位晋升自动入账300")
	# 朝纲+1000：自身段位0→2（跨1、2，+300+800）；总声望 200+1200=1400 → 舞台1（+500）
	rep.add_reputation("chaogang", 1000.0)
	_check(w.points == 300 + 1100 + 500, "轨道跨段+舞台晋升同时入账")
	# 军功+1000：自身段位0→2（+1100）；总 1400+1200=2600 → 舞台2（+1200）
	rep.add_reputation("jungong", 1000.0)
	_check(w.points == 300 + 1100 + 500 + 1100 + 1200, "多轨道多舞台累计入账")
	# 里程碑信号
	var paid: Array = []
	w.milestone_paid.connect(func(amount, reason): paid.append([amount, reason]))
	rep.add_reputation("wenming", 200.0)
	_check(paid.size() == 1 and paid[0][0] == 300, "milestone_paid信号")


func _test_daily_settle() -> void:
	var rep := RepSys.new()
	for t in RepSys.TRACKS:
		rep.add_reputation(t, 10000.0)
	# 不绑定（避免里程碑入账干扰），显式传总声望
	var w := DWallet.new()
	var got := w.settle_daily(rep.get_total())
	_check(got == 42 and w.points == 42, "满总声望42000日结=42")
	_check(DWallet.new().settle_daily(0.0) == 0, "零声望日结0")
	# 绑定路径：settle_daily() 自动取绑定系统总声望
	var w2 := DWallet.new()
	w2.bind_reputation_system(RepSys.new())
	_check(w2.settle_daily(2100.0) == 2, "显式传参优先于绑定系统")


func _test_save_roundtrip() -> void:
	var rep := RepSys.new()
	var w := DWallet.new()
	w.bind_reputation_system(rep)
	rep.add_reputation("minxin", 900.0)  # 段位0→2（+300+800）；总900→舞台1（+500）
	w.earn(777, "系统任务")
	var saved_rep: Dictionary = rep.to_dict()
	var saved_w: Dictionary = w.to_dict()
	# 新实例恢复（模拟读档）
	var rep2 := RepSys.new()
	rep2.from_dict(saved_rep)
	var w2 := DWallet.new()
	w2.from_dict(saved_w)
	_check(is_equal_approx(rep2.get_value("minxin"), 900.0), "存档往返：民心值")
	_check(rep2.get_tier("minxin") == 2, "存档往返：段位")
	_check(rep2.claim_tier_milestone("minxin") == 0, "存档往返：水位防重复（原档已领）")
	_check(w2.points == 300 + 800 + 500 + 777, "存档往返：钱包余额")
	rep2.add_reputation("minxin", 2000.0)  # 2900→段位3
	_check(rep2.claim_tier_milestone("minxin") == 1500, "读档后新跨段领取1500")


func _test_invalid_track() -> void:
	var rep := RepSys.new()
	_check(rep.add_reputation("yinyang", 100.0) == 0.0, "未知道轨拒绝")
	_check(not rep.is_valid_track("tianming"), "未知道轨判否")


func _report() -> void:
	print("[RepTest] ===== 四轨声望+天命点 P1-1：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[RepTest] 失败项：%s" % f)
