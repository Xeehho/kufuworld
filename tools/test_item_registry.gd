extends SceneTree
## P1-3 物品实义表聚焦测试（headless）。
## 运行：godot --headless --path <项目根> --script res://tools/test_item_registry.gd
## 覆盖：登记完整性（wheel+shop 全量 id 必在表）/查询/渠道反查/
##       轮盘产物绑定覆盖/命名漂移防复发。

const Registry := preload("res://scripts/gameplay/item_registry.gd")
const Core := preload("res://scripts/gameplay/destiny_core.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_registry_queries()
	_test_consistency()
	_test_bind_rules()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[ItemTest] FAIL: %s" % label)


func _test_registry_queries() -> void:
	var reg := Registry.new()
	_check(reg.items.size() == 34, "登记34件（全量id实测数）")
	_check(reg.has_item("zhancheng_dao"), "占城稻已登记")
	_check(reg.item_name("zhancheng_dao") == "占城稻种", "名称查询")
	_check(reg.item_name("wuzhe_id") == "wuzhe_id", "未登记回显id")
	_check(reg.ids_for("wheel").size() >= 20, "轮盘渠道≥20件")
	_check(reg.ids_for("shop").size() >= 26, "商城渠道≥26件")
	_check(reg.get_item("huixiang_baoxian")["effect"] == "echo_insurance", "效果字段")


func _test_consistency() -> void:
	# 一致性核心断言：轮盘与商城配置引用的每个 item_id 必须已登记（防漂移复发）
	var reg := Registry.new()
	var core := Core.new()
	var wheel_ids: Array = []
	for pool in core.wheel.config["pools"]:
		for quality in pool["items"]:
			for id in pool["items"][quality]:
				wheel_ids.append(id)
	var shop_ids: Array = core.shop.config["items"].map(func(it): return it["id"])
	var missing := reg.validate_ids({"wheel": wheel_ids, "shop": shop_ids})
	_check(missing.is_empty(), "全量id一致性（缺失清单：%s）" % str(missing))
	# 历史漂移样本不再出现
	_check(not wheel_ids.has("zhancheng_daozhong"), "漂移样本zhancheng_daozhong已清")
	_check(not wheel_ids.has("zhengqi_ji"), "漂移样本zhengqi_ji已清")
	_check(wheel_ids.has("zhancheng_dao") and wheel_ids.has("zhengqiji_tuzhi"), "对齐后id在轮盘")


func _test_bind_rules() -> void:
	# §6.3 防破坏性设计：抽奖产物全部绑定不可交易——轮盘层强制 bound，
	# registry 基准 bind=false 仅表示商城购买形态；服务类天生绑定。
	var reg := Registry.new()
	var core := Core.new()
	core.bridge.wallet.earn(100000, "注资")
	core.wheel.pity_juepin_count = 0
	# 多抽覆盖不同品质（种子抽到绑定）
	var results := core.wheel.draw_ten("jiase", 0, 999999.0)
	_check(results.size() == 10 and results.all(func(r): return bool(r["bound"])), "轮盘产物全部绑定")
	var seed_ids := reg.ids_for("wheel").filter(func(id): return String(reg.get_item(id)["category"]) == "seed")
	_check(seed_ids.size() >= 5, "轮盘良种类≥5（产出种子需种植经营转化）")
	_check(bool(reg.get_item("cangjie_kuorong")["bind"]), "服务类天生绑定")


func _report() -> void:
	print("[ItemTest] ===== P1-3 物品实义表：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[ItemTest] 失败项：%s" % f)
