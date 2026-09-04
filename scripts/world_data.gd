extends Object
class_name WorldData

## 江湖志·世界重构常量数据表（docs/武侠世界重构规划-2026-08-31.md §12）
## 原则：数据驱动——生成器只按表施工，不散落魔法数。各表随阶段启用：
##   W2=CITY_V2 / W3=SECT_TERRITORIES / W4=TOWN_TEMPLATES_V2+NPC_JOBS / W6=WALKABILITY

## ============ 唐制城池蓝图（W2，施工修订版） ============
## 市坊分离、棋盘路网、中轴居北、四门官道。rect 为相对城心偏移（格），half=30。
## 施工修订：西市/东市 y 从 24 改 22（原草案 24+8 越过南城墙）；坊门对齐主街/次街。
const CITY_V2 := {
	"half": 30,
	"main_street_w": 4,       # 朱雀大街/东西大街（x,y ∈ [-2,1]，直通四门）
	"wards": {
		"官署坊": Rect2i(-28, -28, 25, 26),   # x -28..-4, y -28..-3（府衙+捕头厅，唐制官署居北）
		"寺观坊": Rect2i(4, -28, 25, 26),     # 古刹分寺（金脊）
		"西坊":   Rect2i(-28, 4, 25, 16),     # 民居 6（防火巷间距≥2）
		"东坊":   Rect2i(17, 4, 12, 16),      # 民居 5
	},
	"markets": {
		"西市": Rect2i(-16, 22, 14, 8),       # 铁匠/药铺/布庄+市摊（贴主街西侧）
		"东市": Rect2i(2, 22, 12, 8),         # 杂货/民居+市摊（贴主街东侧）
	},
	"gates": {"n": "拱辰门", "s": "明德门", "w": "西成门", "e": "东作门"},
}

## 建筑样式系统（W2/W3）：_compose_big_building 只认 STYLE，不再散传参数
const STYLE_CIVILIAN := {
	"roof": Color(0.45, 0.30, 0.22), "wall": Color(0.90, 0.87, 0.80),
	"ridge_gold": false, "banner": Color(0.55, 0.45, 0.35),
}

## ============ 门派领地（W3） ============
## 选址硬规则：对应气候位找 20x20 全可行区块；领地间≥45，距城≥40，距镇≥20。
const SECT_TERRITORIES := {
	"青峰剑宗": {
		"climate": "temperate_mountain", "radius": 28,
		"style": {"roof": Color(0.43, 0.48, 0.55), "wall": Color(0.90, 0.87, 0.80),
			"banner": Color(0.25, 0.42, 0.70), "ridge_gold": false},
	},
	"铁砂帮": {
		"climate": "desert_oasis", "radius": 24,
		"style": {"roof": Color(0.52, 0.40, 0.26), "wall": Color(0.78, 0.64, 0.44),
			"banner": Color(0.70, 0.16, 0.12), "ridge_gold": false},
	},
	"古刹禅宗": {
		"climate": "bamboo_edge", "radius": 26,
		"style": {"roof": Color(0.72, 0.58, 0.20), "wall": Color(0.86, 0.76, 0.52),
			"banner": Color(0.82, 0.66, 0.14), "ridge_gold": true},
	},
	"药王谷": {
		"climate": "lakeside_bamboo", "radius": 24,
		"style": {"roof": Color(0.30, 0.46, 0.34), "wall": Color(0.82, 0.86, 0.72),
			"banner": Color(0.36, 0.62, 0.40), "ridge_gold": false},
	},
	"幽冥教": {
		"climate": "snow_black_rock", "radius": 28,
		"style": {"roof": Color(0.16, 0.15, 0.18), "wall": Color(0.42, 0.30, 0.30),
			"banner": Color(0.10, 0.08, 0.10), "ridge_gold": false},
	},
}

## ============ 门派主殿 kind 映射（W3） ============
const SECT_HALL_KIND := {
	"青峰剑宗": "hall_qf", "铁砂帮": "hall_ts", "古刹禅宗": "hall_gc",
	"药王谷": "hall_yw", "幽冥教": "hall_ym",
}

## ============ 村镇模板 v2（W4） ============
## 一圈一团一水聚落逻辑：农耕村（环状农带靠水）/ 市镇（主街行肆）/ 渡口村（临河渡亭）。
const TOWN_TEMPLATES_V2 := {
	"farm":  {"houses": [4, 6], "main_street": false, "farm_belt": true,  "ferry": false},
	"market": {"houses": [5, 7], "main_street": true,  "farm_belt": false, "ferry": false},
	"ferry": {"houses": [4, 5], "main_street": false, "farm_belt": false, "ferry": true},
}

## ============ NPC 岗位表（W4） ============
## NPC 落位唯一来源=建筑 door_px + offset；禁止 NPC 生成器自算坐标。
const NPC_JOBS := {
	"铁匠":   {"building": "smithy",     "look": "merchant",     "offset": Vector2i(2, 1)},
	"药师":   {"building": "apothecary", "look": "herbalist_f",  "offset": Vector2i(2, 1)},
	"布庄":   {"building": "cloth",      "look": "seamstress_f", "offset": Vector2i(2, 1)},
	"杂货":   {"building": "grocery",    "look": "merchant",     "offset": Vector2i(2, 1)},
	"货郎":   {"building": "grocer",     "look": "merchant",     "offset": Vector2i(2, 1)},
	"酒楼":   {"building": "tavern",     "look": "tavern_f",     "offset": Vector2i(2, 1)},
	"捕头":   {"building": "yamen",      "look": "guard",        "offset": Vector2i(2, 1)},
	"村正":   {"building": "shrine",     "look": "elder",        "offset": Vector2i(1, 1)},
	"农人":   {"building": "farmhouse",  "look": "peasant_f",    "offset": Vector2i(1, 1)},
	"渡夫":   {"building": "ferry",      "look": "matron_f",     "offset": Vector2i(1, 1)},
	"弟子":   {"building": "hall",       "look": "warrior",      "offset": Vector2i(2, 1)},
	"长老":   {"building": "hall",       "look": "elder",        "offset": Vector2i(1, 1)},
}

## ============ 可行域政策（W6） ============
## 分区：SETTLEMENT/ROAD/FARM 禁碰撞装饰；WILD 岩石聚簇；HOLY_GROUND 故意不可行。
const WALKABILITY := {
	"no_collide_zones": ["SETTLEMENT", "ROAD", "FARM"],
	"wild_rock_cluster": {"min": 2, "max": 5, "near_mountain": 3},
	"corridor_width": 2,   # 野外通行走廊 ≥2 格（2x2 BFS 连通）
}
