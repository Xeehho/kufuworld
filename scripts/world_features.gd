extends Object
class_name WorldFeatures

## 江湖志·世界重构特性开关（docs/武侠世界重构规划-2026-08-31.md §1.3）
## W7 终验起：legacy 旧路径已删，世界生成 FLAG（tang_city/sect_territories/town_v2/bridge_prop/
## walkability_policy）转为状态记录（系统为唯一路径，无回滚分支）。
## 仍生效的行为开关：npc_static（驻留制/巡游切换，巡游 legs 代码保留供 W8 复用）、
## quests_disabled（任务冻结，W8 重启时逐项改回 false）。

const FLAG := {
	"tang_city": true,           # W2 唐制城池蓝图（坊/市/四门/官署/寺观）✅ 2026-09-01 开启（W7 legacy 删）
	"sect_territories": true,    # W3 门派领地 + 主殿 accent ✅ 2026-09-01 开启（W7 legacy 删）
	"town_v2": true,             # W4 村镇模板 v2（一圈一团一水）✅ 2026-09-01 开启（W7 legacy 删）
	"npc_static": true,          # W4 NPC 驻留制（岗job + 驻留，读 door_px 落位）✅ 2026-09-01 开启
	"quests_disabled": false,    # W8 任务重启 ✅ 2026-09-01：告示板恢复发布+主线自动启动（冻结期断言已按规则v2升级）
	"bridge_prop": true,         # W5 石拱桥 prop（可通行语义与外观分离）✅ 2026-09-01 开启（W7 legacy 删）
	"walkability_policy": true,  # W6 可行域政策（SETTLEMENT/ROAD 零碰撞物+走廊连通）✅ 2026-09-01 开启（W7 legacy 删）
}

## 规则版本号：布局/断言规则变更时必须 +1 并登记到重构规划文档（§10.3）
## v2 = W8 任务重启：quest_available_zero → quest_available_positive + 新增 story_started
## （冻结期"零发布"语义随 quests_disabled=false 终止，登记见进度日志 §二·I）
const WORLD_RULES_VERSION := 2
