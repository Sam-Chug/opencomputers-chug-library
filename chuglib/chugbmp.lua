-- ============================================================
-- CREDITS
-- This code is looesly inspired by this repo: https://github.com/max1220/lua-bitmap/tree/master
-- It has been shortened and likely made more finicky to run. But it (might) create a bit less garbage.
-- Bitmaps must be either 24-32 bpp, and no compression is allowed.
-- ============================================================

local component = require("component")
local shell = require("shell")
local event = require("event")
local _, ops = shell.parse(...)
local computer = require("computer")
local version = "0.1.0a"

local bmpOffsetHeader = 1
local bmpOffsetPixel = 11
local bmpOffsetWidth = 19
local bmpOffsetHeight = 23
local bmpOffsetBpp = 29
local bmpOffsetCompression = 31

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

local function closestValidHexFromRGB8(r, g, b)

    -- Get value of each channel from 0-1
    local valR = r / 255
    local valG = g / 255
    local valB = b / 255
    local valGrey = (valR + valG + valB) / 3

    -- Re-inflate values from 0-255, in valid OC increments
    local fixedR = (valR // 0.17) * 51
    local fixedG = math.min(((valG // 0.125) * 36.5) // 1, 255)
    local fixedB = math.min((valB // 0.2) * 64, 255)
    local fixedGrey = (valGrey * 16 // 1) * 15

    -- Get difference of each fixed channel to the origin channels, and the average distance
    -- Do the same for grey, to check if a greyscale value may be closer
    local realDiffAVG = (math.abs(fixedR - r) + math.abs(fixedG - g) + math.abs(fixedB - b)) / 3
    local greyDiffAVG = (math.abs(fixedGrey - r) + math.abs(fixedGrey - g) + math.abs(fixedGrey - b)) / 3

    -- Return whichever color is closer
    if realDiffAVG < greyDiffAVG then return (fixedR << 16) + (fixedG << 8) + fixedB
    else return (fixedGrey << 16) + (fixedGrey << 8) + fixedGrey end
end

local function ParseBMP(fileName)

    -- TODO: This uses a lot of memory I'm guessing

    -- TODO: Send back error if file doesn't exist
    if not fileExists(fileName) then
        return false, "File doesn't exist"
    end

    local file = io.open(fileName, "rb")
    local bmpData = file:read("*a")

    -- TODO: Send back error if magic header not found
    if readShort(bmpData, bmpOffsetHeader) ~= 0x4D42 then
        file:close()
        return false, "Mising BM header"
    end

    -- TODO: Send back error if magic header not found
    if readLong(bmpData, bmpOffsetCompression) ~= 0 then
        file:close()
        return false, "Texture cannot have compression"
    end

    local bpp = readShort(bmpData, bmpOffsetBpp)
    local Bpp = bpp / 8 -- Length of color in bytes

    -- TODO: Send back error if file not in required bpp
    if bpp ~= 24 and bpp ~= 32 then
        file:close()
        return false, "Not 24bpp or 32bpp"
    end

    local width = readLong(bmpData, bmpOffsetWidth)
    local height = readLong(bmpData, bmpOffsetHeight)
    local pixelOffset = readLong(bmpData, bmpOffsetPixel)

    local rowLength = width * Bpp
    local rowStride = math.ceil(rowLength / 4) * 4
    local colorMap = {}

    local r, g, b, index, color = 0, 0, 0, 0, 0
    for x = 0, width - 1 do
        colorMap[x + 1] = {}
        for y = 0, height - 1 do
            index = (pixelOffset + y * rowStride + x * Bpp) + 1

            b = readByte(bmpData, index)
            g = readByte(bmpData, index + 1)
            r = readByte(bmpData, index + 2)

            color = closestValidHexFromRGB8(r, g, b)
            colorMap[x + 1][height - y] = color
        end
    end

    file:close()
    return colorMap
end

-- Benchmarking for image parrot.bmp
-- Minimum memory required to load: 960kb

local function main()

    -- Graphics Library
    local gpu = require("chugraph")
    gpu.SetMainGPU(component.gpu, "doubleHeight", true, true)

    gpu.ClearScreen()
    computer.beep(1000, 0.1)
    gpu.UpdateScreen()

    local test, issue = ParseBMP("parrot.bmp")
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

        if not test then
            gpu.ResetToCommandLine()
            package.loaded["chugraph"] = nil
            print(issue)
            break
        end

        for x = 1, #test do
            for y = 1, #test[1] do
                gpu.SetPixel(x + 30, y, test[x][y])
            end
        end

        gpu.UpdateScreen()
    end
end

if ops.d then main() end

return {
    ParseBMP = ParseBMP
}