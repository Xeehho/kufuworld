extends SceneTree
## P1-3 天命商城聚焦测试（headless）。
## 运行：godot --headless --path <项目根> --script res://tools/test_destiny_shop.gd
## 覆盖：六品类商品表/舞台解锁过滤/天命点购买与失败原因/限购与售罄/
##       无限购/黑市铜钱限量购/回响保险标志/存档往返/配置回退。

const DWallet := preload("res://scripts/gameplay/destiny_wallet.gd")
const Shop := preload("res://scripts/gameplay/destiny_shop.gd")

var passes := 0
var fails: Array = []


func _init() -> void:
	_test_catalog()
	_test_buy_destiny()
	_test_stock_limit()
	_test_black_market()
	_test_echo_insurance()
	_test_roundtrip()
	_test_config_fallback()
	_report()
	quit(1 if fails.size() > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(label)
		print("[ShopTest] FAIL: %s" % label)


func _rich_wallet() -> DWallet:
	var w := DWallet.new()
	w.earn(1000000, "测试注资")
	return w


func _test_catalog() -> void:
	var s := Shop.new(_rich_wallet())
	_check(s.config["categories"].size() == 6, "六品类")
	_check(s.config["items"].size() == 26, "26件商品")
	_check(s.category_name("liangzhong") == "天道良种", "品类名")
	# 舞台解锁过滤：stage0 只有曲辕犁（唯一 unlock_stage=0）
	var stage0 := s.list_items(0)
	_check(stage0.size() == 1 and String(stage0[0]["id"]) == "quyuanli_tuzhi", "舞台0仅曲辕犁")
	# 品类过滤：舞台2武学=吐纳导引术(stage1)+射术(stage2)
	var wuxue2 := s.list_items(2, "wuxue")
	_check(wuxue2.size() == 2 and wuxue2.any(func(it): return String(it["id"]) == "she_shu") and wuxue2.any(func(it): return String(it["id"]) == "tuna_daoyin"), "舞台2武学两件")
	# 舞台4全量（未购时 26 件全开）
	_check(s.list_items(4).size() == 26, "舞台4全量26件")


func _test_buy_destiny() -> void:
	var w := _rich_wallet()
	var s := Shop.new(w)
	var r := s.buy_destiny("quyuanli_tuzhi", 0)
	_check(bool(r["ok"]), "购买曲辕犁成功")
	_check(w.points == 1000000 - 800, "扣天命点800")
	_check(bool(r["item"]["name"] == "曲辕犁图纸"), "返回商品")
	# 失败原因：锁定
	var r2 := s.buy_destiny("boli_tuzhi", 0)
	_check(not bool(r2["ok"]) and String(r2["reason"]) == "locked", "舞台不足拒绝")
	# 失败原因：天命点不足
	var poor := DWallet.new()
	poor.earn(100, "穷测")
	var s2 := Shop.new(poor)
	var r3 := s2.buy_destiny("tongche_tuzhi", 1)
	_check(String(r3["reason"]) == "no_points", "天命点不足拒绝")
	_check(poor.points == 100, "拒绝后不扣费")
	# 失败原因：不存在
	_check(String(s.buy_destiny("wuchapin", 4)["reason"]) == "no_item", "不存在商品拒绝")
	# 购买信号
	var bought: Array = []
	s.purchased.connect(func(item, currency, paid): bought.append([item["id"], currency, paid]))
	s.buy_destiny("tongche_tuzhi", 1)
	_check(bought.size() == 1 and bought[0] == ["tongche_tuzhi", "destiny", 1200], "purchased信号载荷")


func _test_stock_limit() -> void:
	var s := Shop.new(_rich_wallet())
	# stock_limit=1：曲辕犁限购一次
	_check(bool(s.buy_destiny("quyuanli_tuzhi", 0)["ok"]), "首购成功")
	_check(String(s.buy_destiny("quyuanli_tuzhi", 0)["reason"]) == "sold_out", "限购1售罄")
	_check(not s.list_items(0).any(func(it): return String(it["id"]) == "quyuanli_tuzhi"), "售罄商品从列表隐藏")
	# stock_limit=-1：占城稻无限购
	var w := _rich_wallet()
	var s2 := Shop.new(w)
	for i in 3:
		_check(bool(s2.buy_destiny("zhancheng_dao", 1)["ok"]), "占城稻第%d次购买" % (i + 1))
	_check(w.points == 1000000 - 3 * 4000, "三次购买扣12000")


func _test_black_market() -> void:
	var w := _rich_wallet()
	var s := Shop.new(w)
	# 铜钱充足：返回 spent_gold，不扣天命点
	var r := s.buy_black_market("quyuanli_tuzhi", 1000)
	_check(bool(r["ok"]) and int(r["spent_gold"]) == 800, "黑市铜钱购返回扣除额800")
	_check(w.points == 1000000, "黑市不动天命点")
	# 黑市限购与天命点共享计数：同一商品黑市购过则天命点页也售罄
	_check(String(s.buy_destiny("quyuanli_tuzhi", 0)["reason"]) == "sold_out", "黑市购后天命页售罄（共享计数）")
	# 铜钱不足
	var s2 := Shop.new(_rich_wallet())
	_check(String(s2.buy_black_market("feizao_tuzhi", 500)["reason"]) == "no_gold", "铜钱不足拒绝")
	# 黑市售罄
	_check(bool(s2.buy_black_market("feizao_tuzhi", 600)["ok"]), "黑市首购成功")
	_check(String(s2.buy_black_market("feizao_tuzhi", 600)["reason"]) == "sold_out", "黑市限购售罄")


func _test_echo_insurance() -> void:
	var s := Shop.new(_rich_wallet())
	_check(not s.has_echo_insurance(), "初始无保险")
	s.buy_destiny("huixiang_baoxian", 1)
	_check(s.has_echo_insurance(), "购回响保险后生效（死亡惩罚减半标志）")
	_check(String(s.buy_destiny("huixiang_baoxian", 1)["reason"]) == "sold_out", "保险限购1")


func _test_roundtrip() -> void:
	var w := _rich_wallet()
	var s := Shop.new(w)
	s.buy_destiny("quyuanli_tuzhi", 0)
	s.buy_destiny("huixiang_baoxian", 1)
	var saved: Dictionary = s.to_dict()
	var s2 := Shop.new(_rich_wallet())
	s2.from_dict(saved)
	_check(String(s2.buy_destiny("quyuanli_tuzhi", 0)["reason"]) == "sold_out", "往返：限购计数保留")
	_check(s2.has_echo_insurance(), "往返：保险标志保留")


func _test_config_fallback() -> void:
	var s := Shop.new(_rich_wallet(), "res://data/不存在.json")
	_check(s.config["items"].size() == 26, "配置缺失回退内置26件")
	var s2 := Shop.new(_rich_wallet(), "res://data/destiny_shop_config.json")
	_check(s2.find_item("zhengqiji_tuzhi")["price"] == 15000, "JSON加载蒸汽机15000")


func _report() -> void:
	print("[ShopTest] ===== P1-3 商城：PASS %d / FAIL %d =====" % [passes, fails.size()])
	for f in fails:
		print("[ShopTest] 失败项：%s" % f)
