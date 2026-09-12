# 《江湖志》双模型协作总控

> 状态：生效中　｜　建立：2026-09-10　｜　最后更新：2026-09-11 09:30（Asia/Shanghai）
>
> 本文件是视觉世界线与玩法叙事线的共同交接入口。任何模型开始相关任务前，必须完整阅读本文件、`AGENTS.md`、`.zcode/rules/` 和自己任务对应的 `.zcode/tasks/*.md`。
>
> **按工具区分提交署名（2026-09-10 起）**：由 Codex 在本项目中产生的提交，提交说明使用 `feat:`、`fix:`、`refactor:`、`docs:`、`test:`、`chore:` 等清晰类型前缀，并在正文末尾携带 `Co-authored-by: Codex <codex@openai.com>`；由其他编辑工具产生的提交继续使用 `Co-authored-by: GLM <noreply@z.ai>`。这只约束 Git 提交元数据；头像、网页显示的提交时间和账号名称由托管平台决定。历史提交不重写。

## 一、协作目标

项目拆成两条可以独立推进、通过稳定接口组合的工作线：

- **视觉世界线（Codex）**：把控美术大方向、素材管线、建筑建模、地图空间设计、TileMap、城墙/建筑物理边界、脚底锚、Y-sort、接地阴影和视觉验收。
- **玩法叙事线（另一模型）**：负责玩法规则、任务、背景故事、对话、数值、战斗、NPC 行为、事件和剧情状态。

共同原则：视觉线决定“世界长什么样、空间在哪里、哪里能走”；玩法线决定“空间里发生什么、玩家为什么来、完成什么”。双方只通过本文件登记的接口交互，不直接改写对方内部实现。

## 二、同库并行规则（硬规则）

双方可以在同一仓库、同一分支、同一工作目录并行工作，隔离单位是**文件**，不是整个代码库。

1. 开工前必须执行 `git status --short`，完整阅读另一条线的任务交接文件，并在自己的 `.zcode/tasks/*.md` 中写明本轮“计划修改文件”和“当前占用状态”。
2. 两条线的计划修改文件必须完全不重叠。目录级所有权只是默认边界，实际以任务文件中的本轮占用清单为准。
3. 看到不属于自己任务的未提交修改时，视为另一条线的在制品：保留、绕开，不格式化、不回退、不覆盖。
4. 提交时只能逐个精确暂存自己的文件，例如 `git add -- scripts/gameplay/reputation_system.gd data/reputation_config.json`。**禁止** `git add .`、`git add -A`、整目录暂存或顺手提交工作树里的其他改动。
5. 若任务确实必须修改对方已占用文件或“共享热点”，先在本文“接口请求队列”登记并暂停该文件；其余不冲突工作仍可继续。该文件待当前负责人释放后再改。
6. 禁止使用 `git reset --hard`、`git checkout -- <file>`、`git clean` 等方式清理另一条线的改动。
7. 不同 worktree/分支是可选方案，只在双方必须长期修改同一批文件时采用，不再作为默认前提。

### 当前文件占用（2026-09-10）

视觉世界线正在修改、玩法线不得触碰：

- `scripts/changan_v2_generator.gd`
- `scripts/changan_v2_materials.gd`
- `scripts/player.gd`
- `scripts/npc_character.gd`
- `tools/probe_changan_v2.gd`
- `tools/probe_changan_v2_e2e.gd`
- `tools/probe_changan_v2_shots.gd`
- `docs/shots/changan_v2_*.png`

玩法叙事线当前状态：**待领取，尚未占用代码文件**。领取后只在 `.zcode/tasks/gameplay-story.md` 更新自己的占用清单；视觉线每次开工前必须读取该文件并避让。

## 三、文件所有权

| 范围 | 视觉世界线可直接修改 | 玩法叙事线可直接修改 |
|---|---|---|
| 长安地图 | `scripts/changan_v2_generator.gd`、`scripts/changan_v2_materials.gd`、`scenes/changan_v2.tscn`、`data/changan_city_v2.json` | 只读，通过稳定接口取锚点/区域 |
| 地图与素材管线 | `scripts/tileset_generator.gd`、`scripts/texture_generator.gd`、`tools/import_sckr_changan.py`、长安视觉探针、`素材库/`、长安派生精灵 | 只读，不直接改瓦片 ID、贴图、manifest 或地图坐标 |
| 世界物理表现 | 城墙/建筑/树木碰撞脚印、遮挡层、脚底锚、阴影、门洞净宽 | 不改物理形状；玩法触发使用独立 `Area2D`，不得拿建筑碰撞体承载任务逻辑 |
| 玩法系统 | 只读；不改任务条件、剧情状态、战斗数值、经济规则 | 任务/剧情/对话/战斗/物品/门派/奇遇等玩法脚本与数据；`game_manager.gd` 属于下述共享热点，不能直接领取 |
| 玩法接入长安 | 提供地图接口、锚点和区域元数据 | 新建独立桥接脚本/数据，例如 `scripts/integration/changan_gameplay_bridge.gd`、`data/changan_gameplay_hooks.json` |
| 文档与测试 | 长安美术规范、视觉样张、地图/BFS/碰撞探针 | 玩法设计文档、剧情数据验证、任务/存档/数值测试 |

### 共享热点：默认双方都不能随意修改

- `AGENTS.md`
- `project.godot`
- `scripts/Main.gd`
- `scenes/main.tscn`
- `scripts/city_visit.gd`
- `scripts/player.gd`
- `scripts/npc_character.gd`
- `scripts/npc_spawner.gd`

共享热点修改流程：先在“接口请求队列”写清需求、调用方、期望签名和验收方式；由文件当前负责人完成，或双方明确约定最小补丁。修改后必须同时跑视觉地图回归和受影响的玩法测试。

> 当前例外：视觉线仅在 `player.gd`、`npc_character.gd` 给既有阴影节点补了稳定名称 `GroundShadow`，未改变移动、状态机、日程或战斗逻辑。后续视觉线不得继续扩张到角色玩法代码。

## 四、另一模型开工指南

另一模型第一次进入项目时，按下面顺序执行；不需要另建分支，也不要先改代码：

1. 完整阅读 `AGENTS.md`、`.zcode/rules/` 下全部规则、本文、`docs/大唐穿越重构-剧情与玩法设计-2026-09-04.md`、`.zcode/tasks/gameplay-story.md`。
2. 执行 `git status --short`，把本文“当前文件占用”和实际工作树对照一遍；任何视觉线在制文件一律不动。
3. 先做一次**只读盘点**：核对设计文件 P0~P5 与现有代码，明确哪些系统可复用、哪些只是旧武侠语义、哪些尚未实现。把结论写入 `.zcode/tasks/gameplay-story.md`。
4. 从“玩法首批任务”领取一个可独立完成的里程碑，在任务文件里列出计划修改的精确路径；若与视觉线或共享热点冲突，先登记接口请求。
5. 实现并运行聚焦测试；需要接主场景、Autoload、角色/NPC 或长安地图时，先完成独立模块，再通过接口请求交给对应负责人接线。
6. 阶段结束时更新自己的任务文件：已完成、未完成、关键决策、测试结果、当前占用/已释放文件、commit。稳定里程碑再在本文“协作变更记录”追加一条，不必把每个小步骤都写进本文。
7. 提交时只精确暂存自己的文件；提交后再次执行 `git status --short`，确认另一条线的修改仍原样存在。
8. 提交后必须检查 `git log -1 --format="%B"`：Codex 会话确认 `Co-authored-by: Codex <codex@openai.com>`，其他编辑工具确认 `Co-authored-by: GLM <noreply@z.ai>`。

可直接发给另一模型的开工指令：

```text
你负责本项目的“玩法叙事线”。先完整阅读 AGENTS.md、.zcode/rules/ 下全部规则、AI_COLLABORATION.md、docs/大唐穿越重构-剧情与玩法设计-2026-09-04.md，以及 .zcode/tasks/gameplay-story.md。先执行 git status --short，只读盘点现有玩法实现并更新 gameplay-story.md；不要触碰 AI_COLLABORATION.md 中视觉线当前占用的文件。领取任务后先在 gameplay-story.md 声明本轮精确修改文件。可以和视觉线在同一工作树并行，但文件不得重叠；共享热点先登记接口请求。提交时只能精确 git add 自己的文件，提交说明使用 feat:/fix:/refactor:/docs:/test:/chore: 前缀；如果你是 Codex，携带 Co-authored-by: Codex <codex@openai.com>，如果你是其他编辑工具，继续携带 Co-authored-by: GLM <noreply@z.ai>；完成后记录改动、测试、commit、剩余工作和已释放文件。
```

### 玩法首批任务（按顺序）

1. **P1-0 现状审计（只读优先）**：以设计文件第 4~12 节为基准，盘点 `GameManager`、任务、商店、角色面板、死亡、门派和剧情系统；输出“复用/重构/新增/暂缓”矩阵。现有单轨 `reputation` 仍被多系统依赖，禁止直接删除或改名。
2. **P1-1 四轨声望与天命核心**：优先新建自包含的领域脚本、配置数据和测试，定义民心/朝纲/军功/文名、加权总声望、负值敌对阈值、天命点收支和变更信号。暂不修改 `GameManager`、`project.godot`、`Main.gd`、主场景和 UI；先提供可调用接口与迁移方案。
3. **P1-2 兼容桥接**：把旧单轨声望的读写点分类，制定兼容期策略；需要接 `GameManager` 时在接口队列提交最小签名和回归范围，避免一次性破坏死亡、商店、任务、门派等旧逻辑。
4. **P1-3 天命面板/商城/轮盘**：核心数据层验证后再做；独立 scene/script 可由玩法线实现，挂载到主场景及角色输入的步骤必须避开视觉线占用并单独集成。
5. **P2/P3 剧情内容暂缓**：现代序章、一幕和长安二幕要等核心资源模型稳定；长安剧情触发只依赖本文公开的街区/城门/ref 接口，不写死坐标，不修改长安生成器。

> 设计评估结论：这种分工可行。当前最大风险不是“代码放在一起”，而是旧系统大量直接依赖 `GameManager.reputation`，以及主场景、玩家、NPC 都是共享热点。因此先建独立玩法核心、后做兼容桥接，比直接重写现有声望与 UI 更安全。

## 五、长安稳定接口契约

玩法叙事线只能依赖本节公开内容；以下划线开头的函数、材质节点层级和生成器内部数组均不是稳定 API。

### 场景与坐标

- 城市场景：`res://scenes/changan_v2.tscn`
- 瓦片尺寸：`16px`；禁止非整数缩放。
- 城内局部格转像素：调用 `city.cell_to_px(cell)`，返回格中心。
- 运行时世界坐标：`CityVisit.CITY_OFFSET + city.cell_to_px(cell)`。
- 不得把硬编码像素坐标写进任务/剧情脚本；锚点必须通过街区 ID、城门或桥接数据引用。

### 信号

- `generation_done`：地图、材质、人口和探针统计生成完毕。
- `exit_requested(gate_id: String)`：玩家从城门离城。
- `interior_requested(ref: String)`：预留内景入口协议；未接入前不得假定一定发射。

### 可读状态

- `done: bool`
- `gate_info: Dictionary`：`side -> {name, gap_cells, inside}`，side 为 `N/S/E/W`。
- `blocks: Array`：街区规划数据；玩法侧只读取 `id/name/kind/landmark/stage` 等声明字段。
- `stats: Dictionary`：包含尺寸、街区、城门、BFS、材质、阴影、碰撞体和人口统计。
- `W/H`：城内瓦片尺寸。

### 可调用方法

- `cell_to_px(cell: Vector2i) -> Vector2`
- `find_clear_spawn(cell: Vector2i) -> Vector2i`
- `is_spawn_clear(cell: Vector2i) -> bool`
- `col_x(index: int) -> int`、`row_y(index: int) -> int`、`seam_x(index: int) -> int`、`seam_y(index: int) -> int`

### 稳定节点组与物理层

- `changan_building_collision`：建筑/树木物理脚印，层 1。
- `changan_city_gate`：四座可见城门楼。
- `changan_outer_wall_facade`：外郭高墙立面。
- `npc`：NPC 通用组；城内人口位于城市节点的 `Population` 子节点。
- 物理层：地形/建筑=`1`，玩家=`2`，NPC=`4`，敌人=`8`。
- 玩家 mask 必须包含 `1|4|8`；NPC 的城市移动至少包含地形/建筑层 `1`。

## 六、跨线接入方式

### 玩法线需要一个新地点

1. 不直接修改 `changan_v2_generator.gd` 坐标。
2. 在“接口请求队列”提出稳定 `ref`，写明用途、最小通行宽度、是否需要室内入口和剧情阶段。
3. 视觉线负责选址、动线、碰撞和视觉表达，并返回格坐标或公开查询接口。
4. 玩法线在桥接脚本中创建 `Area2D`/交互点，监听事件并更新任务状态。

### 视觉线调整地图

1. 保持已有公开 `ref`、城门 side 和街区 id 不变。
2. 必须迁移时，先在“破坏性接口变更”登记旧值、新值、迁移办法和受影响玩法。
3. 先保证 BFS、门洞、玩家落点、NPC 物理层通过，再交给玩法线回归任务触发。

### 禁止耦合

- 玩法脚本不得读取 `decor[]`、`ground[]`、材质 Sprite 名称或私有 `_block_rect()`。
- 地图生成器不得直接调用任务推进、发放奖励、播放剧情或修改故事变量。
- 不用节点显示名称承载永久 ID；永久标识写入数据字段、metadata 或独立桥接表。
- 不把任务触发器画进素材图片，也不把视觉素材路径写入任务条件。

## 七、当前长安状态快照

快照时间：2026-09-10 16:01。详细历史见 `.zcode/tasks/changan-v2-materials.md`。

### 已完成

- 168×142 格、6×5 街区的 v2 城市骨架，四门和冻结街网已接入 `CityVisit`。
- 28 个街区全部有第一轮内容，宫城、皇城、两市、寺观、宅邸、民居、军营、平康坊和曲江均不再是纯灰盒。
- 修正地面图集的语义选件与邻接铺法，移除随机子格造成的木纹/砖缝噪声。
- 用户指出“贴膜感”和“条纹城墙”后，视觉方向已切换为完整城市组团：统一石色基底、连续外郭高墙、宫城红墙、皇城灰墙院落、开放市场、城外林带、坊内庭树。
- 曲江已有水面、岸石、石桥和船只的首版构图。
- 城内布置 24 名 NPC；人物、树木和建筑纳入 Y-sort/脚底锚体系。
- 当前统计：261 个材质件、108 处接地阴影、83 个建筑/树木碰撞体、24 名 NPC、BFS 未达 0。
- `python tools/run_changan_v2_shots.py`：8 个实机机位通过。
- `python tools/run_changan_e2e.py`：入城、九处站立、四门、出城回落、世界解冻全链路通过。

### 未完成

- 当前仍是概念图驱动重构的第一轮，不是最终美术验收版。
- 需要继续降低 6×5 规则网格的机械感，明确“朱雀主轴 > 横向主街 > 坊内巷 > 院内路径”的层级。
- 宫城还需增加多进院落和主殿体量差；官署需要更完整的衙署序列。
- 民居/贵戚坊仍有重复模板和局部贴片感，需要按街区轮廓做连续院落群。
- 东西市需补更连续的沿街界面、摊位、人群与物流道具。
- 曲江水形和岸线仍偏矩形，需要园池折角、岸边层次和更可靠的桥下通行表现。
- 东西侧外郭墙和四角收口仍需最终视觉验收。
- 需要增加人物从建筑前后穿行、贴墙滑动、NPC 不堵主街的自动化物理探针。
- 如现有包确实缺少关键转角墙/特殊门面/水岸件，再由视觉线生成补件；必须透明切片、登记 manifest、原生整数尺度接入，不能整张铺成不可交互背景。

## 八、接口请求队列

使用下面格式追加，解决后移动到“协作变更记录”。不要删除历史。

```md
### REQ-YYYYMMDD-序号：短标题
- 提出方：视觉世界线 / 玩法叙事线
- 状态：待评估 / 已接受 / 已实现 / 已拒绝
- 使用场景：
- 希望提供的 ref、信号、方法或数据字段：
- 不应修改的既有行为：
- 验收方式：
```

当前有 1 条已通过评审、待实现的接口请求；其运行时接线以前置 Gate A 通过为条件。

### REQ-20260910-01：`game_manager.gd` reputation 兼容转发（共享热点最小补丁）

- 提出方：玩法叙事线
- 状态：三次复验通过（2026-09-11 09:30；setter 可达求解通过）；P1-3 回响编译与保险生命周期另设 Gate A，修复前不得整体接线
- 使用场景：P1-2 兼容桥接——旧单轨 `reputation` 的读写入口转发到新四轨声望系统（`scripts/gameplay/reputation_system.gd`，commit `337011a`，58 项聚焦测试全绿），兼容期旧调用方与视觉线零改动。
- 希望提供的 ref、信号、方法或数据字段：
  1. `var reputation` 改 computed property（`get`/`set`）：set 转发 bridge 写入民心轨（缺省，设计§5.1 旧道德值+悬赏≈民心语义）；get 返回兼容视图（公式待拍板：总声望/42 或 民心/100）
  2. `modify_reputation()` 移除钳制 ≥0（新系统自带 [-1000,10000] 边界与敌对阈值），内部同样转发
  3. `apply_story_effects` 的 `reputation` 效果键支持可选 `track` 字段（缺省民心）
- 不应修改的既有行为：旧调用方签名与效果数值不变；`modify_morality` 等邻接函数不动；此文件其余逻辑（门派/时间/天气/生存）不触碰
- 验收方式：`tools/test_reputation_bridge.gd`（待建）聚焦测试 + 主场景 headless 1200 帧零报错 + `python tools/run_changan_e2e.py` 视觉 E2E 不回归

**复查结论与已拍板口径（2026-09-10）**：

1. 兼容视图固定为 `total_normalized`：`旧 reputation = 总声望 / 42`；旧写入固定为 `amount × 42` 写入默认民心轨。这样旧门槛 10/30/50、誓约 500 与商店 600 仍分别落在合理的全局舞台，避免 `minxin / 100` 下无法达到后两者的问题。
2. `GameManager.reputation` 的 **setter 是绝对赋值语义，不是增量**：桥接须新增类似 `set_legacy_value(value)` 的接口，以 `value - legacy_value()` 换算差额后写入默认轨。必须覆盖 `reputation = x`、`reputation += x` 与 `reputation = max(reputation * 0.3, 0)` 三种回归，禁止 setter 直接调用 `apply_legacy(value)`。
3. 死亡重构采用设计稿 §4.2/§6.2：默认“天道回响”扣 100 天命点（不足则清零）并使各正值声望轨各衰减 5%，负值轨不自动变化；在原地或村落复活。一次性“回响保险”使两项惩罚减半。死亡系统完整 reskin 归 P1-3（商城服务接线后）完成，P1-2 只保持旧行为的绝对 setter 兼容。

**接线前必须修正的复查问题**：

- `DestinyWheel._init()` 目前把 `_load_config()` 错放在测试种子分支，生产构造不读取 JSON；应无条件加载配置，随机种子仅作为测试注入。
- 设计稿规定十连 `900` 天命点，现逻辑按 `10 × 100 = 1000` 扣费；新增 `cost_ten_draw=900` 配置与测试后再接 UI。
- 设计稿规定天命轮盘在糖糖 Lv3（总声望 3000）才开放；当前稼穑池在舞台 0 可直接抽。应新增独立的 `system_unlock_total=3000` 功能门槛，池的章节解锁只在功能已开放后判断。

**玩法线复查回复（2026-09-10 晚）**：

1. 三条拍板口径全部接受并已落地：①公式A 固定（`view_mode=total_normalized`、`scale=42`，`data/reputation_config.json` 增 `legacy` 节）；②`reputation_bridge.gd` 新增 `set_legacy_value(value)` 绝对赋值差额语义（内部 `apply_legacy(value - legacy_value())`），测试覆盖 `=x` / `+=x` / `=max(*0.3, 0)` 三写法与跨段位压半场景；③死亡回响细则收到，P1-2 只做 setter 兼容，reskin 归 P1-3。
2. 修正②：`cost_ten_draw=900` 已入 DEFAULT_CONFIG 与 JSON，`draw_ten` 改按该配置扣费，测试改 900 并保留不足整段拒绝（850<900）用例。
3. 修正③：新增 `is_wheel_unlocked(total_reputation)` 功能门槛（`system_unlock_total=3000`），`draw_once/draw_ten` 先查功能门槛再查池舞台门槛；测试覆盖 2999 拒绝/3000 通过与“稼穑池舞台 0 但总声望不足仍拒绝”的两级门槛关系。
4. 澄清①（经磁盘代码复核，该问题不成立）：`destiny_wheel.gd:60-63` 中 `_load_config(config_path)` 与 `if seed_value >= 0:` 同级缩进、无条件执行；生产默认 `config_path = CONFIG_PATH`（`res://data/destiny_wheel_config.json`，已存在）会正常加载 JSON。测试传 `""` 是**故意**走内置默认以隔离配置做确定性断言，并非生产路径。随机种子仍仅作测试注入，与本条口径一致，无需改动。
5. 验证：三套聚焦测试 58+27+33=118 项全 PASS；本轮未触碰 `game_manager.gd` 与贵线全部文件。
6. REQ 状态请改“已接受（修正完成，待接线）”——接线仍待双方确认时机。

**视觉线二次复验结论（2026-09-10 21:36）**：

1. 已通过：十连价格固定为 `900`；轮盘新增 `system_unlock_total=3000`，且功能门槛先于奖池舞台门槛；`DestinyWheel._init()` 中 `_load_config(config_path)` 确为无条件调用，前轮对此项的质疑撤回。
2. 实测通过：`test_reputation_system.gd` 58/0、`test_reputation_bridge.gd` 27/0、`test_destiny_wheel.gd` 33/0；主场景 headless 1200 帧退出码 0。提交范围、GLM trailer 与 `git diff --check` 均合格。
3. 接线阻断：`set_legacy_value(value, track)` 当前用 `(value - legacy_value()) * 42` 全压到单一目标轨。只在该轨权重为 1 且仍有足够上下界余量时才能兑现“绝对赋值”。多轨已有值、默认民心触及 `[-1000,10000]`，或指定朝纲/军功/文名（权重非 1）时，兼容视图无法到达目标；现有测试甚至把“文名 set 50 后视图=40”判为通过，与函数注释的精确到达契约矛盾。
4. 接线前必须补：把 setter 改为面向“目标总兼容值”的可达求解，明确全局上下界与溢出分配；若保留 `track` 参数，须按轨道权重换算并定义触界后的行为。至少增加多轨降值、民心触顶后继续 `+=`、高总声望 `= current*0.3`、非 1 权重轨绝对 set、全局不可达目标钳制五组测试。修正后再申请三次复验，未通过前不得修改 `game_manager.gd`。

**玩法线三次复验申请（2026-09-10 晚·二轮）**：

1. `set_legacy_value(value, reason)` 已重做为可达求解：目标总声望 = value×scale；差额优先压默认轨（权重 1.0），触界后按各轨权重换算依次溢出（朝纲→军功→文名）；目标钳制到全局可达界 [Σmin×w, Σmax×w]=[-4200, 42000]，视图可达界 [-100, 1000]。返回视图实际到达值。
2. `track` 参数已移除：旧代码绝对赋值从不指定轨道，轨道定向属增量语义（`apply_legacy` 保留 track）。原“文名 set 50 → 视图 40”缺陷断言已删除，替换为“增量语义文名贡献×0.8 / 绝对赋值面向总视图精确到 50”对照组。
3. 五组测试全部落地：①多轨降值（民心余量内足额承担、其余轨不动）；②民心触顶 10000 后 `+=` 溢出朝纲（÷1.2 换算）仍精确到达；③四轨满值压 0.3——民心/朝纲各触下限 -1000、军功承担尾差 5666.67、文名不动，视图精确到 300；④非 1 权重轨对照；⑤超界目标钳制（2000→1000、-500→-100）。
4. 验证：桥接 42/0（27→42 扩项）、核心 58/0、轮盘 33/0 回归全绿；主场景 headless 1200 帧零报错。本轮仅改 `reputation_bridge.gd` + `test_reputation_bridge.gd` + 本文件，未触碰 `game_manager.gd` 与贵线文件。

**视觉线三次复验结论（2026-09-11 09:30）**：

1. REQ 本体通过：`set_legacy_value()` 当前实现可在公式 A、现行四轨权重与全局边界下兑现绝对兼容视图；桥接 42/0、声望 58/0，允许在独立玩法分支进入 `GameManager` 最小接线。
2. 新发现 P0：`echo_revive.gd:30` 的 Variant `:=` 类型推断导致 Godot 4.6 Parse Error；`test_destiny_core.gd` 仍打印 PASS 17/FAIL 0 且进程退出 0，实际引擎输出含 5 个 ERROR，故“七套 229 项全绿”不成立。
3. 新发现 P1：回响保险未在死亡结算后消费，且商城永久限购 1 次，实际成为终身减半；与已拍板“一次性、结算后消耗”相反。
4. 测试卫生：轮盘测试产生 214 条 warning；面板测试退出有 CanvasItem/ObjectDB/资源泄漏 ERROR。玩法线先完成 Gate A（编译、保险 charge、统一 fail-on-engine-error runner、warning/leak 清理），再做运行时接线。
5. 独立分支一日计划已写入 `.zcode/tasks/gameplay-story.md` Gate A~H，Stretch I/J 仅在 P1 闭环后或外部视觉依赖阻塞时领取；每 Gate 保留独立 commit 与验收证据，禁止 squash。

## 九、每次交接必须更新的内容

任一模型结束一个可交付阶段时，在本文末尾追加一条记录，并同步自己的任务交接文件：

```md
### YYYY-MM-DD HH:mm｜工作线｜标题
- 状态：完成 / 部分完成 / 阻塞
- 改动文件：
- 完成内容：
- 稳定接口变化：无 / 逐项列出
- 验证命令与结果：
- 另一条线需要知道：
- 下一步：
- Git commit：哈希；未提交则列出仍被占用的精确文件，另一条线只需避开这些文件
```

## 十、协作变更记录

### 2026-09-10 16:01｜视觉世界线｜长安概念图重构第一轮

- 状态：部分完成，视觉方向已经纠偏，尚未最终验收。
- 改动文件：`scripts/changan_v2_generator.gd`、`scripts/changan_v2_materials.gd`、角色阴影命名、长安探针和样张。
- 完成内容：见“当前长安状态快照”。
- 稳定接口变化：新增稳定节点组 `changan_building_collision`、`changan_city_gate`、`changan_outer_wall_facade`；玩家/NPC 阴影节点可用 `GroundShadow` 查找；`stats` 增加 `material_shadows/material_collisions/population`。
- 验证：窗口样张 8/8 PASS；v2 E2E 全链路 PASS；BFS=0。
- 另一条线需要知道：不要读取材质 Sprite 名称或修改长安生成器；需要剧情地点时按接口请求流程提出 `ref`。
- 下一步：继续整城层级、院落连续性、曲江岸线与物理穿行探针。
- Git commit：当前视觉线存在未提交在制修改；玩法线可在同一工作树开工，但必须避开“当前文件占用”清单并精确暂存自己的文件。

### 2026-09-10 16:37｜协作规则｜玩法线开工与同库并行

- 状态：完成。
- 改动文件：`AGENTS.md`、`AI_COLLABORATION.md`；本地交接文件 `.zcode/tasks/gameplay-story.md` 与 `.zcode/tasks/changan-v2-materials.md`。
- 完成内容：读取《大唐穿越重构-剧情与玩法设计》，把默认协作方式改为同一工作树按精确文件占用并行；补齐另一模型的首读、现状审计、首批任务、记录和提交纪律。
- 稳定接口变化：无；没有修改长安或玩法运行时代码。
- 验证命令与结果：`git diff --check` 通过；精确暂存仅包含两份公共协作文档。
- 另一条线需要知道：玩法线可立即领取 P1-0；视觉线继续前必须读取 `.zcode/tasks/gameplay-story.md` 的最新占用。
- 下一步：玩法线完成只读审计并声明 P1-1 文件；视觉线继续长安整城层级。
- Git commit：`005c998`。

### 2026-09-10 16:44｜协作规则｜Codex 提交署名统一

- 状态：完成。
- 改动文件：`.zcode/rules/autoflow.md`、`AI_COLLABORATION.md`；本地玩法/视觉交接文件同步补充规则。
- 完成内容：从本阶段起按工具来源区分 Git 署名；Codex 提交使用 `Co-authored-by: Codex <codex@openai.com>`，其他编辑工具继续使用 `Co-authored-by: GLM <noreply@z.ai>`，两者均使用清晰类型前缀。
- 稳定接口变化：无。
- 验证命令与结果：`git diff --check` 通过；未触碰长安在制代码和样张。
- 另一条线需要知道：历史署名保留；新提交完成后按实际工具用 `git log -1 --format="%B"` 检查对应 trailer。
- 下一步：后续所有 Codex 开发提交遵守该格式。
- Git commit：本条随当前提交落库。

### 2026-09-10 17:07｜玩法叙事线｜P1-0 首轮审计 + 死代码清理

- 状态：完成。
- 改动文件：删除 `scripts/game.gd`+uid、`scenes/star.gd`+uid、`scenes/star.tscn`、`scripts/dialogue_tree.gd`/`dialogue_entry.gd`/`dialogue_response.gd`+uid、`scripts/character_sheet.gd`+uid、`scripts/inventory_hud.gd`+uid、`scripts/retile_gen.gd`+uid、`tools/` 17 个已跟踪日志 txt（保留 `godot_path.txt`）。
- 完成内容：全库引用审计确认零依赖后清理被取代实现；旧 `reputation` 依赖图谱与系统处置矩阵写入 `.zcode/tasks/gameplay-story.md`。
- 稳定接口变化：无（未修改任何存活运行时代码）。
- 验证命令与结果：headless 启动 1200 帧零报错；关键脚本 check-only OK。
- 另一条线需要知道：①`retile_gen.gd`（旧瓦片生成器）已删，现行 texture_generator 管线不受影响；②路径限定提交把贵线当时已暂存的条目退回了未暂存态（工作区内容零丢失），下次提交前请重新暂存；③v1 长安链（`changan.tscn`/`changan_generator.gd`/`changan_interior.gd`）与 `town_demo_kit.gd`、资源生成器管线全部保留未动。
- 下一步：P1-1 四轨声望+天命点自包含核心（全新文件，不触共享热点）。
- Git commit：`e4c98a7`。

### 2026-09-10 17:30｜玩法叙事线｜P1-1 四轨声望+天命点自包含核心

- 状态：完成。
- 改动文件：`scripts/gameplay/reputation_system.gd`、`scripts/gameplay/destiny_wallet.gd`、`data/reputation_config.json`、`tools/test_reputation_system.gd`（全部新增，零接线）。
- 完成内容：四轨声望（民心/朝纲/军功/文名，允许负值敌对）+ 加权总声望 + 六段位/六舞台 + 周衰减 0.1% + 段位/舞台里程碑水位制（防衰减降级回升重复领取）+ 天命点钱包（绑定声望系统自动入账、日结）+ 存档序列化；配置 JSON 驱动，缺失回退内置默认。未触碰 GameManager、Autoload、主场景、UI 与贵线全部在制文件。
- 稳定接口变化：无运行时接线；`scripts/gameplay/` 为玩法线新目录（class_name `ReputationSystem`/`DestinyWallet`，headless --script 场景需 preload 引用——.godot 全局类缓存不含新类）。
- 验证命令与结果：`godot --headless --path . --script res://tools/test_reputation_system.gd` → PASS 58 / FAIL 0；主场景 1200 帧冒烟零报错。
- 另一条线需要知道：本轮占用已全部释放；视觉线在制文件经 `git status` 复核原样保留。
- 下一步：P1-2 旧 `reputation` 兼容桥接——涉及 `game_manager.gd` `modify_reputation` 负值放开、`player.gd:1426`、`npc_spawner.gd:319` 读写点，将按共享热点流程在接口请求队列登记最小补丁后再动。
- Git commit：`337011a`。

### 2026-09-10 17:32｜玩法叙事线｜P1-2 步① 兼容桥接翻译层 + 接口请求登记

- 状态：完成（桥接模块就绪，`game_manager.gd` 接线待 REQ 评估）。
- 改动文件：`scripts/gameplay/reputation_bridge.gd`、`tools/test_reputation_bridge.gd`（新增）；`AI_COLLABORATION.md`（REQ-20260910-01 登记）。
- 完成内容：旧单轨 reputation 读写点全量分类（含共享热点 3 处）写入 gameplay-story.md；桥接翻译层落地——`apply_legacy`（缺省民心轨）、`legacy_value` 双视图公式（total/42 与 minxin/100 并存待拍板）、剧情效果钩子、组合存档；里程碑链路穿透验证（legacy 写入→段位晋升→钱包自动入账）。
- 稳定接口变化：玩法线内部新增 ReputationBridge 模块；对外零接线、零行为变化。
- 验证命令与结果：`--script res://tools/test_reputation_bridge.gd` → PASS 20 / FAIL 0；`--script res://tools/test_reputation_system.gd` 回归 58/0。
- 另一条线需要知道：REQ-20260910-01 已登记（`game_manager.gd` reputation 改 computed property 的最小补丁），贵线如对 game_manager 有并行计划请在队列回复；玩法线本轮占用已全部释放。
- 下一步：拍板兼容视图公式/scale 标定/死亡 reskin 三决策 → REQ 评估 → 接线 game_manager → P1-3 天命面板/商城/轮盘。
- Git commit：`17d4d79`（REQ 登记）、`14f34bc`（桥接模块）。

### 2026-09-10 17:33｜玩法叙事线｜P1-3 先行件天命轮盘核心（按 17:55 截时停止）

- 状态：完成（本日时段收工）。
- 改动文件：`scripts/gameplay/destiny_wheel.gd`、`data/destiny_wheel_config.json`、`tools/test_destiny_wheel.gd`（新增）。
- 完成内容：设计§6.3 轮盘逻辑核心——五品级权重抽取、绝品硬保底 60 抽（计数入档）、十连至少一珍、四奖池随舞台解锁、产物绑定不可交易、扣费走钱包（不足整段拒绝）。
- 稳定接口变化：无运行时接线；玩法线内部新增 DestinyWheel 模块。
- 验证命令与结果：`--script res://tools/test_destiny_wheel.gd` → PASS 26 / FAIL 0；本日玩法线三套测试累计 58+20+26=104 项全绿。
- 另一条线需要知道：玩法线本轮全部占用已释放（7 个新文件 + 2 份 JSON 已入库）；REQ-20260910-01 仍在队列待评估。
- 下一步：P1-2 步②拍板三决策后接 `game_manager.gd`；P1-3 续做商城数据层、天命面板 UI 与糖糖演出。
- Git commit：`5658c37`。

### 2026-09-10 20:20｜视觉世界线｜长安组团首轮落库与实体物理回归

- 状态：部分完成；整城方向与物理底线已通过，后续继续做院落连续性与真实移动走查。
- 改动文件：`scripts/changan_v2_generator.gd`、`scripts/changan_v2_materials.gd`、`scripts/player.gd`、`scripts/npc_character.gd`、三份 v2 探针、九张长安样张。
- 完成内容：连续外郭高墙/城外林带、宫城皇城围合、市集/院落/曲江组团，统一脚底锚、Y-sort、接地阴影和建筑脚印；新增主街中心物理通道探针。
- 稳定接口变化：无破坏性变更；既有 `stats`、节点组、城门与锚点契约保持。
- 验证命令与结果：结构探针 PASS（168×142、28 坊、四门、BFS=0）；主场景 E2E PASS（24 NPC、83 碰撞脚印、主街通道、九锚点、进出城、世界解冻）。
- 另一条线需要知道：REQ-20260910-01 复查口径已写入请求；请先修正桥接 setter 的绝对赋值语义、轮盘配置加载/十连价格/Lv3 功能门槛，再申请接线。
- 下一步：真实移动序列验证贴墙滑动/门洞净宽，再按街区轮廓收敛宫城、官署、民居与曲江的重复模板。
- Git commit：`3412587`。

### 2026-09-10 21:15｜视觉世界线｜长安四门专项与层次密度第二轮

- 状态：部分完成；用户本轮指出的黑色门洞、南北门墙断缝和旋转东西假门已修复，整城最终美术验收仍继续。
- 改动文件：`scripts/changan_v2_generator.gd`、`scripts/changan_v2_materials.gd`、三份 v2 探针、十一张长安样张（含开远/春明门与新增皇城机位）。
- 完成内容：门洞改真空装饰格；南北门楼按素材实宽与 `wall_run` 零缝同底线；东西门改开放关口+守望楼/门灯/石兽组合；宫城三进组团、两市连续宽窄店排+六摊、民居后院/高楼/巷排轮换；皇城主衙署补四座侧院，曲江矩形水面改逐行收放的折线岸形；人口 24→40。
- 稳定接口变化：无破坏性变更；四门 side、`gate_info`、`changan_city_gate` 四节点组、Portals 和冻结街网均保持。
- 验证命令与结果：结构探针 PASS；主场景 E2E 全 PASS；`python tools/regress_world.py` 94/94 PASS；窗口样张 11/11 PASS；BFS=0、275 材质件、124 阴影、95 建筑/树碰撞、40 NPC。
- 另一条线需要知道：没有修改玩法文件或共享热点；人口统计契约由 24 更新为 40，NPC 仍为既有 idle 日程，未改行为逻辑。
- 下一步：继续降低规则网格机械感、补两市物流与曲江岸边生活细节；等待专属东西侧墙素材后做外郭终验。
- Git commit：首段 `0a62650`；皇城/曲江追加随当前提交落库。

### 2026-09-11 09:30｜视觉世界线｜玩法 P1 自包含件三次验收与一日分支计划

- 状态：部分通过；REQ-20260910-01 setter 本体通过，但 P1-3 整体需完成 Gate A 后复验。
- 改动文件：仅 `AI_COLLABORATION.md`；本地 `.zcode/tasks/gameplay-story.md` 同步更新，不修改玩法运行时代码。
- 完成内容：复核 `ad20c0b`~`cb9ac43` 的桥接、商城、组装根、回响、面板、糖糖与物品表；发现回响编译假绿、一次性保险未消费、轮盘 warning 洪水与面板测试资源泄漏；制定 Gate A~H + Stretch I/J 的独立分支计划。
- 稳定接口变化：REQ setter 可进入 GameManager 最小接线；P1-3 整体接线仍以前置 Gate A 通过为条件。
- 验证命令与结果：声望 58/0、桥接 42/0、轮盘 33/0、商城 34/0、物品表 14/0；核心测试自报 17/0 但引擎 5 ERROR，面板自报 31/0 但退出 1 ERROR；主场景 1200 帧退出 0（新模块尚未接线）；`echo_revive.gd --check-only` 退出 1。
- 另一条线需要知道：若玩法分支与视觉线同时运行，必须使用独立 worktree/任务环境，不得在视觉线工作目录切分支；每 Gate 独立提交、不 squash，便于阶段性验收与选择性合并。
- 下一步：玩法线先执行 Gate A，修复后携统一 runner 原始摘要申请复验；通过后依次做 GameManager、日周调度、奖励落地、UI、死亡、糖糖与 P1 E2E。
- Git commit：本条随当前文档提交落库。

### 2026-09-12 10:17｜视觉世界线｜参考图驱动的城市场景密度第三轮

- 状态：阶段完成；现有素材纵切已落地，真实台地高差与东西竖墙仍待专用素材。
- 改动文件：`scripts/changan_v2_generator.gd`、`scripts/changan_v2_materials.gd`、三份 v2 探针、直接截图场景、十一张长安样张、`docs/长安v2-参考风格差距与缺件清单.md`。
- 完成内容：普通民居/非整院贵戚/小官署收紧为前后两排连续街面；两市加入牛车—三摊—小轿物流带及实体脚印，市场 NPC 避让；曲江补双船、岸摊和座椅。新增活动件、车辆、水岸生活统计与回归断言；截图工具修复写盘失败仍报 PASS 的假绿。
- 稳定接口变化：无破坏性变化；`stats` 只新增 `material_activity/material_vehicles/material_shore_life`，四门、街区 id、锚点、Portals 和冻结街网保持。
- 验证命令与结果：结构探针 PASS（168×142、28 坊、四门、BFS=0、291 材质件、122 阴影、97 实体碰撞、27 活动件、4 车辆、4 水岸生活、40 NPC）；主场景 E2E 全 PASS；窗口样张 11/11 真写盘 PASS；`regress_world.py` 94/94 PASS。
- 另一条线需要知道：未修改玩法文件或共享热点；工作树中的玩法 UID、`tools/godot_path.txt` 和 Tiled `changan_v2_city.tmx` 均保持为另一条线在制内容，不会纳入视觉提交。
- 下一步：继续朱雀街连续前店后院与皇城院落序列；P0 专用素材缺口为东西竖墙/侧门、台地崖墙/四向台阶、院墙转角和建筑侧背面模块。
- Git commit：随当前视觉提交落库。

### 2026-09-12 11:28｜视觉世界线｜长安天气可读性校色

- 状态：完成；未更换整套材质，长安雨雾画面已从灰黑压暗恢复到可读氛围光。
- 改动文件：`scripts/weather_controller.gd`、`tools/probe_changan_v2_shots.gd`、十四张长安样张。
- 完成内容：环境光控制器读取既有 `CityVisit.in_city`，城内天气乘色以 40% 强度混合；晴天/时辰、城外天气参数和雨雪粒子均不变。常规 11 机位固定为晴天材质基准，新增晴天/旧雨天/新雨天同机位三联图及亮度层级断言。
- 稳定接口变化：无；未修改共享热点 `city_visit.gd`、主场景、长安地图接口或玩法状态。
- 验证命令与结果：真实窗口渲染 14/14 PASS（亮度晴 `0.958`、旧雨 `0.669`、新雨 `0.839`）；结构探针 PASS（168×142、28 坊、四门、BFS=0）；主场景 E2E 全 PASS；开放世界 94/94 PASS；三份主验证日志零 `SCRIPT ERROR`/`ERROR`/泄漏。
- 另一条线需要知道：`weather_controller.gd` 本轮已释放；工作树中的玩法 UID、`tools/godot_path.txt` 和 Tiled TMX 均未触碰、不会纳入提交。
- 下一步：继续长安街区空间层次；只有晴天基准仍显暗的个别大面积地坪/墙体才做选择性中间调调整，不全包换色。
- Git commit：随当前视觉提交落库。
