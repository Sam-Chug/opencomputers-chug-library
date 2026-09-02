local component = require("component")
local shell = require("shell")
local event = require("event")
local _, ops = shell.parse(...)
local computer = require("computer")
local version = "0.1.0a"

local function main()

    package.path = package.path .. ";../chuglib/?.lua"

    local gpu = require("chugraph")
    gpu.SetMainGPU(component.gpu, "doubleHeight", true, true)

    gpu.ClearScreen()
    computer.beep(1000, 0.1)
    gpu.UpdateScreen()

    while true do
        gpu.ClearScreen()
        local tEvent = table.pack(event.pull(0))
        if tEvent[1] == "key_down" then local sKey = string.upper(string.char(tEvent[3]))
            if sKey == "Q" then
                gpu.ResetToCommandLine()
                package.loaded["chugraph"] = nil
                break
            end
        end

        gpu.SetText(5, 5, "THIS IS A TEST STRING", 0xFFFFFF, 0x000000, false)
        gpu.SetText(11, 11, "▄▀ABCDEFGHIJKLMNOPQRSTUVWXYZ▀▄", 0xFFFFFF, 0x000000, false)
        gpu.SetText(11, 13, "▄▀⌂⫐╭DEFGHIJKLMNOPQRSTUVWXYZ▀▄", 0xFFFFFF, 0x000000, false)

        gpu.UpdateScreen()
    end
end

if ops.d then main() end
