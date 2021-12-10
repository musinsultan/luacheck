local stage = {}

stage.warnings = {
    ["1001"] = {message_format = "Tarantool timeout error", fields = {}}
}

function stage.run(chstate)
   chstate:warn("1001", 2, 1, 2)
end

return stage
