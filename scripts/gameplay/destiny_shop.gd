class_name DestinyShop
extends RefCounted
## 天命商城核心（P1-3 数据层，暂不接 UI）。
## 设计依据：docs/大唐穿越重构-剧情与玩法设计-2026-09-04.md §6.2。
## 六品类：天道良种/格物图纸/医道残卷/武学秘传/名物线索/服务——
## 商品 Tier 与解锁舞台挂钩（与轮盘池同尺度：0~4）。
## 天命点商品走 DestinyWallet.spend；黑市页签用铜钱限量购低级图纸
## （§6.1 单向水龙头：铜钱→低级图纸，禁止反向兑换天命点）。
## 铜钱不接 GameManager（共享热点）：调用方传当前铜钱，返回扣除额。
## 商品效果 item_id 为占位命名，物品/农场/仓界系统接线时统一登记。
## 服务类（仓界扩容/回响保险）只记账：回响保险标志由死亡系统 reskin
## 时读取（REQ 口径：两项死亡惩罚减半）。

signal purchased(item: Dictionary, currency: String, paid: int)  # currency: destiny/gold

const DWalletScript := preload("res://scripts/gameplay/destiny_wallet.gd")

const CONFIG_PATH := "res://data/destiny_shop_config.json"

## 内置默认：与 JSON 同源维护；缺失回退。stage=解锁舞台（0~4）；
## stock_limit=限购次数（-1 无限）；black_market 条目带 gold_price。
const DEFAULT_CONFIG: Dictionary = {
	"categories": [
		{"id": "liangzhong", "name": "天道良种"},
		{"id": "tuzhi", "name": "格物图纸"},
		{"id": "yidao", "name": "医道残卷"},
		{"id": "wuxue", "name": "武学秘传"},
		{"id": "mingwu", "name": "名物线索"},
		{"id": "fuwu", "name": "服务"},
	],
	"items": [
		# 天道良种（绝/传世；产出"种子"需种植经营转化，保农场玩法价值）
		{"id": "zhancheng_dao", "category": "liangzhong", "name": "占城稻种", "tier": "juepin", "price": 4000, "unlock_stage": 1, "stock_limit": -1},
		{"id": "shuangji_dao", "category": "liangzhong", "name": "双季稻种", "tier": "juepin", "price": 6000, "unlock_stage": 2, "stock_limit": -1},
		{"id": "hongshu_zhongzi", "category": "liangzhong", "name": "红薯种", "tier": "chuanshi", "price": 9000, "unlock_stage": 2, "stock_limit": 1},
		{"id": "tudu_zhongzi", "category": "liangzhong", "name": "土豆种", "tier": "chuanshi", "price": 9000, "unlock_stage": 3, "stock_limit": 1},
		{"id": "yumi_zhongzi", "category": "liangzhong", "name": "玉米种", "tier": "chuanshi", "price": 12000, "unlock_stage": 3, "stock_limit": 1},
		# 格物图纸（良→传世；终局蒸汽机舞台4）
		{"id": "quyuanli_tuzhi", "category": "tuzhi", "name": "曲辕犁图纸", "tier": "liangpin", "price": 800, "unlock_stage": 0, "stock_limit": 1},
		{"id": "tongche_tuzhi", "category": "tuzhi", "name": "筒车图纸", "tier": "liangpin", "price": 1200, "unlock_stage": 1, "stock_limit": 1},
		{"id": "shuidui_tuzhi", "category": "tuzhi", "name": "水碓图纸", "tier": "zhenpin", "price": 2500, "unlock_stage": 1, "stock_limit": 1},
		{"id": "feizao_tuzhi", "category": "tuzhi", "name": "肥皂图纸", "tier": "liangpin", "price": 1000, "unlock_stage": 1, "stock_limit": 1},
		{"id": "boli_tuzhi", "category": "tuzhi", "name": "玻璃图纸", "tier": "zhenpin", "price": 3000, "unlock_stage": 2, "stock_limit": 1},
		{"id": "shuini_tuzhi", "category": "tuzhi", "name": "水泥图纸", "tier": "zhenpin", "price": 3500, "unlock_stage": 2, "stock_limit": 1},
		{"id": "huozijue_tuzhi", "category": "tuzhi", "name": "活字印刷图纸", "tier": "zhenpin", "price": 4000, "unlock_stage": 2, "stock_limit": 1},
		{"id": "huoyao_gailiang", "category": "tuzhi", "name": "火药改良图纸", "tier": "juepin", "price": 8000, "unlock_stage": 3, "stock_limit": 1},
		{"id": "zhengqiji_tuzhi", "category": "tuzhi", "name": "蒸汽机图纸", "tier": "chuanshi", "price": 15000, "unlock_stage": 4, "stock_limit": 1},
		# 医道残卷（珍/绝）
		{"id": "zhongdou_fq", "category": "yidao", "name": "种痘法残卷", "tier": "juepin", "price": 7000, "unlock_stage": 2, "stock_limit": 1},
		{"id": "liejiu_xiaodu", "category": "yidao", "name": "烈酒蒸馏消毒残卷", "tier": "zhenpin", "price": 2500, "unlock_stage": 1, "stock_limit": 1},
		{"id": "qingmeisu_ct", "category": "yidao", "name": "青霉素粗提残卷", "tier": "juepin", "price": 9000, "unlock_stage": 3, "stock_limit": 1},
		# 武学秘传（珍/绝）
		{"id": "tuna_daoyin", "category": "wuxue", "name": "吐纳导引术", "tier": "zhenpin", "price": 2000, "unlock_stage": 1, "stock_limit": 1},
		{"id": "masuo_shu", "category": "wuxue", "name": "马槊术", "tier": "juepin", "price": 6000, "unlock_stage": 3, "stock_limit": 1},
		{"id": "she_shu", "category": "wuxue", "name": "射术", "tier": "zhenpin", "price": 2500, "unlock_stage": 2, "stock_limit": 1},
		{"id": "qi_changdao", "category": "wuxue", "name": "戚氏长刀（东御彩蛋）", "tier": "juepin", "price": 7000, "unlock_stage": 4, "stock_limit": 1},
		# 名物线索（珍，剧情道具）
		{"id": "wangxizhi_moben", "category": "mingwu", "name": "王羲之摹本下落", "tier": "zhenpin", "price": 3000, "unlock_stage": 2, "stock_limit": 1},
		{"id": "xiyu_shanglu", "category": "mingwu", "name": "西域商路图", "tier": "zhenpin", "price": 3000, "unlock_stage": 3, "stock_limit": 1},
		{"id": "woguo_bufang", "category": "mingwu", "name": "倭国布防图", "tier": "zhenpin", "price": 3000, "unlock_stage": 4, "stock_limit": 1},
		# 服务（良；回响保险=死亡两项惩罚减半，REQ 口径）
		{"id": "cangjie_kuorong", "category": "fuwu", "name": "仓界扩容+5格", "tier": "liangpin", "price": 1500, "unlock_stage": 1, "stock_limit": -1},
		{"id": "huixiang_baoxian", "category": "fuwu", "name": "回响保险（死亡惩罚减半）", "tier": "liangpin", "price": 500, "unlock_stage": 1, "stock_limit": 1},
	],
	"black_market": [
		# 铜钱限量购低级图纸（单向水龙头）
		{"id": "quyuanli_tuzhi", "gold_price": 800, "stock_limit": 1},
		{"id": "feizao_tuzhi", "gold_price": 600, "stock_limit": 1},
	],
}

var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
var wallet: DWalletScript
var purchase_counts: Dictionary = {}  # item_id -> int（天命点+黑市共享计数）
var echo_insured: bool = false  # 回响保险标志（死亡系统 reskin 读取）


func _init(wallet: DWalletScript, config_path: String = CONFIG_PATH) -> void:
	self.wallet = wallet
	if not config_path.is_empty() and FileAccess.file_exists(config_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if parsed is Dictionary:
			for key in parsed.keys():
				if DEFAULT_CONFIG.has(key):
					config[key] = parsed[key]
	else:
		push_warning("[Shop] 配置缺失，使用内置默认：%s" % config_path)


func category_name(category_id: String) -> String:
	for c in config["categories"]:
		if String(c["id"]) == category_id:
			return String(c["name"])
	return category_id


func find_item(item_id: String) -> Dictionary:
	for it in config["items"]:
		if String(it["id"]) == item_id:
			return it
	return {}


func find_black_market_item(item_id: String) -> Dictionary:
	for it in config["black_market"]:
		if String(it["id"]) == item_id:
			return it
	return {}


## 按解锁舞台列可购商品（已售罄过滤；locked=false 只列已解锁）。
func list_items(stage: int, category: String = "") -> Array:
	var out: Array = []
	for it in config["items"]:
		if not category.is_empty() and String(it["category"]) != category:
			continue
		if int(it["unlock_stage"]) > stage:
			continue
		if _sold_out(String(it["id"])):
			continue
		out.append(it)
	return out


func _sold_out(item_id: String) -> bool:
	var item := find_item(item_id)
	var limit := int(item.get("stock_limit", -1))
	return limit >= 0 and int(purchase_counts.get(item_id, 0)) >= limit


## 天命点购买。返回 {ok, reason, item}；失败不扣费。
func buy_destiny(item_id: String, stage: int) -> Dictionary:
	var item := find_item(item_id)
	if item.is_empty():
		return _fail("no_item", item_id)
	if int(item["unlock_stage"]) > stage:
		return _fail("locked", item_id)
	if _sold_out(item_id):
		return _fail("sold_out", item_id)
	var price := int(item["price"])
	if not wallet.spend(price, "天命商城·%s" % item["name"]):
		return _fail("no_points", item_id)
	_record_purchase(item)
	purchased.emit(item, "destiny", price)
	return {"ok": true, "reason": "", "item": item}


## 黑市购买（铜钱）。gold=调用方当前铜钱；成功返回 {ok, spent_gold}，
## 由调用方自行扣铜钱（shop 不接 GameManager 共享热点）。
func buy_black_market(item_id: String, gold_available: int) -> Dictionary:
	var bm := find_black_market_item(item_id)
	if bm.is_empty():
		return _fail("no_item", item_id)
	if _sold_out(item_id):
		return _fail("sold_out", item_id)
	var price := int(bm["gold_price"])
	if gold_available < price:
		return _fail("no_gold", item_id)
	_record_purchase(find_item(item_id))
	var item := find_item(item_id)
	purchased.emit(item, "gold", price)
	return {"ok": true, "reason": "", "spent_gold": price, "item": item}


## 回响保险是否生效（死亡系统 reskin 读取：天命点惩罚与声望衰减各减半）。
func has_echo_insurance() -> bool:
	return echo_insured


func _record_purchase(item: Dictionary) -> void:
	var item_id := String(item.get("id", ""))
	purchase_counts[item_id] = int(purchase_counts.get(item_id, 0)) + 1
	if item_id == "huixiang_baoxian":
		echo_insured = true


func _fail(reason: String, item_id: String) -> Dictionary:
	return {"ok": false, "reason": reason, "item_id": item_id}


## 存档序列化（限购计数与保险标志必须入档，防读档重购）。
func to_dict() -> Dictionary:
	return {"purchase_counts": purchase_counts.duplicate(true), "echo_insured": echo_insured}


func from_dict(data: Dictionary) -> void:
	if data.get("purchase_counts") is Dictionary:
		purchase_counts = data["purchase_counts"].duplicate(true)
	echo_insured = bool(data.get("echo_insured", false))
