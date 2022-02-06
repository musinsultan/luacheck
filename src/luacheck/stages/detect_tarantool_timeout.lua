local stage = {}

local module_name = {}
-- module_name = {
--    "net.box" = {
--        [0] = "net_box",
--        ["connect"] = "conn"
--   }
-- }
local temp_name = ""

stage.warnings = {
    ["1001"] = { message_format = "Tarantool timeout error", fields = {} }
}

local modules = {
    ["net.box"] = {
        ["self"] = {[0] = {"connect", "ping", "wait_connected", "wait_state", "call", "request"}}, --net.box.self:connect
        ["connect"] = {
            [0] = {"ping", "wait_connected", "wait_state", "call", "request"},
            ["space"] = {
                ["*"] = {[0] = {"testspace"}} -- connect.space.<spacename>.testspace({timeout=})
            }
        }
    },
    ["fiber"] = {
        ["channel"] = {[0] = {"get", "put"}}, -- ie fiber.channel:put
        ["cond"] = {[0] = {"wait"}}
    },
    ["socket"] = {
        [0] = {"tcp_connect", "getdrinfo", "tcp_server", "iowait"},
    --    ["socket"] = {[0] = {"read", "readable", "writeable", "wait"}} -- ?????? socket_object = socket(*argv)
    }
}

--__--__--__--__--__--__
-- For debug only
--__--__--__--__--__--__
local function tprint (tbl, indent)
    if type(tbl) == "boolean" then 
        return tbl
    end
    if not indent then indent = 0 end
    local toprint = string.rep(" ", indent) .. "{\r\n"
    indent = indent + 2 
    for k, v in pairs(tbl) do
        toprint = toprint .. string.rep(" ", indent)
      if (type(k) == "number") then
        toprint = toprint .. "[" .. k .. "] = "
      elseif (type(k) == "string") then
        toprint = toprint  .. k ..  "= "   
      end
      if (type(v) == "number") then
        toprint = toprint .. v .. ",\r\n"
      elseif (type(v) == "string") then
        toprint = toprint .. "\"" .. v .. "\",\r\n"
      elseif (type(v) == "table") then
        toprint = toprint .. tprint(v, indent + 2) .. ",\r\n"
      else
        toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
      end
    end
    toprint = toprint .. string.rep(" ", indent-2) .. "}"
    return toprint
  end
  --__--__--__--__--__--__

local function find_timeout(chstate, node, index_id)
    if node[index_id+1] then
        for j = index_id + 1, #node do
            local tablenode = node[j]
            if tablenode.tag == "Table" then
                for k = 1, #tablenode do
                    if tablenode[k][1][1] == "timeout" then
                        return
                    end
                end
            end
        end
    end
    chstate:warn("1001", node.line, 1,2)
end

local function find_netbox_methods(chstate, node, index_id, netbox_id)
    local selfnode = node[index_id][netbox_id + 1]
    if selfnode and selfnode[1] == "self" then
        for i = index_id + 1, #node do
            local funcnode = node[i]
            if funcnode.tag == "String" and funcnode[1] == "ping" then
                find_timeout(chstate, node, i)
            end
        end
    end
end

local function find_node_with_module(chstate, node)
    -- Нужно сделать рекурсивно, до появления последней функции ???
    -- например, net_box.self:ping(), net_box.connect.space.<>.testspace()
    -- 2) При вызове функции на любой из объектов (module_name) проверять имя функции в массиве (modules[?]...[?][0]) и
    --    отправлять на ф-ию выше для проверки timeout

    if node.tag == "Invoke" then
        for i = 1, #node do
            local node_invoke = node[i]
            if node_invoke.tag == "Index" then
                for j = 1, #node_invoke do
                    local node_index = node_invoke[j]
                    if node_index.tag == "Id" then
                        if node_index[1] == module_name then
                            find_netbox_methods(chstate, node, i, j)
                        else
                            break
                        end
                    end
                end
            end
        end
    end
end

local function deep_search_in_array(reqvalue, array, toreturn)
    for ind,val in pairs(array) do
        table.insert(toreturn, ind)
        if type(val) == "string" then
            if val == reqvalue then
                return toreturn
            end
            else if type(val) == "table" then
                return deep_search_in_array(reqvalue, val, toreturn)
            end
        end
    end
    return false
end

local function is_value_in_module_name(reqvalue)
    for module, arModule in pairs(module_name) do
        local t = deep_search_in_array(reqvalue, arModule, {})
        if t then
            table.insert(t, 1, module)
            table.remove(t, #t)
            return t
        end
    end
    return false
end

local function detect_in_nodes(chstate, nodes)
    -- Если объявляется новая переменная, ее имя запоминается в temp_name, если в нее записывается require нужного
    -- модуля (из ключей modules) то имя записывается в module_name[название модуля][0]

    -- Нужно запоминать новые переменные, хранящие в себе интересующие объекты (если метод, возвращающий объект есть в ключах 
    --    соответствующего массива, независимо от уровня вложенности.)
    for _, node in ipairs(nodes) do
        -- print(tprint(module_name))
        -- print(tprint(is_value_in_module_name('net_box')))
        if node.tag == "Id" then
            temp_name = node[1]
        end
        if node.tag == "Call"  then
            if node[1][1] == "require" and modules[node[2][1]] then
                module_name[node[2][1]] = {[0] = temp_name}
                temp_name = ""
            end
            if is_value_in_module_name(node[1][1]) then
            --    if node[2][1] есть в ключах массива modules на уровне вложенности node[1][1]
            -- записать temp_name + проверить вызовы функций дальше
            end
        end
        if module_name ~= {} then
            find_node_with_module(chstate, node)
        end
    end
end

-----------------------------
-- Ниже менять ничего не надо
-----------------------------

local function detect_in_line(chstate, line)
    for _, item in ipairs(line.items) do
        if item.tag == "Eval" then
            find_node_with_module(chstate, item.node)
        elseif item.tag == "Local" then
            if item.rhs then
                detect_in_nodes(chstate, item.rhs)
            end
        elseif item.tag == "Set" then
            detect_in_nodes(chstate, item.lhs)
            detect_in_nodes(chstate, item.rhs)
        end
    end
end

function stage.run(chstate)
    for _, line in ipairs(chstate.lines) do
        detect_in_line(chstate, line)
    end
end

return stage