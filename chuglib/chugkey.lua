local computer = require("computer")
local shell = require("shell")
local _, ops = shell.parse(...)

local chugkey = {
    keysPressed = {}
}

function chugkey.parseKeyCode(e)
    local rKey
    -- Key pressed, but not a char, check for any wanted command keys
    if e[3] == 0 then
        if e[4] ~= 0 then
            if e[4] == 0xCB then rKey = "LEFT"
            elseif e[4] == 0xCD then rKey = "RIGHT"
            elseif e[4] == 0xC8 then rKey = "UP"
            elseif e[4] == 0xD0 then rKey = "DOWN"
            end
        end
    -- Else char pressed
    else rKey = string.upper(string.char(e[3])) end
    return rKey
end

function chugkey.isKeyDown(handler, keyCode)
    return handler.keysPressed[keyCode]
end

function chugkey.updateKeypress(handler)
    local tEvent = table.pack(computer.pullSignal(0))
    local sKey = nil
    -- Parse keycode
    if tEvent[1] == "key_down" then
        sKey = handler.parseKeyCode(tEvent)
        if sKey ~= nil then handler.keysPressed[sKey] = true end
    elseif tEvent[1] == "key_up" then
        sKey = handler.parseKeyCode(tEvent)
        if sKey ~= nil then handler.keysPressed[sKey] = false end
    end
end

function chugkey.debugPrintKeyPresses(handler)
    local printString = ""
    for k, _ in pairs(handler.keysPressed) do
        if handler.keysPressed[k] then
            if k ~= nil then printString = printString .. k .. ", " end
        end
    end
    print(printString)
end

local inputManager = chugkey
local function main()
    while true do
        inputManager.updateKeypress(inputManager)
        inputManager.debugPrintKeyPresses(inputManager)

        if inputManager.isKeyDown(inputManager, "Q") then
            print("Exiting program")
            break
        end
    end
end

local function setVariables()
    if ops.d then main() end
end
setVariables()

return chugkey