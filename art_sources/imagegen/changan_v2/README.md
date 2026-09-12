# 长安 v2 Image 2.0 补件源

本目录保留可重切的生成源图；运行时不直接加载这些大图，而由
`tools/import_sckr_changan.py` 按 `AI_PROPS` 固定源窗生成
`sprites/changan_ai/` 下的透明像素件，并登记到 `data/sckr_manifest.json`。

## 生产提示词摘要

- `side_gate_bridge_magenta.png`：16-bit top-down pixel art，唐代灰瓦木构；单体南北纵向屋脊门桥，连接上下竖墙，东西道路从桥下贯通；严格俯视、正交、无人物、无文字、无阴影、纯洋红背景，禁止正面门楼和十字墙。
- `side_wall_run_magenta.png`：16-bit top-down pixel art，单条南北纵向外郭城墙墙顶步道；左右青灰垛墙、中间暖灰步道，严格俯视、正交、无门、无建筑、无文字、无阴影、纯洋红背景，禁止正面墙立面。
- `outer_wall_horizontal_magenta.png`：以前一张竖墙源为精确色板和像素密度参考，生成同族东西横向墙顶步道；上下青灰垛墙、中间暖灰步道，严格俯视、正交、纯洋红背景，禁止正面立面、门楼和转角。
- `outer_gate_horizontal_magenta.png`：以竖向门桥和横向墙顶为精确家族参考，生成同族东西横向屋脊门桥；南北道路从中央穿过，左右短墙帽与横墙对接，严格俯视、正交、纯洋红背景。
- `terrace_stairs_magenta.png`：以目标概念图、当前宫城实机图和新城墙色板为参考，生成宽幅暖石台面、青灰挡墙、中央向南大阶梯；严格俯视正交、纯洋红背景，无建筑、人物和绿植，用作宫城可通行高台。

正式派生件只允许整数倍 `NEAREST` 缩放；东西侧可水平镜像，但禁止把正面墙或正面门楼旋转成侧向素材。
