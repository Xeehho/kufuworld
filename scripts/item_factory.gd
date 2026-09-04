extends Object
class_name ItemFactory

# Phase C 共享物品工厂：农场/敌人掉落/工作台合成共用
# 与 inventory_manager.gd 的类型常量保持一致（ITEM_CONSUMABLE=2 / ITEM_MATERIAL=3 / ITEM_WEAPON=0）

const TextureGen = preload("res://scripts/texture_generator.gd")

# id -> [名称, 描述, 类型, 品质, 价格, 饱食恢复]
const PHASE_C_ITEMS := {
	"vegetable_seeds": ["菜种", "可播撒在开垦好的农田上", 3, 0, 6, 0],
	"berry": ["野浆果", "林间灌木结的红色浆果", 2, 0, 4, 8],
	"veggie": ["青菜", "田里种出的新鲜青菜", 2, 0, 12, 18],
	"iron_ingot": ["铁锭", "熔炉冶炼出的铁锭，锻造材料", 3, 1, 40, 0],
	"roasted_berry": ["烤浆果", "篝火烤过的浆果，更顶饱", 2, 0, 10, 30],
	# 敌人掉落物（与inventory_manager默认物品同id同属性，可正确堆叠）
	"iron_ore": ["铁矿石", "山贼携带的铁矿，可熔炼", 3, 0, 10, 0],
	"herb_material": ["草药", "白骨教众掉落的药草，可炼丹", 3, 0, 8, 0],
	# 合成武器（陷阱25：一切合成/掉落物id必须收录，否则give()静默失败）
	"iron_sword": ["铁剑", "工作台锻打的铁剑", 0, 1, 80, 0],
}

# 武器攻击力补全表（PHASE_C_ITEMS基础格式无攻击力字段，按id补）
const WEAPON_ATTACK := {"iron_sword": 8}

static func _script():
	return load("res://scripts/item_resource.gd")

# 统一入口：按 id 构建物品 Resource（未知 id 返回 null）
static func create(id: String) -> Resource:
	var def: Array = PHASE_C_ITEMS.get(id, [])
	if def.is_empty():
		return null
	var item = Resource.new()
	item.set_script(_script())
	item.item_id = id
	item.item_name = def[0]
	item.description = def[1]
	item.item_type = def[2]
	item.rarity = def[3]
	item.base_price = def[4]
	item.hunger_restore = def[5]
	# 武器补攻击力（工作台铁剑等需与商店同物同强度）
	if WEAPON_ATTACK.has(id):
		item.attack_bonus = WEAPON_ATTACK[id]
	return item

# 便捷：把 count 个物品塞进 InventoryManager（找不到管理器时只打日志）
static func give(id: String, count: int = 1) -> bool:
	var inv = _inventory()
	if inv == null:
		print("[ItemFactory] InventoryManager 不存在，丢弃 %s x%d" % [id, count])
		return false
	var item = create(id)
	if item == null:
		push_warning("[ItemFactory] 未知物品id: " + id)
		return false
	return inv.add_item(item, count)

static func _inventory() -> Node:
	var root = Engine.get_main_loop()
	if root == null:
		return null
	var tree := root as SceneTree
	# 常规：InventoryManager挂在主场景下；兜底：Main/InventoryManager（探针等自定义场景时current_scene不同）
	var inv = tree.current_scene.get_node_or_null("InventoryManager") if tree.current_scene else null
	if inv == null:
		inv = tree.root.get_node_or_null("Main/InventoryManager")
	return inv
