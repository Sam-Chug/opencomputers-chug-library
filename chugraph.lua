local component = require("component")
local event = require("event")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")
local term = require("term")

local chugraph = {
    version = "0.2.0a"
}

-- Functional resolution of the screen
local funcWidth = 0
local funcHeight = 0

local gpu, buffer
local screenWidth, screenHeight

local drawingMode = 0 -- | 0 = 1x1 █ | 1 = 1x2 ▀ | 2 = 0.5 x 1 ██

local topHalfBlock = "▀"; local bottomHalfBlock = "▄"; local fullBlock = "█"
local currentForeground = -1; local currentBackground = -1

local screenBuffer = {}
local debugMode = false
local debugDrawWhiteLines = false
local debugDrawColorLines = false
local gpuUsageStats = {
    set = 0, fore = 0, back = 0, fill = 0, get = 0, blit = 0, pack = 0, unpack = 0,
    lastSet = 0, lastFore = 0, lastBack = 0, lastFill = 0, lastGet = 0, lastBlit = 0, lastPack = 0, lastUnpack = 0,
    invert = 0, lastInvert = 0,
    cpuTime = os.clock() or 0, lastCpuTime = os.clock() or 0,
    frameTime = computer.uptime() or 0, lastFrameTime = computer.uptime() or 0,
    usedMem = computer.totalMemory() - computer.freeMemory(),
    cpuTimeTotal = 0, frameTimeTotal = 0, usedMemTotal = 0
}

local Insert = table.insert
local Sub = string.sub

-- BUGS =======================================================
-- drawing doubleRes pixel on the bottom half of a text string will not be picked up by the renderer

-- TODO OPTIMIZATIONS =========================================
-- Clear function to clear only set pixels
-- Reduce memory usage
-- Look into swapping screenBuffer to a 1D array, where each index is a string containing all packed strings for that row
    -- This probably would greatly increase cpu overhead at the cost of huge memory savings

-- Benchmarking:
--       Blank Screen                                                (Values echoed for each benchmark)
--  800kb |  9ms cpu |  50ms f |   460 pack |  1976 unpack - Initial value
--  640kb |  8ms cpu |  50ms f |   460 pack |  1516 unpack - Removed unpack from addToFrameBuffer()
--  470kb |  7ms cpu |  50ms f |   460 pack |  1516 unpack - Removed bad caching tables
--  470kb |  7ms cpu |  50ms f |   460 pack |  1516 unpack - Shortened fillGroup table variable names
--  410kb |  7ms cpu |  50ms f |   460 pack |  1516 unpack - Removed iterative concat in fillGroup
--  405kb |  7ms cpu |  50ms f |   460 pack |  1516 unpack - Turned fillGroup into an array
--  405kb |  7ms cpu |  50ms f |   460 pack |   828 unpack - Function to return just forecolor from packed pixel
--  420kb |  7ms cpu |  50ms f |     3 fore |     2 back   - Pack/Unpack fully optimized(?) now optimize fore/back
--  420kb |  7ms cpu |  50ms f |     3 fore |     2 back   - Further optimized setFore/setBack
--  420kb |  7ms cpu |  50ms f |     3 fore |     2 back   - Optimized drawing groups to use less ram
--  405kb |  5ms cpu |  50ms f |     3 fore |     2 back   - Optimized resetting screenBuffer's update byte
--  435kb |  3ms cpu |  50ms f |     3 fore |     2 back   - Moved pixel update reset to drawFrame
--  435kb |  3ms cpu |  50ms f |   504 pack |   144 unpack - Optimized pixel unpacking
--  400kb |  3ms cpu |  50ms f |   504 pack |   144 unpack - Less garbage produced while unpacking
--  390kb |  4ms cpu |  50ms f |   504 pack |   144 unpack - Turned screenBuffer into 1D array
--  370kb |  4ms cpu |  50ms f |   504 pack |     0 unpack - Removed string.unpack, Cleaned up things that may become garbage

--      350 White Lines
--  770kb | 41ms cpu | 102ms f | 22000 pack | 37000 unpack - 
--  820kb | 28ms cpu |  98ms f | 22000 pack | 14500 unpack - 
--  620kb | 21ms cpu |  52ms f | 22000 pack | 14500 unpack - 
--  600kb | 20ms cpu |  51ms f | 22000 pack | 14500 unpack - 
--  790kb | 19ms cpu |  50ms f | 22000 pack | 14500 unpack - 
--  780kb | 19ms cpu |  50ms f | 22000 pack | 14500 unpack - 
--  690kb | 18ms cpu |  50ms f | 22000 pack |  7400 unpack - 
--  680kb | 19ms cpu |  50ms f |     3 fore |     7 back   - 
--  690kb | 18ms cpu |  50ms f |     3 fore |     4 back   - Seems good for 2 colors
--  690kb | 18ms cpu |  50ms f |     3 fore |     4 back   - 
--  680kb | 16ms cpu |  50ms f |     3 fore |     4 back   - 
--  770kb | 15ms cpu |  50ms f |     3 fore |     4 back   - Seems more ram hungry
--  770kb | 15ms cpu |  50ms f | 22000 pack |   149 unpack - Seems more ram hungry
--  700kb | 16ms cpu |  50ms f | 22000 pack |   149 unpack - Decent ram savings
--  660kb | 16ms cpu |  50ms f | 22000 pack |     0 unpack - 

--      350 Color Lines
-- 1250kb | 76ms cpu | 135ms f | 23000 pack | 44000 unpack - 
-- 1320kb | 62ms cpu | 100ms f | 23000 pack | 22000 unpack - 
-- 1200kb | 51ms cpu | 100ms f | 23000 pack | 22000 unpack - 
-- 1100kb | 50ms cpu | 100ms f | 23000 pack | 22000 unpack - Inconsistent ram usage
-- 1100kb | 51ms cpu | 100ms f | 23000 pack | 22000 unpack - Inconsistent ram usage
-- 1100kb | 51ms cpu | 100ms f | 23000 pack | 22000 unpack - More consistent ram usage, but leaks
-- 1200kb | 49ms cpu | 100ms f | 23000 pack | 10800 unpack - Seems more stable, less leaky
-- 1050kb | 52ms cpu | 100ms f |     9 fore |    68 back   - 
-- 1050kb | 50ms cpu | 100ms f |     9 fore |    66 back   - Not as good as I thought
--  830kb | 49ms cpu | 100ms f |    10 fore |    66 back   - Saves a ton of memory
--  820kb | 47ms cpu | 100ms f |    10 fore |    66 back   - 
--  810kb | 47ms cpu | 100ms f |    10 fore |    66 back   - Not much of a change
--  810kb | 45ms cpu | 100ms f | 23000 pack |   156 unpack - 
--  810kb | 46ms cpu | 100ms f | 23000 pack |   156 unpack - 
--  720kb | 45ms cpu | 100ms f | 23000 pack |     0 unpack - 

-- TODO ==============================================
-- move demo to separate file
-- refit chugraph to work entirely with the 1x2 pixel format:
    -- too many options to flex between all without bloat
    -- different resolutions would likely have different color spaces, namely braille

-- SETTINGS ===================================================

-- Set how pixels should be rendered to the screen, either as full text blocks or some fractional text block
local function setResolutionMode(resMode)
    if resMode == "basic" then
        drawingMode = 0
        funcWidth = screenWidth; funcHeight = screenHeight
    elseif resMode == "doubleHeight" then
        drawingMode = 1
        funcWidth = screenWidth; funcHeight = screenHeight * 2
    elseif resMode == "halfWidth" then
        drawingMode = 2
        funcWidth = screenWidth // 2; funcHeight = screenHeight
    end
end

local function setBuffer(width, height)
    buffer = gpu.allocateBuffer(width, height)
    gpu.setActiveBuffer(buffer)
end

local function FreeAllBuffers()
    chugraph.ClearScreen()
    gpu.freeBuffer(buffer)
    gpu.freeAllBuffers()
end

-- Pack/unpack pixel format
-- Packed string is 8 bytes
-- I3: Fore, I3: Back, B: Char, B; Update
local packingFormat = "I3I3BB"

-- Wants lua numbers
local function unpackPixel(x, y)
    -- If index < 1 or index >= funcWidth * funcHeight then print(index) end
    gpuUsageStats.unpack = gpuUsageStats.unpack + 1
    return string.unpack(packingFormat, screenBuffer[y * funcWidth + x])
end

local function packPixel(x, y, fore, back, char, update)
    gpuUsageStats.pack = gpuUsageStats.pack + 1
    screenBuffer[y * funcWidth + x] = packingFormat:pack(fore, back, string.byte(char), update or 1)
end

local function getPixelChar(x, y)
    return screenBuffer[y * funcWidth + x]:byte(-2)
end

-- Return if second-to-last byte is an empty space or not
local function getPixelTextState(x, y)
    return screenBuffer[y * funcWidth + x]:byte(-2) ~= 1
end

-- Return last byte in packed string, the update byte
local function getPixelUpdateState(x, y)
    return screenBuffer[y * funcWidth + x]:byte(-1)
end

-- Return color value from packed string, first three bytes
local function getPixelForeColor(x, y)
    local b, g, r = screenBuffer[y * funcWidth + x]:byte(1, 3)
    return (r << 16) + (g << 8) + b
end

local function getPixelBackColor(x, y)
    local b, g, r = screenBuffer[y * funcWidth + x]:byte(4, 6)
    return (r << 16) + (g << 8) + b
end

-- Set empty screen buffer
-- Fore, Back, Char, isText, Update
local packedPixelTemplate
local function buildScreenData()
    screenBuffer = {}
    packedPixelTemplate = packingFormat:pack(0x000000, 0x000000, string.byte(""), 0)
    for i = 1, funcWidth * funcHeight do
        Insert(screenBuffer, packedPixelTemplate)
    end
end

-- Reset all pixels within region to default values
local function resetUpdateForRegion(x, y, width, height)
    for i = 0, width - 1 do
        for j = 0, height - 1 do
            screenBuffer[(y + j) * funcWidth + (x + i)] = packedPixelTemplate
        end
    end
end

-- Set main GPU and settings for Chugraph
function chugraph.SetMainGPU(g, resMode, useBuffer, enableDebug)
    gpu = g; -- TODO: detect gpu tier

    screenWidth, screenHeight = gpu.getResolution()
    setResolutionMode(resMode or "basic")

    if useBuffer or false then setBuffer(screenWidth, screenHeight) end
    if enableDebug or false then debugMode = true end

    buildScreenData()
end

-- Set graphics buffer back to default, clear screen, and exit to console
function chugraph.ResetToCommandLine()
    FreeAllBuffers()
    gpu.setForeground(0xFFFFFF)
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, screenWidth, screenHeight, " ")
    term.setCursor(1, 1)
end

-- GPU DRAWING ================================================

local function bitblt()
    gpu.bitblt(0, 1, 1, screenWidth, screenHeight, buffer, 1, 1)
    gpuUsageStats.blit = gpuUsageStats.blit + 1
end

-- Set foreground drawing color
local function setForeground(color)
    if currentForeground ~= color then
        gpu.setForeground(color)
        gpuUsageStats.fore = gpuUsageStats.fore + 1;
        currentForeground = color
    end
end

-- Set background drawing color
local function setBackground(color)
    if currentBackground ~= color then
        gpu.setBackground(color)
        gpuUsageStats.back = gpuUsageStats.back + 1;
        currentBackground = color
    end
end

-- Set string to screen
local function set(x, y, foreColor, backColor, string)
    setForeground(foreColor)
    setBackground(backColor)

    gpu.set(x, y, string)
    gpuUsageStats.set = gpuUsageStats.set + 1
end

-- Compile char string and draw it at position
local function drawCharGroup(drawGroups)
    for rKey, rVal in pairs(drawGroups) do
        for cKey, cVal in pairs(rVal) do
            for i = 1, #cVal.x do
                set(cVal.x[i], cVal.y[i], rKey, cKey, cVal.s[i])
            end
        end
    end
end

-- Check if pixel requires a redraw, also checks for other screen res modes
local function needsUpdate(x, y)
    local checkForUpdate = getPixelUpdateState(x, y) -- this pixel
    if drawingMode == 0 then return checkForUpdate -- basic mode
    elseif drawingMode == 1 then -- if doubleHeight then check pixel below
        local nextYUpdate = getPixelUpdateState(x, y + 1)
        if checkForUpdate == 1 or nextYUpdate == 1 then return 1 end
        else return 0
    end
    return 0
end

-- Return inverse character based on current screen res mode
local function getInverseChar(char)
    if char == topHalfBlock then
        return bottomHalfBlock
    elseif char == bottomHalfBlock then
        return topHalfBlock
    elseif char == fullBlock then
        return " "
    elseif char == " " then
        return fullBlock
    end
    return char
end

-- Use real-screen coordinates to return compiled pixel data based on the set drawing mode
local function returnPixelData(x, y)

    -- If text, return letter and fore/back color
    local char = getPixelChar(x, y)
    if char ~= 1 then
        return getPixelForeColor(x, y), getPixelBackColor(x, y), string.char(char), true

    -- Else, this is a filled pixel so return back color
    else
        -- Only unpack pixel data if the index needs an update
        local fore = getPixelForeColor(x, y)

        -- Package pixel's sprites and fore/back colors
        if drawingMode == 0 then

            -- Basic pixel TODO this is probably broken
            local back = getPixelBackColor(x, y)
            return fore, back, fullBlock, false

        elseif drawingMode == 1 then -- Double Y resolution

            -- If top pixel set, both pixels require an update
            local downFore = getPixelForeColor(x, y + 1)
            if fore == downFore then
                -- same color, send full block
                return fore, downFore, fullBlock, false
            else
                -- different color, send half block
                return fore, downFore, topHalfBlock, false
            end
        end
    end
end

-- Loop through screenBuffer and draw pixels that were changed this frame
local function DrawFrame()
    local xInc = 1; local yInc = 1
    if drawingMode == 1 then -- TODO: Having these checks everywhere might be stupid
        yInc = 2
    end

    -- Holder variables
    local xSkipIndex = 0
    local drawGroup = {}

    -- Cache variables before iterating
    local fillGroup = {}
    local twoColCheck = false
    local startFore, startBack, startChar, startText = 0, 0, " ", false
    local newFore, newBack, newChar, newText = 0, 0, " ", false
    local checkLen = 0
    local indexTop = 0
    local indexBot = 0

    for y = 1, funcHeight, yInc do -- For each line,
        for x = 1, funcWidth, xInc do -- Run each pixel 
            if x + xSkipIndex > funcWidth then goto skipx end

            -- If pixel doesn't require update, skip
            if needsUpdate(x + xSkipIndex, y) == 0 then goto continue end

            -- Fore is the color of the first pixel put to the screen, (favor top-most pixel?)
            -- Back is the background of the first pixel put to the screen
            -- If initially the same, set back to the first available second

            -- Mark pixel as finished updating
            indexTop = y * funcWidth + x + xSkipIndex
            indexBot = (y + 1) * funcWidth + x + xSkipIndex
            screenBuffer[indexTop] = Sub(screenBuffer[indexTop], 1, -2) .. "\0"
            screenBuffer[indexBot] = Sub(screenBuffer[indexBot], 1, -2) .. "\0"

            -- Get starting fill fillgroup values
            startFore, startBack, startChar, startText = returnPixelData(x + xSkipIndex, y)

            -- Start fill group
            fillGroup = {x + xSkipIndex, (y // yInc) + 1, startFore, startBack}
            local charString = {startChar}; local charsAdded = 1
            twoColCheck = false
            while true do -- loop until non-matching pixel found

                -- Get next pixel in row
                checkLen = charsAdded
                if xSkipIndex + x + 1 > funcWidth then break end
                newFore, newBack, newChar, newText = returnPixelData(x + xSkipIndex + 1, y)

                -- If pixel's text state changes, break
                if startText ~= newText then break end

                -- If new fore/back are the same
                if newFore == newBack then

                    -- If original fore/back are the same
                    if fillGroup[3] == fillGroup[4] then

                        -- If new colors equal to original, insert returned char
                        if newFore == fillGroup[3] then
                            Insert(charString, newChar)
                            charsAdded = charsAdded + 1
                        -- Otherwise, return inversed char, and set new color to original back
                        else
                            Insert(charString, getInverseChar(newChar))
                            charsAdded = charsAdded + 1
                            fillGroup[4] = newBack
                        end

                    -- If original fore/back are not the same
                    elseif fillGroup[3] ~= fillGroup[4] then

                        -- If new fore and original fore match, insert returned char
                        if fillGroup[3] == newFore then
                            Insert(charString, newChar)
                            charsAdded = charsAdded + 1
                        -- If new fore and original back match, insert inverted char
                        elseif fillGroup[4] == newFore then
                            Insert(charString, getInverseChar(newChar))
                            charsAdded = charsAdded + 1
                        end
                    end
                -- If new fore/back are not the same
                else
                    -- If original fore/back are the same
                    if fillGroup[3] == fillGroup[4] then

                        -- If new fore matches original fore, insert returned char and set original back to new fore
                        if newFore == fillGroup[3] then
                            Insert(charString, newChar)
                            charsAdded = charsAdded + 1
                            fillGroup[4] = newBack
                        -- If new back matches original fore, then insert inverted char and set original back to new fore
                        elseif newBack == fillGroup[3] then
                            Insert(charString, getInverseChar(newChar))
                            charsAdded = charsAdded + 1
                            fillGroup[4] = newFore
                        end

                    -- New and original match exactly, insert returned char
                    elseif fillGroup[3] == newFore and fillGroup[4] == newBack then
                        Insert(charString, newChar)
                        charsAdded = charsAdded + 1

                    -- New and original match but are inverted, return inverted char
                    elseif fillGroup[3] == newBack and fillGroup[4] == newFore then
                        Insert(charString, getInverseChar(newChar))
                        charsAdded = charsAdded + 1
                    else break end
                end

                -- If no new chars added to draw string, exit loop
                if charsAdded == checkLen then
                    break
                -- Else, pixel is ready to draw and no longer requires updating
                else
                    screenBuffer[indexTop + 1] = Sub(screenBuffer[indexTop + 1], 1, -2) .. "\0"
                    screenBuffer[indexBot + 1] = Sub(screenBuffer[indexBot + 1], 1, -2) .. "\0"
                end

                -- Colors different, sort colors by numerical value
                -- If need to swap, inverse characters in string
                if (not twoColCheck) and (fillGroup[3] ~= fillGroup[4]) and (not startText) then
                    if fillGroup[3] < fillGroup[4] then
                        for i = 1, charsAdded do
                            charString[i] = getInverseChar(charString[i])
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
                drawGroup[fillGroup[3]][fillGroup[4]] = {x = {}, y = {}, s = {}}
            end
            Insert(drawGroup[fillGroup[3]][fillGroup[4]].x, fillGroup[1])
            Insert(drawGroup[fillGroup[3]][fillGroup[4]].y, fillGroup[2])
            Insert(drawGroup[fillGroup[3]][fillGroup[4]].s, table.concat(charString))

            fillGroup = nil
            ::continue::
        end
        ::skipx::
        xSkipIndex = 0
    end
    -- Finally, draw and apply new frame data, then reset update value for all pixels
    drawCharGroup(drawGroup)
    drawGroup = nil
end

-- GET/SET ====================================================

-- Set index to input pixel data
local function addToFrameBuffer(x, y, foreColor, backColor, char)

    x = x // 1; y = y // 1
    if x < 1 or x > funcWidth or y < 1 or y > funcHeight then return end

    -- If char specified, set char
    -- Otherwise is pixel, so set empty space
    if backColor == nil then backColor = foreColor end
    packPixel(x, y, foreColor, backColor, char or "")
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
function chugraph.Fill(x, y, width, height, foreColor, backColor)
    for i = x, x + width - 1 do
        for j = y, y + height - 1 do
            addToFrameBuffer(i, j, foreColor, backColor)
        end
    end
end

-- Clear region, send straight to gpu command, then loop and reset updates
function chugraph.ClearRegion(x, y, width, height)

    -- TODO: Handle fractional pixel clears, clear basic-sized pixel here and send fractionals to update regularly
    local widthFixed = width; local heightFixed = height
    local xFixed = x; local yFixed = y
    if drawingMode == 1 then
        heightFixed = (height // 2) + 1
        yFixed = (y // 2) + 1
    end

    resetUpdateForRegion(x, y, width, height)

    setForeground(0x000000); setBackground(0x000000)
    gpu.fill(xFixed, yFixed, widthFixed, heightFixed, " ")
    gpuUsageStats.fill = gpuUsageStats.fill + 1
end

function chugraph.ClearScreen()
    chugraph.ClearRegion(1, 1, funcWidth, funcHeight)
end

-- Return pixel data
function chugraph.GetPixel(x, y)
    -- TODO: This probably doesn't work after changing how chars are stored
    local fore, back, char = unpackPixel(x, y)
    return string.char(char) or " ", fore, back
end

-- Set text to screen, rounds to nearest 
function chugraph.SetText(x, y, string, foreColor, backColor, vertical)
    local fixedX = x; local fixedY = y -- Crush pos into basic resolution pos, based on current functional screen res
    if drawingMode == 1 then -- doubleheight
        fixedY = (((fixedY + 1) // 2) * 2) - 1
    end

    textToFrameBuffer(fixedX, fixedY, foreColor, backColor, string, vertical or false)
end

function chugraph.SetPixel(x, y, color)
    addToFrameBuffer(x, y, color)
end

function chugraph.GetAspectRatio()
    return funcHeight / funcWidth
end

function chugraph.GetScreenWidth()
    return funcWidth
end

function chugraph.GetScreenHeight()
    return funcHeight
end

-- COLOR ======================================================

function chugraph.GetGreyscaleColor(value)
    if value ~= value then return 0xFF0000 end

    value = math.floor(value * 16) * 15
    value = (value * 256 * 256) + (value * 256) + value
    value = math.max(math.min(value, 0xFFFFFF), 0x000000)
    return value
end

-- MATH =======================================================

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
        chugraph.SetPixel(x, y, color)
        if D > 0 then
            y = y + yi; D = D + (2 * (dy - dx))
        else
            D = D + (2 * dy)
        end
    end
end

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
        chugraph.SetPixel(x, y, color)
        if D > 0 then
            x = x + xi; D = D + (2 * (dx - dy))
        else
            D = D + (2 * dx)
        end
    end
end

-- Draw line from one point to the other
function chugraph.DrawLine(x1, y1, x2, y2, color)
    x1 = x1 // 1; y1 = y1 // 1
    x2 = x2 // 1; y2 = y2 // 1
    if math.abs(y2 - y1) < math.abs(x2 - x1) then
        if x1 > x2 then drawLineLow(x2, y2, x1, y1, color)
        else drawLineLow(x1, y1, x2, y2, color) end
    else
        if y1 > y2 then drawLineHigh(x2, y2, x1, y1, color)
        else drawLineHigh(x1, y1, x2, y2, color) end
    end
end

-- Draw triangle from three sets of points
function chugraph.DrawTriangle(tri, color)

    chugraph.DrawLine(tri[1].x, tri[1].y, tri[2].x, tri[2].y, color)
    chugraph.DrawLine(tri[2].x, tri[2].y, tri[3].x, tri[3].y, color)
    chugraph.DrawLine(tri[3].x, tri[3].y, tri[1].x, tri[1].y, color)
end

local function fillFlatBottomTriangle(x1, y1, x2, y2, x3, y3, color)
    local invSlope1 = (x2 - x1) / (y2 - y1)
    local invSlope2 = (x3 - x1) / (y3 - y1)
    local xStart = x1
    local xEnd = x1

    for y = y1, y3 do
        chugraph.DrawLine(xStart // 1, y, xEnd // 1, y, color)
        xStart = xStart + invSlope1
        xEnd = xEnd + invSlope2
    end
end

local function fillFlatTopTriangle(x1, y1, x2, y2, x3, y3, color)
    local invSlope1 = (x3 - x1) / (y3 - y1)
    local invSlope2 = (x3 - x2) / (y3 - y2)

    local xStart = x3
    local xEnd = x3

    for y = y3, y2, -1 do
        chugraph.DrawLine(xStart // 1, y, xEnd // 1, y, color)
        xStart = xStart - invSlope1
        xEnd = xEnd - invSlope2
    end
end

-- FillTriangle sources:
-- https://mclark45.medium.com/scanline-based-triangle-filling-harnessing-flat-bottom-and-flat-top-configurations-00d2994da20f
-- https://www.sunshine2k.de/coding/java/TriangleRasterization/TriangleRasterization.html

-- Fill triangle specified by input point set and color
function chugraph.FillTriangle(tri, color)

    -- rounding down removes gaps between top/bottom tris
    -- look at how 3dtest handles filling tris for better coordinate handling
    local x1 = tri[1].x // 1; local y1 = tri[1].y // 1
    local x2 = tri[2].x // 1; local y2 = tri[2].y // 1
    local x3 = tri[3].x // 1; local y3 = tri[3].y // 1

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

-- DEBUG ======================================================

-- Memory
local memDiv = 1024 -- Measuring KB
local memString = "KB"

-- Debug Tracking
local debugTimeCycles = 2; local debugCycleReset = 200
local debugForeColor = 0xFFFFFF; local debugBackColor = 0x330040

-- Write debug stats to graphcis buffer
local function drawDebug()

    -- Log cpu usage time and the time since last frame shown (50ms is optimal)
    local averageCpuTime = gpuUsageStats.cpuTimeTotal / debugTimeCycles
    local averageFrameTime = gpuUsageStats.frameTimeTotal // debugTimeCycles
    local averageUsedMem = gpuUsageStats.usedMemTotal // debugTimeCycles

    local cpuTimeDiff = (gpuUsageStats.cpuTime - gpuUsageStats.lastCpuTime) * 1000
    local frameTimeDiff = math.ceil((gpuUsageStats.frameTime - gpuUsageStats.lastFrameTime) * 1000)

    -- Draw debug information to screen
    local line1 = string.format("SET: %5d | FILL: %4d | PACK: %5d", gpuUsageStats.lastSet, gpuUsageStats.lastFill, gpuUsageStats.lastPack)
    local line2 = string.format("SFORE: %3d | SBACK: %3d | INVR: %5d", gpuUsageStats.lastFore, gpuUsageStats.lastBack, gpuUsageStats.lastInvert)
    local line3 = string.format("CPU: %6.1fms | AVG: %6.1fms", cpuTimeDiff, averageCpuTime)
    local line4 = string.format("GPU: %6.1fms | AVG: %6.1fms", 1.0, 1.0)
    local line5 = string.format("FRAME: %4dms | AVG:   %4dms", frameTimeDiff, averageFrameTime)
    local line6 = string.format("MEM: %6.1f%s | AVG: %6.1f%s", gpuUsageStats.usedMem / memDiv, memString, averageUsedMem / memDiv, memString)
    chugraph.Fill(1, funcHeight - 13, 38, 14, debugBackColor, debugBackColor)
    chugraph.SetText(1, funcHeight - 12, line1, debugForeColor, debugBackColor, false)
    chugraph.SetText(1, funcHeight - 10, line2, debugForeColor, debugBackColor, false)
    chugraph.SetText(1, funcHeight - 8,"--------------------------------------", debugForeColor, debugBackColor, false)
    chugraph.SetText(1, funcHeight - 6, line3, debugForeColor, debugBackColor, false)
    chugraph.SetText(1, funcHeight - 4, line4, debugForeColor, debugBackColor, false)
    chugraph.SetText(1, funcHeight - 2, line5, debugForeColor, debugBackColor, false)
    chugraph.SetText(1, funcHeight - 0, line6, debugForeColor, debugBackColor, false)

    debugTimeCycles = debugTimeCycles + 1
    if debugTimeCycles > debugCycleReset then
        gpuUsageStats.cpuTimeTotal = averageCpuTime
        gpuUsageStats.frameTimeTotal = averageFrameTime
        gpuUsageStats.usedMemTotal = averageUsedMem
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

    gpuUsageStats.set = 0; gpuUsageStats.fore = 0; gpuUsageStats.back = 0
    gpuUsageStats.fill = 0; gpuUsageStats.get = 0; gpuUsageStats.blit = 0
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

-- PUSH TO SCREEN =================================

-- Blit gpu buffer to screen
function chugraph.UpdateScreen()
    if debugMode then drawDebug() end
    DrawFrame()
    bitblt()

    takeDebugMeasurements()
end

-- DEMO ===========================================

-- TODO: Make separate demo functions and loop them by pressing some key
-- Draw a random line inside rect
local random = math.random
local function demoDrawRandomLine(x, y, width, height)

    -- TODO right-most + bottom-most side is not being cleared
    -- Either ClearRegion() isnt built correctly or DrawLine is drawing longer than it should
    chugraph.ClearScreen()
    if debugDrawColorLines then
        for i = 1, 50 do
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFF0000)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0x00FF00)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0x0000FF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFF00)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0x00FFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFF00FF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
        end
    end

    if debugDrawWhiteLines then
        for i = 1, 50 do
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
            chugraph.DrawLine(random(1, width) + x, random(1, height) + y, random(1, width) + x, random(1, height) + y, 0xFFFFFF)
        end
    end
end

-- Full clear screen to reset demo to cl
local function demoCloseClear()
    gpu.setForeground(0xFFFFFF)
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, screenWidth, screenHeight, " ")
end

-- Show examples of graphical features
-- TODO: error handling
local function demoGraphics()
    chugraph.SetMainGPU(component.gpu, "doubleHeight", true, true)
    chugraph.ClearScreen()

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

        demoDrawRandomLine(5, 5, funcWidth - 5, funcHeight - 5)
        chugraph.SetText(1, 1, 'Press "Q" To Exit Demo', 0xFFFFFF, 0x000000, false)
        chugraph.UpdateScreen()
    end
end

-- CL OPTIONS =================================================

-- set arguments upon startup
local function setVariables()
    if ops.w then debugDrawWhiteLines = true end
    if ops.c then debugDrawColorLines = true end
    if ops.d then demoGraphics() end
end
setVariables()
-- demoGraphics()

-- CREDITS
print("Drawn By Chugraph " .. chugraph.version)
return chugraph