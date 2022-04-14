local url = require "socket.url"

local string_format = string.format

local kong_response = kong.response

local get_headers = ngx.req.get_headers
local get_method = ngx.req.get_method
local ngx_re_match = ngx.re.match
local ngx_re_find = ngx.re.find

local HTTP = "http"
local HTTPS = "https"

local function parse_url(host_url)
    local parsed_url = url.parse(host_url)
    if not parsed_url.port then
        if parsed_url.scheme == HTTP then
            parsed_url.port = 80
         elseif parsed_url.scheme == HTTPS then
            parsed_url.port = 443
         end
    end
    if not parsed_url.path then
        parsed_url.path = "/"
    end
    return parsed_url
end

local function compose_payload(parsed_url, forward_headers)
    local headers = get_headers()
    local target_method = ngx.var.request_method
    local target_uri = ngx.var.request_uri

    -- header payload
    local headers_payload = ""
    for header, value in pairs(headers) do
        if forward_headers[header] ~= nil then
            headers_payload = headers_payload .. header .. ": " .. value .. "\r\n"
        end
    end

    -- biuld url: path + query
    local url
    if parsed_url.query then
        url = parsed_url.path .. "?" .. parsed_url.query
    else
        url = parsed_url.path
    end

    return string_format(
        "%s %s%s HTTP/1.1\r\n%s\r\n",
        target_method, url, target_uri, headers_payload)
end

-- headers_table takes array a and build hash table where key is lower-cased
-- element from array and value is true
local function headers_table(a)
    local hash = {}
    for _, v in ipairs(a) do
        hash[string.lower(v)] = true
    end
    return hash
end

return function(self, conf)
    if not conf.run_on_preflight and get_method() == "OPTIONS" then
        return
    end

    local name = "[oathkeeper] "
    local ok, err
    local parsed_url = parse_url(conf.url)
    local host = parsed_url.host
    local port = tonumber(parsed_url.port)
    local forward_headers = headers_table(conf.forward_headers)
    local return_headers = headers_table(conf.return_headers)

    -- Host is required header in OathKeeper
    if forward_headers["host"] == nil then
        forward_headers["host"] = true
    end

    local payload = compose_payload(parsed_url, forward_headers)

    local sock = ngx.socket.tcp()
    sock:settimeout(conf.timeout)

    ok, err = sock:connect(host, port)
    if not ok then
        ngx.log(ngx.ERR, name .. "failed to connect to " .. host .. ":" .. tostring(port) .. ": ", err)
        return kong.response.exit(500, {
            code = 500,
            message = "failed to connect to auth middleware"
        })
    end

    if parsed_url.scheme == HTTPS then
        local _, err = sock:sslhandshake(true, host, false)
        if err then
            ngx.log(ngx.ERR, name .. "failed to do SSL handshake with " .. host .. ":" .. tostring(port) .. ": ", err)
            return kong.response.exit(500, {
                code = 500,
                message = "failed to do SSL handshake with auth middleware"
            })
        end
    end

    ok, err = sock:send(payload)
    if not ok then
        ngx.log(ngx.ERR, name .. "failed to send data to " .. host .. ":" .. tostring(port) .. ": ", err)
        return kong.response.exit(500, {
            code = 500,
            message = "failed to send data to auth middleware"
        })
    end
    if conf.debug then
        print("\n***\nsent payload:\n" .. payload .. "\n***\n")
    end

    local line, err = sock:receive("*l")

    if err then 
        ngx.log(ngx.ERR, name .. "failed to read response status from " .. host .. ":" .. tostring(port) .. ": ", err)
        return kong.response.exit(500, {
            code = 500,
            message = "failed to read response status from auth middleware"
        })
    end
    if conf.debug then
        print("\n***\nreceived first line:\n" .. line .. "\n***\n")
    end
    
    -- status code
    local status_code = tonumber(string.match(line, "%s(%d%d%d)%s"))

    -- headers
    local headers = {}
    repeat
        line, err = sock:receive("*l")
        if err then
            ngx.log(ngx.ERR, name .. "failed to read header " .. host .. ":" .. tostring(port) .. ": ", err)
            return kong.response.exit(500, {
                code = 500,
                message = "failed to read header from auth middleware"
            })
        end

        local pair = ngx_re_match(line, "(.*?):\\s*(.*)", "jo")

        if pair then
            local key = string.lower(pair[1])
            headers[key] = pair[2]
            if return_headers[key] ~= nil then
                kong.service.request.set_header(pair[1], pair[2])
                if conf.debug then
                    print(line)
                end
            end
        end
    until ngx_re_find(line, "^\\s*$", "jo")
    
    -- body
    local body
    if headers['content-length'] ~= nil then
        body, err = sock:receive(tonumber(headers['content-length']))
        if err then
            ngx.log(ngx.ERR, name .. "failed to read body " .. host .. ":" .. tostring(port) .. ": ", err)
            return kong.response.exit(500, {
                code = 500,
                message = "failed to read body from auth middleware"
            })
        end
    end

    if status_code > 299 then
        if not body then
            body = ""
        end
        return kong.response.exit(status_code, body, headers)
    end
end