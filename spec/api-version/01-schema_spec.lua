local PLUGIN_NAME = "api-version"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("accepts with request_header_name and auth_server_url", function()
    local ok, err = validate({
        request_header_name = "test_name",
        auth_server_url = "http://127.0.0.1",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does not accepts without auth_server_url", function()
    local ok, err = validate({
        request_header_name = "test_name",
      })
    assert.is(err)
    assert.is_falsy(ok)
  end)

    it("does not accepts without request_header_name", function()
    local ok, err = validate({
        auth_server_url = "http://127.0.0.1",
      })
    assert.is(err)
    assert.is_falsy(ok)
  end)
end)
