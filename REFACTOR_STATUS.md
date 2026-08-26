# 江湖志 星露谷式重构 - 进度交接文档

> 分支: feat | 里程碑提交: dbc98a1(Phase A) → Phase B(5e7343b) → Phase C(528a685) → Phase D → **Phase F已完成(见下，七项修复+UI重构)** | 逻辑探针31(C)+32(D)+Phase F运行时探针全绿（headless 0错误）

## ⚠️ Phase E 状态声明
**Phase E 暂不需要执行（用户明确指示暂缓）。** Phase E备选池内容（NPC竖向行走帧程序补齐/存档持久化/血条闪烁联动与第二BGM主题）保留在下方原文档中仅作备忘，新任务不要主动实施；除非用户再次明确要求。

## 尺寸规范（本次确立的和谐基准）
- 瓦片 16x16 px；玩家 Body_A 64x64帧 scale=1（人物实际16宽x30高约2格，星露谷比例）
- NPC/Mob 32x32帧 scale=1（Phase B已统一：merchant/elder源64px→最近邻缩到32px）；碰撞全部脚部小盒 12x8 @position(0,-4)
- 相机 zoom=3 已有；全局纹理过滤已改 nearest
- 帧偏移：玩家 anim.offset=(0,-16)，NPC=(0,-15)（脚线对齐节点原点）

## 已完成
### Phase A（dbc98a1，略）
1. 素材转换管线 tools/import_pack_assets.py；玩家192帧/NPC200帧/Mob138帧/地形自动选片
2. 大树道具系统 world_generator.gd TREE_SHEETS + _spawn_tree_prop()（y排序大冠幅道具）
3. player.gd rebuild_sprite_frames 新规格
4. npc.tscn/main.tscn/npc_character.gd 碰撞脚部化
5. 探针自动化验证管线（无视觉模型的替代方案）

### Phase B 世界观感（本次完成，全项）
1. **中式房屋重调色**（texture_generator.gd）：
   - 黛青瓦顶三阶 #455C6B / 高光#617D8C / 檐影#2B3B47（城镇/门派/多格建筑house2~5共用）
   - 茅屋(cottage)赭石茅草顶 #947047系（_ROOF_THATCH），与黛青形成民居/瓦房区分
   - _img_house_roof(img, roof_pal) 参数化调色板，_img_save_house 增加 roof_kind 形参
2. **程序贴图修复+降饱和**：
   - 发现根因：rock/fence/bridge/flower/tree_pine/tree_oak/tree_bamboo 均按32px坐标绘制，
     在16x16画布上大面积越界（rock仅20%不透明、fence右桩整根丢失、bridge右半被裁）
   - 全部重写为格内构图：rock冷灰大石+小石、fence双杆双桩、bridge竖向板面双栏杆、
     flower三朵降饱和、pine/oak/bamboo重排；山岩转冷灰蓝(#96A0AA系)呼应黛青顶
   - 磁盘PNG是陈旧旧版产物——改代码后必须删PNG重生成（用tools/regen_tiles.gd）
3. **树影落地感**（world_generator.gd _spawn_tree_prop）：
   - 48x20径向衰减白椭圆纹理缓存 + modulate黑30%，宽=clamp(cell.x*0.42,24,56)
   - 关键z序：prop.z_index=2（原1）、shadow.z_index=-1相对→等效z=1，
     实现"地面之上、树干之下"；曾用等效z0被TileMap完全盖住不可见（已踩坑验证）
   - A/B差分定量验证：有影/无影两跑逐像素对比，森林机位暗化像素12850、亮度比0.656≈理论0.70
4. **NPC观感修复**：Peasant_A/Tavern_B源图64x64帧直接导出导致商人/长者放大一倍且脚线错位；
   import_pack_assets.py 加 resize_nearest 统一缩到32x32后重导出（sprites/npc 200帧全部32px）
5. **NPC上下行走评估结论**：素材包 Npc's/* 只有Side表（无Up/Down源），复用side帧是包限制非导入缺陷；
   维持现状，若后续不能接受可在Phase D程序生成简易背影/正面帧
6. **管线权属厘清（防覆盖陷阱）**：
   - terrain五件套(grass/grass_dark/path/farmland/water)归python管线，generate_tiles不再写这五个
   - Main._ensure_textures 改为只校验生成器管辖瓦片+调 generate_tiles()（严禁generate_all，
     其内含 generate_player_frames/generate_npc_frames 会把素材包人物帧冲成程序画法）；
     地形瓦片缺失时 push_warning 提示重跑 python tools/import_pack_assets.py terrain

## 已完成（续）
### Phase C Stardew交互玩法（本次完成，全项，逻辑探针31/31绿+视觉审计通过）
1. **面前格子高亮指示器**：player.gd运行时生成16x16描边ImageTexture（z_index=30），每帧随facing指向邻格，
   仅IDLE/MOVE且无模态UI时显示
2. **工具系统**：数字键1-4切换（锄头/水壶/菜种/采集，再按同键收回徒手）；装备工具时左键=使用工具（星露谷式），
   播attack动画2.6倍速0.26s；结果飘字反馈（成功黄/失败红）。farm_system API全部返回{ok,msg}
3. **农田三态瓦片**：草地(0/18)→锄头→农田16→水壶→湿润农田33（tileset_generator新注册，farmland_wet.png由
   make_phase_c_assets.py从farmland.png压暗烘焙）；雨天自动补水
4. **作物状态机**：种→浇水→3天(每天需复浇)→成熟→采集入库。阶段贴图sprites/farm/crop_0..3.png程序烘焙；
   farm_system.on_new_day()推进days/stage并回写地面干湿；未熟采集被拒并提示进度
5. **浆果丛**：FarmSystem就绪时在出生点10~55瓦片可达草地上散布12丛（间距≥7），采集得野浆果x2-3，
   空丛2天后再生（berry_bush/_empty.png烘焙）
6. **敌人系统**：mob.gd(Orc=山贼刀客/斥候，Skeleton=白骨教众刀卒/法师/刺客)，idle4/run6/death按文件数帧
   从sprites/mobs直读；AI游荡→仇恨圈追击→蓄力0.38s(变黄预警)→近战命中走player.take_hit_with_stance
   （combat_stance真实减伤/破绽/大硬直闭环）；受击红闪+击退+强制进战，死亡播death帧+掉落入背包+90s营地重生
   （玩家远离260px才重生，全场≤12只）；mob_spawner.gd两座营地锚定出生点(-30,-22)/(28,32)瓦片
7. **玩家攻击接通真实目标**：_deal_damage()经_find_mob_in_front()(56px扇形cos>0.25)命中最近mob调take_damage，
   命中特效/飘字移到怪身上
8. **制作站台**：station_system.gd——工作台(铁锭→铁剑)/熔炉(铁矿x2→铁锭)/炼丹台(草药x2→金创药)/篝火(浆果→烤浆果)；
   建造模式数字键6-9摆放(build_slot_6..9新输入动作)，F键34px内最近站台合成，缺材料红字提示；
   贴图经tools/make_phase_c_assets.py从downloaded_assets/Stations裁剪烘焙到sprites/stations/（篝火4帧火焰循环），
   运行时load_png_texture直读；站台z_index=2与树道具同层避TileMap吞没
9. **物品工厂**：item_factory.gd统一Phase C物品目录（菜种/浆果/青菜/铁锭/烤浆果/铁矿/草药——后两者id与
   inventory默认物品对齐可堆叠）；初始发放菜种x5

## 已完成（续2）
### Phase D 打磨（本次完成，全项，逻辑探针32/32绿）
1. **玩家死亡闭环接death_system**：health<=0时death_system.trigger_death()**直接驱动**player.play_death_visual()
   （播death_方向8帧+State.DEAD锁输入物理+_is_dead标记供mob自动脱战+停打坐）；_apply_outcome()后调
   player.on_respawn_reset()复位IDLE。信号player_died/respawned仍保留给HUD，但表现不依赖连接时序——
   GameManager.take_hit内部触发的首次emit早于任何connect（Main._ready中途await使deferred提前落空，已踩坑）
2. **受击反馈**：take_hit_with_stance(dmg, from_pos)——红闪(1,0.35,0.35→白0.22s)+hurt_方向4帧(hurt_timer
   0.32s内IDLE/MOVE不覆盖动画)+朝远离攻击者方向9px微击退(mob传入自身位置)+相机震动3级；STAGGER大硬直
   不叠加hurt帧；死亡后免疫后续hit
3. **音效/BGM占位**：tools/make_phase_d_audio.py程序合成12个音效(swing/hit/hurt/mob_die/player_die/till/
   water/plant/harvest/craft_ok/craft_fail/ui)+26.9s五声羽调BGM循环(audio/sfx|audio/bgm，22050Hz16bit mono，
   首尾交叉拼接无缝循环)；audio_controller.gd挂World下AudioController——AudioStreamWAV.load_from_file直读
   (无import数据)，6播放器轮换池+BGM finished重播循环，play_sfx(name,vol,pitch)+history[]记录；
   接线：攻击起手swing(-9dB)/命中敌人才hit/hurt/工具四动作成功才响/站台合成成败/切工具ui/mob_die带随机音高/
   player_die；AudioController缺失时_sfx静默降级不影响逻辑
4. **日夜光照微调**（weather_controller）：调色板改夜(0.40,0.46,0.72)/晨雾暖粉(0.84,0.64,0.56)/落日暖橙
   (0.86,0.55,0.42)；新增WEATHER_LIGHT天气调制表(CLEAR1.0/CLOUDY0.90/RAIN0.78冷蓝/SNOW0.94/FOG0.88乳白
   非土色)+current_light每帧lerp(delta*2)平滑承接小时段与天气切换；开局直接落目标光避免白闪
5. **树影随昼夜强度变化**（可选项一并完成）：world_generator阴影精灵set_meta("shadow_base_a",0.30)；
   weather_controller._tick_tree_shadows每0.5s按_daylight_factor()(正午1→夜0.15分段曲线×云雨削弱
   0.55+0.45*mult)缩放group tree_shadow的modulate.a(clamp 0.22~1.0)

## 已完成（续3）
### Phase F 七项体验修复 + UI游戏化（本次完成，运行时探针全绿/headless 0错误）
> 用户原始需求逐条对应：1玩家外衣发型 2NPC名字过大 3部分NPC模型过小 4名字隐藏+远距点击查看 5房屋拆围栏巨大化 6地形按区域+可达性保证 7任务日志与人物面板重构

1. **F1 玩家外衣+发型**（tools/import_pack_assets.py 着装引擎 `_dress_frame()`）：
   - 裸模Body_A颜色域重绘：皮肤亮(0xd9a066)/暗(0xa26543)两色阈值分类→4连通分量找头部
   - 乌发(38,30,44)+高光、发髻3px+朱红发带(down/up)；脸窗按方向保留（down中央/right前侧/left镜像/up全后脑）
   - 身体：黛蓝长衫(64,76,112)+暗部/赭红腰带/深裤/黑靴；down向加米白V领镶边。描边纯黑像素零改动（114px前后一致已验证）
   - 192帧全部着装，探针采样 robe_px=54 hair_px=81 生效；SurvivalHUD头像裁剪框同步改(24,15,16,17)
2. **F2 NPC名牌比例**：删除npc.tscn常驻NameLabel/StateLabel → 隐藏式NameTag(font_size=5×zoom3≈15px屏显,描边2)
3. **F3 NPC模型归一化**（管线 export_npcs 重写）：源表frame0测内容bbox定全局scale→目标高29px统一
   - 每帧独立bbox裁剪缩放，脚底以本表frame0为基准锚定y=31（walk起伏delta等比保留）
   - merchant/elder从charH=15修复到29（此前64px源整帧缩半导致过小）；200帧全量PNG完整性校验通过
   - ⚠️踩坑：整条union-strip重采样会破坏帧边界（透明间隔导致帧切片错位→PNG损坏），必须逐帧处理
4. **F4 点击NPC=查看信息（与攻击解耦）**：
   - player.gd `_npc_at_mouse()`：鼠标位置r=13圆形物理查询命中"npc"组→`_click_npc_info()`打开NPCInfoHUD+名牌闪现2.2s，不触发攻击/工具（左右键均让路）
   - 悬停高亮(modulate 1.22)+悬停期间名牌常驻；名牌默认隐藏，仅点击/悬停显示
5. **F5 房屋拆围栏+巨大化（星露谷比例）**：
   - texture_generator 新增 generate_big_buildings()：hut54x48/house74x64/manor100x84/temple122x100 四型程序绘制
     （黛青瓦顶带瓦沟/檐口阴影/受光翘边、米墙砖缝、朱红柱/金匾/宝顶庙宇专属、门钉窗棂），输出 sprites/buildings/
   - world_generator BUILDING_PROPS系统：footprint占格写override_cells[39]（参与碰撞+可达性，TileMap只铺地面）
     + Sprite2D(z_index=4,墙脚压地6px) + StaticBody2D矩形碰撞 挂World
   - 城镇重写 _generate_single_town：half=7~9 十字土路+四象限大建筑(manor/temple主建筑+民居2-4栋)+开阔农田斑(无栅栏)
     门格自动向主路铺径(_carve_door_path)；城镇POI同步去栅栏改大宅道具；POI地标贴图升级为大建筑、标签字号13→5
   - 实测20栋大建筑落位(footprint 317格)；⚠️Godot对重名子节点生成"@Node2D@N"，调试统计用building_prop分组勿靠名字前缀
6. **F6 饥荒式群系建图+连通性保障**：
   - _setup_biomes()：环形撒9群系首府(plains/forest/bamboo/mountain/desert/snow/lake轮转)+中央固定plains出生区；
     _biome_kind()最近首府归属+detail_noise抖动边界
   - get_tile_id默认分支按群系重写：forest密林/bamboo竹海/desert沙+石/snow雪原/lake圆湖(r<11水,15沙环)/
     mountain山脊成势(r>0.62山体)且谷地沙地走廊(r<=0.40天然可穿行)
   - _ensure_connectivity()：最多6轮——BFS出生点可达集→扫描未达可走pocket(flood上限4000格,≥6格才修)→
     最近点对L形开路(_carve_connection:水架桥17/山石沙化6)。"石中沙地"类孤岛全部打通（实测carved≈96格/轮1次收敛，
     残留109格均为<6格小凹缝属设计内忽略）；完成后重算reachable_cells供NPC/Mob选址用最新数据
7. **F7 任务日志+人物面板游戏化**：
   - quest_log_hud.gd（新）：页签(进行中/可接取/已完成UITheme风格)+任务卡片(类别徽记配色/难度星/描述autowrap/
     真ProgressBar进度Jade色/奖励行/接取放弃按钮)+N刷新·数字键快接·F1弃保留；ESC可关
   - character_sheet.gd（新）：V键开关居中弹窗——头像框(idle_down_0头部裁剪nearest放大)+称号(按声望5档)+
     左列伤势/饥饿/内力/中毒样式化进度条+右列道德声望盘缠木石门派职位贡献内功环境十项履历；
     加入"ui_modal"组，player._is_ui_blocking遍历该组锁移动
   - survival_hud.gd瘦身：旧ASCII任务日志整体迁出，操作指南补V键与点击NPC说明

## Phase F 验证记录（复现命令）
- 素材重建: python tools/import_pack_assets.py player && python tools/import_pack_assets.py npc
- 语法检查: python tools/run_check.py scripts/world_generator.gd ...（GameManager/DialogManager报Identifier not found属--script模式假错）
- 运行时探针: project.godot [autoload]注入 ProbeF="*res://tools/probe_autoload_f.gd" → headless --quit-after 900 →
  读 tools/probe_f_log.txt（完毕后必须移除ProbeF！本次已恢复）。指标: biome_seeds=10 building_props=20 footprint=317 orphan=109 npc=12 robe_px=54
- 干净启动: --headless --quit-after 600 无任何ERROR

## 未完成（建议新任务按序推进）
### Phase E 备选池
- （可选）NPC竖向行走帧程序补齐（素材包仅Side表，程序生成背影/正面易违和，需谨慎）
- （可选）作物/农田/站台存档持久化（当前无任何save系统）
- （可选）受击/死亡时survival_hud血条闪烁联动；BGM随昼夜/战斗切换第二主题

## 验证工具（Phase B新增/扩展；Phase C再扩）
- tools/regen_tiles.gd: 无头重生成生成器管辖瓦片。
  用法: <godot_exe> --headless --path . --script res://tools/regen_tiles.gd
  刻意绕开generate_all/player帧/npc帧/包管地形（文件头注释说明）。日志tools/regen_log.txt
- tools/analyze_phase_b.py: 截图调色板命中率分析（森林树冠命中+阴影带；城镇黛青/茅草/山岩/木构命中）
- probe_autoload.gd 扩展: 第4机位自动传送最近POI(存probe_shot_3.png)；ShadowAudit采样树脚阴影对
- Phase B验证结论: 城镇shot3 黛青30371/茅草19122/米墙2676/冷灰岩138597/暖木17605采样命中——新调色板全部上屏
- **Phase C新增**: tools/probe_phase_c.gd逻辑探针(31项断言：农田三态/生长停滞与成熟/浆果丛/营地生成/
  前向检测/伤害闭环双向/掉落/站台合成缺料拒绝) + tools/probe_phase_c_visual.gd视觉布景探针
  (摆湿田/成熟作物/四站台/双怪截图probe_shot_c.png并输出世界锚点) + tools/probe_state.gd地面id状态探针；
  分析端用烘焙PNG主色做最近邻分类（湿润田81/81像素命中湿色调，干田65/81干色调）
- Phase C验证结论: 31/31逻辑全绿；站台x4/指示器/双怪/成熟作物/湿干农田差分全部上屏
- **Phase D新增**: tools/probe_phase_d.gd逻辑探针(32项断言：音频装载与播放拒绝/昼夜光照亮度差与is_daytime/
  天气雨天变暗/树影正午满浓夜晚微弱+meta抽检/红闪hurt计时窗与衰减回白/死亡闭环全链路(engaged→DEAD状态→
  death动画→mob可读_is_dead→复活复位IDLE→被救回血40)/农活经_use_tool全链路回归+till音效接线) +
  tools/run_probe_d.py运行器(临时注入ProbeAutoload→跑游戏→无论成败还原project.godot→stdout落盘
  probe_game_stdout.txt防超时丢日志) + tools/check_scripts.py(--check-only批量语法检查，注意player/weather/
  mob报autoload标识不可见假错见备忘) + tools/make_phase_d_audio.py音源合成
- Phase D验证结论: 32/32逻辑全绿（唯一error是无害shader cache提示）

## 关键陷阱备忘（务必先读）
- 【致命】运行时触发 generate_all() 会用程序画法覆盖 sprites/player|npc 的素材包帧！
  重生成瓦片一律走 gen.generate_tiles() 或 tools/regen_tiles.gd
- 【隐蔽】树道具子精灵 z_index=-1 相对→等效z0 会与TileMap同层被盖住不可见；
  树体已抬到z=2给阴影让位。凡往World挂z0的装饰都会被地形吞掉，注意层级（Phase C作物/浆果丛/站台均z=2）
- 【流程】texture_generator.gd 改完必须删对应PNG再重生成才生效（磁盘PNG是产物非源文件）
- 运行时PNG必须走 TextureGen.load_png_texture()，禁止load res://（新PNG无import数据）
- 探针用完勿把ProbeAutoload留在project.godot的[autoload]（每次跑完立即移除，Phase C已遵守）
- project.godot注释只能用分号";"——"//"会让紧邻的input action解析丢失（Phase C踩坑：tool_slot_1曾消失）
- GDScript三元式优先级低于%和算术——"a % b if c else d"解析为"(a%b) if c else d"；数组下标/Variant返回值
  不能用:=推断类型（get_item_count等需显式": int"），--script独立SceneTree模式autoload标识符不可见属假错
- ItemFactory目录(PHASE_C_ITEMS)必须收录一切掉落/合成物id，否则give()静默返回false不进背包
  （铁矿石/草药已与inventory默认物品对齐同id堆叠）
- 敌人营地锚定出生点而非固定坐标；find_nearest_reachable(max_r=40)可能把不可达锚点拉回出生区，
  营地成员会立刻进仇恨圈——测试玩家行为前先把玩家传远（探针已内置+520,+520位移）
- CLI杀进程丢stdout缓冲——探针一律文件日志(tools/probe_log.txt)；窗口模式(GUI子系统)连stdout都没有，
  只能靠文件日志+产物存在性判断
- Godot编辑器MCP在线(session my-godot-project@5056)；editor_state空参会报错，传session_id
- 大雾天气让截图全屏土色——分析前先清WeatherController+还原CanvasModulate
- godot_path.txt是GBK编码且路径含中文目录，bash直接展开会乱码——经python subprocess调用
- 本模型无视觉输入：所有画面结论必须来自tools/*.py调色板统计或探针内采样，禁止凭空断言
  （湿润农田是压暗棕而非偏蓝——审计谓词要对照烘焙PNG实测主色，勿凭想象设阈值）
- 【Phase D新】death_system触发玩家表现的正确姿势是trigger_death/_apply_outcome内直接找player组节点调用
  方法，不要只靠player_died/player_respawned信号——GameManager.take_hit内部check_death触发的首次emit
  必然早于player侧任何connect时机（player._ready的call_deferred也晚于不了它，因Main._ready中途await
  process_frame会让deferred提前冲刷），信号仅作HUD等旁路通知
- 【Phase D新】weather_controller._process每帧用world_time重算current_hour——探针/测试想固定时段必须改
  wc.world_time=h*60*time_scale（直接赋current_hour下一帧就被覆盖，已踩坑）
- 【Phase D新】探针断言音效别用audio_controller.last_played（会被后续音效覆盖），用history.has()
- 【Phase D新】--check-only对引用autoload单例的脚本必报假错（player.gd:DialogManager等），只看真解析错
  （如probe曾报115行Expected end of statement=两条语句被拼一行）
- 【Phase D新】run_code后台长命令（>60s预算）用node child_process spawn detached+输出重定向到文件再轮询；
  runner的Popen stdout必须落文件句柄而非PIPE，否则timeout路径丢弃全部游戏日志无从排障
- 【Phase D新】本机环境user://落在项目根Godot/app_userdata（已加.gitignore）；project.godot注入/还原探针
  autoload后要检查[autoload]节残留空行（CRLF文件replace("\n")匹配不上\r\n）
