-- scriptsafari.lua
local HttpService = game:GetService("HttpService")
local url = "https://raw.githubusercontent.com/VapeVoidware/VW-Add/main/nightsintheforest.lua"

local success, response = pcall(function()
    return HttpService:GetAsync(url, true)
end)

if success then
    local scriptFunction, err = loadstring(response)
    if scriptFunction then
        local execSuccess, execResult = pcall(scriptFunction)
        if execSuccess then
            print("Скрипт nightsintheforest.lua успешно выполнен!")
        else
            warn("Ошибка при выполнении nightsintheforest.lua: " .. tostring(execResult))
        end
    else
        warn("Ошибка компиляции nightsintheforest.lua: " .. tostring(err))
    end
else
    warn("Ошибка загрузки nightsintheforest.lua: " .. tostring(response))
end
