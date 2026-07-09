local PLUGIN_NAME = "api-version"

local http = require("resty.http")

describe(PLUGIN_NAME .. ": (unit)", function()

  local plugin, config
  local auth_server_url, request_header_name, request_header_value
  local upstream_jwt_header_name
  local upstream_jwt_header_value
  local exited_status

  local fake_request_header_value= "fake-client-token" 
  local fake_jwt = "fake-jwt-token"
  local time = 0

  local old_kong
  local old_http_new

  setup(function()
    old_kong = _G.kong
    old_http_new = http.new

    _G.kong = {  
      log = {
        inspect = function(...) print(...) end, 
        err = function(...) print("ERROR: ", ...) end
      },
      
      request = {
        get_header = function(name)
          return fake_request_header_value
        end
      },
      
      service = {
        request = {
          set_header = function(name, val)
            upstream_jwt_header_name = name
            upstream_jwt_header_value = val
          end,
          get_header = function(name)
          end
        },
      },
      
      response = {
        set_header = function(name, val)
        end,
        exit = function(status, body)
          exited_status = status
        end
      },

      cache = {
        get = function(key, opts, cb, ...)
          if config.cache_ttl and time >= config.cache_ttl then 
            return { status = 200, jwt = fake_jwt .. "-cache"}, nil
          else 
            return { status = 200, jwt = fake_jwt}, nil
          end
        end
      },

    }

    local mock_httpc = {
        request_uri = function(self, uri, params)
          auth_server_url = uri
          request_header_value = params.headers[config.request_header_name]
            return {
                status = 200,
                body = '{"jwt": "fake-jwt-token"}'
            }, nil
        end
    }
    
    local http = require("resty.http")
    http.new = function() return mock_httpc end

    plugin = require("kong.plugins."..PLUGIN_NAME..".handler")
  end)

  teardown(function()
    _G.kong = old_kong
    http.new = old_http_new
  end)

  before_each(function()
    exited_status = nil
    auth_server_url = nil
    request_header_value = nil
    upstream_jwt_header_name = nil
    upstream_jwt_header_value = nil
    time = 0

    config = {
      auth_server_url = "http://localhost:8000",
      request_header_name = "Authorization",
    }
  end)

  it("normal request", function()
    plugin:access(config)
    
    assert.is_nil(exited_status) 
    assert.is_same(auth_server_url, config.auth_server_url) 
    assert.is_same(request_header_value, fake_request_header_value) 
  end)

  it("normal request with request_header_value", function()
    config.request_header_value = "request_header_value"
    plugin:access(config)
    
    assert.is_nil(exited_status) 
    assert.is_same(auth_server_url, config.auth_server_url) 
    assert.is_same(request_header_value, config.request_header_value) 
  end)

  it("normal request with upstream_jwt_header_name", function()
    config.upstream_jwt_header_name = "X-Upstream-Jwt"
    plugin:access(config)
    
    assert.is_nil(exited_status) 
    assert.is_same(upstream_jwt_header_name, config.upstream_jwt_header_name) 
    assert.is_same(upstream_jwt_header_value, fake_jwt) 
  end)

  it("normal request with cache_ttl", function()
    config.cache_ttl = 10
    config.upstream_jwt_header_name = "X-Upstream-Jwt"
    plugin:access(config)
    
    assert.is_nil(exited_status) 
    assert.is_same(upstream_jwt_header_value, fake_jwt) 

    time = 10
    plugin:access(config)
    assert.is_nil(exited_status) 
    assert.is_same(upstream_jwt_header_value, fake_jwt .. "-cache") 

  end)
end)