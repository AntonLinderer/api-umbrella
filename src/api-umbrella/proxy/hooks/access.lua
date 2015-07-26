local start_time = ngx.now()

-- Try to find the matching API backend first, since it dictates further
-- settings and requirements.
local api = ngx.ctx.matched_api
if not api then
  return true
end

local api_key_validator = require "api-umbrella.proxy.middleware.api_key_validator"
local api_settings = require "api-umbrella.proxy.middleware.api_settings"
local error_handler = require "api-umbrella.proxy.error_handler"
local https_validator = require "api-umbrella.proxy.middleware.https_validator"
local ip_validator = require "api-umbrella.proxy.middleware.ip_validator"
local rate_limit = require "api-umbrella.proxy.middleware.rate_limit"
local referer_validator = require "api-umbrella.proxy.middleware.referer_validator"
local rewrite_request = require "api-umbrella.proxy.middleware.rewrite_request"
local role_validator = require "api-umbrella.proxy.middleware.role_validator"
local user_settings = require "api-umbrella.proxy.middleware.user_settings"
local utils = require "api-umbrella.proxy.utils"

-- Fetch the settings from the matched API.
local settings, err = api_settings(api)
if err then
  return error_handler(err, settings)
end

-- Validate the API key that's passed in, if this API requires API keys.
local user, err = api_key_validator(settings)
if err then
  return error_handler(err, settings)
end

-- Fetch and merge any user-specific settings.
local err = user_settings(settings, user)
if err then
  return error_handler(err, settings)
end

-- If this API requires access over HTTPS, verify that it's happening.
local err, err_data = https_validator(settings, user)
if err then
  return error_handler(err, settings, err_data)
end

-- If this API requires roles, verify that the user has those.
local err = role_validator(settings, user)
if err then
  return error_handler(err, settings)
end

-- If this API or user requires the traffic come from certain IP addresses,
-- verify those.
local err = ip_validator(settings, user)
if err then
  return error_handler(err, settings)
end

-- If this API or user requires the traffic come from certain HTTP referers,
-- verify those.
local err = referer_validator(settings, user)
if err then
  return error_handler(err, settings)
end

-- If we've gotten this far, it means the user is authorized to access this
-- API, so apply the rate limits for this user and API.
local err = rate_limit(settings, user)
if err then
  return error_handler(err, settings)
end

-- Perform any request rewriting.
local err = rewrite_request(user, api, settings)
if err then
  return error_handler(err, settings)
end

-- Store the settings for use by the header_filter.
ngx.ctx.settings = settings

-- Compute how much time we spent in Lua processing during this phase of the
-- request.
utils.overhead_timer(start_time)
