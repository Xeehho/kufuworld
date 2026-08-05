extends Control

# 商店UI - 居中面板，买卖切换，可点击物品行，统一样式

const ITEM_WEAPON = 0
const ITEM_ARMOR = 1
const ITEM_CONSUMABLE = 2
const ITEM_MATERIAL = 3
const ITEM_MANUAL = 4
const ITEM_ACCESSORY = 5

const PANEL_W = 560
const PANEL_H = 520

var shop_panel: Panel
var title_label: Label
var item_list: VBoxContainer
var gold_label: Label
var hint_label: Label
var detail_label: Label
var scroll: ScrollContainer
var close_btn: Button = null
var buy_btn: Button = null
var sell_btn: Button = null
var feedback_label: Label = null
var equipped_label: Label = null
var is_open: bool = false
var mode: String = "buy"
var displayed_items: Array = []
var feedback_timer: float = 0.0

func _ready():
	# 全屏锚定以便面板居中；根节点不拦截鼠标
	# 注意：必须用 set_anchors_and_offsets_preset，否则0尺寸节点会永远保持0尺寸
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_ui()
	visible = false

func _create_ui():
	shop_panel = Panel.new()
	UITheme.center_panel(shop_panel, PANEL_W, PANEL_H)
	shop_panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	add_child(shop_panel)

	# 标题
	title_label = Label.new()
	title_label.position = Vector2(20, 10)
	title_label.size = Vector2(280, 24)
	UITheme.style_title(title_label, 17)
	shop_panel.add_child(title_label)

	# 金钱
	gold_label = Label.new()
	gold_label.position = Vector2(PANEL_W - 210, 12)
	gold_label.size = Vector2(150, 22)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.style_label(gold_label, 14, UITheme.GOLD)
	shop_panel.add_child(gold_label)

	# 关闭按钮
	close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.size = Vector2(30, 26)
	close_btn.position = Vector2(PANEL_W - 40, 8)
	UITheme.style_button(close_btn, 12)
	close_btn.pressed.connect(close_shop)
	shop_panel.add_child(close_btn)

	# 买入/卖出切换
	buy_btn = Button.new()
	buy_btn.text = " 买入 "
	buy_btn.size = Vector2(76, 28)
	buy_btn.position = Vector2(20, 42)
	UITheme.style_button(buy_btn, 13)
	buy_btn.pressed.connect(func(): mode = "buy"; _refresh_display())
	shop_panel.add_child(buy_btn)

	sell_btn = Button.new()
	sell_btn.text = " 卖出 "
	sell_btn.size = Vector2(76, 28)
	sell_btn.position = Vector2(104, 42)
	UITheme.style_button(sell_btn, 13)
	sell_btn.pressed.connect(func(): mode = "sell"; _refresh_display())
	shop_panel.add_child(sell_btn)

	# 物品列表
	scroll = ScrollContainer.new()
	scroll.position = Vector2(16, 78)
	scroll.size = Vector2(PANEL_W - 32, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_panel.add_child(scroll)

	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 4)
	scroll.add_child(item_list)

	# 物品详情
	var detail_bg = Panel.new()
	detail_bg.position = Vector2(16, 346)
	detail_bg.size = Vector2(PANEL_W - 32, 78)
	detail_bg.add_theme_stylebox_override("panel", UITheme.inset_style())
	shop_panel.add_child(detail_bg)

	detail_label = Label.new()
	detail_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_label.offset_left = 8
	detail_label.offset_top = 6
	detail_label.offset_right = -8
	detail_label.offset_bottom = -6
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UITheme.style_label(detail_label, 11, Color(0.85, 0.84, 0.88))
	detail_label.text = "选择物品查看详情"
	detail_bg.add_child(detail_label)

	# 装备信息（卖出模式显示）
	equipped_label = Label.new()
	equipped_label.position = Vector2(16, 430)
	equipped_label.size = Vector2(PANEL_W - 32, 36)
	equipped_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UITheme.style_label(equipped_label, 11, Color(0.6, 0.8, 1))
	equipped_label.visible = false
	shop_panel.add_child(equipped_label)

	# 交易反馈
	feedback_label = Label.new()
	feedback_label.position = Vector2(16, 468)
	feedback_label.size = Vector2(PANEL_W - 32, 20)
	UITheme.style_label(feedback_label, 12, Color(0.3, 1, 0.3))
	shop_panel.add_child(feedback_label)

	# 操作提示
	hint_label = Label.new()
	hint_label.position = Vector2(16, 492)
	UITheme.style_label(hint_label, 10, UITheme.TEXT_DIM)
	hint_label.text = "K=开关商店 | 点击物品=交易 | Tab=切换买/卖 | R=使用/装备"
	shop_panel.add_child(hint_label)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.is_action_pressed("toggle_shop"):
			toggle_shop()
		elif is_open:
			if event.keycode == KEY_ESCAPE:
				close_shop()
			elif event.keycode == KEY_TAB:
				mode = "sell" if mode == "buy" else "buy"
				_refresh_display()
			elif event.is_action_pressed("shop_use_equip"):
				_handle_use_equipped()

func _process(delta):
	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_label.text = ""

func toggle_shop():
	if is_open:
		close_shop()
	else:
		open_shop()

func open_shop():
	is_open = true
	visible = true
	shop_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(shop_panel, "modulate:a", 1.0, 0.15)
	var shop = _get_shop()
	if shop:
		shop.open_shop()
	_refresh_display()

func close_shop():
	is_open = false
	visible = false
	var shop = _get_shop()
	if shop:
		shop.close_shop()

func _refresh_display():
	var shop = _get_shop()
	if shop == null:
		return

	title_label.text = "🏪 " + shop.shop_name
	gold_label.text = "铜钱: " + str(GameManager.gold)

	# 买入/卖出按钮高亮当前模式
	if mode == "buy":
		buy_btn.add_theme_color_override("font_color", UITheme.GOLD)
		sell_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		sell_btn.add_theme_color_override("font_color", UITheme.GOLD)
		buy_btn.add_theme_color_override("font_color", UITheme.TEXT_DIM)

	for child in item_list.get_children():
		child.queue_free()

	displayed_items.clear()
	detail_label.text = "选择物品查看详情"

	if mode == "buy":
		_show_buy_list(shop)
		equipped_label.visible = false
	else:
		_show_sell_list()
		_show_equipped_info()
		equipped_label.visible = true

func _make_item_row(text_str: String, color: Color, idx: int) -> Button:
	var btn = Button.new()
	btn.text = text_str
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(btn, 12)
	btn.add_theme_color_override("font_color", color)
	btn.pressed.connect(_on_item_row_pressed.bind(idx))
	btn.mouse_entered.connect(func(): if idx < displayed_items.size(): _show_item_detail(displayed_items[idx]["item"]))
	item_list.add_child(btn)
	return btn

func _show_buy_list(shop):
	displayed_items.clear()
	for i in range(shop.shop_items.size()):
		var slot = shop.shop_items[i]
		var item = slot["item"]
		if slot["stock"] <= 0:
			continue
		var price = shop.get_buy_price(item)
		var rarity_badge = _get_rarity_badge(item.rarity)
		var supply_indicator = _get_supply_indicator(item.supply_level)
		var color = _get_rarity_color(item.rarity)
		var idx = displayed_items.size()
		var text_str = "%s %s %s | %d铜 %s | 库存:%d" % [rarity_badge, item.item_name, item.get_type_name(), price, supply_indicator, slot["stock"]]
		_make_item_row(text_str, color, idx)
		displayed_items.append({"item": item, "shop_index": i, "price": price, "stock": slot["stock"]})
	if displayed_items.is_empty():
		var empty = Label.new()
		empty.text = "（货架空空如也）"
		UITheme.style_label(empty, 12, UITheme.TEXT_DIM)
		item_list.add_child(empty)

func _show_sell_list():
	var inv = _get_inventory()
	if inv == null:
		return
	displayed_items.clear()
	var shop = _get_shop()
	for i in range(inv.inventory.size()):
		var slot = inv.inventory[i]
		var item = slot["item"]
		var price = shop.get_sell_price(item) if shop else int(item.base_price * 0.5)
		var rarity_badge = _get_rarity_badge(item.rarity)
		var color = _get_rarity_color(item.rarity)
		var idx = displayed_items.size()
		var text_str = "%s %s x%d | 卖%d铜 | %s" % [rarity_badge, item.item_name, slot["count"], price, item.get_effect_description().left(16)]
		_make_item_row(text_str, color, idx)
		displayed_items.append({"item": item, "inv_index": i, "price": price, "count": slot["count"]})
	if displayed_items.is_empty():
		var empty = Label.new()
		empty.text = "（背包空空如也，去商店买入或完成任务获取物品吧）"
		UITheme.style_label(empty, 12, UITheme.TEXT_DIM)
		item_list.add_child(empty)

func _show_equipped_info():
	var inv = _get_inventory()
	if inv == null:
		return
	var info = "当前装备: "
	if inv.equipped_weapon:
		info += "武器[%s 攻+%d] " % [inv.equipped_weapon.item_name, int(inv.equipped_weapon.attack_bonus)]
	else:
		info += "武器[无] "
	if inv.equipped_armor:
		info += "防具[%s 防+%d] " % [inv.equipped_armor.item_name, int(inv.equipped_armor.defense_bonus)]
	else:
		info += "防具[无] "
	if inv.equipped_accessory:
		info += "饰品[%s]" % inv.equipped_accessory.item_name
	else:
		info += "饰品[无]"
	equipped_label.text = info

func _on_item_row_pressed(idx: int):
	if idx < 0 or idx >= displayed_items.size():
		return
	var entry = displayed_items[idx]
	var item = entry["item"]
	_show_item_detail(item)
	var shop = _get_shop()
	if shop == null:
		return
	if mode == "buy":
		if shop.buy_item(entry["shop_index"]):
			_show_feedback("已购买 %s -%d铜" % [item.item_name, entry["price"]])
		else:
			_show_feedback("购买失败! 铜钱不足或库存不足")
	else:
		if shop.sell_item(item.item_id):
			_show_feedback("已卖出 %s +%d铜" % [item.item_name, entry["price"]])
		else:
			_show_feedback("卖出失败!")
	_refresh_display()

func _handle_use_equipped():
	var inv = _get_inventory()
	if inv == null:
		return
	if mode == "sell":
		for slot in inv.inventory:
			var item = slot["item"]
			if item.item_type == ITEM_CONSUMABLE:
				inv.use_item(item.item_id)
				_show_feedback("使用了 %s" % item.item_name)
				_refresh_display()
				return
			elif item.item_type == ITEM_WEAPON or item.item_type == ITEM_ARMOR or item.item_type == ITEM_ACCESSORY:
				inv.equip_item(item.item_id)
				_show_feedback("装备了 %s" % item.item_name)
				_refresh_display()
				return

func _show_item_detail(item):
	var detail = "[%s] %s - %s\n" % [_get_rarity_badge(item.rarity), item.item_name, item.get_rarity_name()]
	detail += item.description + "\n"
	detail += item.get_effect_description()
	if item.supply_level > 0 or item.demand_level > 0:
		detail += "\n供需: 供应%d/需求%d" % [item.supply_level, item.demand_level]
	detail_label.text = detail

func _show_feedback(msg: String):
	feedback_label.text = msg
	feedback_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3) if "已" in msg else Color(1, 0.4, 0.3))
	feedback_timer = 2.5

func _get_rarity_badge(rarity: int) -> String:
	var badges = ["凡", "良", "稀", "史", "传"]
	if rarity >= 0 and rarity < badges.size():
		return "[" + badges[rarity] + "]"
	return "[凡]"

func _get_rarity_color(rarity: int) -> Color:
	var colors = [Color(0.8, 0.8, 0.8), Color(0.3, 1, 0.3), Color(0.3, 0.6, 1), Color(0.8, 0.3, 1), Color(1, 0.8, 0.2)]
	if rarity >= 0 and rarity < colors.size():
		return colors[rarity]
	return Color.WHITE

func _get_supply_indicator(level: int) -> String:
	if level >= 80:
		return "(供>>求)"
	elif level >= 60:
		return "(供>求)"
	elif level >= 40:
		return "(供=求)"
	elif level >= 20:
		return "(供<求)"
	else:
		return "(供<<求)"

func _get_shop():
	var main = get_node_or_null("/root/Main")
	if main:
		return main.get_node_or_null("ShopSystem")
	return null

func _get_inventory():
	var main = get_node_or_null("/root/Main")
	if main:
		return main.get_node_or_null("InventoryManager")
	return null
