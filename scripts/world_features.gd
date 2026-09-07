extends Object
class_name WorldFeatures

## 江湖志·世界重构特性开关（docs/武侠世界重构规划-2026-08-31.md §1.3）
## W7 终验起：legacy 旧路径已删，世界生成 FLAG（tang_city/sect_territories/town_v2/bridge_prop/
## walkability_policy）转为状态记录（系统为唯一路径，无回滚分支）。
## 仍生效的行为开关：npc_static（驻留制/巡游切换，巡游 legs 代码保留供 W8 复用）、
## quests_disabled（任务冻结，W8 重启时逐项改回 false）。

const FLAG := {
	"tang_city": true,           # W2 唐制城池蓝图 ✅ 2026-09-01 开启（W7 legacy 删）→ 2026-09-07 青石城整体退役（长安城体验模式，生成路径已删）
	"sect_territories": true,    # W3 门派领地 + 主殿 accent ✅ 2026-09-01 开启（W7 legacy 删）
	"town_v2": true,             # W4 村镇模板 v2（一圈一团一水）✅ 2026-09-01 开启（W7 legacy 删）
	"npc_static": true,          # W4 NPC 驻留制（岗job + 驻留，读 door_px 落位）✅ 2026-09-01 开启
	"quests_disabled": true,     # 任务冻结 ✅ 2026-09-07 长安城体验模式：主线不启动+告示板零发布（W8 重启语义暂停，恢复时改回 false 并同步 regress 断言组 quest）
	"mobs_disabled": true,       # 野怪冻结 ✅ 2026-09-07 长安城体验模式：营地不生成、不重生（story_camps 本就随 quests_disabled 拒绝；恢复时改回 false）
	"always_day": true,          # 时辰恒白天 ✅ 2026-09-07 长安城体验模式：WeatherController 钉 world_time=巳时（宵禁永不闭门、夜色不降临；恢复改 false）
	"encounters_disabled": true, # 奇遇随机触发冻结 ✅ 2026-09-07 长安体验模式：随机掷骰停（手动入口不受影响；恢复改 false）
	"bridge_prop": true,         # W5 石拱桥 prop（可通行语义与外观分离）✅ 2026-09-01 开启（W7 legacy 删）
	"walkability_policy": true,  # W6 可行域政策（SETTLEMENT/ROAD 零碰撞物+走廊连通）✅ 2026-09-01 开启（W7 legacy 删）
	"demo_town": false,          # 城镇样板区 2026-09-07 暂关：入口路/选址硬依赖青石城四门官道（_gate_reachable/_lay_gate_road），官道随城退役后失锚——待改锚出生点/长安外郭后重开
}

## 规则版本号：布局/断言规则变更时必须 +1 并登记到重构规划文档（§10.3）
## v2 = W8 任务重启：quest_available_zero → quest_available_positive + 新增 story_started
## v3 = W8 观感修复：desert 直方图排除河畔绿洲带（临水≤12 格合法绿洲，探针 oasis_skipped）+
##   桥水侧不变量（陆上裸 17 降级 path）+ POI 避让镇建成区 + 渡亭选址前置验证（登记见进度日志 §二·J）
## v4 = v4 城镇全量重构 M0（docs/立项-v4城镇全量重构.md §3.5）：is_in_settlement 改净空登记制
##   （镇心欧氏 13/城 cheby half+2/门派 cheby r 硬编码废除，统一读 _town_clear_rects）+
##   回归断言登记制升级（城坐标/采样圆改读登记表）+ 新增 door_on_lane/footprint_no_overlap/
##   prop_node_budget 断言
## v5 = 2026-09-07 长安城体验模式：青石城整体退役（CITY_V2/城生成/四门官道/城内NPC 删除，
##   回归 city 组与官道断言删除、quest 组回冻结语义、mob 组加 camps_zero、npc 预算剔除城15）+
##   时辰恒白天 + 野怪/任务冻结（quests_disabled/mobs_disabled）
const WORLD_RULES_VERSION := 5
