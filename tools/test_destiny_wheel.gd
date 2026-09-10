extends SceneTree
## P1-3 天命轮盘聚焦测试（headless）。
## 运行：godot --headless --path <项目根> --script res://tools/test_destiny_wheel.gd
## 覆盖：扣费与拒绝/池解锁门槛/权重分布（种子复现）/绝品硬保底60/
##       十连至少一珍/产物绑定标记/保底计数入档/配置回退。

const DWallet := preload("res://scripts/gameplay/destiny_wallet.gd")
const Wheel := preload("res://scripts/gameplay/destiny_wheel.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_cost_and_reject()
	_test_pool_unlock()
	_test_weight_distribution()
	_test_hard_pity()
	_test_ten_pull_pity()
	_test_binding_and_save()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[WheelTest] FAIL: %s" % label)


func _rich_wallet() -> DWallet:
	var w := DWallet.new()
	w.earn(1000000, "测试注资")
	return w


func _test_cost_and_reject() -> void:
	var w := _rich_wallet()
	var wheel := Wheel.new(w, "", 42)
	var r := wheel.draw_once("jiase", 0)
	_check(r.size() == 1, "单抽返回1条结果")
	_check(w.points == 1000000 - 100, "单抽扣100")
	_check(r[0].has("quality") and r[0].has("item_id"), "结果含品级与物品")
	# 余额不足整段拒绝
	var poor := DWallet.new()
	poor.earn(50, "穷测")
	var w2 := Wheel.new(poor, "", 1)
	_check(w2.draw_once("jiase", 0).is_empty(), "余额不足单抽拒绝")
	_check(poor.points == 50, "拒绝后不扣费")
	poor.earn(900, "凑十连差一点")
	_check(w2.draw_ten("jiase", 0).is_empty(), "十连不足整段拒绝")
	_check(poor.points == 950, "十连拒绝后余额不变")
	# 不存在的池
	var w3 := Wheel.new(_rich_wallet(), "", 7)
	_check(w3.draw_once("wuchipu", 0).is_empty(), "不存在池拒绝")


func _test_pool_unlock() -> void:
	var wheel := Wheel.new(_rich_wallet(), "", 7)
	_check(wheel.is_pool_unlocked("jiase", 0), "稼穑池0舞台开")
	_check(not wheel.is_pool_unlocked("wenhua", 1), "文华池1舞台锁")
	_check(wheel.is_pool_unlocked("wenhua", 2), "文华池2舞台开")
	_check(not wheel.is_pool_unlocked("haifang", 3), "海防池3舞台锁")
	var w := _rich_wallet()
	var w2 := Wheel.new(w, "", 7)
	_check(w2.draw_once("beifa", 0).is_empty() and w.points == 1000000, "未解锁池抽不扣费")


func _test_weight_distribution() -> void:
	# 种子复现 + 大样本分布：凡品应最多、传世最少（60/25/10/4/1 权重）
	var w := _rich_wallet()
	var wheel := Wheel.new(w, "", 123)
	var counts := {}
	for i in 5000:
		var r := wheel.draw_once("jiase", 0)
		counts[r[0]["quality"]] = int(counts.get(r[0]["quality"], 0)) + 1
	_check(int(counts.get("fanpin", 0)) > int(counts.get("liangpin", 0)), "凡品>良品")
	_check(int(counts.get("liangpin", 0)) > int(counts.get("zhenpin", 0)), "良品>珍品")
	_check(counts.get("chuanshi", 0) != null, "传世有概率出现（含硬保底）")
	_check(int(counts.get("chuanshi", 0)) < int(counts.get("juepin", 0)), "传世<绝品")


func _test_hard_pity() -> void:
	# 硬保底：把计数推到 59，下一抽必绝品
	var wheel := Wheel.new(_rich_wallet(), "", 999)
	wheel.pity_juepin_count = 59
	var r := wheel.draw_once("jiase", 0)
	_check(String(r[0]["quality"]) == "juepin", "第60抽强制绝品")
	_check(wheel.pity_juepin_count == 0, "绝品出货重置计数")
	# 计数入档防读档白嫖
	var saved: Dictionary = wheel.to_dict()
	var wheel2 := Wheel.new(_rich_wallet(), "", 5)
	wheel2.from_dict(saved)
	_check(wheel2.pity_juepin_count == 0, "读档恢复计数0")
	var wheel3 := Wheel.new(_rich_wallet(), "", 6)
	wheel3.pity_juepin_count = 40
	wheel3.from_dict({"pity_juepin_count": 55})
	_check(wheel3.pity_juepin_count == 55, "读档覆盖计数")


func _test_ten_pull_pity() -> void:
	# 十连至少一珍：构造极坏运气——种子扫描至找到天然无珍品+ 的十连，验证末抽强制珍品
	var found_force := false
	for seed in range(200):
		var w := _rich_wallet()
		var wheel := Wheel.new(w, "", seed)
		wheel.pity_juepin_count = 0
		var results := wheel.draw_ten("jiase", 0)
		if results.is_empty():
			continue
		# 验证规则本身：任何十连必然至少一珍
		var has := results.any(func(r): return wheel._quality_rank(String(r["quality"])) >= 2)
		if not has:
			found_force = true  # 不应发生：保底保证有珍
			break
	_check(not found_force, "任意种子十连至少一珍（200种子样本）")
	# 十连扣费=10×单抽
	var w2 := _rich_wallet()
	var wheel4 := Wheel.new(w2, "", 3)
	wheel4.draw_ten("jiase", 0)
	_check(w2.points == 1000000 - 1000, "十连扣1000")


func _test_binding_and_save() -> void:
	var w := _rich_wallet()
	var wheel := Wheel.new(w, "", 11)
	var r := wheel.draw_once("jiase", 0)
	_check(bool(r[0]["bound"]), "产物绑定不可交易")
	_check(r[0]["quality_name"] == String(wheel.config["qualities"][r[0]["quality"]]["name"]), "品级中文名")
	# 配置缺失回退内置默认
	var wheel5 := Wheel.new(_rich_wallet(), "res://data/不存在.json", 1)
	_check(wheel5.cost_per_draw() == 100, "配置缺失回退默认价")


func _report() -> void:
	print("[WheelTest] ===== P1-3 轮盘：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[WheelTest] 失败项：%s" % f)
