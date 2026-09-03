local component = require("component")
local event = require("event")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")
local term = require("term")

local version = "0.3.3a"

local funcWidth, funcHeight = 0, 0
local gpu, buffer, screenWidth, screenHeight

local charBlockT, charBlockB, charBlockF = "▀", "▄", "█"
local inverseChars = {["▀"] = "▄", ["▄"] = "▀", ["█"] = " ", [" "] = "█"}
local currentForeground, currentBackground = -1, -1
local sceneBGColor = 0x000000

-- Screen buffer arrays
local colorBuffer = {}
local charBuffer = {}
local drawBuffer = {}

-- Color look up tables
local hexLUT, colLUT = {}, {}

-- Debug crap
local debugMode = false
local debugDrawWhiteLines = false
local debugDrawColorLines = false
local debugTestColorLUTs = false
local debugDoBenchmark = false

local gpuUsageStats = {
    set = 0, fore = 0, back = 0, fill = 0, get = 0, blit = 0, pack = 0, unpack = 0,
    lastSet = 0, lastFore = 0, lastBack = 0, lastFill = 0, lastGet = 0, lastBlit = 0, lastPack = 0, lastUnpack = 0,
    invert = 0, lastInvert = 0,
    cpuTime = os.clock() or 0, lastCpuTime = os.clock() or 0,
    frameTime = computer.uptime() or 0, lastFrameTime = computer.uptime() or 0,
    usedMem = computer.totalMemory() - computer.freeMemory(),
    cpuTimeTotal = 0, frameTimeTotal = 0, usedMemTotal = 0, gpuUsageTotal = 0
}

local TableInsert, Concat = table.insert, table.concat
local Sub, StringFormat = string.sub, string.format
local Modulo, Abs, Min, Max = math.fmod, math.abs, math.min, math.max
local GPUAllocateBuffer, GPUSetActiveBuffer, GPUFreeBuffer, GPUFreeAllBuffers
local GPUGetRes, GPUSetFG, GPUSetBG
local GPUSet, GPUFill, GPUBitBlt

-- ============================================================
-- GET/SET PIXEL DATA
-- ============================================================

-- TODO: Merge with GetPixel()
local function unpackPixel(x, y)
    local index = y * funcWidth + x
    return colorBuffer[index] >> 24, colorBuffer[index] % 16777216, charBuffer[index], drawBuffer[index]
end

local function packPixel(x, y, fore, back, char, update)
    gpuUsageStats.pack = gpuUsageStats.pack + 1
    local index = y * funcWidth + x
    colorBuffer[index] = (fore << 24) + (back or 0x000000)
    charBuffer[index] = char
    drawBuffer[index] = update
end

-- Set empty screen buffer
-- Fore, Back, Char, isText, Update
local function buildScreenData()
    for i = 1, funcWidth * funcHeight do
        colorBuffer[i] = sceneBGColor << 24
        charBuffer[i] = nil
        drawBuffer[i] = false
    end
end

-- Reset all pixels within region to default values
local function resetUpdateForRegion(x, y, width, height)
    for i = 0, width - 1 do
        for j = 0, height - 1 do
            local index = (y + j) * funcWidth + x + i
            colorBuffer[index] = sceneBGColor << 24
            charBuffer[index] = nil
            drawBuffer[index] = false
        end
    end
end

-- ============================================================
-- GPU DRAWING
-- ============================================================

-- Blit VRAM to main screen
local function bitblt()
    GPUBitBlt(0, 1, 1, screenWidth, screenHeight, buffer, 1, 1)
    gpuUsageStats.blit = gpuUsageStats.blit + 1
end

-- Set foreground drawing color
local function setForeground(color)
    if currentForeground ~= color then
        GPUSetFG(color)
        currentForeground = color
        gpuUsageStats.fore = gpuUsageStats.fore + 1
    end
end

-- Set background drawing color
local function setBackground(color)
    if currentBackground ~= color then
        GPUSetBG(color)
        currentBackground = color
        gpuUsageStats.back = gpuUsageStats.back + 1
    end
end

-- Set string to screen
local function set(x, y, foreColor, backColor, string)
    setForeground(foreColor)
    setBackground(backColor)

    GPUSet(x, y, string)
    gpuUsageStats.set = gpuUsageStats.set + 1
end

-- Compile char string and draw it at position
local function drawCharGroup(drawGroups)
    for rKey, rVal in pairs(drawGroups) do
        for cKey, cVal in pairs(rVal) do
            for i = 1, #cVal[1] do
                set(cVal[1][i], cVal[2][i], rKey, cKey, cVal[3][i])
            end
        end
    end
end

-- Use real-screen coordinates to return compiled pixel data based on the set drawing mode
local function returnPixelData(x, y)

    -- Get char of pixel
    local char = charBuffer[y * funcWidth + x]

    -- If char unset, return pixel data
    if char == nil then

        -- Get top and bottom colors
        local fore = colorBuffer[y * funcWidth + x] >> 24
        local downFore = colorBuffer[(y + 1) * funcWidth + x] >> 24

        if fore == downFore then
            -- Same color, send full block
            return fore, downFore, charBlockF, false
        else
            -- Different color, send half block
            return fore, downFore, charBlockT, false
        end
    -- Else, return char with pixel data
    else
        return colorBuffer[y * funcWidth + x] >> 24, colorBuffer[y * funcWidth + x] % 16777216, char, true
    end
end

-- Loop through screenBuffer and draw pixels that were changed this frame
local function DrawFrame()

    -- Cache variables before iterating
    local xInc, yInc = 1, 2
    local xSkipIndex = 0
    local fillGroup, drawGroup, charString = {0, 0, 0, 0}, {}, {}
    local twoColCheck = false
    local startFore, startBack, startChar, startText = 0, 0, " ", false
    local newFore, newBack, newChar, newText = 0, 0, " ", false
    local checkLen, indexTop, indexBot, charsAdded = 0, 0, 0, 0

    for y = 1, funcHeight, yInc do -- For each line,
        for x = 1, funcWidth, xInc do -- Run each pixel,
            if x + xSkipIndex > funcWidth then goto skipx end

            -- If pixel doesn't require update, skip
            indexTop = y * funcWidth + x + xSkipIndex
            indexBot = (y + 1) * funcWidth + x + xSkipIndex
            if drawBuffer[indexTop] then goto startGroup
            elseif not drawBuffer[indexBot] then goto continue end

            -- Mark pixel as finished updating
            ::startGroup::
            drawBuffer[indexTop] = false
            drawBuffer[indexBot] = false

            -- Get starting fill fillgroup values
            startFore, startBack, startChar, startText = returnPixelData(x + xSkipIndex, y)

            -- Start fill group
            fillGroup = {x + xSkipIndex, (y // yInc) + 1, startFore, startBack}
            charString = {startChar}; charsAdded = 1; twoColCheck = false
            while true do -- loop until non-matching pixel found

                -- Get next pixel in row
                checkLen = charsAdded
                if xSkipIndex + x + 1 > funcWidth then break end
                newFore, newBack, newChar, newText = returnPixelData(x + xSkipIndex + 1, y)

                -- If pixel's text state changes, break
                if startText ~= newText then break end

                -- If new fore/back are the same
                if newFore ~= newBack then

                    -- New and original match exactly, insert returned char
                    if fillGroup[3] == newFore and fillGroup[4] == newBack then
                        charsAdded = charsAdded + 1
                        charString[charsAdded] = newChar

                    -- New and original match but are inverted, return inverted char
                    elseif fillGroup[3] == newBack and fillGroup[4] == newFore then
                        charsAdded = charsAdded + 1
                        charString[charsAdded] = inverseChars[newChar]

                    -- If original fore/back are the same
                    elseif fillGroup[3] == fillGroup[4] then

                        -- If new fore matches original fore, insert returned char and set original back to new fore
                        if newFore == fillGroup[3] then
                            charsAdded = charsAdded + 1
                            charString[charsAdded] = newChar
                            fillGroup[4] = newBack
                        -- If new back matches original fore, then insert inverted char and set original back to new fore
                        elseif newBack == fillGroup[3] then
                            charsAdded = charsAdded + 1
                            charString[charsAdded] = inverseChars[newChar]
                            fillGroup[4] = newFore
                        end
                    else break end

                -- If new fore/back are not the same
                else

                    -- If original fore/back are not the same
                    if fillGroup[3] ~= fillGroup[4] then

                        -- If new fore and original fore match, insert returned char
                        if fillGroup[3] == newFore then
                            charsAdded = charsAdded + 1
                            charString[charsAdded] = newChar
                        -- If new fore and original back match, insert inverted char
                        elseif fillGroup[4] == newFore then
                            charsAdded = charsAdded + 1
                            charString[charsAdded] = inverseChars[newChar]
                        end

                    -- If original fore/back are the same
                    elseif fillGroup[3] == fillGroup[4] then

                        -- If new colors equal to original, insert returned char
                        if newFore == fillGroup[3] then
                            charsAdded = charsAdded + 1
                            charString[charsAdded] = newChar
                        -- Otherwise, return inversed char, and set new color to original back
                        else
                            charsAdded = charsAdded + 1
                            charString[charsAdded] = inverseChars[newChar]
                            fillGroup[4] = newBack
                        end
                    end
                end

                -- If no new chars added to draw string, exit loop
                if charsAdded == checkLen then
                    break

                -- Else, pixel is ready to draw and no longer requires updating
                else
                    drawBuffer[indexTop + 1] = false
                    drawBuffer[indexBot + 1] = false
                end

                -- Colors different, sort colors by numerical value
                -- If need to swap, inverse characters in string
                if (not twoColCheck) and (fillGroup[3] ~= fillGroup[4]) and (not startText) then
                    if fillGroup[3] < fillGroup[4] then
                        for i = 1, charsAdded do
                            charString[i] = inverseChars[charString[i]]
                        end
                        fillGroup[3], fillGroup[4] = fillGroup[4], fillGroup[3]
                        gpuUsageStats.invert = gpuUsageStats.invert + 1
                    end
                    twoColCheck = true
                end

                -- Increment x search index
                xSkipIndex = xSkipIndex + 1
                if xSkipIndex + x > funcWidth then break end
            end

            -- Add grouped pixels to list
            if drawGroup[fillGroup[3]] == nil then drawGroup[fillGroup[3]] = {} end
            if drawGroup[fillGroup[3]][fillGroup[4]] == nil then
                drawGroup[fillGroup[3]][fillGroup[4]] = {{}, {}, {}}
            end
            TableInsert(drawGroup[fillGroup[3]][fillGroup[4]][1], fillGroup[1])
            TableInsert(drawGroup[fillGroup[3]][fillGroup[4]][2], fillGroup[2])
            TableInsert(drawGroup[fillGroup[3]][fillGroup[4]][3], Concat(charString))

            fillGroup = nil
            charString = nil
            ::continue::
        end
        ::skipx::
        xSkipIndex = 0
    end
    -- Finally, draw and apply new frame data, then reset update value for all pixels
    drawCharGroup(drawGroup)
    drawGroup = nil
end

-- ============================================================
-- GET/SET
-- ============================================================

-- Set index to input pixel data
local function addToFrameBuffer(x, y, foreColor, backColor, char)

    x = x // 1; y = y // 1
    if x < 1 or x > funcWidth or y < 1 or y > funcHeight then return end

    -- Set pixel data from function args
    packPixel(x, y, foreColor, backColor, char, true)
end

-- Set index and consecutive indices to string pixel data
local function textToFrameBuffer(x, y, foreColor, backColor, text, vertical)

    x = x // 1; y = y // 1
    if x < 1 or x > funcWidth or y < 1 or y > funcHeight then return end

    if not vertical then
        for i = 1, string.len(text) do
            addToFrameBuffer(x + i - 1, y, foreColor, backColor, Sub(text, i, i))
        end
    else
        for i = 1, string.len(text) do
            addToFrameBuffer(x, y + i - 1, foreColor, backColor, Sub(text, i, i))
        end
    end
end

-- Fill area on screen with specified color and char
-- TODO: This should just fill and update the screen buffer
local function Fill(x, y, width, height, foreColor, backColor)
    for i = x, x + width - 1 do
        for j = y, y + height - 1 do
            addToFrameBuffer(i, j, foreColor, backColor)
        end
    end
end

-- Clear region, send straight to gpu command, then loop and reset updates
local function ClearRegion(x, y, width, height)

    -- TODO: Handle fractional pixel clears, clear basic-sized pixel here and send fractionals to update regularly
    local widthFixed, heightFixed = width, (height // 2) + 1
    local xFixed, yFixed = x, (y // 2) + 1

    resetUpdateForRegion(x, y, width, height)
    setForeground(sceneBGColor); setBackground(sceneBGColor)
    GPUFill(xFixed, yFixed, widthFixed, heightFixed, " ")
    gpuUsageStats.fill = gpuUsageStats.fill + 1
end

-- TODO: This could probably be faster? Just reset the arrays or refactor so nil works as a zeroed value
local function ClearScreen()
    ClearRegion(1, 1, funcWidth, funcHeight)
end

-- Return pixel data
local function GetPixel(x, y)
    local fore, back, char = unpackPixel(x, y)
    return char or nil, fore, back
end

-- Set text to screen, rounds to nearest 
local function SetText(x, y, string, foreColor, backColor, vertical)
    -- Crush pos into basic resolution pos, based on double-height res
    local fixedX = x;
    local fixedY = y % 2 == 1 and y or y - 1

    textToFrameBuffer(fixedX, fixedY, foreColor, backColor, string, vertical or false)
end

local function SetPixel(x, y, color)
    x = x // 1; y = y // 1
    if x < 1 or x > funcWidth or y < 1 or y > funcHeight then return end

    -- Set pixel data from function args
    packPixel(x, y, color, nil, nil, true)
end

local function GetAspectRatio()
    return funcHeight / funcWidth
end

local function GetScreenWidth()
    return funcWidth
end

local function GetScreenHeight()
    return funcHeight
end

local function SetSceneBackground(color)
    sceneBGColor = color
end

-- ============================================================
-- COLOR
-- ============================================================

-- Return closest valid color from RGB values ranging from 0-255
local function ClosestValidHexFromRGB8(r, g, b)

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

-- Return closest valid color from RGB values ranging from 0-1
local function ClosestValidHexFromRGB1(r, g, b)

    -- Get 0-255 scaled RGB values to compare against
    local r255 = r * 255
    local g255 = g * 255
    local b255 = b * 255

    -- Get grey value from average RGB channels
    local valGrey = (r + g + b) / 3

    -- Re-inflate values from 0-255, in valid OC increments
    local fixedR = (r // 0.17) * 51
    local fixedG = math.min(((g // 0.125) * 36.5) // 1, 255)
    local fixedB = math.min((b // 0.2) * 64, 255)
    local fixedGrey = (valGrey * 16 // 1) * 15

    -- Get difference of each fixed channel to the origin channels, and the average distance
    -- Do the same for grey, to check if a greyscale value may be closer
    local realDiffAVG = (math.abs(fixedR - r255) + math.abs(fixedG - g255) + math.abs(fixedB - b255)) / 3
    local greyDiffAVG = (math.abs(fixedGrey - r255) + math.abs(fixedGrey - g255) + math.abs(fixedGrey - b255)) / 3

    -- Return whichever color is closer
    if realDiffAVG < greyDiffAVG then return (fixedR << 16) + (fixedG << 8) + fixedB
    else return (fixedGrey << 16) + (fixedGrey << 8) + fixedGrey end
end

-- Return greyscale color from input value (0 - 1)
local function GetGreyscaleColor(value)
    -- Sanitize input
    if value ~= value then return 0xFF0000 end
    value = Max(Min(value, 1), 0)

    -- Return valid hex color
    value = (value * 16 // 1) * 15
    value = (value << 16) + (value << 8) + value
    return value
end

-- Apply shade level to input color
-- Testing: https://onecompiler.com/lua/44z92yjhe
local function GetShadedColor(color, shade)

    -- Extract RGB channels, get channel values from 1-255
    -- shade = shade
    local r = Min((color >> 16) * shade, 255)
    local g = Min(((color % 65536) >> 8) * shade, 255)
    local b = Min((color % 256) * shade, 255)

    -- Return closest valid color
    return ClosestValidHexFromRGB8(r, g, b)
end

-- Blend first color with second color.
-- Third agument is the amount of the second color to blend:
-- 0 -> outputs color 1 and 1 -> outputs color 2
local function BlendColor(c1, c2, amount)

    -- Sanitize input blend amount
    amount = Max(Min(amount, 1), 0)

    -- Isolate RGB values from both colors
    local r1 = (c1 >> 16)
    local g1 = ((c1 % 65536) >> 8)
    local b1 = (c1 % 256)
    local r2 = (c2 >> 16)
    local g2 = ((c2 % 65536) >> 8)
    local b2 = (c2 % 256)

    -- Get difference between each RGB value
    local rDiff = ((r2 - r1) * amount) // 1
    local gDiff = ((g2 - g1) * amount) // 1
    local bDiff = ((b2 - b1) * amount) // 1

    -- Get blended RGB values and Grey value
    local rNew = r1 + rDiff
    local gNew = g1 + gDiff
    local bNew = b1 + bDiff

    -- Return closest valid color
    return ClosestValidHexFromRGB8(rNew, gNew, bNew)
end

-- Unused, unless I really feel like saving ram
local function createColorLUTs()
    -- Cache RGB color values from 1 - 240
    local index = 1
    for r = 0, 5 do
        for g = 0, 7 do
            for b = 0, 4 do

                local hexR = r * 51
                local hexG = (g * 36.5) // 1
                local hexB = Min(b * 64, 255)
                local hexValue = (hexR << 16) + (hexG << 8) + hexB

                hexLUT[index] = hexValue
                colLUT[hexValue] = index

                index = index + 1
            end
        end
    end

    -- 16 Remaining slots for greyscale
    for g = 15, 240, 15 do
        local hexValue = (g << 16) + (g << 8) + g

        hexLUT[index] = hexValue
        colLUT[hexValue] = index

        index = index + 1
    end
end

-- ============================================================
-- MATH
-- ============================================================

-- DrawLine helper function
local function drawLineLow(x1, y1, x2, y2, color)

    local dx = x2 - x1
    local dy = y2 - y1
    local yi = 1
    if dy < 0 then
        yi = -1
        dy = -dy
    end

    local D = (2 * dy) - dx
    local y = y1

    for x = x1, x2 do
        SetPixel(x, y, color)
        if D > 0 then
            y = y + yi; D = D + (2 * (dy - dx))
        else
            D = D + (2 * dy)
        end
    end
end

-- DrawLine helper function
local function drawLineHigh(x1, y1, x2, y2, color)

    local dx = x2 - x1
    local dy = y2 - y1
    local xi = 1

    if dx < 0 then
        xi = -1
        dx = -dx
    end

    local D = (2 * dx) - dy
    local x = x1

    for y = y1, y2 do
        SetPixel(x, y, color)
        if D > 0 then
            x = x + xi; D = D + (2 * (dx - dy))
        else
            D = D + (2 * dx)
        end
    end
end

-- Draw line from one point to the other
local function DrawLine(x1, y1, x2, y2, color)

    x1 = x1 // 1; y1 = y1 // 1
    x2 = x2 // 1; y2 = y2 // 1

    if Abs(y2 - y1) < Abs(x2 - x1) then
        if x1 > x2 then drawLineLow(x2, y2, x1, y1, color)
        else drawLineLow(x1, y1, x2, y2, color) end
    else
        if y1 > y2 then drawLineHigh(x2, y2, x1, y1, color)
        else drawLineHigh(x1, y1, x2, y2, color) end
    end
end

-- Draw triangle from three sets of points
local function DrawTriangle(p, color)
    DrawLine(p[1][1], p[1][2], p[2][1], p[2][2], color)
    DrawLine(p[2][1], p[2][2], p[3][1], p[3][2], color)
    DrawLine(p[3][1], p[3][2], p[1][1], p[1][2], color)
end

-- FillTriangle helper function
local function fillFlatBottomTriangle(x1, y1, x2, y2, x3, y3, color)
    local invSlope1 = (x2 - x1) / (y2 - y1)
    local invSlope2 = (x3 - x1) / (y3 - y1)
    local xStart = x1
    local xEnd = x1

    for y = y1, y3 do
        DrawLine(xStart // 1, y, xEnd // 1, y, color)
        xStart = xStart + invSlope1
        xEnd = xEnd + invSlope2
    end
end

-- FillTriangle helper function
local function fillFlatTopTriangle(x1, y1, x2, y2, x3, y3, color)
    local invSlope1 = (x3 - x1) / (y3 - y1)
    local invSlope2 = (x3 - x2) / (y3 - y2)

    local xStart = x3
    local xEnd = x3

    for y = y3, y2, -1 do
        DrawLine(xStart // 1, y, xEnd // 1, y, color)
        xStart = xStart - invSlope1
        xEnd = xEnd - invSlope2
    end
end

-- Fill triangle specified by input point set and color
local function FillTriangle(tri, color)

    -- rounding down removes gaps between top/bottom tris
    -- look at how 3dtest handles filling tris for better coordinate handling
    local x1 = tri[1][1] // 1; local y1 = tri[1][2] // 1
    local x2 = tri[2][1] // 1; local y2 = tri[2][2] // 1
    local x3 = tri[3][1] // 1; local y3 = tri[3][2] // 1

    -- sort by y value
    if y1 > y2 then
        y1, y2 = y2, y1
        x1, x2 = x2, x1
    end
    if y2 > y3 then
        y2, y3 = y3, y2
        x2, x3 = x3, x2
    end
    if y1 > y2 then
        y1, y2 = y2, y1
        x1, x2 = x2, x1
    end

    if y2 == y3 then
        fillFlatBottomTriangle(x1, y1, x2, y2, x3, y3, color)
    elseif y1 == y2 then
        fillFlatTopTriangle(x1, y1, x2, y2, x3, y3, color)
    else
        local mx = ((((x3 - x1) * (y2 - y1)) / (y3 - y1)) + x1) // 1
        local my = y2

        fillFlatBottomTriangle(x1, y1, x2, y2, mx, my, color)
        fillFlatTopTriangle(x2, y2, mx, my, x3, y3, color)
    end
end

-- ============================================================
-- DEBUG
-- ============================================================

-- Memory
local memDiv = 1024 -- Measuring KB
local memString = "KB"

-- Debug Tracking
local debugTimeCycles, debugCycleReset = 2, 50
local debugForeColor, debugBackColor = 0xFFFFFF, 0x330040

local function getGPUUsage()
    -- These values were tested using an empty debug screen, and pushing until frames dropped below 20fps average.
    -- They do not reflect the real gpu call budget, but are a good measurement of chugraph
    return gpuUsageStats.lastSet  / 2200 +
           gpuUsageStats.lastFill / 1400 +
           gpuUsageStats.lastFore / 2000 +
           gpuUsageStats.lastBack / 2000 +
           gpuUsageStats.lastGet  / 2000
end

-- Write debug stats to graphcis buffer
local function drawDebug()

    -- Timing Test Bench: https://onecompiler.com/lua/44zp873h2
    local averageCpuTime = gpuUsageStats.cpuTimeTotal / debugTimeCycles
    local averageFrameTime = gpuUsageStats.frameTimeTotal // debugTimeCycles
    local averageUsedMem = gpuUsageStats.usedMemTotal // debugTimeCycles
    local cpuTimeDiff = (gpuUsageStats.cpuTime - gpuUsageStats.lastCpuTime) * 1000
    local frameTimeDiff = math.ceil((gpuUsageStats.frameTime - gpuUsageStats.lastFrameTime) * 1000)

    local gpuUsage = getGPUUsage() * 100
    gpuUsageStats.gpuUsageTotal = gpuUsageStats.gpuUsageTotal + gpuUsage
    local averageGpuUsage = gpuUsageStats.gpuUsageTotal / debugTimeCycles

    -- Gather debugging information to show on panel
    local debugLines = {
        StringFormat(" FPS:   %4.1f |           ", 1000 / averageFrameTime),
        StringFormat(" PIXU: %5d | INVR: %5d ", gpuUsageStats.lastPack, gpuUsageStats.lastInvert),
        StringFormat(" SET: %6d | FILL: %5d ", gpuUsageStats.lastSet, gpuUsageStats.lastFill),
        StringFormat(" SFORE: %4d | SBACK: %4d ", gpuUsageStats.lastFore, gpuUsageStats.lastBack),
        " -------------------------",
        StringFormat(" CPU: %4.1fms | AVG: %4.1fms ", cpuTimeDiff, averageCpuTime),
        StringFormat(" GPU: %5.1f%% | AVG: %5.1f%% ", gpuUsage, averageGpuUsage),
        StringFormat(" MEM: %4d%s | AVG: %4d%s ", (gpuUsageStats.usedMem / memDiv) // 1, memString, (averageUsedMem / memDiv) // 1, memString),
        StringFormat(" FRM: %4dms | AVG: %4dms ", frameTimeDiff, averageFrameTime),
    }

    -- Flavor
    Fill(1, funcHeight - 18, 27, 17, debugBackColor, debugBackColor)
    DrawLine(1, funcHeight - 19, 27, funcHeight - 19, 0xFFFFFF)
    DrawLine(1, funcHeight - 22, 5, funcHeight - 22, 0xFFFFFF)
    DrawLine(13, funcHeight - 22, 27, funcHeight - 22, 0xFFFFFF)
    SetText(1, funcHeight - 20, "DEBUG", debugForeColor, debugBackColor, false)
    SetText(13, funcHeight - 20, StringFormat("Chugraph %s", version), debugForeColor, debugBackColor, false)

    -- Draw debug strings
    for i = 1, #debugLines do
        local posY = funcHeight - (#debugLines - i) * 2
        SetText(1, posY, debugLines[i], debugForeColor, debugBackColor, false)
    end

    -- Average up to n time cycles, reset average afterwards
    -- Not the most accurate "average", but close enough
    debugTimeCycles = debugTimeCycles + 1
    if debugTimeCycles > debugCycleReset then
        gpuUsageStats.cpuTimeTotal = averageCpuTime
        gpuUsageStats.frameTimeTotal = averageFrameTime
        gpuUsageStats.usedMemTotal = averageUsedMem
        gpuUsageStats.gpuUsageTotal = averageGpuUsage
        debugTimeCycles = 2
    end
end

-- Reset gpu usage counts
local function takeDebugMeasurements()
    gpuUsageStats.lastSet = gpuUsageStats.set; gpuUsageStats.lastFore = gpuUsageStats.fore
    gpuUsageStats.lastBack = gpuUsageStats.back; gpuUsageStats.lastFill = gpuUsageStats.fill
    gpuUsageStats.lastGet = gpuUsageStats.get; gpuUsageStats.lastBlit = gpuUsageStats.blit
    gpuUsageStats.lastPack = gpuUsageStats.pack; gpuUsageStats.lastUnpack = gpuUsageStats.unpack
    gpuUsageStats.lastInvert = gpuUsageStats.invert

    gpuUsageStats.set = 0;  gpuUsageStats.fore = 0;   gpuUsageStats.back = 0
    gpuUsageStats.fill = 0; gpuUsageStats.get = 0;    gpuUsageStats.blit = 0
    gpuUsageStats.pack = 0; gpuUsageStats.unpack = 0; gpuUsageStats.invert = 0

    gpuUsageStats.lastCpuTime = gpuUsageStats.cpuTime
    gpuUsageStats.cpuTime = os.clock() or 0
    gpuUsageStats.lastFrameTime = gpuUsageStats.frameTime
    gpuUsageStats.frameTime = computer.uptime()

    gpuUsageStats.usedMem = computer.totalMemory() - computer.freeMemory()
    gpuUsageStats.usedMemTotal = gpuUsageStats.usedMemTotal + gpuUsageStats.usedMem

    local cpuTimeDiff = (gpuUsageStats.cpuTime - gpuUsageStats.lastCpuTime) * 1000
    gpuUsageStats.cpuTimeTotal = gpuUsageStats.cpuTimeTotal + cpuTimeDiff
    local frameTimeDiff = math.ceil((gpuUsageStats.frameTime - gpuUsageStats.lastFrameTime) * 1000)
    gpuUsageStats.frameTimeTotal = gpuUsageStats.frameTimeTotal + frameTimeDiff
end

-- ============================================================
-- PUSH TO SCREEN
-- ============================================================

-- Blit gpu buffer to screen
local function UpdateScreen()
    if debugMode then drawDebug() end
    DrawFrame()
    bitblt()
    takeDebugMeasurements()
end

-- ============================================================
-- DEMO
-- ============================================================

createColorLUTs()
local random = math.random
-- TODO: Make separate demo functions and loop them by pressing some key
local function drawDemoGraphics(x, y, width, height)
    ClearScreen()

    -- Benchmark whatever function needs to be tested
    if debugDoBenchmark then

    end

    -- Draw 350 random white lines
    if debugDrawWhiteLines then
        for i = 1, 50 do
            for j = 1, 7 do
                DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            end
        end
    end

    -- Draw 350 random colored lines
    local colors = {0x0000FF, 0x00FF00, 0x00FFFF, 0xFF0000, 0xFF00FF, 0xFFFF00, 0xFFFFFF}
    if debugDrawColorLines then
        for i = 1, 50 do
            for j = 1, 7 do
                DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, colors[j])
            end
        end
    end

    -- Draw all available colors in a neat grid matching the gpu's documentation page
    -- Just here to make sure the LUT's are working correclty
    if debugTestColorLUTs then
        for i = 1, 256 do
            local xPos = Modulo((i - 1), 40)
            local yPos = (i - 1) // 40

            -- We know that i from 1 - 255 returns valid hex colors
            -- We should pass these hex colors through the color index LUT to make sure they pair correctly
            local hexValue = hexLUT[i]
            local colorIndex = colLUT[hexValue]
            local retestHex = hexLUT[colorIndex]
            SetPixel(xPos + 10, yPos + 10, hexValue)
            SetPixel(xPos + 10, yPos + 25, retestHex)
        end
    end
end

-- Allocate and set active screen buffer
local function setBuffer(width, height)
    buffer = GPUAllocateBuffer(width, height)
    GPUSetActiveBuffer(buffer)
end

-- Free all buffers
local function FreeAllBuffers()
    ClearScreen()
    GPUFreeBuffer(buffer)
    GPUFreeAllBuffers() -- For safe keeping
end

-- Full clear screen to reset demo to cl
local function demoCloseClear()
    GPUSetFG(0xFFFFFF)
    GPUSetBG(0x000000)
    GPUFill(1, 1, screenWidth, screenHeight, " ")
end

-- Set graphics buffer back to default, clear screen, and exit to console
local function ResetToCommandLine()
    FreeAllBuffers()
    GPUSetFG(0xFFFFFF)
    GPUSetBG(0x000000)
    GPUFill(1, 1, screenWidth, screenHeight, " ")
    term.setCursor(1, 1)
end

-- Set main GPU and settings for Chugraph
local function SetMainGPU(g, _, useBuffer, enableDebug)

    gpu = g
    GPUAllocateBuffer = gpu.allocateBuffer
    GPUSetActiveBuffer = gpu.setActiveBuffer
    GPUFreeBuffer = gpu.freeBuffer
    GPUFreeAllBuffers = gpu.freeAllBuffers
    GPUGetRes = gpu.getResolution
    GPUSetFG = gpu.setForeground
    GPUSetBG = gpu.setBackground
    GPUSet = gpu.set
    GPUFill = gpu.fill
    GPUBitBlt = gpu.bitblt

    screenWidth, screenHeight = GPUGetRes()
    funcWidth = screenWidth; funcHeight = screenHeight * 2

    if useBuffer or false then setBuffer(screenWidth, screenHeight) end
    if enableDebug or false then debugMode = true end

    buildScreenData()
end

-- Show examples of graphical features
-- TODO: error handling
local function demoGraphics()
    SetMainGPU(component.gpu, "doubleHeight", true, true)
    ClearScreen()

    while true do
        local tEvent = table.pack(event.pull(0))
        if tEvent[1] == "key_down" then local sKey = string.upper(string.char(tEvent[3]))
            if sKey == "Q" then
                FreeAllBuffers()
                demoCloseClear()
                term.setCursor(1, 1)
                break
            end
        end

        drawDemoGraphics(5, 5, funcWidth - 10, funcHeight - 10)
        SetText(1, 1, 'Press "Q" To Exit Demo', 0xFFFFFF, 0x000000, false)
        UpdateScreen()
    end
end

-- ============================================================
-- CL OPTIONS
-- ============================================================

-- Set arguments upon startup
local function setVariables()
    if ops.w then debugDrawWhiteLines = true end
    if ops.c then debugDrawColorLines = true end
    if ops.b then debugDoBenchmark = true end
    if ops.p then
        debugTestColorLUTs = true
        createColorLUTs()
    end
    if ops.d then demoGraphics() end
end
setVariables()

print("Rendered with Chugraph " .. version)
return {
    SetMainGPU = SetMainGPU,
    ResetToCommandLine = ResetToCommandLine,
    UpdateScreen = UpdateScreen,

    ClearRegion = ClearRegion,
    ClearScreen = ClearScreen,
    SetSceneBackground = SetSceneBackground,

    GetPixel = GetPixel,
    SetPixel = SetPixel,
    SetText = SetText,
    Fill = Fill,

    GetAspectRatio = GetAspectRatio,
    GetScreenWidth = GetScreenWidth,
    GetScreenHeight = GetScreenHeight,

    ClosestValidHexFromRGB8 = ClosestValidHexFromRGB8,
    ClosestValidHexFromRGB1 = ClosestValidHexFromRGB1,
    GetGreyscaleColor = GetGreyscaleColor,
    GetShadedColor = GetShadedColor,
    BlendColor = BlendColor,

    DrawLine = DrawLine,
    DrawTriangle = DrawTriangle,
    FillTriangle = FillTriangle
}