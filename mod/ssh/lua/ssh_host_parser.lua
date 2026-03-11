local Parser = {}

local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function Parser.parse(input)
    local text = trim(input)
    if text == "" then
        return nil, "主机地址不能为空，使用 user@host:port"
    end

    local user, host, portText = text:match("^([^@%s]+)@([^:%s]+):?(%d*)$")
    if not user or not host then
        return nil, "格式错误，使用 user@host:port，例如 jax@192.168.31.43:22"
    end

    local port = tonumber(portText ~= "" and portText or "22")
    if not port or port < 1 or port > 65535 then
        return nil, "端口号无效，范围应为 1-65535"
    end

    local endpoint = string.format("%s@%s:%d", user, host, port)
    return {
        endpoint = endpoint,
        name = endpoint,
        user = user,
        host = host,
        port = port,
    }
end

return Parser
