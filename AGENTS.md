# AGENTS.md - 江湖志开发指南

本文档面向开发者和AI辅助工具，介绍项目架构、开发规范和注意事项。

---

## 项目概览

《江湖志》是一款基于 Godot 4.6 的 2D 武侠RPG，采用程序化地图生成、像素风美术风格（参考星露谷物语/饥荒），包含战斗、修炼、门派、生存等完整系统。

---

## 架构设计

### 场景树结构

```
Main (Node2D) [Main.gd]
└── World (Node2D, y_sort_enabled) [map_builder.gd]
    ├── TileMap (TileMap, 2层: 地面+装饰)
    ├── Player (CharacterBody2D, z_index=5) [player.gd]
    │   ├── CollisionShape2D
    │   ├── Camera2D
    │   ├── AnimatedSprite2D
    │   └── AttackIndicator (ColorRect)
    ├── WorldGenerator (Node2D) [world_generator.gd] — 运行时动态创建
    ├── WeatherController (Node) [weather_controller.gd] — 运行时动态创建
    ├── NPCSpawner (Node2D) [npc_spawner.gd] — 运行时动态创建
    ├── CanvasModulate
    ├── EnvironmentZones
    │   ├── ColdPond (Area2D)
    │   ├── BambooGrove (Area2D)
    │   └── MountainPeak (Area2D)
    └── UI (CanvasLayer)
```

### 初始化顺序

`Main._ready()` 中的初始化顺序至关重要，不可随意调换：

1. `_ensure_textures()` — 生成纹理/瓦片集/精灵帧（仅首次运行）
2. `await process_frame` — 等待一帧确保资源就绪
3. `_setup_world_generator()` — 创建世界生成器（触发chunk加载）
4. `_setup_weather()` — 天气系统
5. `_setup_hud()` — 生存状态HUD
6. `_setup_clan_simulator()` — 门派模拟
7. `_setup_event_hud()` — 世界事件HUD
8. `_setup_quest_system()` — 任务系统
9. `_setup_encounter_system()` — 奇遇系统
10. `_setup_oath_system()` — 誓约系统
11. `_setup_quest_log()` — 任务日志
12. `_setup_quick_menu()` — 快捷菜单
13. `_setup_combat_stance()` — 战斗架势
14. `_setup_combat_hud()` — 战斗HUD
15. `_setup_inventory()` — 物品管理
16. `_setup_shop()` / `_setup_shop_hud()` — 商店系统
17. `_setup_death_system()` / `_setup_death_hud()` — 死亡系统
18. `_setup_npc_spawner()` — NPC生成（必须在纹理和世界之后）

### 自动加载（Autoload）

| 名称 | 脚本 | 用途 |
|------|------|------|
| GameManager | `game_manager.gd` | 全局状态：道德/声望/金钱/内力/生存属性/NPC关系/时间/天气 |
| DialogManager | `dialog_manager.gd` | 对话流程控制 |

---

## 核心系统详解

### 世界生成 (`world_generator.gd`)

- **Chunk系统**：16×16瓦片为一个chunk，加载半径3（7×7 chunks）
- **地形生成**：三层噪声（高度/湿度/细节），6种地形类型
- **双层TileMap**：Layer 0 = 地面（草/沙/水/山），Layer 1 = 装饰（树/建筑/花/桥）
- **世界边界**：半径80瓦片，外围强制为深水
- **河流**：2-3条正弦曲线河流，宽度3-5格，每隔15格有桥
- **城镇**：3-5个随机城镇，结构为栅栏→农田→房屋+路
- **POI**：6种兴趣点类型，每种有专属地形铺设
- **碰撞**：水域(5)/山脉(3)/雪山(7)有物理碰撞，不可通行

**瓦片ID映射**：

| ID | 瓦片 | 碰撞 | 层 |
|----|------|------|-----|
| 0 | 草地 | 否 | 0 |
| 1 | 小路 | 否 | 0 |
| 2 | 城镇房屋 | 否 | 1 |
| 3 | 山脉 | 是 | 0 |
| 4 | 松树 | 否 | 1 |
| 5 | 水域 | 是 | 0 |
| 6 | 沙地 | 否 | 0 |
| 7 | 雪山 | 是 | 0 |
| 8 | 橡树 | 否 | 1 |
| 9 | 竹子 | 否 | 1 |
| 10 | 茅屋 | 否 | 1 |
| 11 | 寺庙 | 否 | 1 |
| 12 | 洞穴入口 | 否 | 1 |
| 13 | 花朵 | 否 | 1 |
| 14 | 石头 | 否 | 1 |
| 15 | 栅栏 | 否 | 1 |
| 16 | 农田 | 否 | 0 |
| 17 | 桥 | 否 | 1 |
| 18 | 深色草地 | 否 | 0 |

### 玩家系统 (`player.gd`)

- **状态机**：IDLE / MOVE / ATTACK / BLOCK / DODGE / MEDITATE / BUILD / STAGGER
- **4方向动画**：down / left / right / up，每种有 idle(4帧) / walk(6帧) / attack(4帧) / block(2帧)
- **帧尺寸**：32×48像素，1.5倍缩放
- **z_index**：5（确保在瓦片之上）
- **碰撞形状**：24×36矩形

### NPC系统 (`npc_character.gd` + `npc_spawner.gd`)

- **5种外观**：warrior / scholar / merchant / elder / mysterious，根据性格自动分配
- **日程状态**：idle / walking / working / sleeping
- **4方向动画**：idle(4帧) / walk(6帧) × 4方向
- **z_index**：5

### 战斗系统

- **架势**：`combat_stance.gd` — 攻击/防御/中立三架势，破绽值管理
- **连招**：`combo_tree.gd` + `combo_route.gd` — 0.5秒窗口内连续输入
- **技能**：`skill.gd` — 6类武器×3阶段（起手/连击/终结）= 18种技能
- **内功**：`inner_skill.gd` — 五行属性，环境影响修炼效率

### 资源生成器

所有 `@tool` 脚本在编辑器中运行，也可在游戏首次运行时自动触发：

| 生成器 | 输出 | 触发条件 |
|--------|------|---------|
| `texture_generator.gd` | `sprites/tiles/*.png`, `sprites/player/*.png`, `sprites/npc/*.png` | 纹理PNG不存在 |
| `tileset_generator.gd` | `tilesets/ground_tiles.tres` | TileSet无瓦片源 |
| `frames_generator.gd` | `sprites/player/player_frames.tres` | SpriteFrames不存在 |
| `skill_generator.gd` | `resources/skills/*.tres` | 技能资源不存在 |
| `inner_generator.gd` | `resources/inner/*.tres` | 内功资源不存在 |
| `combo_generator.gd` | `resources/combo_tree.tres` | 连招树不存在 |
| `clan_generator.gd` | `resources/clans/*.tres` | 门派资源不存在 |

---

## 开发规范

### 代码风格

- GDScript，Godot 4.x 语法
- 缩进：Tab
- 命名：函数用 `snake_case`，常量用 `UPPER_SNAKE_CASE`，变量用 `snake_case`
- 中文注释和日志输出
- 状态机模式：match 枚举状态分发处理

### 场景与脚本关系

- 场景文件（`.tscn`）尽量保持精简，复杂节点在运行时动态创建
- 主场景 `main.tscn` 中不直接引用 `ground_tiles.tres`（运行时动态加载），避免编辑器报错
- NPC场景 `npc.tscn` 中 AnimatedSprite2D 的 sprite_frames 在运行时动态赋值

### 资源管理

- **纹理**：首次运行自动生成到 `sprites/` 目录，无需手动创建
- **TileSet**：运行时生成，场景中不静态引用
- **SpriteFrames**：运行时生成，场景中可静态引用（`player_frames.tres`）
- **游戏数据**：`resources/` 下的 `.tres` 文件由生成器创建，可手动编辑调整数值

### 修改注意事项

1. **修改纹理**：删除 `sprites/` 下对应PNG，重新运行游戏自动重新生成
2. **修改瓦片集**：删除 `tilesets/ground_tiles.tres`，重新运行自动重新生成
3. **修改地图生成**：编辑 `world_generator.gd` 中的噪声参数和地形规则
4. **修改角色外观**：编辑 `texture_generator.gd` 中的绘制函数，删除旧PNG重新生成
5. **添加新瓦片类型**：
   - 在 `texture_generator.gd` 中添加绘制函数
   - 在 `tileset_generator.gd` 的 `textures` 字典中注册
   - 在 `world_generator.gd` 的 `get_tile_id()` 中使用
   - 如需碰撞，添加到 `collision_tile_ids` 数组
   - 如有透明区域，添加到 `decor_tiles` 数组（放在Layer 1）

---

## 已知问题与待优化

### 当前已知问题

- NPC帧动画资源在首次运行时可能未及时加载，有回退占位矩形显示
- 地图chunk卸载已禁用（避免空隙），长时间游戏可能内存增长
- POI标签可能被树木等装饰瓦片遮挡

### 待优化方向

- 添加更多POI类型和地形变体
- NPC路径寻路（目前随机行走）
- 战斗系统伤害反馈和特效
- 音效和背景音乐
- 存档/读档系统
- 小地图UI
- 多语言支持

---

## 调试技巧

### 日志输出

所有脚本使用 `print()` 输出日志，关键系统有前缀标识：

- `[Main]` — 主场景初始化
- `[WorldGen]` — 世界生成
- `[TileSetGen]` — 瓦片集生成
- `[TextureGen]` — 纹理生成
- `[Combat]` — 战斗系统
- `[Clan]` — 门派系统
- `[Build]` — 建造系统

### MCP调试

项目集成了 `godot_ai` MCP 插件，可通过以下方式调试：

- `editor_screenshot` — 截取游戏画面
- `logs_read` — 读取Godot输出日志
- `scene_get_hierarchy` — 查看场景树
- `node_get_properties` — 查看节点属性

### 常见问题排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| TileSet y_sort_origin 报错 | Godot 4中TileSet无此属性 | 在TileData上设置 |
| 地图灰色区域 | 装饰瓦片无地面底层 | 使用双层TileMap |
| 角色穿过水域 | TileSet碰撞未正确设置 | 确认物理层和碰撞多边形 |
| NPC无建模 | 纹理未生成就加载 | NPCSpawner延迟创建 |
| POI被遮挡 | z_index过低 | POI z_index=10, 标签=20 |
| 角色顶部消失 | z_index低于瓦片 | Player/NPC z_index=5 |
