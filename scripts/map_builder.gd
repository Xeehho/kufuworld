@tool
extends Node2D

# 地图构建器 - 现在由WorldGenerator的chunk系统统一管理瓦片
# 此脚本保留作为World节点的挂载脚本，不再手动铺砖

func _ready():
	# 不再手动构建固定地图，由WorldGenerator的chunk系统动态生成
	# 保留TileMap节点供WorldGenerator使用
	pass
