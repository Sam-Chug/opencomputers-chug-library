local component = require("component")
local shell = require("shell")
local event = require("event")
local _, ops = shell.parse(...)
local computer = require("computer")
local version = "0.1.0a"

-- ============================================================
-- CREDITS
-- This code is looesly inspired by this repo: https://github.com/max1220/lua-bitmap/tree/master
-- It has been shortened and likely made more finicky to run. But it creates a lot less garbage.
-- ============================================================

local offsetHeader = 54
local offsetWidth = 19
local offsetHeight = 23
local offsetBpp = 29 -- Only support 24-32bpp
local offsetPixel = 11
local offsetCompression = 31 -- No compression allowed, sorry

local function readByte(bytes, offset)
    return string.byte(bytes, offset, offset)
end

local function readShort(bytes, offset)
    local value = 0
    for i = 0, 1 do
        value = value + string.byte(bytes, offset + i) * (256 ^ i)
    end
    return value
end

local function readLong(bytes, offset)
    local value = 0
    for i = 0, 3 do
        value = value + string.byte(bytes, offset + i) * (256 ^ i)
    end
    return value
end

local function fileExists(fileName)
    local f = io.open(fileName, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function closestValidHexFromRGB(r, g, b)

    -- Get value of each channel from 0-1
    local valR = r / 255
    local valG = g / 255
    local valB = b / 255
    local valGrey = (r + g + b) / 3

    -- Re-inflate values from 0-255, in valid OC increments
    local fixedR = (r // 0.17) * 51
    local fixedG = ((g // 0.125) * 36.5) // 1
    local fixedB = math.min((b // 0.25) * 64, 255)
    local fixedGrey = (valGrey * 16 // 1) * 15

    -- Get difference of each fixed channel to the origin channels, and the average distance
    local realDiffR = math.abs(fixedR - r)
    local realDiffG = math.abs(fixedG - g)
    local realDiffB = math.abs(fixedB - b)
    local realDiffAVG = (realDiffR + realDiffG + realDiffB) / 3

    -- Do the same for grey, to check if a greyscale value may be closer
    local greyDiffR = math.abs(fixedGrey - r)
    local greyDiffG = math.abs(fixedGrey - g)
    local greyDiffB = math.abs(fixedGrey - b)
    local greyDiffAVG = (greyDiffR + greyDiffG + greyDiffB) / 3

    -- Return whichever color is closer
    if realDiffAVG <= greyDiffAVG then return (fixedR << 16) + (fixedG << 8) + fixedB
    else return (fixedGrey << 16) + (fixedGrey << 8) + fixedB end
end

local function ParseBMP(fileName)

    -- TODO: Send back error if file doesn't exist
    if not fileExists(fileName) then return false end

    local file = io.open(fileName, "rb")
    local infoHeader = file:read(offsetHeader)

    -- TODO: Send back error if magic header not found
    if readShort(infoHeader, 1) ~= 0x4D42 then
        file:close()
        return false
    end

    -- TODO: Send back error if magic header not found
    if readLong(infoHeader, offsetCompression) ~= 0 then
        file:close()
        return false
    end

    local bpp = readShort(infoHeader, offsetBpp)
    local Bpp = bpp / 8 -- Length of color in bytes

    -- TODO: Send back error if file not in required bpp
    if bpp ~= 24 and bpp ~= 32 then
        file:close()
        return false
    end

    local width = readLong(infoHeader, offsetWidth)
    local height = readLong(infoHeader, offsetHeight)
    local pixelOffset = readLong(infoHeader, offsetPixel)

    local rowLength = width * Bpp
    local rowStride = math.ceil(rowLength / 4) * 4
    local colorMap = {}
    for x = 0, width - 1 do
        colorMap[x] = {}
        for y = 0, height - 1 do
            print()
            print(x, y)
            local index = pixelOffset + y * rowStride + x * Bpp
            local b = readByte(infoHeader, index)
            local g = readByte(infoHeader, index + 1)
            local r = readByte(infoHeader, index + 2)

            local color = closestValidHexFromRGB(r, g, b)
            colorMap[x][y] = color
        end
    end

    file:close()
    return colorMap
end

-- Graphics Library
local gpu = require("chugraph")
gpu.SetMainGPU(component.gpu, "doubleHeight", false, true)

local function main()

    gpu.ClearScreen()
    computer.beep(1000, 0.1)
    gpu.SetText(5, 5, "ChugBMP", 0xFFFFFF, 0x000000, false)
    gpu.UpdateScreen()

    local test = ParseBMP("parrot.bmp")
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
        if not test then break end
        gpu.SetText(5, 5, test[1][1], 0xFFFFFF, 0x000000, false)

        for x = 1, #test do
            for y = 1, #test[1] do
                gpu.SetPixel(x, y, test[x][y])
            end
        end

        gpu.UpdateScreen()
    end
end
main()