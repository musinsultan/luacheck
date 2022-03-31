local stage = {}

local function timeout_message_format(warning)
    return "Timeout is required for \"{funcname}\" of module \"{modulename}\""
 end
 stage.warnings = {
    ["1001"] = {message_format = timeout_message_format,
       fields = {"funcname", "modulename"}}
 }
local function warn_timeout(chstate, node, funcname, modulename)
    chstate:warn("1001", node.line, 1, 2, {
       funcname = funcname,
       modulename = modulename
    })
 end

local modules = {
    ["net.box"] = {
        [1] = {"connect"}, -- net_box.connect({timeout})
        ["self"] = {[0] = {"connect", "ping", "wait_connected", "wait_state", "call", "request"}}, --net_box.self:connect()
        ["connect"] = {
            [0] = {"ping", "wait_connected", "wait_state", "call", "request"}, -- net_box.connect:ping()
            [1] = {"space"},    -- net_box.connect.space() 
            ["space"] = {
                ["*"] = {[1] = {"testspace"}} -- net_box.connect.space.<spacename>.testspace({timeout=})
            }
        }
    },
    ["fiber"] = {
        ["channel"] = {[0] = {"get", "put"}}, -- ie fiber.channel:put
        ["cond"] = {[0] = {"wait"}}
    },
    ["socket"] = { 
        [0] = {"tcp_connect", "getdrinfo", "tcp_server", "iowait"},
        -- ["socket"] = {[0] = {"read", "readable", "writeable", "wait"}} --  socket_object = socket(*argv)
    },
    ["vshard"] = {
        ["router"] = {
            [1] = {"call", "callro", "callrw", "callre", "callbro", "callbre"}  -- vshard.router.call({timeout})
        }
    }
}


-- local temp_name = ""
local temp_node = {}
local module_name = {}
-- module_name = {
--    "net.box" = {
--        [0] = "net_box",
--        ["connect"] = "conn"
--   }
-- }

local function shallow_copy(t)
    local t2 = {}
    for k,v in pairs(t) do
      t2[k] = v
    end
    return t2
  end

local function set_value_to_array_keys(array, value, keys)
    -- Устанавливает значение элемента массива array по набору ключей keys
    -- array[keys[1]][keys[2]]... = value
    local copykeys = shallow_copy(keys)
    for ind, val in pairs(copykeys) do
        if #copykeys == 1 then
            array[copykeys[1]] = value
            return value
        end
        if array[val] then
            table.remove(copykeys, ind)
            return set_value_to_array_keys(array[val], value, copykeys)
        else
            array[table.remove(copykeys, ind)] = {}
            return set_value_to_array_keys(array[val], value, copykeys)
        end
    end
end

local function get_value_from_keys_array(array, keys)
    -- Возвращает значение элемента массива array по ключам keys 
    -- array[keys[1]][keys[2]]...
    local copykeys = shallow_copy(keys)
    if #copykeys == 1 then
        return array[copykeys[1]]
    else
        if array[copykeys[1]] then
            return get_value_from_keys_array(array[table.remove(copykeys,1)], copykeys)
        end
        return false
    end
end

local function deep_search_in_array(reqvalue, array, toreturn)
    -- Рекурсивный поиск значения (строкового) в массиве. Возвращает массив из ключей до искомого значения
    -- false, если не нашлось
    for ind,val in pairs(array) do
        table.insert(toreturn, ind)
        if type(val) == "string" then
            if val == reqvalue then
                return toreturn
            end
        else 
            if type(val) == "table" then
                return deep_search_in_array(reqvalue, val, toreturn)
            end
        end
        table.remove(toreturn, #toreturn)
    end
    return false
end

local function is_value_in_module_name(reqvalue)
    -- Возвращает массив из последовательных ключей до имени переменной в массиве module_name
    -- false если не нашлось
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

local function get_call_chain(node, chain, pars)
    --Возвращает массив с цепочкой вызова через точку (net_box.connect ...)
    -- К pars можно обратиться, она хранит в себе параметры вызова функций (кроме последней)
    -- по тем же индексам
    if node.tag == "Call" then
        for i = 2,#node do
            if node[i] then
                if node[i].tag == 'Table' then
                    pars[#chain+1] = node[i]
                end 
            end
        end
        return get_call_chain(node[1], chain, pars)
    end
    if node.tag == "Index" then
        table.insert(chain, 1, node[2][1])
        return get_call_chain(node[1], chain, pars)
    end
    table.insert(chain, 1, node[1])
    local p2 = {}
    for i=1,#chain do
        p2[i] = pars[#chain-i+1]
    end
    for i=1,#chain do
        pars[i] = p2[i]
    end
    return chain
end

local function checkrest(nodes, node_index)
    
end

local function check_calls_for_timeout(chstate, nodes, node_index, node, chain, pars, is_last)
    local el = table.remove(chain,#chain)
    table.insert(chain, 1)  -- проверяем вызовы через точку, поэтому индекс 1 (net_box.connect({timeout=}))
    local funcs = get_value_from_keys_array(modules, chain)
    if funcs then
        if deep_search_in_array(el, funcs, {}) then
            if not is_last then -- Не последний элемент в строке
                if not pars[#chain] or not deep_search_in_array("timeout", pars[#chain], {})then
                    warn_timeout(chstate, node, el, chain[1])
                end
            else
                if not nodes[node_index+1] then -- Последний в строке, параметров нет
                    if not pars[#chain] or not deep_search_in_array("timeout", pars[#chain], {})then
                        warn_timeout(chstate, node, el, chain[1])
                    end
                else    -- Есть параметры, но таймаута нет
                    if nodes[node_index+1].tag == "String" then
                        -- Чекнуть параметр для последнего объекта перед двоеточием
                        if not pars[#chain] or not deep_search_in_array("timeout", pars[#chain], {})then
                            warn_timeout(chstate, node, el, chain[1])
                        end
                    else
                        local flag = false
                        for i=1,#nodes-node_index do
                            if nodes[node_index+i].tag == "Table" then
                                if  deep_search_in_array("timeout", nodes[node_index+i], {}) then
                                    flag = true
                                end
                            end
                        end
                        if not flag then
                            warn_timeout(chstate, node, el, chain[1])
                        end
                    end
                end
            end
        end
    end
    if nodes[node_index+1] and nodes[node_index+1].tag == "String" then
        -- Чекнуть функцию после двоеточия
        local chain0 = shallow_copy(chain)
        chain0[#chain0] = el
        table.insert(chain0, 0)
        local funcs0 = get_value_from_keys_array(modules, chain0)
        if funcs0 then
            if deep_search_in_array(nodes[node_index+1][1], funcs0, {}) then
                if not nodes[node_index+2] or not deep_search_in_array("timeout", nodes[node_index+2], {}) then
                    warn_timeout(chstate, node, nodes[node_index+1][1], chain[1])
                end
            end
        end
    end
end

local function process_functions(chstate, nodes, node_index, node)

    -- Если результат вызова функции/метода записывается в переменную - у node тег Invoke
    -- Он состоит из 3х node, раскрываем и записываем в nodes вместо одного Invoke
    if node.tag == "Invoke" then
        table.remove(nodes, node_index)
        for ind, val in ipairs(node) do
            table.insert(nodes, node_index+ind-1, val)
        end
        return process_functions(chstate, nodes, node_index, nodes[node_index])
    end
    if node.tag == "Call" or node.tag == "Index" then
        local pars = {}
        local chain = get_call_chain(node, {}, pars)
        local mod = is_value_in_module_name(chain[1])

        
        if mod then -- Если первая переменная(!) в цепочке вызовов запомнена в module_name
            -- Заменяем в чейне имя переменной на полный путь до объекта. В параметры записываем timeout,
            -- чтобы не было ложных срабатываний
            table.remove(chain,1)
            for i=1,#mod do
                table.insert(chain, i, mod[i])
                table.insert(pars, i, {"timeout"})
            end
            -- Для каждого промежуточного шага проверяем timeout, если он нужен
            for i=2,#chain do
                local nchain = {}
                for j=1,i do
                    nchain[j] = chain[j]
                end
                check_calls_for_timeout(chstate, nodes, node_index, node, nchain, pars, #nchain==#chain)
                nchain = {}
            end
        end
    end
end

local function remember_names(node, temp_name)
    -- Если объявляется новая переменная, ее имя запоминается в temp_name, если в нее записывается require нужного
    -- модуля (из ключей modules) то имя записывается в module_name[название модуля][0]
    
    -- if node.tag == "Id" then
    --     temp_name = node[1]
    -- end
    if node.tag == "Call" or node.tag =="Index" then
        if node[1][1] == "require" and modules[node[2][1]] then

            module_name[node[2][1]] = {[0] = temp_name}
            temp_name = ""
        end

        local chain = get_call_chain(node, {}, {})
        local mod = is_value_in_module_name(chain[1])
        if mod then -- Если первая переменная(!) в цепочке вызовов запомнена в module_name
            chain[1] = mod[1]   -- В цепочке вызовов меняем переменную на модуль
            if chain[1] == "net.box" and chain[3] == "space" and not chain[4] and temp_name ~= "" then
                -- Небольшой костыль, чтобы работать с любыми именами space
                -- В массив modules[net.box][connect][space] добавляется ключ с именем спейса
                local towrite = get_value_from_keys_array(modules, chain)
                towrite[temp_name] = towrite["*"]
                set_value_to_array_keys(modules, towrite, chain)
                set_value_to_array_keys(module_name, {[temp_name] = {[0] = temp_name}}, chain)
                temp_name = ""
                return
            end
            if get_value_from_keys_array(modules, chain) then
                set_value_to_array_keys(module_name, {[0] = temp_name}, chain)
                temp_name = ""
            end
        end
    end
end

local function detect_in_nodes(chstate, nodes)
    for node_index, node in ipairs(nodes) do
        if node.tag == 'Call' then
            for i,nd in ipairs(node) do
                if i~=1 then
                    if nd.tag == 'Call' or nd.tag =='Index' then
                        process_functions(chstate, nodes, node_index, nd)
                    end
                end
            end
        end
        if module_name ~= {} then
            process_functions(chstate, nodes, node_index, node)
        end
    end
end


local function detect_in_line(chstate, line)
    for _, item in ipairs(line.items) do
        if item.tag == "Eval" then
            detect_in_nodes(chstate, item.node)
        elseif item.tag == "Local" then
            if item.rhs then
            for _, rh in ipairs(item.rhs) do
                remember_names(rh, item.lhs[1][1])
            end
                -- detect_in_nodes(chstate, {temp_node})
            detect_in_nodes(chstate, item.rhs)
        end
        elseif item.tag == "Set" then
            for _, rh in ipairs(item.rhs) do
                remember_names(rh, item.lhs[1][1])
            end
            -- detect_in_nodes(chstate, item.lhs)
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