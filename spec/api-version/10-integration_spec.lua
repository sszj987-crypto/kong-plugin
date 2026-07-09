local helpers = require "spec.helpers"
local PLUGIN_NAME = "api-version"

for _, strategy in helpers.all_strategies() do if strategy == "postgres" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      local mock_auth_route = bp.routes:insert({ paths = { "/mock-auth" } })
      bp.plugins:insert({
        name = "pre-function",
        route = { id = mock_auth_route.id },
        config = {
          access = {
            [[
              local headers = ngx.req.get_headers()
              if headers["authorization"] == "fake-client-token" then
                ngx.status = 200
                ngx.header.content_type = "application/json"
                local dynamic_jwt = "jwt-token-" .. tostring(ngx.now())
                ngx.say('{"jwt": "' .. dynamic_jwt .. '"}')
                return ngx.exit(200)
              else
                ngx.status = 403 
                return ngx.exit(403)
              end
            ]]
          }
        }
      })

      local route1 = bp.routes:insert({ hosts = { "test1.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          auth_server_url = "http://127.0.0.1:9000/mock-auth",
          request_header_name = "Authorization",
        },
      }

      local route2 = bp.routes:insert({ hosts = { "test2.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          auth_server_url = "http://127.0.0.1:9000/mock-auth",
          request_header_name = "Authorization",
          request_header_value = "fixed-request-header-value",
        },
      }

      local route3 = bp.routes:insert({ hosts = { "test3.com" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route3.id },
        config = {
          auth_server_url = "http://127.0.0.1:9000/mock-auth",
          request_header_name = "Authorization",
          upstream_jwt_header_name = "X-Upstream-Jwt",
        },
      }

      local route4 = bp.routes:insert({ 
        hosts = { "test4.com" } 
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route4.id },
        config = {
          auth_server_url = "http://127.0.0.1:9000/mock-auth",
          request_header_name = "Authorization",
          upstream_jwt_header_name = "X-Upstream-Jwt", 
          cache_ttl = 1, 
        },
      }

      -- start kong
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME .. ",pre-function",
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      pcall(helpers.stop_kong)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    it("normal request", function()
      local r = client:get("/request", {
        headers = {
          host = "test1.com",
          ["Authorization"] = "fake-client-token"
        }
      })
      assert.response(r).has.status(200)
    end)

    it("abnormal request without request_header_name", function()
      local r = client:get("/request", {
        headers = {
          host = "test2.com"
        }
      })
      assert.response(r).has.status(401)
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
      assert.is_not.is_nil(injected_jwt)
    end)

    it("normal request with cache_ttl", function()
        local r1 = client:get("/request", {
          headers = { host = "test4.com", ["Authorization"] = "fake-client-token" }
        })
        assert.response(r1).has.status(200)
        local jwt1 = assert.request(r1).has.header("X-Upstream-Jwt")
        
        local r2 = client:get("/request", {
          headers = { host = "test4.com", ["Authorization"] = "fake-client-token" }
        })
        assert.response(r2).has.status(200)
        local jwt2 = assert.request(r2).has.header("X-Upstream-Jwt")

        assert.equal(jwt1, jwt2)

        local socket = require("socket")
        socket.sleep(2)

        local r3 = client:get("/request", {
          headers = { host = "test4.com", ["Authorization"] = "fake-client-token" }
        })
        assert.response(r3).has.status(200)
        local jwt3 = assert.request(r3).has.header("X-Upstream-Jwt")

        assert.not_equal(jwt1, jwt3)
      end)

  end)

end end