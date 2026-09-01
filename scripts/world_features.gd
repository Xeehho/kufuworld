extends Object
class_name WorldFeatures

## 江湖志·世界重构特性开关（docs/武侠世界重构规划-2026-08-31.md §1.3）
## 铁律：一个阶段只开一个 FLAG；每阶段结束跑 tools/regress_world.py 全量回归，红灯不过夜。
## 旧路径在开关后保留至 W7 终验，任何阶段可独立回滚（FLAG 关闭即回旧路径）。

const FLAG := {
	"tang_city": true,           # W2 唐制城池蓝图（坊/市/四门/官署/寺观）✅ 2026-09-01 开启
	"sect_territories": true,    # W3 门派领地 + 主殿 accent ✅ 2026-09-01 开启
	"town_v2": true,             # W4 村镇模板 v2（一圈一团一水）✅ 2026-09-01 开启
	"npc_static": true,          # W4 NPC 驻留制（岗job + 驻留，读 door_px 落位）✅ 2026-09-01 开启
	"quests_disabled": true,     # W4 起冻结任务系统（W8 重启时逐项改回 false）✅ 2026-09-01 接线
	"bridge_prop": true,         # W5 石拱桥 prop（可通行语义与外观分离）✅ 2026-09-01 开启
	"walkability_policy": false, # W6 可行域政策（SETTLEMENT/ROAD 零碰撞物+走廊连通）
}

## 规则版本号：布局/断言规则变更时必须 +1 并登记到重构规划文档（§10.3）
const WORLD_RULES_VERSION := 1
