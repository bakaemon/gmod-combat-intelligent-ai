local BR = CAI.Brain
BR.Exec = BR.Exec or {}
BR.Exec.Engage = BR.Exec.Engage or {}
local Engage = BR.Exec.Engage

function Engage.NewCore()
    local core = { overrides = {} }
    function core.Override(name, fn)
        local list = core.overrides[name]
        if not list then list = {} core.overrides[name] = list end
        table.insert(list, fn)
    end
    function core.Dispatch(name, ctx)
        local list = core.overrides[name]
        if not list then return false, false end
        for _, fn in ipairs(list) do
            local h, s = fn(ctx)
            if s then return true, true end
            if h then return true, false end
        end
        return false, false
    end
    return core
end