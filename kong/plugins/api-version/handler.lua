-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.

--assert(ngx.get_phase() == "timer", "The world is coming to an end!")

---------------------------------------------------------------------------------------------
-- In the code below, just remove the opening brackets; `[[` to enable a specific handler
--
-- The handlers are based on the OpenResty handlers, see the OpenResty docs for details
-- on when exactly they are invoked and what limitations each handler has.
---------------------------------------------------------------------------------------------

local resty_sha256 = require "resty.sha256"
local str = require "resty.string"
local http = require "resty.http"
local cjson = require "cjson"

local plugin = {
  PRIORITY = 1000, -- set the plugin priority, which determines plugin execution order
  VERSION = "0.1", -- version in X.Y.Z format. Check hybrid-mode compatibility requirements.
}



-- do initialization here, any module level code runs in the 'init_by_lua_block',
-- before worker processes are forked. So anything you add here will run once,
-- but be available in all workers.



-- handles more initialization, but AFTER the worker process has been forked/created.
-- It runs in the 'init_worker_by_lua_block'
function plugin:init_worker()

  -- your custom code here
  kong.log.debug("saying hi from the 'init_worker' handler")

end --]]


---[[ Executed every time a plugin config changes.
-- This can run in the `init_worker` or `timer` phase.
-- @param configs table|nil A table with all the plugin configs of this plugin type.
function plugin:configure(configs)
  kong.log.notice("saying hi from the 'configure' handler, got ", (configs and #configs or 0)," configs")

  if configs == nil then
    return -- no configs, nothing to do
  end

  -- your custom code here

end --]]


--[[ runs in the 'ssl_certificate_by_lua_block'
-- IMPORTANT: during the `certificate` phase neither `route`, `service`, nor `consumer`
-- will have been identified, hence this handler will only be executed if the plugin is
-- configured as a global plugin!
function plugin:certificate(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'certificate' handler")

end --]]



--[[ runs in the 'rewrite_by_lua_block'
-- IMPORTANT: during the `rewrite` phase neither `route`, `service`, nor `consumer`
-- will have been identified, hence this handler will only be executed if the plugin is
-- configured as a global plugin!
function plugin:rewrite(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'rewrite' handler")

end --]]



local function fetch_remote_auth(url, header_name, header_value)
  local httpc = http.new()
  
  local res, err = httpc:request_uri(url, {
    method = "GET",
    headers = {
      [header_name] = header_value
    }
  })
  if not res then
    kong.log.err("Failed to request_uri err: ", err)
    return nil, err
  end

  local jwt_token
  if res.status == 200 and res.body then
    local body_json = cjson.decode(res.body)
    if body_json and body_json.jwt then
      jwt_token = body_json.jwt
    end
  end

  return {
    status = res.status,
    jwt = jwt_token
  }
end

-- runs in the 'access_by_lua_block'
function plugin:access(plugin_conf)

  kong.log.inspect(plugin_conf)   -- check the logs for a pretty-printed config!

  local auth_result, err

  local request_header_value = kong.request.get_header(plugin_conf.request_header_name)
  if not request_header_value then
    return kong.response.exit(401, { message = "Missing authentication header" })
  end

  -- 可选1: 需求没有讲清楚这个配置的作用，存在多种理解，1黑白名单：只允许某些值的用户不通过或通过；2：默认配置：开启后默认使用配置；
  -- 如果配置了request_header_value，强行替换；
  if plugin_conf.request_header_value then 
    request_header_value = plugin_conf.request_header_value
  end
  
  -- 可选3: 开启cache_ttl，缓存鉴权响应
  if plugin_conf.cache_ttl and plugin_conf.cache_ttl > 0 then
    local sha256 = resty_sha256:new()
    sha256:update(request_header_value)
    local digest = sha256:final()
    local request_header_val_sha256 = str.to_hex(digest)

    local cache_key = "request_header_val_sha256_cache:" .. request_header_val_sha256
    
    auth_result, err = kong.cache:get(
      cache_key, 
      { ttl = plugin_conf.cache_ttl }, 
      fetch_remote_auth, 
      plugin_conf.auth_server_url, 
      plugin_conf.request_header_name, 
      request_header_value
    )
  else
    auth_result, err = fetch_remote_auth(
      plugin_conf.auth_server_url, 
      plugin_conf.request_header_name, 
      request_header_value
    )
  end
  
  if err then
    kong.log.err("Failed to reach auth server: ", err)
    return kong.response.exit(500, { message = "Internal Server Error" })
  end

  if auth_result.status ~= 200 then
    local reject_status = (auth_result.status >= 400 and auth_result.status < 500) and auth_result.status or 401
    return kong.response.exit(reject_status, { message = "Unauthorized by remote server" })
  end

  -- 可选4: 响应带了jwt
  if plugin_conf.upstream_jwt_header_name and auth_result.jwt then
    kong.service.request.set_header(plugin_conf.upstream_jwt_header_name, auth_result.jwt)
  end


end


-- runs in the 'header_filter_by_lua_block'
function plugin:header_filter(plugin_conf)

  -- your custom code here, for example;
  kong.response.set_header(plugin_conf.response_header, "this is on the response")

end --]]


--[[ runs in the 'body_filter_by_lua_block'
function plugin:body_filter(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'body_filter' handler")

end --]]


--[[ runs in the 'log_by_lua_block'
function plugin:log(plugin_conf)

  -- your custom code here
  kong.log.debug("saying hi from the 'log' handler")

end --]]


-- return our plugin object
return plugin
