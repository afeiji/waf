-- 配置文件
config = {}
config.host = '192.168.2.21'
config.port = '6379'
config.password = '123456'
config.select_db = '1'

-- 设置访问频率
config.mx_day = 1000
config.mx_hou = 100
config.mx_min = 50
config.mx_sec = 5

-- 设置空UA访问频率
config.er_mx_day = 20
config.er_mx_hou = 10
config.er_mx_min = 5
config.er_mx_sec = 3

-- 黑名单时长
config.block_days = 1

-- 四天黑名单次数
config.block_count = 5

return config
