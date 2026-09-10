# 《江湖志》双模型协作总控

> 状态：生效中　｜　建立：2026-09-10　｜　最后更新：2026-09-10 16:37（Asia/Shanghai）
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

当前无待处理接口请求。

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
