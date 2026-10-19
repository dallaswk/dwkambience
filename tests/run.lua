-- Pruebas de shared/ sin el juego. Desde la raíz del recurso: lua tests/run.lua

dofile('shared/interp.lua')
dofile('shared/evaluate.lua')
dofile('shared/scene.lua')

local passed, failed = 0, 0

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(('FAIL  %s\n      %s'):format(name, err))
    end
end

function eq(a, b, msg)
    if a ~= b then error(('%s: esperado %s, obtenido %s'):format(msg or 'eq', tostring(b), tostring(a)), 2) end
end

function near(a, b, msg, eps)
    if type(a) ~= 'number' or math.abs(a - b) > (eps or 1e-6) then
        error(('%s: esperado ~%s, obtenido %s'):format(msg or 'near', tostring(b), tostring(a)), 2)
    end
end

function deepEq(a, b, path)
    path = path or 'data'
    if type(a) ~= type(b) then error(('%s: tipo %s ~= %s'):format(path, type(a), type(b)), 0) end
    if type(a) ~= 'table' then
        if a ~= b then error(('%s: %s ~= %s'):format(path, tostring(a), tostring(b)), 0) end
        return
    end
    for k, v in pairs(a) do deepEq(v, b[k], path .. '.' .. tostring(k)) end
    for k in pairs(b) do
        if a[k] == nil then error(('%s.%s: falta'):format(path, tostring(k)), 0) end
    end
end

dofile('tests/scene_spec.lua')
dofile('tests/interp_spec.lua')
dofile('tests/evaluate_spec.lua')

print(('%d ok, %d fallos'):format(passed, failed))
if failed > 0 then os.exit(1) end
