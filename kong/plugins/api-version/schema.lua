local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "api-version"


local schema = {
  name = PLUGIN_NAME,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          {  auth_server_url = typedefs.url {
                required = true,
            }},
          {
            request_header_name = typedefs.header_name {
                required = true,
            }},
          {
            request_header_value = {
                type = "string",
                required = false,
            }},
          {
            cache_ttl = {
                type = "integer",
                default = 0,
                required = false,
            }},
          {
            upstream_jwt_header_name = {
                type = "string",
                default = "X-JWT",
                required = false,
            }},
        },
      },
    },
  },
}

return schema
