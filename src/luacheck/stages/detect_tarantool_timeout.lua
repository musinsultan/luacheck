local stage = {}

stage.warnings = {
    ["1001"] = { message_format = "Tarantool timeout error", fields = {} }
}

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

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

local function find_node_with_netbox(chstate, node)
    if node.tag == "Invoke" then
        for i = 1, #node do
            local node_invoke = node[i]
            if node_invoke.tag == "Index" then
                for j = 1, #node_invoke do
                    local node_index = node_invoke[j]
                    if node_index.tag == "Id" then
                        if node_index[1] == "net_box" then
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

local function detect_in_nodes(chstate, nodes)
    for _, node in ipairs(nodes) do
        find_node_with_netbox(chstate, node)
    end
end

function detect_omitted_timeouts_in_line(chstate, line)
    for _, item in ipairs(line.items) do
        if item.tag == "Eval" then
            find_node_with_netbox(chstate, item.node)
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
        detect_omitted_timeouts_in_line(chstate, line)
    end
end

return stage