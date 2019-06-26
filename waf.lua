package.path = "/usr/local/nginx/lua/cap/?.lua;/usr/local/nginx/lua/lib/?.lua;"
-- 导入模块
local server_config = require("config")

-- 是否不为黑名单
local flag = true

-- redis连接
local redis = require "resty.redis"
local conn = redis.new()
local host = server_config.host
local port = server_config.port
local auth = server_config.password
local db = server_config.select_db

-- 设置访问频率
local mx_day = server_config.mx_day
local mx_hou = server_config.mx_hou
local mx_min = server_config.mx_min
local mx_sec = server_config.mx_sec

-- 设置空UA访问频率
local er_mx_day = server_config.er_mx_day
local er_mx_hou = server_config.er_mx_hou
local er_mx_min = server_config.er_mx_min
local er_mx_sec = server_config.er_mx_sec

-- 黑名单时长
local block_days = server_config.block_days

-- 四天黑名单次数
local block_count = server_config.block_count

-- 获取客户端ip
local function get_client_ip()
	local ip = ngx.var.http_x_forwarded_for or ngx.var.remote_addr
	-- print( '----------remote ', ngx.var.remote_addr, ' ------forward ', ngx.var.http_x_forwarded_for)
	-- print('------ ', tostring(ngx.req.get_headers()))
	return ip
end

local function init_keys(conn, key, ttl_time)
	conn:set(key, 0)
	conn:expire(key, ttl_time)
	end

local function block_ip_2_cap(conn, ip)
	conn:init_pipeline()
	conn:incr('blk:' .. ip)
	conn:expire('blk:' .. ip, block_days * 24 * 3600)
	-- init_keys(conn, "vis:dd:" .. ip, 24 * 3600)
	init_keys(conn, "vis:hh:" .. ip, 3600)
	init_keys(conn, "vis:mm:" .. ip, 60)
	init_keys(conn, "vis:ss:" .. ip, 1)
	init_keys(conn, "er:hh:" .. ip, 3600)
	init_keys(conn, "er:mm:" .. ip, 60)
	init_keys(conn, "er:ss:" .. ip, 1)
        conn:commit_pipeline()
end	

local function close_redis(red)
        if not red then
                return
        end
        local pool_max_idle_time = 10000  --毫秒  
        local pool_size =  100 --连接池大小  
        local ok, err = red:set_keepalive(pool_max_idle_time, pool_size)
        if not ok then
                red:close()
        end
end


function main()
	conn:set_timeout(2000)
	local ok = conn.connect(conn,host,port)
	if not ok then
		return -1
	end
	local ok,err = conn:auth(auth)
	if not ok then
		return -1
	end
	
	conn:select(db)
	-- 获取客户端ip
	local ip = get_client_ip()
	local uri = ngx.var.request_uri
	local scheme = ngx.var.scheme
	local headers = ngx.req.get_headers()
	local host = headers['host']
	local ua = headers['user-agent']
	local cookie = ngx.var.http_cookie
	local http_referer = ngx.var.http_referer

	local get_sogou_ip = conn:sismember('whitelist_sogou', ip)
	if tonumber(get_sogou_ip) == 1 then
                return 0
        end

	local get_baidu_ip = conn:sismember('whitelist_baidu', ip)
        if tonumber(get_baidu_ip) == 1 then
                return 0
        end

	local get_360_ip = conn:sismember('whitelist_360', ip)
        if tonumber(get_360_ip) == 1 then
                return 0
        end

	
	local get_yisou_ip = conn:sismember('whitelist_yisou', ip)
        if tonumber(get_360_ip) == 1 then
                return 0
        end


	local get_user_ip = conn:sismember('whitelist_user', ip)
        if tonumber(get_user_ip) == 1 then
                return 0
        end


	-- local resp = conn:sismember('whitelist', ip)
	-- -- 如果有，resp返回0，直接return 0 正常退出脚本，不再进行下面计算
	-- if tonumber(resp) == 1 then
	-- 	return 0
	-- end

	if ua == nil or host == nil then
		ngx.redirect('https://cap.169kang.com/sorry.html',302)
		return -1
	end

	
	local enterblk, err = conn:get('enterblk:' .. ip)
	if enterblk ~= ngx.null and  tonumber(enterblk) >= block_count then
 		ngx.redirect('https://cap.169kang.com/sorry.html',302)
		return -1
	end

	-- -- 如果ua是Sogou web spider，直接退出脚本
	-- if string.find(ua, 'Sogou web spider') or string.find(ua,'Baiduspider') then return 0 end
	-- if string.find(string.lower(ua),'360spider') or string.find(ua, 'YisouSpider') then return 0 end
	-- if string.find(ua, '360so') then return 0 end

	-- -- sogou ---
    	-- if 'Mozilla/5.0 (Linux; U; Android 4.1.1; zh-CN; GT-N7100 Build/JRO03C) AppleWebKit/534.31 (KHTML, like Gecko) UCBrowser/9.3.0.321 U3/0.8.0 Mobile Safari/534.31' == ua then return 0 end
	-- if 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0' == ua then return 0 end
	-- -- mip
	-- if 'Mozilla/5.0 (Linux;u;Android 4.2.2;zh-cn;) AppleWebKit/534.46 (KHTML,like Gecko) Version/5.1 Mobile Safari/10600.6.3 (compatible; baidumib;mip; + https://www.mipengine.org)' == ua then return 0 end

	-- 判断ip是否为黑名单, php删黑名单
	local isblk, err = conn:get('blk:' .. ip)
	if isblk ~= ngx.null then
		block_ip_2_cap(conn, ip)
		-- 是黑名单，跳转到其它页面
		local source = scheme .. "://" .. host .. uri
                local dest = "https://cap.169kang.com/index.php?continue=" .. source
                ngx.redirect(dest, 302)
		return -1
	end

	-- 获取分钟级访问次数，大于访问次数阈值就到黑名单，小于就继续+1
	local dd, err = conn:get("vis:dd:" .. ip)
	local hh, err = conn:get("vis:hh:" .. ip)
	local mm, err = conn:get("vis:mm:" .. ip)
	local ss, err = conn:get("vis:ss:" .. ip)

	-- 空referer
	local erdd, err = conn:get("er:dd:" .. ip)
	local erhh, err = conn:get("er:hh:" .. ip)
	local ermm, err = conn:get("er:mm:" .. ip)
	local erss, err = conn:get("er:ss:" .. ip)

	-- 只能从dd为空时，初始化化全部的key，不能从ss，因为当ss为空时，dd不一定为空，这样就不能初始化
	if dd == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'vis:ss:' .. ip, 1)
		init_keys(conn, 'vis:mm:' .. ip, 60)
		init_keys(conn, 'vis:hh:' .. ip, 3600)
		init_keys(conn, 'vis:dd:' .. ip, 24 * 3600)
		local res, err = conn:commit_pipeline()
		if res == ngx.null then
			return -1
		end
		-- 初始化要get下当前的值，不然下面取得值是一个get不能tonumber转换
		dd = conn:get("vis:dd:" .. ip)
		hh = conn:get("vis:hh:" .. ip)
		mm = conn:get("vis:mm:" .. ip)
		ss = conn:get("vis:ss:" .. ip)
	end	

	if erdd == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'er:ss:' .. ip, 1)
                init_keys(conn, 'er:mm:' .. ip, 60)
                init_keys(conn, 'er:hh:' .. ip, 3600)
                init_keys(conn, 'er:dd:' .. ip, 24 * 3600)
                local res, err = conn:commit_pipeline()
                if res == ngx.null then
                        return -1
                end
		erdd = conn:get("er:dd:" .. ip)
                erhh = conn:get("er:hh:" .. ip)
                ermm = conn:get("er:mm:" .. ip)
                erss = conn:get("er:ss:" .. ip)
	end

	if hh == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'vis:ss:' .. ip, 1)
		init_keys(conn, 'vis:mm:' .. ip, 60)
		init_keys(conn, 'vis:hh:' .. ip, 3600)
		res, err = conn:commit_pipeline()
		if res == ngx.null then
                        return -1
                end
		hh = conn:get("vis:hh:" .. ip)
		mm = conn:get("vis:mm:" .. ip)
                ss = conn:get("vis:ss:" .. ip)
	end	

	if erhh == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'er:ss:' .. ip, 1)
                init_keys(conn, 'er:mm:' .. ip, 60)
                init_keys(conn, 'er:hh:' .. ip, 3600)
                res, err = conn:commit_pipeline()
                if res == ngx.null then
                        return -1
                end
		erhh = conn:get("er:hh:" .. ip)
                ermm = conn:get("er:mm:" .. ip)
                erss = conn:get("er:ss:" .. ip)
	end

	if mm == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'vis:ss:' .. ip, 1)
		init_keys(conn, 'vis:mm:' .. ip, 60)
		res,err = conn:commit_pipeline()
		if res == ngx.null then
                        return -1
                end
		mm = conn:get("vis:mm:" .. ip)
		ss = conn:get("vis:ss:" .. ip)
	end	

	if ermm == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'er:ss:' .. ip, 1)
                init_keys(conn, 'er:mm:' .. ip, 60)
                res,err = conn:commit_pipeline()
                if res == ngx.null then
                        return -1
                end
		ermm = conn:get("er:mm:" .. ip)
                erss = conn:get("er:ss:" .. ip)
	end

	-- ss为空，dd不为空，这时候dd就不能初始化了，而是要+1
	if ss == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'vis:ss:' .. ip, 1)
		-- re
		init_keys(conn, 'er:ss:' .. ip, 1)
		res,err = conn:commit_pipeline()
		if res == ngx.null then
                        return -1
                end
		ss = conn:get("vis:ss:" .. ip)
	end	

	if erss == ngx.null then
		conn:init_pipeline()
		init_keys(conn, 'er:ss:' .. ip, 1)
                res,err = conn:commit_pipeline()
		if res == ngx.null then
                        return -1
                end
		erss = conn:get("er:ss:" .. ip)
	end

	-- 上面表示等于空，下面表示不等于空，即key已经有值了,是否大于阈值
	
	if tonumber(erss) >= er_mx_sec or tonumber(ermm) >= er_mx_min then
		flag = false
	end

	if tonumber(erhh) >= er_mx_hou then
                flag = false
        end



	if tonumber(ss) >= mx_sec or tonumber(mm) >= mx_min then
		flag = false	
	end

	if tonumber(hh) >= mx_hou then
		flag = false	
	end

	-- 如果大于天级阈值,直接不能访问
	if tonumber(dd) >= mx_day then
		conn:set("enterblk:" .. ip, block_count)
		conn:expire("enterblk:" .. ip, 24 * 3600)
		init_keys(conn, "vis:dd:" .. ip, 24 * 3600)
		init_keys(conn, "vis:hh:" .. ip, 3600)
		init_keys(conn, "vis:mm:" .. ip, 60)
		init_keys(conn, "vis:ss:" .. ip, 1)
		ngx.redirect('https://cap.169kang.com/sorry.html',302)
		return -1	
	end

	if tonumber(erdd) >= er_mx_day then
		flag = false
		-- conn:set("enterblk:" .. ip, block_count)
		-- conn:expire("enterblk:" .. ip, 24 * 3600)
		-- init_keys(conn, "er:dd:" .. ip, 24 * 3600)
		-- init_keys(conn, "er:hh:" .. ip, 3600)
		-- init_keys(conn, "er:mm:" .. ip, 60)
		-- init_keys(conn, "er:ss:" .. ip, 1)
		-- ngx.redirect('https://cap.169kang.com/sorry.html',302)
		-- return -1	
	end

	local accept_kind = headers['accept']
	-- accept_kind有可能会出现空的情况，没判断会出现500
	if flag then
		if not accept_kind or (accept_kind and (string.match(accept_kind, 'text/html') or accept_kind == '*/*')) or string.match(uri, '.html') then

			if http_referer == nil and cookie == nil then
				conn:incr('er:ss:' .. ip)
				conn:incr('er:mm:' .. ip)
				conn:incr('er:hh:' .. ip)
				conn:incr('er:dd:' .. ip)
        		end
			conn:init_pipeline()
			conn:incr('vis:ss:' .. ip)
			conn:incr('vis:mm:' .. ip)
			conn:incr('vis:hh:' .. ip)
			conn:incr('vis:dd:' .. ip)
			local respTable ,err = conn:commit_pipeline()
			if respTable == ngx.null then
				return -1
			end
		end

	else 
		block_ip_2_cap(conn, ip)
		-- 黑名单累计
		local enterblk_ip = conn:get('enterblk:' .. ip)
		if enterblk_ip == ngx.null then
			init_keys(conn, 'enterblk:' .. ip, 24 * 3600)
		else
			conn:incr('enterblk:' .. ip)
		end
                return -1
	end
	return -1
	
end

local status = main()
close_redis(conn)
