class_name ItemRegistry
extends RefCounted
## 物品实义表（P1-3 接线前置件）：全物品 id 的唯一权威表。
## 轮盘（destiny_wheel）与商城（destiny_shop）配置引用的每个 item_id
## 必须在本表登记——此前两处占位命名已漂移（15/20 不一致），本表统一口径。
## effect 为接线期占位（物品/农场/仓界/武学系统接线时落地真实效果）；
## bind=false 为基准属性：轮盘来源产物由 DestinyWheel 强制 bound=true（§6.3）。
## source 记录可获取渠道（shop/wheel），供反查与一致性校验。

signal registered(item_id: String)

const CONFIG_PATH := "res://data/item_registry.json"

var items: Dictionary = {}


func _init(config_path: String = CONFIG_PATH) -> void:
	if config_path.is_empty() or not FileAccess.file_exists(config_path):
		push_warning("[ItemReg] 配置缺失：%s" % config_path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if parsed is Dictionary and parsed.get("items") is Dictionary:
		items = parsed["items"]
	else:
		push_warning("[ItemReg] 配置解析失败：%s" % config_path)


func has_item(item_id: String) -> bool:
	return items.has(item_id)


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func item_name(item_id: String) -> String:
	return String(get_item(item_id).get("name", item_id))


## 按获取渠道反查（source 含 shop/wheel）。
func ids_for(source: String) -> Array:
	var out: Array = []
	for id in items.keys():
		if items[id].get("source", []).has(source):
			out.append(id)
	return out


## 一致性校验：wheel/shop 配置引用的每个 item_id 都必须已登记。
## 返回缺失清单（空=通过）。接线期与聚焦测试共同使用，防止占位漂移复发。
func validate_ids(id_sets: Dictionary) -> Array:
	var missing: Array = []
	for set_name in id_sets.keys():
		for id in id_sets[set_name]:
			if not has_item(id):
				missing.append("%s:%s" % [set_name, id])
	return missing
