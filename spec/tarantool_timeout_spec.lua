local helper = require "spec.helper"

local function assert_warnings(warnings, src)
    assert.same(warnings, helper.get_stage_warnings("detect_tarantool_timeout", src))
end

describe("tarantool timeout", function()
    it("gives no warning if timeout used", function()
        assert_warnings({}, [[
            net_box = require('net.box')
            net_box.connect({timeout=1})
            net_box.connect({timeout=1}):ping({timeout=1})
            space = net_box.connect({timeout=1}).space({timeout=1})
            space.testspace({timeout=1})
    ]])
    end)

    it("Warning if method used without timeout", function()
        assert_warnings({
            {code = "1001", line = 2, column = 1, end_column = 1, funcname="connect", modulename="net.box"},
            {code = "1001", line = 3, column = 1, end_column = 1, funcname="ping", modulename="net.box"},
            {code = "1001", line = 5, column = 1, end_column = 1, funcname="connect", modulename="net.box"},
            {code = "1001", line = 6, column = 1, end_column = 1, funcname="testspace", modulename="net.box"}
        }, [[
            net_box = require('net.box')
            net_box.connect()
            net_box.connect({timeout=1}):ping()

            space = net_box.connect().space({timeout=1})
            space.testspace({var=1})
        ]])
    end)

    it("Warning if method used without timeout", function()
        assert_warnings({
            {code = "1001", line = 3, column = 1, end_column = 1, funcname="wait", modulename="fiber"}
        }, [[
            local fb = require("fiber")
            fb.cond():wait({timeout=1})
            fb.cond():wait({})
        ]])
    end)

    it("Warning if method used without timeout", function()
        assert_warnings({
            {code = "1001", line = 3, column = 1, end_column = 1, funcname="call", modulename="vshard"}
        }, [[
            local vsh = require("vshard")
            a = foo(vsh.router.call(1, {timeout=1}))
            a = foo(vsh.router.call(1, {timout=1}))
        ]])
    end)



end)

