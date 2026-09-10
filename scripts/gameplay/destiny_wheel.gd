class_name DestinyWheel
extends RefCounted
## 天命轮盘核心（P1-3 数据层先行件，暂不接 UI）。
## 设计依据：docs/大唐穿越重构-剧情与玩法设计-2026-09-04.md §6.3。
## 品级：凡品(白)/良品(绿)/珍品(蓝)/绝品(紫)/传世(金)，权重配置驱动。
## 保底：60 抽必出绝品+（硬保底计数，出货即重置）；十连至少一珍（十连内
## 无珍品+ 则第十抽强制提为珍品）。分池随舞台解锁（稼穑/文华/北伐/海防）。
## 抽奖产物全部绑定不可交易（bound=true）；良种类产出"种子"由物品表
## item_id 标记，经营转化属物品系统接线，本模块只管概率、保底与账目。
## 扣费走 DestinyWallet.spend；余额不足整段拒绝，不产生半次十连。

signal drawn(results: Array, pool_id: String)  # results = [{quality, quality_name, item_id, bound}]

const DWalletScript := preload("res://scripts/gameplay/destiny_wallet.gd")

const CONFIG_PATH := "res://data/destiny_wheel_config.json"

const QUALITY_ORDER: PackedStringArray = ["fanpin", "liangpin", "zhenpin", "juepin", "chuanshi"]

## 内置默认：与 JSON 同源维护；缺失回退（保运行可用）。
## item_id 为占位命名（物品系统接线时统一命名登记）。
## cost_ten_draw：设计§4.2 规定十连 900（低于 10×100 凑单优惠）。
## system_unlock_total：设计§4.2 糖糖成长表——轮盘为 Lv3 功能（总声望 3000 解锁）。
const DEFAULT_CONFIG: Dictionary = {
	"cost_per_draw": 100,
	"cost_ten_draw": 900,
	"system_unlock_total": 3000.0,
	"qualities": {
		"fanpin": {"name": "凡品", "weight": 60.0},
		"liangpin": {"name": "良品", "weight": 25.0},
		"zhenpin": {"name": "珍品", "weight": 10.0},
		"juepin": {"name": "绝品", "weight": 4.0},
		"chuanshi": {"name": "传世", "weight": 1.0},
	},
	"pity": {"juepin_hard": 60, "ten_pull_zhenpin": true},
	"pools": [
		{"id": "jiase", "name": "稼穑池", "unlock_stage": 0, "items": {
			"fanpin": ["liangzhong_changgui"], "liangpin": ["zhancheng_daozhong"],
			"zhenpin": ["shuangji_daozhong"], "juepin": ["hongshu_zhongzi"],
			"chuanshi": ["yumi_zhongzi"]}},
		{"id": "wenhua", "name": "文华池", "unlock_stage": 2, "items": {
			"fanpin": ["suanxue_rumen"], "liangpin": ["wuxin_canjuan_a"],
			"zhenpin": ["wangxizhi_moben"], "juepin": ["xiyu_shanglutub"],
			"chuanshi": ["wenzhang_zhen"]}},
		{"id": "beifa", "name": "北伐池", "unlock_stage": 3, "items": {
			"fanpin": ["bingxue_rumen"], "liangpin": ["quyuanli_tuzhi"],
			"zhenpin": ["masuo_shu"], "juepin": ["sheshu_jichu"],
			"chuanshi": ["huoyao_peifang"]}},
		{"id": "haifang", "name": "海防池", "unlock_stage": 4, "items": {
			"fanpin": ["chuanhai_rumen"], "liangpin": ["huochong_tuzhi"],
			"zhenpin": ["qishu_tuzhi"], "juepin": ["qijia_changdao"],
			"chuanshi": ["zhengqi_ji"]}},
	],
}

var config: Dictionary = DEFAULT_CONFIG.duplicate(true)
var wallet: DWalletScript
## 绝品硬保底计数：连续未出绝品+ 的抽数（出货即清零；入档防读档白嫖）
var pity_juepin_count: int = 0
var rng := RandomNumberGenerator.new()


func _init(wallet: DWalletScript, config_path: String = CONFIG_PATH, seed_value: int = -1) -> void:
	self.wallet = wallet
	if seed_value >= 0:
		rng.seed = seed_value  # 测试可复现
	_load_config(config_path)


func _load_config(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_warning("[Wheel] 配置缺失，使用内置默认：%s" % path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for key in parsed.keys():
			if DEFAULT_CONFIG.has(key):
				config[key] = parsed[key]


func cost_per_draw() -> int:
	return int(config["cost_per_draw"])


func cost_ten_draw() -> int:
	return int(config.get("cost_ten_draw", cost_per_draw() * 10))


## 轮盘功能门槛：糖糖 Lv3（总声望 ≥ system_unlock_total）才开放，设计§4.2。
## 与池的舞台解锁是两级门槛：功能未开时任何池都不可抽。
func is_wheel_unlocked(total_reputation: float) -> bool:
	return total_reputation >= float(config.get("system_unlock_total", 0.0))


func pool_ids() -> Array:
	return config["pools"].map(func(p): return String(p["id"]))


## 分池随总声望舞台解锁（稼穑 0 舞台即开；文华=2；北伐=3；海防=4）。
func is_pool_unlocked(pool_id: String, stage: int) -> bool:
	var pool := _find_pool(pool_id)
	return not pool.is_empty() and stage >= int(pool.get("unlock_stage", 0))


## 单抽。功能未解锁/池不存在或未解锁/余额不足：返回空数组且不扣费。
func draw_once(pool_id: String, stage: int = 0, total_reputation: float = 0.0) -> Array:
	if not is_wheel_unlocked(total_reputation):
		return []
	var pool := _find_pool(pool_id)
	if pool.is_empty() or not is_pool_unlocked(pool_id, stage):
		return []
	if not wallet.spend(cost_per_draw(), "天命轮盘·%s单抽" % pool["name"]):
		return []
	var result := _make_result(pool, _roll_quality())
	var results := [result]
	drawn.emit(results, pool_id)
	return results


## 十连：整段扣费 cost_ten_draw（900，设计§4.2）；十连至少一珍（无珍品+ 则末抽强制珍品）。
func draw_ten(pool_id: String, stage: int = 0, total_reputation: float = 0.0) -> Array:
	if not is_wheel_unlocked(total_reputation):
		return []
	var pool := _find_pool(pool_id)
	if pool.is_empty() or not is_pool_unlocked(pool_id, stage):
		return []
	if not wallet.spend(cost_ten_draw(), "天命轮盘·%s十连" % pool["name"]):
		return []
	var results: Array = []
	for i in 10:
		results.append(_make_result(pool, _roll_quality()))
	if bool(config["pity"].get("ten_pull_zhenpin", true)):
		var has_zhenpin := results.any(func(r): return _quality_rank(String(r["quality"])) >= _quality_rank("zhenpin"))
		if not has_zhenpin:
			results[9] = _make_result(pool, "zhenpin")
	drawn.emit(results, pool_id)
	return results


## 权重随机 + 绝品硬保底：计数到 hard-1（第 hard 抽）强制绝品，传世仍按权重自然出。
func _roll_quality() -> String:
	var hard := int(config["pity"].get("juepin_hard", 60))
	if hard > 0 and pity_juepin_count >= hard - 1:
		pity_juepin_count = 0
		return "juepin"
	var qualities: Dictionary = config["qualities"]
	var total := 0.0
	for q in qualities.keys():
		total += float(qualities[q]["weight"])
	var roll := rng.randf() * total
	var acc := 0.0
	var picked := "fanpin"
	for q in qualities.keys():
		acc += float(qualities[q]["weight"])
		if roll <= acc:
			picked = q
			break
	if _quality_rank(picked) >= _quality_rank("juepin"):
		pity_juepin_count = 0
	else:
		pity_juepin_count += 1
	return picked


func _quality_rank(quality: String) -> int:
	return QUALITY_ORDER.find(quality)


func _make_result(pool: Dictionary, quality: String) -> Dictionary:
	var items: Array = pool.get("items", {}).get(quality, [])
	var item_id := ""
	if items.size() > 0:
		item_id = String(items[rng.randi_range(0, items.size() - 1)])
	return {
		"quality": quality,
		"quality_name": String(config["qualities"].get(quality, {}).get("name", quality)),
		"item_id": item_id,
		"bound": true,
	}


func _find_pool(pool_id: String) -> Dictionary:
	for p in config["pools"]:
		if String(p["id"]) == pool_id:
			return p
	return {}


## 存档序列化（保底计数必须入档，否则读档后保底重算可被白嫖）。
func to_dict() -> Dictionary:
	return {"pity_juepin_count": pity_juepin_count}


func from_dict(data: Dictionary) -> void:
	pity_juepin_count = int(data.get("pity_juepin_count", 0))
