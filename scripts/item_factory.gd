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
}

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
	return (root as SceneTree).current_scene.get_node_or_null("InventoryManager")
