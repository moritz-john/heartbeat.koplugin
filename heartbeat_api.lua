local http = require("socket.http")
local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")

local API = {}

--- Executes a REST request to Home Assistant
-- Only POST requests include service_data / request_body / source
function API:performRequest(url, token, service_data)
    http.TIMEOUT = 6 -- in seconds

    local request_body = rapidjson.encode(service_data)
    local response_body = {}

    -- result, status code, headers, status line
    local result, code = http.request {
        url = url,
        method = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. token,
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    }

    local raw_response = table.concat(response_body)

    -- Error Handling
    if result == nil then
        -- e.g. code =  "connection refused" or "timeout"
        return true, tostring(code)
    elseif code ~= 200 and code ~= 201 then
        -- e.g. code = 400, raw_response = "400: Bad Request" or JSON {error message}
        return true, tostring(code .. " | Server Response:\n" .. raw_response)
    end

    -- Success
    return false, ""
end

return API
