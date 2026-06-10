extends Resource

# 物品资源类 - 装备、药品、材料、秘籍

enum ItemType { WEAPON, ARMOR, CONSUMABLE, MATERIAL, MANUAL, ACCESSORY }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var item_id: String = ""
@export var item_name: String = ""
@export var description: String = ""
@export var item_type: int = ItemType.CONSUMABLE
@export var rarity: int = Rarity.COMMON
@export var base_price: int = 10
@export var stackable: bool = true
@export var max_stack: int = 99

# 装备属性
@export var attack_bonus: float = 0.0
@export var defense_bonus: float = 0.0
@export var qi_bonus: float = 0.0
@export var health_bonus: float = 0.0
@export var speed_bonus: float = 0.0

# 消耗品属性
@export var heal_amount: float = 0.0
@export var qi_restore: float = 0.0
@export var hunger_restore: float = 0.0
@export var poison_cure: float = 0.0

# 秘籍属性
@export var skill_unlock: String = ""
@export var element: String = ""

# 五行属性
@export var wuxing_element: String = ""  # 金木水火土

# 供求参数
@export var supply_level: int = 50   # 0-100, 越高供应越充足
@export var demand_level: int = 50   # 0-100, 越高需求越旺盛

func get_rarity_name() -> String:
	var names = ["凡品", "良品", "稀有", "史诗", "传说"]
	if rarity >= 0 and rarity < names.size():
		return names[rarity]
	return "凡品"

func get_type_name() -> String:
	var names = ["武器", "防具", "药品", "材料", "秘籍", "饰品"]
	if item_type >= 0 and item_type < names.size():
		return names[item_type]
	return "物品"

func get_effect_description() -> String:
	var effects = []
	if attack_bonus > 0:
		effects.append("攻击+" + str(attack_bonus))
	if defense_bonus > 0:
		effects.append("防御+" + str(defense_bonus))
	if qi_bonus > 0:
		effects.append("内力+" + str(qi_bonus))
	if health_bonus > 0:
		effects.append("气血+" + str(health_bonus))
	if speed_bonus > 0:
		effects.append("速度+" + str(speed_bonus))
	if heal_amount > 0:
		effects.append("恢复" + str(heal_amount) + "气血")
	if qi_restore > 0:
		effects.append("恢复" + str(qi_restore) + "内力")
	if hunger_restore > 0:
		effects.append("恢复" + str(hunger_restore) + "饱食")
	if poison_cure > 0:
		effects.append("解毒" + str(poison_cure))
	if skill_unlock != "":
		effects.append("习得: " + skill_unlock)
	if wuxing_element != "":
		effects.append("五行: " + wuxing_element)
	if effects.is_empty():
		return "无特殊效果"
	return "，".join(effects)
