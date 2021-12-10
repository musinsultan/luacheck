local helper = require "spec.helper"

local function assert_warnings(warnings, src)
    assert.same(warnings, helper.get_stage_warnings("detect_tarantool_timeout", src))
end

describe("tarantool timeout", function()
    it("detects net.box ping without timeout", function()
        assert_warnings({code = "1001", line = 2, column = 1, end_column = 1}, [[
        net_box = require('net.box')
        net_box.self:ping()
        ]])
    end)
end)

