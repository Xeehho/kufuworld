extends Node

# 物品管理器 - 背包系统、物品使用、经济管理
# 物品类型常量（与item_resource.gd中的ItemType枚举对应）
const ITEM_WEAPON = 0
const ITEM_ARMOR = 1
const ITEM_CONSUMABLE = 2
const ITEM_MATERIAL = 3
const ITEM_MANUAL = 4
const ITEM_ACCESSORY = 5
# 稀有度常量
const RARITY_COMMON = 0
const RARITY_UNCOMMON = 1
const RARITY_RARE = 2
const RARITY_EPIC = 3
const RARITY_LEGENDARY = 4

var inventory: Array = []  # [{item: Resource, count: int}]
var max_slots: int = 45
var equipped_weapon: Resource = null
var equipped_armor: Resource = null
var equipped_accessory: Resource = null

signal inventory_changed
signal item_used(item, count)
signal equipment_changed

func _ready():
	_create_default_items()

func add_item(item: Resource, count: int = 1) -> bool:
	# 查找已有堆叠
	if item.stackable:
		for slot in inventory:
			if slot["item"].item_id == item.item_id:
				if slot["count"] + count <= item.max_stack:
					slot["count"] += count
					inventory_changed.emit()
					print("[Inventory] +" + str(count) + " " + item.item_name)
					return true
				else:
					var overflow = slot["count"] + count - item.max_stack
					slot["count"] = item.max_stack
					if inventory.size() < max_slots:
						var new_slot = {"item": item, "count": overflow}
						inventory.append(new_slot)
						inventory_changed.emit()
						print("[Inventory] +" + str(count) + " " + item.item_name)
						return true
	# 新槽位
	if inventory.size() >= max_slots:
		print("[Inventory] 背包已满!")
		return false
	inventory.append({"item": item, "count": count})
	inventory_changed.emit()
	print("[Inventory] +" + str(count) + " " + item.item_name)
	return true

func remove_item(item_id: String, count: int = 1) -> bool:
	for i in range(inventory.size()):
		if inventory[i]["item"].item_id == item_id:
			if inventory[i]["count"] > count:
				inventory[i]["count"] -= count
				inventory_changed.emit()
				return true
			elif inventory[i]["count"] == count:
				inventory.remove_at(i)
				inventory_changed.emit()
				return true
			else:
				return false
	return false

func has_item(item_id: String, count: int = 1) -> bool:
	for slot in inventory:
		if slot["item"].item_id == item_id:
			return slot["count"] >= count
	return false

func get_item_count(item_id: String) -> int:
	var total = 0
	for slot in inventory:
		if slot["item"].item_id == item_id:
			total += slot["count"]
	return total

func use_item(item_id: String) -> bool:
	for slot in inventory:
		if slot["item"].item_id == item_id:
			var item = slot["item"]
			if item.item_type == ITEM_CONSUMABLE:
				_apply_consumable(item)
				slot["count"] -= 1
				if slot["count"] <= 0:
					inventory.erase(slot)
				item_used.emit(item, 1)
				inventory_changed.emit()
				return true
			elif item.item_type == ITEM_MANUAL:
				_learn_manual(item)
				slot["count"] -= 1
				if slot["count"] <= 0:
					inventory.erase(slot)
				item_used.emit(item, 1)
				inventory_changed.emit()
				return true
			else:
				print("[Inventory] 该物品无法直接使用")
				return false
	print("[Inventory] 物品不存在")
	return false

func _apply_consumable(item):
	if item.heal_amount > 0:
		GameManager.health = min(GameManager.health + item.heal_amount, 100)
	if item.qi_restore > 0:
		GameManager.restore_qi(item.qi_restore)
	if item.hunger_restore > 0:
		GameManager.eat_food(item.hunger_restore)
	if item.poison_cure > 0:
		GameManager.poison = max(GameManager.poison - item.poison_cure, 0)
	print("[Inventory] 使用了 " + item.item_name + ": " + item.get_effect_description())

func _learn_manual(item):
	if item.skill_unlock != "" and not GameManager.unlocked_skills.has(item.skill_unlock):
		GameManager.unlocked_skills.append(item.skill_unlock)
		print("[Inventory] 习得武学: " + item.skill_unlock)
	else:
		print("[Inventory] 已习得该武学或秘籍无效")

func equip_item(item_id: String) -> bool:
	for slot in inventory:
		if slot["item"].item_id == item_id:
			var item = slot["item"]
			var t = item.item_type
			if t == ITEM_WEAPON:
				if equipped_weapon:
					add_item(equipped_weapon)
				equipped_weapon = item
			elif t == ITEM_ARMOR:
				if equipped_armor:
					add_item(equipped_armor)
				equipped_armor = item
			elif t == ITEM_ACCESSORY:
				if equipped_accessory:
					add_item(equipped_accessory)
				equipped_accessory = item
			else:
				print("[Inventory] 该物品无法装备")
				return false
			slot["count"] -= 1
			if slot["count"] <= 0:
				inventory.erase(slot)
			equipment_changed.emit()
			inventory_changed.emit()
			print("[Inventory] 装备了 " + item.item_name)
			return true
	return false

func unequip_slot(slot_type: String):
	if slot_type == "weapon" and equipped_weapon:
		add_item(equipped_weapon)
		equipped_weapon = null
		equipment_changed.emit()
	elif slot_type == "armor" and equipped_armor:
		add_item(equipped_armor)
		equipped_armor = null
		equipment_changed.emit()
	elif slot_type == "accessory" and equipped_accessory:
		add_item(equipped_accessory)
		equipped_accessory = null
		equipment_changed.emit()

func get_total_attack() -> float:
	var total = 0.0
	if equipped_weapon:
		total += equipped_weapon.attack_bonus
	if equipped_armor:
		total += equipped_armor.attack_bonus
	if equipped_accessory:
		total += equipped_accessory.attack_bonus
	return total

func get_total_defense() -> float:
	var total = 0.0
	if equipped_weapon:
		total += equipped_weapon.defense_bonus
	if equipped_armor:
		total += equipped_armor.defense_bonus
	if equipped_accessory:
		total += equipped_accessory.defense_bonus
	return total

func get_total_qi_bonus() -> float:
	var total = 0.0
	if equipped_weapon:
		total += equipped_weapon.qi_bonus
	if equipped_armor:
		total += equipped_armor.qi_bonus
	if equipped_accessory:
		total += equipped_accessory.qi_bonus
	return total

func _create_default_items():
	var items_data = [
		_create_item("gold_herb", "金创药", "常见外伤药", ITEM_CONSUMABLE, RARITY_COMMON, 15, 0, 0, 25, 0, 0, 0, 0),
		_create_item("qi_pill", "回气丹", "恢复内力的丹药", ITEM_CONSUMABLE, RARITY_COMMON, 20, 0, 0, 0, 30, 0, 0, 0),
		_create_item("meat_bun", "肉包子", "填饱肚子的食物", ITEM_CONSUMABLE, RARITY_COMMON, 5, 0, 0, 5, 0, 30, 0, 0),
		_create_item("antidote", "解毒散", "解除毒素", ITEM_CONSUMABLE, RARITY_UNCOMMON, 35, 0, 0, 0, 0, 0, 40, 0),
		_create_item("iron_sword", "铁剑", "普通的铁剑", ITEM_WEAPON, RARITY_COMMON, 80, 8, 2, 0, 0, 0, 0, 0),
		_create_item("steel_sword", "精钢剑", "精炼钢材打造", ITEM_WEAPON, RARITY_UNCOMMON, 200, 15, 4, 0, 0, 0, 0, 0),
		_create_item("cloth_armor", "布甲", "普通防护", ITEM_ARMOR, RARITY_COMMON, 60, 0, 8, 0, 0, 0, 0, 0),
		_create_item("leather_armor", "皮甲", "皮革防护", ITEM_ARMOR, RARITY_UNCOMMON, 150, 0, 15, 0, 0, 0, 0, 0),
		_create_item("iron_ore", "铁矿石", "锻造材料", ITEM_MATERIAL, RARITY_COMMON, 10, 0, 0, 0, 0, 0, 0, 0),
		_create_item("herb_material", "草药", "炼丹材料", ITEM_MATERIAL, RARITY_COMMON, 8, 0, 0, 0, 0, 0, 0, 0),
		_create_item("jade_ring", "玉佩", "温润玉佩", ITEM_ACCESSORY, RARITY_RARE, 300, 0, 3, 15, 10, 0, 0, 0),
	]
	for d in items_data:
		add_item(d, 3 if d.item_type == ITEM_CONSUMABLE else 1)
	GameManager.gold = 100

func _create_item(id: String, name_str: String, desc: String, type: int, rarity_val: int, price: int, atk: float, def_val: float, heal: float, qi_r: float, hunger_r: float, poison_c: float, speed_b: float) -> Resource:
	var item_script = load("res://scripts/item_resource.gd")
	var item = Resource.new()
	item.set_script(item_script)
	item.item_id = id
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
	return item
