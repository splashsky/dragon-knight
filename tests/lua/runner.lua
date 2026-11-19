-- runner.lua :: runs tests/lua/test_*.lua inside a dk VM. tests/run.sh installs this as
-- cli/user.lua in a scratch copy of app/ and runs `dk user <module>...`.
return {
  run = function(...)
    local failed, passed = 0, 0
    for _, mod in ipairs({ ... }) do
      local tests = require(mod)
      local names = {}
      for name in pairs(tests) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if ok then
          passed = passed + 1
        else
          failed = failed + 1
          io.stderr:write("FAIL [lua] ", mod, ".", name, ": ", tostring(err), "\n")
        end
      end
    end
    print(string.format("lua: %d passed, %d failed", passed, failed))
    return failed == 0 and 0 or 1
  end,
}
