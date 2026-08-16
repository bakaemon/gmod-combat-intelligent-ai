local BR = CAI.Brain
BR.Hooks = BR.Hooks or {}
BR.HOOK_LOADER = "loader"

function BR.RegisterHook(module, scope, fn)
    BR.Hooks[module] = BR.Hooks[module] or {}
    BR.Hooks[module][scope] = BR.Hooks[module][scope] or {}
    table.insert(BR.Hooks[module][scope], fn)
end

function BR.Call(module, scope, ...)
    local list = BR.Hooks[module] and BR.Hooks[module][scope]
    if not list then return false end
    for _, fn in ipairs(list) do fn(...) end
    return true
end

function BR.CallScopes(module, ...)
    local hooks = BR.Hooks[module]
    if not hooks then return end
    for scope, list in pairs(hooks) do
        if scope ~= BR.HOOK_LOADER then
            for _, fn in ipairs(list) do fn(...) end
        end
    end
end