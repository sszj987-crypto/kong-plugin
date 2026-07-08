local helpers = require "spec.helpers"
local PLUGIN_NAME = "api-version"

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      local route1 = bp.routes:insert({ hosts = { "test1.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          auth_server_url = "http://httpbin.org/status/200", -- 使用 httpbin 模拟 200 成功响应
          request_header_name = "Authorization",
        },
      }

      local route2 = bp.routes:insert({ hosts = { "test2.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          auth_server_url = "http://httpbin.org/status/200",
          request_header_name = "Authorization",
          request_header_value = "fixed-request-header-value",
        },
      }

      local route3 = bp.routes:insert({ hosts = { "test3.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = {
          auth_server_url = "http://httpbin.org/status/200",
          request_header_name = "Authorization",
          upstream_jwt_header_name = "X-Upstream-Jwt",
        },
      }

      local route4 = bp.routes:insert({ hosts = { "test4.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route4.id },
        config = {
          auth_server_url = "http://httpbin.org/status/200",
          request_header_name = "Authorization",
          upstream_jwt_header_name = "X-Upstream-Jwt",
          cache_ttl = 1,
        },
      }

      -- start kong
      assert(helpers.start_kong({
        database   = strategy,
        plugins = "bundled," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("request logic validation", function()
      
      it("normal request", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Authorization"] = "fake-client-token"
          }
        })
        assert.response(r).has.status(200)
      end)

      it("normal request with request_header_value", function()
        local r = client:get("/request", {
          headers = {
            host = "test2.com"
          }
        })
        assert.response(r).has.status(200)
      end)

      it("normal request with upstream_jwt_header_name", function()
        local r = client:get("/request", {
          headers = {
            host = "test3.com",
            ["Authorization"] = "fake-client-token"
          }
        })
        assert.response(r).has.status(200)
        
        local injected_jwt = assert.request(r).has.header("X-Upstream-Jwt")
        assert.is_not_nil(injected_jwt)
      end)

      it("normal request with cache_ttl", function()
        local r1 = client:get("/request", {
          headers = {
            host = "test4.com",
            ["Authorization"] = "fake-client-token"
          }
        })
        assert.response(r1).has.status(200)

        time.sleep(2)
        local r2 = client:get("/request", {
          headers = {
            host = "test4.com",
            ["Authorization"] = "fake-client-token"
          }
        })
        assert.response(r2).has.status(200)
      end)

    end)

  end)

end end