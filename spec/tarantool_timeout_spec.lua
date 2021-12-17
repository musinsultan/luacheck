local helper = require "spec.helper"

local function assert_warnings(warnings, src)
    assert.same(warnings, helper.get_stage_warnings("detect_tarantool_timeout", src))
end

describe("tarantool timeout", function()
    it("detects net.box ping without parameters", function()
        assert_warnings({{code = "1001", line = 2, column = 1, end_column = 1}}, [[
        net_box = require('net.box')
        net_box.self:ping()
        ]])
    end)

    it("detects net.box ping without timeout in parameters", function()
        assert_warnings({{code = "1001", line = 2, column = 1, end_column = 1}}, [[
        net_box = require('net.box')
        net_box.self:ping({not_timeout=0})
        ]])
    end)

    it("gives no warning if timeout used", function()
        assert_warnings({}, [[
        net_box = require('net.box')
        vaar = net_box.self:ping({timeout=100})
        ]])
    end)

end)

