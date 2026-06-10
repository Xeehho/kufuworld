extends Node

# 商店系统 - NPC商人、供求定价、买卖交易
# 物品类型常量（与inventory_manager.gd一致）
const ITEM_WEAPON = 0
const ITEM_ARMOR = 1
const ITEM_CONSUMABLE = 2
const ITEM_MATERIAL = 3
const ITEM_MANUAL = 4
const ITEM_ACCESSORY = 5
const RARITY_COMMON = 0
const RARITY_UNCOMMON = 1
const RARITY_RARE = 2
const RARITY_EPIC = 3
const RARITY_LEGENDARY = 4

var shop_items: Array = []  # [{item: Resource, stock: int, sold_count: int}]
var shop_open: bool = false
var shop_name: String = "江湖杂货铺"
var price_modifier: float = 1.0  # 声望折扣

signal shop_opened
signal shop_closed
signal transaction_made(action: String, item_name: String, price: int, count: int)

func _ready():
	_create_shop_inventory()

func open_shop(shop_name_str: String = "江湖杂货铺"):
	shop_name = shop_name_str
	shop_open = true
	price_modifier = max(0.7, 1.0 - GameManager.reputation * 0.0005)
	shop_opened.emit()
	print("[Shop] " + shop_name + " 开张! 声望折扣: " + str(int((1 - price_modifier) * 100)) + "%")

func close_shop():
	shop_open = false
	shop_closed.emit()
	print("[Shop] 商店关闭")

func get_buy_price(item) -> int:
	var supply_factor = _get_supply_factor(item)
	var demand_factor = _get_demand_factor(item)
	var price = int(item.base_price * supply_factor * demand_factor * price_modifier)
	return max(price, 1)

func get_sell_price(item) -> int:
	return max(int(get_buy_price(item) * 0.5), 1)

func buy_item(index: int, count: int = 1) -> bool:
	if index < 0 or index >= shop_items.size():
		return false
	var slot = shop_items[index]
	var item = slot["item"]
	if slot["stock"] < count:
		print("[Shop] 库存不足!")
		return false
	var total_price = get_buy_price(item) * count
	if GameManager.gold < total_price:
		print("[Shop] 铜钱不足! 需要" + str(total_price) + "，持有" + str(GameManager.gold))
		return false
	GameManager.modify_gold(-total_price)
	var inv = _get_inventory_manager()
	if inv:
		inv.add_item(item, count)
	slot["stock"] -= count
	slot["sold_count"] += count
	item.supply_level = max(item.supply_level - count * 2, 5)
	item.demand_level = min(item.demand_level + count, 95)
	transaction_made.emit("买入", item.item_name, total_price, count)
	print("[Shop] 买入 " + str(count) + "x " + item.item_name + " 花费" + str(total_price) + "铜钱")
	return true

func sell_item(item_id: String, count: int = 1) -> bool:
	var inv = _get_inventory_manager()
	if not inv:
		return false
	if not inv.has_item(item_id, count):
		print("[Shop] 背包中没有该物品!")
		return false
	var item = _find_item_in_inventory(inv, item_id)
	if item == null:
		return false
	var total_price = get_sell_price(item) * count
	GameManager.modify_gold(total_price)
	inv.remove_item(item_id, count)
	item.supply_level = min(item.supply_level + count * 2, 95)
	item.demand_level = max(item.demand_level - count, 5)
	transaction_made.emit("卖出", item.item_name, total_price, count)
	print("[Shop] 卖出 " + str(count) + "x " + item.item_name + " 获得" + str(total_price) + "铜钱")
	return true

func _get_supply_factor(item) -> float:
	var s = item.supply_level
	if s >= 80:
		return 0.7 + (100 - s) * 0.005
	elif s >= 50:
		return 0.85 + (80 - s) * 0.005
	elif s >= 20:
		return 1.0 + (50 - s) * 0.017
	else:
		return 1.5 + (20 - s) * 0.01

func _get_demand_factor(item) -> float:
	var d = item.demand_level
	if d >= 80:
		return 1.2 + (d - 80) * 0.01
	elif d >= 50:
		return 1.0 + (d - 50) * 0.007
	elif d >= 20:
		return 0.8 + (d - 20) * 0.007
	else:
		return 0.6 + d * 0.01

func _find_item_in_inventory(inv, item_id: String):
	for slot in inv.inventory:
		if slot["item"].item_id == item_id:
			return slot["item"]
	return null

func restock():
	for slot in shop_items:
		var max_stock = 20
		if slot["item"].rarity >= RARITY_RARE:
			max_stock = 5
		elif slot["item"].rarity >= RARITY_UNCOMMON:
			max_stock = 10
		slot["stock"] = min(slot["stock"] + randi_range(3, 8), max_stock)
		slot["item"].supply_level = move_toward(slot["item"].supply_level, 50, 5)
		slot["item"].demand_level = move_toward(slot["item"].demand_level, 50, 5)
	print("[Shop] 商店补货完成")

func _create_shop_inventory():
	var items_data = [
		_shop_item("金创药", "常见外伤药", ITEM_CONSUMABLE, RARITY_COMMON, 15, 20, 0, 0, 25, 0, 0, 0, 0),
		_shop_item("回气丹", "恢复内力", ITEM_CONSUMABLE, RARITY_COMMON, 20, 15, 0, 0, 0, 30, 0, 0, 0),
		_shop_item("肉包子", "充饥食物", ITEM_CONSUMABLE, RARITY_COMMON, 5, 30, 0, 0, 5, 0, 30, 0, 0),
		_shop_item("解毒散", "解除毒素", ITEM_CONSUMABLE, RARITY_UNCOMMON, 35, 8, 0, 0, 0, 0, 0, 40, 0),
		_shop_item("大还丹", "恢复大量气血", ITEM_CONSUMABLE, RARITY_RARE, 120, 3, 0, 0, 80, 20, 0, 20, 0),
		_shop_item("铁剑", "普通铁剑", ITEM_WEAPON, RARITY_COMMON, 80, 5, 8, 2, 0, 0, 0, 0, 0),
		_shop_item("精钢剑", "精炼钢剑", ITEM_WEAPON, RARITY_UNCOMMON, 200, 3, 15, 4, 0, 0, 0, 0, 0),
		_shop_item("玄铁重剑", "稀世重剑", ITEM_WEAPON, RARITY_RARE, 500, 1, 30, 8, 0, 0, 0, 0, 0),
		_shop_item("布甲", "普通防护", ITEM_ARMOR, RARITY_COMMON, 60, 5, 0, 8, 0, 0, 0, 0, 0),
		_shop_item("皮甲", "皮革防护", ITEM_ARMOR, RARITY_UNCOMMON, 150, 3, 0, 15, 0, 0, 0, 0, 0),
		_shop_item("铁矿石", "锻造材料", ITEM_MATERIAL, RARITY_COMMON, 10, 20, 0, 0, 0, 0, 0, 0, 0),
		_shop_item("草药", "炼丹材料", ITEM_MATERIAL, RARITY_COMMON, 8, 25, 0, 0, 0, 0, 0, 0, 0),
		_shop_item("玉佩", "温润玉佩", ITEM_ACCESSORY, RARITY_RARE, 300, 2, 0, 3, 0, 0, 0, 0, 0),
	]
	shop_items = items_data

func _shop_item(name_str: String, desc: String, type: int, rarity_val: int, price: int, stock: int, atk: float, def_val: float, heal: float, qi_r: float, hunger_r: float, poison_c: float, speed_b: float) -> Dictionary:
	var item_script = load("res://scripts/item_resource.gd")
	var item = Resource.new()
	item.set_script(item_script)
	item.item_id = name_str
	item.item_name = name_str
	item.description = desc
	item.item_type = type
	item.rarity = rarity_val
	item.base_price = price
	item.attack_bonus = atk
	item.defense_bonus = def_val
	item.heal_amount = heal
	item.qi_restore = qi_r
	item.hunger_restore = hunger_r
	item.poison_cure = poison_c
	item.speed_bonus = speed_b
	return {"item": item, "stock": stock, "sold_count": 0}

func _get_inventory_manager():
	var main = get_node_or_null("/root/Main")
	if main:
		return main.get_node_or_null("InventoryManager")
	return null
