local helper = require "spec.helper"

local function assert_warnings(warnings, src)
    assert.same(warnings, helper.get_stage_warnings("detect_tarantool_timeout", src))
end

describe("tarantool timeout", function()
    it("detects lines with only whitespace", function()
        assert_warnings({}, [[
        net_box = require('net.box')
        net_box.self:ping()
        ]])
    end)
end)
