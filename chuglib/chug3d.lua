local component = require("component")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")
local version = "0.1.0a"

-- ============================================================
-- CREDITS
-- The code here was originally built following a tutorial by Javidx9 on youtube
-- "Code-It-Yourself! 3D Graphics Engine" -> https://youtu.be/ih20l3pJoeU
-- Since then, I have done what I could to make this run faster in a low-memory lua environment.
-- What results is some terribly unreadable code.
-- ============================================================

-- Graphics Library
local gpu = require("chugraph")
gpu.SetMainGPU(component.gpu, "doubleHeight", true, true)

-- Input manager
local inputManager = require("chugkey")

-- ============================================================
-- RENDER CONFIGS
-- ============================================================

local doNormalFlatColoring = false
local doDepthBufferColoring = false
local doShadedColoring = false

local doModelRotate = false
local doModelRotateX = false
local doModelRotateZ = false
local doModelRotateY = false

local doDrawTextured = true
local doDrawFlatShaded = false -- Not yet implemented
local doDrawWireframe = false
local doDepthBlending = false

local backgroundColor = 0x00DBFF
local depthFadeDist = 0.4 -- 
local bfcThreshold = 0.0 -- Cull any face whos dot product against camera normal is above this
local bfcLazyThreshold = 0.8 -- Lazy backface culling threshold. Faces turned this far away should be lazy occluded
local lightDirection = {0.1, 0.1, -1} -- [Sunlight-ish](0.3, 1, 0) | [Topdown-ish](0.1, 0.1, -1)
local shadeMaximum = 5 / 16 -- Maximum darkness in the most shaded areas
local lightBias = 0.3 -- Softens faces that are 90 degrees offset to light direction
local fNear = 0.25
local fFar = 1000
local fFov = 90

local modelFile = "teapot.obj"

local function setVariables()
    -- load model from input filename
    if ops.model ~= nil then
        if string.find(ops.model, ".obj") == nil then
            modelFile = ops.model .. ".obj"
        else modelFile = ops.model end
    end
    if ops.back ~= nil then
        backgroundColor = ops.back + 0
    end
    if ops.n then doNormalFlatColoring = true end
    if ops.d then doDepthBufferColoring = true end
    if ops.s then doShadedColoring = true end
    if ops.b then doDepthBlending = true end
    if ops.r then
        doModelRotate = true
        if ops.x then doModelRotateX = true
        elseif ops.z then doModelRotateZ = true
        elseif ops.y then doModelRotateY = true
        else
            doModelRotateX = true
            doModelRotateZ = true
            doModelRotateY = true
        end
    end
    if ops.w then doDrawWireframe = true end
end
setVariables()

-- ============================================================
-- LUA NONSENSE
-- ============================================================

local cos = math.cos; local sin = math.sin; local tan = math.tan
local min = math.min; local max = math.max; local abs = math.abs
local mod = math.fmod; local random = math.random
local GetCPUTime = os.clock

local ClearScreen = gpu.ClearScreen; local UpdateScreen = gpu.UpdateScreen
local SetText = gpu.SetText; local SetPixel = gpu.SetPixel
local DrawTriangle = gpu.DrawTriangle; local FillTriangle = gpu.FillTriangle
local GetGreyscaleColor = gpu.GetGreyscaleColor; local GetShadedColor = gpu.GetShadedColor
local BlendColor = gpu.BlendColor

local TInsert = table.insert; local TRemove = table.remove
local vertCount = 0

-- ============================================================
-- TEXTURES (Move to chugraph?)
-- ============================================================

-- local missingTex = {
--     {0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D},
--     {0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C},
--     {0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0},
--     {0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF},
--     {0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D},
--     {0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C},
--     {0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0},
--     {0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF},
--     {0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D},
--     {0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C},
--     {0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0},
--     {0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF},
--     {0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D},
--     {0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C},
--     {0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0, 0x1E1E1E, 0x2D2D2D, 0xCC00C0, 0xFF00C0},
--     {0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF, 0x2D2D2D, 0x3C3C3C, 0xFF00C0, 0xFF00FF},
-- }

local missingTex = {
    {0xFF00FF, 0x2D2D2D, 0xFF00FF, 0x2D2D2D},
    {0x2D2D2D, 0xFF00FF, 0x2D2D2D, 0xFF00FF},
    {0xFF00FF, 0x2D2D2D, 0xFF00FF, 0x2D2D2D},
    {0x2D2D2D, 0xFF00FF, 0x2D2D2D, 0xFF00FF},
}

local grassSide = { -- Grass block side
    {0x33B640, 0x009200, 0x339240, 0x009200, 0x33B640, 0x009200, 0x339240, 0x339240},
    {0x009200, 0x33B640, 0x339240, 0x339240, 0x009200, 0x339240, 0x009200, 0x339240},
    {0x339240, 0x339240, 0x009200, 0x664900, 0x339240, 0x339240, 0x664900, 0x009200},
    {0x664940, 0x009200, 0x664900, 0x664900, 0x339240, 0x664940, 0x664940, 0x664940},
    {0x664900, 0x664940, 0x787878, 0x664940, 0x664900, 0x664900, 0x664940, 0x664900},
    {0x664940, 0x994900, 0x994900, 0x664940, 0x664940, 0x664940, 0x994900, 0x787878},
    {0x664940, 0x664940, 0x664940, 0x664900, 0x664940, 0x994900, 0x664940, 0x664940},
    {0x664940, 0x664900, 0x664900, 0x787878, 0x664940, 0x664940, 0x664900, 0x664940}
}
local grassTop = { -- Grass block side
    {0x33B640, 0x009200, 0x009200, 0x009200, 0x33B640, 0x33B640, 0x339240, 0x009200},
    {0x009200, 0x33B640, 0x33B640, 0x339240, 0x009200, 0x339240, 0x009200, 0x33B640},
    {0x33B640, 0x009200, 0x339240, 0x009200, 0x33B640, 0x009200, 0x009200, 0x009200},
    {0x339240, 0x33B640, 0x009200, 0x009200, 0x33B640, 0x339240, 0x33B640, 0x339240},
    {0x33B640, 0x009200, 0x339240, 0x33B640, 0x339240, 0x009200, 0x339240, 0x009200},
    {0x009200, 0x33B640, 0x009200, 0x339240, 0x009200, 0x339240, 0x009200, 0x33B640},
    {0x33B640, 0x339240, 0x009200, 0x009200, 0x33B640, 0x33B640, 0x339240, 0x339240},
    {0x009200, 0x33B640, 0x339240, 0x339240, 0x009200, 0x339240, 0x009200, 0x339240}
}
local grassBottom = { -- Grass block side
    {0x664900, 0x664940, 0x787878, 0x664940, 0x664900, 0x664900, 0x664940, 0x664900},
    {0x664940, 0x994900, 0x994900, 0x664940, 0x664940, 0x664940, 0x994900, 0x787878},
    {0x664940, 0x664940, 0x664940, 0x664900, 0x664940, 0x994900, 0x664940, 0x664940},
    {0x664940, 0x664900, 0x664900, 0x787878, 0x664940, 0x664940, 0x664900, 0x664940},
    {0x664900, 0x664940, 0x787878, 0x664940, 0x664900, 0x664900, 0x664940, 0x664900},
    {0x664940, 0x994900, 0x994900, 0x664940, 0x664940, 0x664940, 0x994900, 0x787878},
    {0x664940, 0x664940, 0x664940, 0x664900, 0x664940, 0x994900, 0x664940, 0x664940},
    {0x664940, 0x664900, 0x664900, 0x787878, 0x664940, 0x664940, 0x664900, 0x664940}
}

local loadedTextures = {{name = "missingTex", w = #missingTex, h = #missingTex[1], tex = missingTex}}

-- ============================================================
-- STRUCTS
-- ============================================================

-- Some notes:
-- Vec2D ---- Array -> [u] [v] [w]
-- Vec3D ---- Array -> [x] [y] [z] [w]

-- TODO: Potential optimization ->
-- Triangle - Array -> [3 Points[Vec3D]] [3 UVs[Vec2D]] [Tex] [Col] [Lighting Value]
-- This was tried and benchmarked for a ~3% cpu performance boost
-- I don't mind making the code harder to read but the resulting madness is not worth that small of an improvement

local function Vec2D(u, v, w)
    return {u or 0, v or 0, w or 1}
end

local function Vec3D(x, y, z, w)
    return {x or 0, y or 0, z or 0, w or 1}
end

-- Triangle as an array, to save on memory
local function FastTriangle()
    return {{{0, 0, 0, 1}, {0, 0, 0, 1}, {0, 0, 0, 1}}, {{0, 0, 1}, {0, 0, 1}, {0, 0, 1}}, 1, 1, 1}
end

-- Triangle with KV pairs
local function Triangle(vec1, vec2, vec3, uv1, uv2, uv3, texName)

    -- TODO: Move this to where the mesh is loaded
    --  -> Triangles should not always be asking for a texture
    -- local texIndex = 1 -- 1 is the fallback for a missing texture
    -- if texName ~= nil then
    --     -- look for texture in loaded textures
    --     for i = 1, #loadedTextures do
    --         if texName == loadedTextures[i].name then
    --             texIndex = i
    --             goto addtri end
    --     end
    -- end
    -- ::addtri::

    return {
        p = {vec1 or {0, 0, 0, 1}, vec2 or {0, 0, 0, 1}, vec3 or {0, 0, 0, 1}}, -- Points
        t = {uv1 or {0, 0, 1}, uv2 or {0, 1, 1}, uv3 or {1, 1, 1}},             -- Texture Coordinates
        tex = 1,                                                                -- Texture index (in loadedTextures)
        col = 0x000000,                                                         -- Color (if flat-colored)
        l = 0,                                                                  -- Lighting Value (0-1)
    }
end

local function Mat4x4()
    return {
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0},
        {0, 0, 0, 0}
    }
end

-- ============================================================
-- MESH PARSING
-- ============================================================

-- Load .obj from file at filenam, parse vertex/face data and build a list of triangles from it 
local function getMeshFromFile(filename)
    local f = io.open(filename, "r")
    if f then
        f:close()
        local verts = {}
        local tris = {}
        local uvs = {}
        for line in io.lines(filename) do
            local data = {}
            for item in line:gmatch("%S+") do
                TInsert(data, item)
            end
            if data == nil or data[1] == nil then goto continue end

            -- Vertex position
            if data[1] == "v" then
                TInsert(verts, {tonumber(data[2]), tonumber(data[3]), tonumber(data[4]), 1})

            -- TODO: Vertex normals, could do shading eventually
            elseif data[1] == "vn" then
                -- Do nothing... for now....

            -- UVs
            elseif data[1] == "vt" then
                TInsert(uvs, Vec2D(tonumber(data[2]), tonumber(data[3])))

            -- Face data
            elseif data[1] == "f" then

                -- Check if face data packs other information inside
                local _, parts = data[2]:gsub("/", "")

                -- If more information than points given, then parse it
                if parts == 1 then

                    local pointData = {}
                    for i = 1, 3 do
                        for item in data[1 + i]:gmatch("%d+") do
                            TInsert(pointData, tonumber(item))
                        end
                    end

                    TInsert(tris, Triangle(
                        {verts[pointData[1]][1], verts[pointData[1]][2], verts[pointData[1]][3], 1},
                        {verts[pointData[3]][1], verts[pointData[3]][2], verts[pointData[3]][3], 1},
                        {verts[pointData[5]][1], verts[pointData[5]][2], verts[pointData[5]][3], 1},
                        {uvs[pointData[2]][1], uvs[pointData[2]][2], 1},
                        {uvs[pointData[4]][1], uvs[pointData[4]][2], 1},
                        {uvs[pointData[6]][1], uvs[pointData[6]][2], 1}
                    ))

                elseif parts == 2 then
                    -- vert/uv/vnormal

                    local pointData = {}
                    for i = 1, 3 do
                        for item in data[1 + i]:gmatch("%d+") do
                            TInsert(pointData, tonumber(item))
                        end
                    end

                    TInsert(tris, Triangle(
                        {verts[pointData[1]][1], verts[pointData[1]][2], verts[pointData[1]][3], 1},
                        {verts[pointData[4]][1], verts[pointData[4]][2], verts[pointData[4]][3], 1},
                        {verts[pointData[7]][1], verts[pointData[7]][2], verts[pointData[7]][3], 1},
                        {uvs[pointData[2]][1], uvs[pointData[2]][2], 1},
                        {uvs[pointData[5]][1], uvs[pointData[5]][2], 1},
                        {uvs[pointData[8]][1], uvs[pointData[8]][2], 1}
                    ))

                -- Otherwise, just grab the verts
                else
                    TInsert(tris, Triangle(
                        {verts[tonumber(data[2])][1], verts[tonumber(data[2])][2], verts[tonumber(data[2])][3], 1},
                        {verts[tonumber(data[3])][1], verts[tonumber(data[3])][2], verts[tonumber(data[3])][3], 1},
                        {verts[tonumber(data[4])][1], verts[tonumber(data[4])][2], verts[tonumber(data[4])][3], 1}
                    ))
                end
            end
            ::continue::
        end
        vertCount = #verts
        return tris
    else return false end
end

-- ============================================================
-- STRUCT FUNCTIONS
-- ============================================================

-- #region Vector Math

-- Add one vector to another
local function vectorAdd(v1, v2)
    return {v1[1] + v2[1], v1[2] + v2[2], v1[3] + v2[3], 1}
end

-- Subtract one vector from another
local function vectorSub(v1, v2)
    return {v1[1] - v2[1], v1[2] - v2[2], v1[3] - v2[3], 1}
end

-- Multiply vector by a value K
local function vectorMul(v1, k)
    return {v1[1] * k, v1[2] * k, v1[3] * k, 1}
end

-- Divide vector by a value K
local function vectorDiv(v1, k)
    return {v1[1] / k, v1[2] / k, v1[3] / k, 1}
end

-- Get dot product of two input vectors
local function vectorDotProduct(v1, v2)
    return v1[1] * v2[1] + v1[2] * v2[2] + v1[3] * v2[3]
end

-- Get length of vector
local function vectorLength(v)
    return vectorDotProduct(v, v) ^ 0.5
end

-- Normalize vector between -1 and 1
local function vectorNormalize(v)
    local l = vectorLength(v)
    return {v[1] / l, v[2] / l, v[3] / l, 1}
end

-- Get cross product of two input vectors
local function vectorCrossProduct(v1, v2)
    local v = {0, 0, 0, 1}
    v[1] = v1[2] * v2[3] - v1[3] * v2[2]
    v[2] = v1[3] * v2[1] - v1[1] * v2[3]
    v[3] = v1[1] * v2[2] - v1[2] * v2[1]
    return v
end

-- Get position at which vector intersects plane
local function vectorIntersectPlane(planeDP, ad, bd, lineStart, lineEnd)
    local t = (planeDP - ad) / (bd - ad)
    local lineStartToEnd = vectorSub(lineEnd, lineStart)
    local lineToIntersect = vectorMul(lineStartToEnd, t)
    return vectorAdd(lineStart, lineToIntersect), t
end

-- Original function, for reference
-- This is only called in one function, so things can be simplified quite a bit
-- local function vectorIntersectPlane(planeP, inPlaneN, lineStart, lineEnd)
--     local planeN = vectorNormalize(inPlaneN)
--     local planeD = vectorDotProduct(planeN, planeP)
--     local ad = vectorDotProduct(lineStart, planeN)
--     local bd = vectorDotProduct(lineEnd, planeN)
--     local t = (planeD - ad) / (bd - ad)
--     local lineStartToEnd = vectorSub(lineEnd, lineStart)
--     local lineToIntersect = vectorMul(lineStartToEnd, t)
--     return vectorAdd(lineStart, lineToIntersect), t
-- end

-- #endregion

-- Return triangle from individual points
-- A quicker replacement of deepCopy that runs faster
-- TODO: This might suck too much even if it helps
local function triFromArray(x1, y1, z1, x2, y2, z2, x3, y3, z3,
                                           u1, v1, w1, u2, v2, w2, u3, v3, w3, tex, col, l)
    return {
        p = {{x1, y1, z1}, {x2, y2, z2}, {x3, y3, z3}},
        t = {{u1, v1, w1}, {u2, v2, w2}, {u3, v3, w3}},
        tex = tex,
        col = col,
        l = l
    }
end


local insidePoints = {}; local nInsideP = 0
local outsidePoints = {}; local nOutsideP = 0
local insideTex = {}; local nInsideT = 0
local outsideTex = {}; local nOutsideT = 0

-- Test triangle against input plane
-- Return clipped triangle(s) if triangle intersects plane
local function triClipPlane(planeP, planeN, inTri)
    -- local planeN = vectorNormalize(inPlaneN)

    local planeDP = vectorDotProduct(planeN, planeP)
    local function dist(p)
        return (planeN[1] * p[1] + planeN[2] * p[2] + planeN[3] * p[3] - planeDP)
    end

    insidePoints = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}; nInsideP = 0
    outsidePoints = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}; nOutsideP = 0
    insideTex = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}; nInsideT = 0
    outsideTex = {{0, 0, 0}, {0, 0, 0}, {0, 0, 0}}; nOutsideT = 0

    local d0 = dist(inTri[1][1])
    local d1 = dist(inTri[1][2])
    local d2 = dist(inTri[1][3])

    if d0 >= 0 then
        nInsideP = nInsideP + 1
        insidePoints[nInsideP] = inTri[1][1]

        nInsideT = nInsideT + 1
        insideTex[nInsideT] = inTri[2][1]
    else
        nOutsideP = nOutsideP + 1
        outsidePoints[nOutsideP] = inTri[1][1]

        nOutsideT = nOutsideT + 1
        outsideTex[nOutsideT] = inTri[2][1]
    end
    if d1 >= 0 then
        nInsideP = nInsideP + 1
        insidePoints[nInsideP] = inTri[1][2]

        nInsideT = nInsideT + 1
        insideTex[nInsideT] = inTri[2][2]
    else
        nOutsideP = nOutsideP + 1
        outsidePoints[nOutsideP] = inTri[1][2]

        nOutsideT = nOutsideT + 1
        outsideTex[nOutsideT] = inTri[2][2]
    end
    if d2 >= 0 then
        nInsideP = nInsideP + 1
        insidePoints[nInsideP] = inTri[1][3]

        nInsideT = nInsideT + 1
        insideTex[nInsideT] = inTri[2][3]
    else
        nOutsideP = nOutsideP + 1
        outsidePoints[nOutsideP] = inTri[1][3]

        nOutsideT = nOutsideT + 1
        outsideTex[nOutsideT] = inTri[2][3]
    end

    -- All points outside plane, should not be drawn
    if nInsideP == 0 then
        return 0

    -- All points within plane, requires no clipping
    elseif nInsideP == 3 then
        return 1, inTri

    -- Two points outside plane, return smaller tri
    elseif nInsideP == 1 and nOutsideP == 2 then

        -- Triangle needs to be clipped, two points lie outside
        local outTri1 = {{{0, 0, 0, 1}, {0, 0, 0, 1}, {0, 0, 0, 1}}, {{0, 0, 1}, {0, 0, 1}, {0, 0, 1}}}

        outTri1[1][1] = {insidePoints[1][1], insidePoints[1][2], insidePoints[1][3], insidePoints[1][4]}
        outTri1[2][1] = {insideTex[1][1], insideTex[1][2], insideTex[1][3]}

        local t
        local lsDP = vectorDotProduct(insidePoints[1], planeN)
        outTri1[1][2], t = vectorIntersectPlane(
            planeDP,
            lsDP, vectorDotProduct(outsidePoints[1], planeN),
            insidePoints[1], outsidePoints[1]
        )
        outTri1[2][2][1] = t * (outsideTex[1][1] - insideTex[1][1]) + insideTex[1][1]
        outTri1[2][2][2] = t * (outsideTex[1][2] - insideTex[1][2]) + insideTex[1][2]
        outTri1[2][2][3] = t * (outsideTex[1][3] - insideTex[1][3]) + insideTex[1][3]

        outTri1[1][3], t = vectorIntersectPlane(
            planeDP,
            lsDP, vectorDotProduct(outsidePoints[2], planeN),
            insidePoints[1], outsidePoints[2]
        )
        outTri1[2][3][1] = t * (outsideTex[2][1] - insideTex[1][1]) + insideTex[1][1]
        outTri1[2][3][2] = t * (outsideTex[2][2] - insideTex[1][2]) + insideTex[1][2]
        outTri1[2][3][3] = t * (outsideTex[2][3] - insideTex[1][3]) + insideTex[1][3]

        return 1, outTri1

    -- One point outside plane, return two smaller tris
    elseif nInsideP == 2 and nOutsideP == 1 then

        -- Triangle needs to be clipped, one pointing lies outside
        local outTri1 = {{{0, 0, 0, 1}, {0, 0, 0, 1}, {0, 0, 0, 1}}, {{0, 0, 1}, {0, 0, 1}, {0, 0, 1}}}
        local outTri2 = {{{0, 0, 0, 1}, {0, 0, 0, 1}, {0, 0, 0, 1}}, {{0, 0, 1}, {0, 0, 1}, {0, 0, 1}}}

        local t
        outTri1[1][1] = {insidePoints[1][1], insidePoints[1][2], insidePoints[1][3], insidePoints[1][4]}
        outTri1[1][2] = {insidePoints[2][1], insidePoints[2][2], insidePoints[2][3], insidePoints[2][4]}
        outTri1[2][1] = {insideTex[1][1], insideTex[1][2], insideTex[1][3]}
        outTri1[2][2] = {insideTex[2][1], insideTex[2][2], insideTex[2][3]}

        local leDP = vectorDotProduct(outsidePoints[1], planeN)
        outTri1[1][3], t = vectorIntersectPlane(
            planeDP,
            vectorDotProduct(insidePoints[1], planeN), leDP,
            insidePoints[1], outsidePoints[1]
        )
        outTri1[2][3][1] = t * (outsideTex[1][1] - insideTex[1][1]) + insideTex[1][1]
        outTri1[2][3][2] = t * (outsideTex[1][2] - insideTex[1][2]) + insideTex[1][2]
        outTri1[2][3][3] = t * (outsideTex[1][3] - insideTex[1][3]) + insideTex[1][3]

        outTri2[1][1] = {insidePoints[2][1], insidePoints[2][2], insidePoints[2][3], insidePoints[2][4]}
        outTri2[2][1] = {insideTex[2][1], insideTex[2][2], insideTex[2][3]}

        outTri2[1][2] = {outTri1[1][3][1], outTri1[1][3][2], outTri1[1][3][3], outTri1[1][3][4]}
        outTri2[2][2][1] = outTri1[2][3][1]
        outTri2[2][2][2] = outTri1[2][3][2]
        outTri2[2][2][3] = outTri1[2][3][3]
        outTri2[1][3], t = vectorIntersectPlane(
            planeDP,
            vectorDotProduct(insidePoints[2], planeN), leDP,
            insidePoints[2], outsidePoints[1]
        )
        outTri2[2][3][1] = t * (outsideTex[1][1] - insideTex[2][1]) + insideTex[2][1]
        outTri2[2][3][2] = t * (outsideTex[1][2] - insideTex[2][2]) + insideTex[2][2]
        outTri2[2][3][3] = t * (outsideTex[1][3] - insideTex[2][3]) + insideTex[2][3]

        return 2, outTri1, outTri2
    end
    return 0
end

-- #region Matrix Math

-- Return vector i multiplied by matrix m
local function matrixMultiplyVector(m, i)
    local v = {0, 0, 0, 0}
    v[1] = i[1] * m[1][1] + i[2] * m[2][1] + i[3] * m[3][1] + i[4] * m[4][1]
	v[2] = i[1] * m[1][2] + i[2] * m[2][2] + i[3] * m[3][2] + i[4] * m[4][2]
	v[3] = i[1] * m[1][3] + i[2] * m[2][3] + i[3] * m[3][3] + i[4] * m[4][3]
	v[4] = i[1] * m[1][4] + i[2] * m[2][4] + i[3] * m[3][4] + i[4] * m[4][4]
    return v
end

local function matrixMakeIdentity()
    return {{1, 0, 0, 0}, {0, 1, 0, 0,}, {0, 0, 1, 0}, {0, 0, 0, 1}}
end

-- Get rotation matrix at X angle angleRad
local function matrixMakeRotationX(angleRad)
    local matrix = Mat4x4()
    matrix[1][1] = 1
	matrix[2][2] = cos(angleRad * 0.5)
	matrix[2][3] = sin(angleRad * 0.5)
	matrix[3][2] = -sin(angleRad * 0.5)
	matrix[3][3] = cos(angleRad * 0.5)
	matrix[4][4] = 1
    return matrix
end

-- Get rotation matrix at Y angle angleRad
local function matrixMakeRotationY(angleRad)
    local matrix = Mat4x4()
    matrix[1][1] = cos(angleRad)
	matrix[1][3] = sin(angleRad)
	matrix[3][1] = -sin(angleRad)
	matrix[2][2] = 1
	matrix[3][3] = cos(angleRad)
	matrix[4][4] = 1
    return matrix
end

-- Get rotation matrix at Z angle angleRad
local function matrixMakeRotationZ(angleRad)
    local matrix = Mat4x4()
    matrix[1][1] = cos(angleRad)
	matrix[1][2] = sin(angleRad)
	matrix[2][1] = -sin(angleRad)
	matrix[2][2] = cos(angleRad)
	matrix[3][3] = 1
	matrix[4][4] = 1
    return matrix
end

-- Get matrix translated to values x, y, z
local function matrixMakeTranslation(x, y, z)
    local matrix = Mat4x4()
    matrix[1][1] = 1
    matrix[2][2] = 1
    matrix[3][3] = 1
    matrix[4][4] = 1
    matrix[4][1] = x
    matrix[4][2] = y
    matrix[4][3] = z
    return matrix
end

-- Create projection matrix from input FOV, aspect ratio, near and far distance
local function matrixMakeProjection(fFovDegrees, fAspectRatio, inFNear, inFFar)
    local fFovRad = 1 / tan(fFovDegrees * 0.5 / 180 * 3.14159)
    local matrix = Mat4x4()
    matrix[1][1] = fAspectRatio * fFovRad
    matrix[2][2] = fFovRad
    matrix[3][3] = inFFar / (inFFar - inFNear)
	matrix[4][3] = (-inFFar * inFNear) / (inFFar - inFNear)
	matrix[3][4] = 1
	matrix[4][4] = 0
    return matrix
end

-- Multiply matrix m1 by matrix m2
local function matrixMultiplyMatrix(m1, m2)
    local matrix = Mat4x4()
    for c = 1, 4 do
        for r = 1, 4 do
            matrix[r][c] = m1[r][1] * m2[1][c] + m1[r][2] * m2[2][c] + m1[r][3] * m2[3][c] + m1[r][4] * m2[4][c]
        end
    end
    return matrix
end


local function matrixPointAt(pos, target, up)
    local newForward = vectorSub(target, pos)
    newForward = vectorNormalize(newForward)

    local a = vectorMul(newForward, vectorDotProduct(up, newForward))
    local newUp = vectorSub(up, a)
    newUp = vectorNormalize(newUp)

    local newRight = vectorCrossProduct(newUp, newForward)

    local matrix = Mat4x4()
    matrix[1][1] = newRight[1];  	matrix[1][2] = newRight[2];	    matrix[1][3] = newRight[3];	    matrix[1][4] = 0
	matrix[2][1] = newUp[1];	    matrix[2][2] = newUp[2];	    matrix[2][3] = newUp[3];		matrix[2][4] = 0
	matrix[3][1] = newForward[1];	matrix[3][2] = newForward[2];	matrix[3][3] = newForward[3];	matrix[3][4] = 0
	matrix[4][1] = pos[1];			matrix[4][2] = pos[2];			matrix[4][3] = pos[3];			matrix[4][4] = 1
	return matrix;
end

-- Return inverse of matrix m
local function matrixQuickInverse(m)
    local matrix = Mat4x4()
	matrix[1][1] = m[1][1]; matrix[1][2] = m[2][1]; matrix[1][3] = m[3][1]; matrix[1][4] = 0
	matrix[2][1] = m[1][2]; matrix[2][2] = m[2][2]; matrix[2][3] = m[3][2]; matrix[2][4] = 0
	matrix[3][1] = m[1][3]; matrix[3][2] = m[2][3]; matrix[3][3] = m[3][3]; matrix[3][4] = 0
	matrix[4][1] = -(m[4][1] * matrix[1][1] + m[4][2] * matrix[2][1] + m[4][3] * matrix[3][1])
	matrix[4][2] = -(m[4][1] * matrix[1][2] + m[4][2] * matrix[2][2] + m[4][3] * matrix[3][2])
	matrix[4][3] = -(m[4][1] * matrix[1][3] + m[4][2] * matrix[2][3] + m[4][3] * matrix[3][3])
	matrix[4][4] = 1
	return matrix;
end
-- #endregion

-- ============================================================
-- RUNTIME
-- ============================================================

local loadedMesh = {}
local matProj, matRotY, matRotZ, matRotX
local fTheta = 0
local vCamera = Vec3D()
local vLookDir = Vec3D()
local fYaw = 0
local fPitch = 0

local screenWidth, screenHeight
local halfWidth, halfHeight
local trisDrawnLast = 0
local timeLast = computer.uptime()
local nowTime = computer.uptime()
local elapsedTime = 0.1
local function updateElapsedTime()
    nowTime = computer.uptime()
    elapsedTime = nowTime - timeLast
    timeLast = nowTime
end

local function createMesh()
    -- Load model, or default to the cube
    local tris = {}
    local texture = {}
    local defaultCube = {
        Triangle({0, 0, 0, 1}, {0, 1, 0, 1}, {1, 1, 0, 1}, {0, 1, 1}, {0, 0, 1}, {1, 0, 1}, "grassSide"),
        Triangle({0, 0, 0, 1}, {1, 1, 0, 1}, {1, 0, 0, 1}, {0, 1, 1}, {1, 0, 1}, {1, 1, 1}, "grassSide"),
        Triangle({1, 0, 0, 1}, {1, 1, 0, 1}, {1, 1, 1, 1}, {0, 1, 1}, {0, 0, 1}, {1, 0, 1}, "grassSide"),
        Triangle({1, 0, 0, 1}, {1, 1, 1, 1}, {1, 0, 1, 1}, {0, 1, 1}, {1, 0, 1}, {1, 1, 1}, "grassSide"),
        Triangle({1, 0, 1, 1}, {1, 1, 1, 1}, {0, 1, 1, 1}, {0, 1, 1}, {0, 0, 1}, {1, 0, 1}, "grassSide"),
        Triangle({1, 0, 1, 1}, {0, 1, 1, 1}, {0, 0, 1, 1}, {0, 1, 1}, {1, 0, 1}, {1, 1, 1}, "grassSide"),
        Triangle({0, 0, 1, 1}, {0, 1, 1, 1}, {0, 1, 0, 1}, {0, 1, 1}, {0, 0, 1}, {1, 0, 1}, "grassSide"),
        Triangle({0, 0, 1, 1}, {0, 1, 0, 1}, {0, 0, 0, 1}, {0, 1, 1}, {1, 0, 1}, {1, 1, 1}, "grassSide"),
        Triangle({0, 1, 0, 1}, {0, 1, 1, 1}, {1, 1, 1, 1}, {0, 1, 1}, {0, 0, 1}, {1, 0, 1}, "grassTop"),
        Triangle({0, 1, 0, 1}, {1, 1, 1, 1}, {1, 1, 0, 1}, {0, 1, 1}, {1, 0, 1}, {1, 1, 1}, "grassTop"),
        Triangle({1, 0, 1, 1}, {0, 0, 1, 1}, {0, 0, 0, 1}, {0, 1, 1}, {0, 0, 1}, {1, 0, 1}, "grassBottom"),
        Triangle({1, 0, 1, 1}, {0, 0, 0, 1}, {1, 0, 0, 1}, {0, 1, 1}, {1, 0, 1}, {1, 1, 1}, "grassBottom")
    }
    if modelFile == "default-cube" then
        -- Default mesh, if no others are specified
        tris = defaultCube
    else
        -- TODO:
        -- Look for bmp or some texture format with the same name as the loaded mesh
        local meshToLoad = getMeshFromFile(modelFile)
        if meshToLoad then
            tris = meshToLoad
        else
            modelFile = "default-cube-fallback"
            tris = defaultCube
        end
    end

    -- Breaking the mesh into nameless arrays might seem stupid, and it probably is
    -- But we only have to deal with its nameless indices once during the entire rasterizing process
    -- So by all means, this is probably fine
    -- [1]  [2]  [3]  [4]  - Point 1
    -- [5]  [6]  [7]  [8]  - Point 2
    -- [9]  [10] [11] [12] - Point 3
    -- [13] [14] [15]      - UV 1
    -- [16] [17] [18]      - UV 1
    -- [19] [20] [21]      - UV 1
    -- [22]                - Loaded Texture Index
    -- [23]                - Tricount
    -- [24]                - Lazy Culling Countdown

    loadedMesh = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, 0, {}}
    for i = 1, #tris do
        loadedMesh[1][i]  = tris[i].p[1][1]; loadedMesh[2][i]  = tris[i].p[1][2]; loadedMesh[3][i]  = tris[i].p[1][3]; loadedMesh[4][i]  = tris[i].p[1][4]
        loadedMesh[5][i]  = tris[i].p[2][1]; loadedMesh[6][i]  = tris[i].p[2][2]; loadedMesh[7][i]  = tris[i].p[2][3]; loadedMesh[8][i]  = tris[i].p[2][4]
        loadedMesh[9][i]  = tris[i].p[3][1]; loadedMesh[10][i] = tris[i].p[3][2]; loadedMesh[11][i] = tris[i].p[3][3]; loadedMesh[12][i] = tris[i].p[3][4]
        loadedMesh[13][i] = tris[i].t[1][1]; loadedMesh[14][i] = tris[i].t[1][2]; loadedMesh[15][i] = tris[i].t[1][3]
        loadedMesh[16][i] = tris[i].t[2][1]; loadedMesh[17][i] = tris[i].t[2][2]; loadedMesh[18][i] = tris[i].t[2][3]
        loadedMesh[19][i] = tris[i].t[3][1]; loadedMesh[20][i] = tris[i].t[3][2]; loadedMesh[21][i] = tris[i].t[3][3]
        loadedMesh[22][i] = tris[i].tex; loadedMesh[24][i] = 0
    end
    loadedMesh[23] = #tris

    screenWidth = gpu.GetScreenWidth(); screenHeight = gpu.GetScreenHeight()
    halfWidth = 0.5 * screenWidth; halfHeight = 0.5 * screenHeight
    matProj = matrixMakeProjection(fFov, gpu.GetAspectRatio(), fNear, fFar)
end

-- ============================================================
-- COLORS & TEXTURES TODO: Move all of this to chugraph
-- ============================================================

-- TODO: Move to chugraph
-- TODO: Optimize/fix oob errors
local depthBuffer = {}
local function resetDepthBuffer()
    depthBuffer = {}
end

-- TODO: Move to chugraph
-- TODO: Redo with barycentric coordinates?
local function getUVCoordinateColor(u, v)
    local uColor = ((u * 256) // 1) * 65536
    local vColor = ((v * 256) // 1) * 256
    return min(max(uColor + vColor, 0), 0xFFFFFF)
end

-- TODO: Move to chugraph
-- Get color from xyz value of face normal
local function getColorFromNormal(normal)
    -- Offset it for prettier colors
    local fixed = vectorAdd(vectorMul(normal, 0.5), Vec3D(0.5, 0.5, 0.5))

    -- Inflate channel values back to 1-255, rounding to nearest available color index
    fixed[1] = (fixed[1] // 0.17) * 51
    fixed[2] = ((fixed[2] // 0.125) * 36.5) // 1
    fixed[3] = min((fixed[3] // 0.25) * 64, 255)

    -- Recompile into hex color
    return (fixed[1] << 16) + (fixed[2] << 8) + fixed[3]
end


-- TODO: Something is wrong here. FIX: u, v = v, u; u = 1 - u
-- TODO: Move to chugraph
-- Return color from texture at position u, v (has issues)
local function uvSampleTexture(u, v, texIndex)
    local texWidth = loadedTextures[texIndex].w
    local texHeight = loadedTextures[texIndex].h
    u = ((u * texWidth) + 1) // 1
    v = ((v * texHeight) + 1) // 1
    u = min(max(u, 1), texWidth)
    v = min(max(v, 1), texHeight)
    if u > texWidth or u < 1 or v > texHeight or v < 1 then return 0xFFFFFF end
    return loadedTextures[texIndex].tex[v][u]
end

-- TODO: Move to chugraph
-- Draw triangle based on cl args
local function drawTexturedTriangle(x, y, tri, texU, texV, texW)
    -- TODO: More of these should be combinable
    -- Greyscale depth buffer
    if doDepthBufferColoring then
        SetPixel(x, y, GetGreyscaleColor(texW))

    -- Blend texture color into the background
    elseif doDepthBlending then
        local sampleColor = uvSampleTexture(texU / texW, texV / texW, tri.tex)
        if doShadedColoring then
            sampleColor = GetShadedColor(sampleColor, tri.l)
        end
        SetPixel(x, y, BlendColor(sampleColor, backgroundColor, texW ^ depthFadeDist))

    -- RGB according to surface normals
    elseif doNormalFlatColoring then
        SetPixel(x, y, tri.col)

    -- Shade texture based on angle to specified light source
    elseif doShadedColoring then
        local sampleColor = uvSampleTexture(texU / texW, texV / texW, tri.tex)
        SetPixel(x, y, GetShadedColor(sampleColor, tri.l))

    -- Just texture
    else
        SetPixel(x, y, uvSampleTexture(texU / texW, texV / texW, tri.tex))
    end
end

-- ============================================================
-- PROJECTION & RENDERING
-- ============================================================

-- Draw projected triangle to the screen
local function texturedTriangle(tri)

    tri.p[1][1] = tri.p[1][1] // 1;  tri.p[2][1] = tri.p[2][1] // 1;  tri.p[3][1] = tri.p[3][1] // 1
    tri.p[1][2] = tri.p[1][2] // 1;  tri.p[2][2] = tri.p[2][2] // 1;  tri.p[3][2] = tri.p[3][2] // 1

    if (tri.p[2][2] < tri.p[1][2]) then
        tri.p[1][1], tri.p[2][1] = tri.p[2][1], tri.p[1][1]
        tri.p[1][2], tri.p[2][2] = tri.p[2][2], tri.p[1][2]
        tri.t[1][1], tri.t[2][1] = tri.t[2][1], tri.t[1][1]
        tri.t[1][2], tri.t[2][2] = tri.t[2][2], tri.t[1][2]
        tri.t[1][3], tri.t[2][3] = tri.t[2][3], tri.t[1][3]
    end
    if (tri.p[3][2] < tri.p[1][2]) then
        tri.p[1][1], tri.p[3][1] = tri.p[3][1], tri.p[1][1]
        tri.p[1][2], tri.p[3][2] = tri.p[3][2], tri.p[1][2]
        tri.t[1][1], tri.t[3][1] = tri.t[3][1], tri.t[1][1]
        tri.t[1][2], tri.t[3][2] = tri.t[3][2], tri.t[1][2]
        tri.t[1][3], tri.t[3][3] = tri.t[3][3], tri.t[1][3]
    end
    if (tri.p[3][2] < tri.p[2][2]) then
        tri.p[2][1], tri.p[3][1] = tri.p[3][1], tri.p[2][1]
        tri.p[2][2], tri.p[3][2] = tri.p[3][2], tri.p[2][2]
        tri.t[2][1], tri.t[3][1] = tri.t[3][1], tri.t[2][1]
        tri.t[2][2], tri.t[3][2] = tri.t[3][2], tri.t[2][2]
        tri.t[2][3], tri.t[3][3] = tri.t[3][3], tri.t[2][3]
    end

    local dx1 = tri.p[2][1] - tri.p[1][1]
    local dy1 = tri.p[2][2] - tri.p[1][2]
    local du1 = tri.t[2][1] - tri.t[1][1]
    local dv1 = tri.t[2][2] - tri.t[1][2]
    local dw1 = tri.t[2][3] - tri.t[1][3]

    local dx2 = tri.p[3][1] - tri.p[1][1]
    local dy2 = tri.p[3][2] - tri.p[1][2]
    local du2 = tri.t[3][1] - tri.t[1][1]
    local dv2 = tri.t[3][2] - tri.t[1][2]
    local dw2 = tri.t[3][3] - tri.t[1][3]

    local texU, texV, texW = 0, 0, 0

    local daxStep = 0; local dbxStep = 0
    local du1Step = 0; local du2Step = 0
    local dv1Step = 0; local dv2Step = 0
    local dw1Step = 0; local dw2Step = 0
    local y1Delta; local y2Delta
    local ax; local bx
    local texSu; local texEu
    local texSv; local texEv
    local texSw; local texEw

    daxStep = dx1 / abs(dy1)
    dbxStep = dx2 / abs(dy2)
    du1Step = du1 / abs(dy1)
    dv1Step = dv1 / abs(dy1)
    dw1Step = dw1 / abs(dy1)
    du2Step = du2 / abs(dy2)
    dv2Step = dv2 / abs(dy2)
    dw2Step = dw2 / abs(dy2)

    for i = tri.p[1][2], tri.p[2][2] do

        y1Delta = i - tri.p[1][2]
        ax = (tri.p[1][1] + y1Delta * daxStep) // 1
        bx = (tri.p[1][1] + y1Delta * dbxStep) // 1

        -- Starting value
        texSu = tri.t[1][1] + y1Delta * du1Step
        texSv = tri.t[1][2] + y1Delta * dv1Step
        texSw = tri.t[1][3] + y1Delta * dw1Step

        -- Ending value
        texEu = tri.t[1][1] + y1Delta * du2Step
        texEv = tri.t[1][2] + y1Delta * dv2Step
        texEw = tri.t[1][3] + y1Delta * dw2Step

        if ax > bx then
            ax, bx = bx, ax
            texSu, texEu = texEu, texSu
            texSv, texEv = texEv, texSv
            texSw, texEw = texEw, texSw
        end

        texU = texSu
        texV = texSv
        texW = texSw

        local tStep = 1 / (bx - ax)
        local t = 0

        for j = ax, bx - 1 do

            texU = (1 - t) * texSu + t * texEu
            texV = (1 - t) * texSv + t * texEv
            texW = (1 - t) * texSw + t * texEw

            local depthIndex = (i * screenWidth) + j + 1
            if depthBuffer[depthIndex] == nil or texW > depthBuffer[depthIndex] then

                -- Draw pixel of triangle according to cl arg settings
                drawTexturedTriangle(j, i, tri, texU, texV, texW)
                depthBuffer[depthIndex] = texW
            end
            t = t + tStep
        end
    end

    dx1 = tri.p[3][1] - tri.p[2][1]
    dy1 = tri.p[3][2] - tri.p[2][2]
    du1 = tri.t[3][1] - tri.t[2][1]
    dv1 = tri.t[3][2] - tri.t[2][2]
    dw1 = tri.t[3][3] - tri.t[2][3]

    daxStep = dx1 / abs(dy1)
    dbxStep = dx2 / abs(dy2)
    du1Step = 0; dv1Step = 0
    du1Step = du1 / abs(dy1)
    dv1Step = dv1 / abs(dy1)
    dw1Step = dw1 / abs(dy1)

    for i = tri.p[2][2], tri.p[3][2] do

        y1Delta = i - tri.p[1][2]
        y2Delta = i - tri.p[2][2]
        ax = (tri.p[2][1] + y2Delta * daxStep) // 1
        bx = (tri.p[1][1] + y1Delta * dbxStep) // 1

        -- Starting value
        texSu = tri.t[2][1] + y2Delta * du1Step
        texSv = tri.t[2][2] + y2Delta * dv1Step
        texSw = tri.t[2][3] + y2Delta * dw1Step

        -- Ending value
        texEu = tri.t[1][1] + y1Delta * du2Step
        texEv = tri.t[1][2] + y1Delta * dv2Step
        texEw = tri.t[1][3] + y1Delta * dw2Step

        if ax > bx then
            ax, bx = bx, ax
            texSu, texEu = texEu, texSu
            texSv, texEv = texEv, texSv
            texSw, texEw = texEw, texSw
        end

        texU = texSu
        texV = texSv
        texW = texSw

        local tStep = 1 / (bx - ax)
        local t = 0

        for j = ax, bx - 1 do

            texU = (1 - t) * texSu + t * texEu
            texV = (1 - t) * texSv + t * texEv
            texW = (1 - t) * texSw + t * texEw

            local depthIndex = (i * screenWidth) + j + 1
            if depthBuffer[depthIndex] == nil or texW > depthBuffer[depthIndex] then

                -- Draw pixel of triangle according to cl arg settings
                drawTexturedTriangle(j, i, tri, texU, texV, texW)
                depthBuffer[depthIndex] = texW
            end
            t = t + tStep
        end
    end
end

-- Timing variables
local rasterTrisStart; local rasterTrisEnd

-- Clip each triangle against each side of the viewport
-- After clipping, render each triangle
-- TODO: Would be easier to benchmark if rendering was moved to a separate function
local function viewportClipTriangles(rasterTris)

    rasterTrisStart = GetCPUTime() -- Timing

    local clipped = {}
    local listTriangles = {}
    local nNewTriangles

    for i = 1, #rasterTris[1] do

        -- TODO: Move this below the screenspace check, need to refactor drawing loop though
        clipped = {}
        -- TODO: Remove triFromArray and move to full array storage
        listTriangles = {
            triFromArray(
            rasterTris[1][i],  rasterTris[2][i],  rasterTris[3][i],
            rasterTris[4][i],  rasterTris[5][i],  rasterTris[6][i],
            rasterTris[7][i],  rasterTris[8][i],  rasterTris[9][i],
            rasterTris[10][i], rasterTris[11][i], rasterTris[12][i],
            rasterTris[13][i], rasterTris[14][i], rasterTris[15][i],
            rasterTris[16][i], rasterTris[17][i], rasterTris[18][i],
            rasterTris[19][i], rasterTris[20][i], rasterTris[21][i]
        )}

        -- Check if any points are outside of screen space
        if rasterTris[1][i] < 1 or rasterTris[1][i] > screenWidth then goto clipTri end
        if rasterTris[2][i] < 1 or rasterTris[2][i] > screenHeight then goto clipTri end
        if rasterTris[4][i] < 1 or rasterTris[4][i] > screenWidth then goto clipTri end
        if rasterTris[5][i] < 1 or rasterTris[5][i] > screenHeight then goto clipTri end
        if rasterTris[7][i] < 1 or rasterTris[7][i] > screenWidth then goto clipTri end
        if rasterTris[8][i] < 1 or rasterTris[8][i] > screenHeight then goto clipTri end
        goto skipClip

        -- If not, clip triangles against sides of viewport
        ::clipTri::
        nNewTriangles = 1
        for p = 1, 4 do

            local nTrisToAdd = 0
            while nNewTriangles > 0 do

                -- TODO: Refactor test to be array only
                -- Edit: Probably not but still a place where optimization might help
                local testTri = listTriangles[1]
                nNewTriangles = nNewTriangles - 1

                -- Check against each plane of the viewport
                -- Before sending to clip, make sure at least one point actually lies outside of that viewport plane
                if p == 1 then
                    -- Top
                    if testTri.p[1][2] < 1 or testTri.p[2][2] < 1 or testTri.p[3][2] < 1 then
                        nTrisToAdd, clipped[1], clipped[2] = triClipPlane({0, 0, 0}, {0, 1, 0}, {testTri.p, testTri.t})
                    else
                        nTrisToAdd = -1
                        clipped[1] = testTri
                    end
				elseif p == 2 then
                    -- Bottom
                    if testTri.p[1][2] > screenHeight or testTri.p[2][2] > screenHeight or testTri.p[3][2] > screenHeight then
                        nTrisToAdd, clipped[1], clipped[2] = triClipPlane({0, screenHeight, 0}, {0, -1, 0}, {testTri.p, testTri.t})
                    else
                        nTrisToAdd = -1
                        clipped[1] = testTri
                    end
                elseif p == 3 then
                    -- Left
                    if testTri.p[1][1] < 1 or testTri.p[2][1] < 1 or testTri.p[3][1] < 1 then
                        nTrisToAdd, clipped[1], clipped[2] = triClipPlane({0, 0, 0}, {1, 0, 0}, {testTri.p, testTri.t})
                    else
                        nTrisToAdd = -1
                        clipped[1] = testTri
                    end
				elseif p == 4 then
                    -- Right
                    if testTri.p[1][1] > screenWidth or testTri.p[2][1] > screenWidth or testTri.p[3][1] > screenWidth then
                        nTrisToAdd, clipped[1], clipped[2] = triClipPlane({screenWidth, 0, 0}, {-1, 0, 0}, {testTri.p, testTri.t})
                    else
                        nTrisToAdd = -1
                        clipped[1] = testTri
                    end
                end

                if nTrisToAdd == -1 then
                    -- Removed deep copy, this is faster
                    TInsert(listTriangles, {
                        p = {{clipped[1].p[1][1], clipped[1].p[1][2], clipped[1].p[1][3]},
                             {clipped[1].p[2][1], clipped[1].p[2][2], clipped[1].p[2][3]},
                             {clipped[1].p[3][1], clipped[1].p[3][2], clipped[1].p[3][3]}},
                        t = {{clipped[1].t[1][1], clipped[1].t[1][2], clipped[1].t[1][3]},
                             {clipped[1].t[2][1], clipped[1].t[2][2], clipped[1].t[2][3]},
                             {clipped[1].t[3][1], clipped[1].t[3][2], clipped[1].t[3][3]}},
                        tex = testTri.tex, col = testTri.col, l = testTri.l
                    })
                end

                for w = 1, nTrisToAdd do
                    -- Removed deep copy, this is faster
                    TInsert(listTriangles, {
                        p = {{clipped[w][1][1][1], clipped[w][1][1][2], clipped[w][1][1][3]},
                             {clipped[w][1][2][1], clipped[w][1][2][2], clipped[w][1][2][3]},
                             {clipped[w][1][3][1], clipped[w][1][3][2], clipped[w][1][3][3]}},
                        t = {{clipped[w][2][1][1], clipped[w][2][1][2], clipped[w][2][1][3]},
                             {clipped[w][2][2][1], clipped[w][2][2][2], clipped[w][2][2][3]},
                             {clipped[w][2][3][1], clipped[w][2][3][2], clipped[w][2][3][3]}},
                        tex = testTri.tex, col = testTri.col, l = testTri.l
                    })
                end
                TRemove(listTriangles, 1)
            end
            nNewTriangles = #listTriangles
        end
        ::skipClip::

        -- Rasterize triangles
        for j = 1, #listTriangles do

            -- TODO: Make more of these combinable
            -- Render differently based on what was specified in the cl args
            if doDrawTextured then
                texturedTriangle(listTriangles[j])
            elseif doDrawFlatShaded then -- TODO: Move to textured triangle
                FillTriangle(listTriangles[j].p, GetGreyscaleColor(listTriangles[j].l))
            end

            if doDrawWireframe then
                DrawTriangle(listTriangles[j].p, 0xFFFFFF)
            end

            -- Debug
            trisDrawnLast = trisDrawnLast + 1
        end
    end
    rasterTrisEnd = GetCPUTime()
end

local projectTimeStart; local projectTimeEnd
local segmentTimeStart; local segmentTimeStartFrameTotal = 0
local lazyCulledCount = 0

-- For all tris in the loaded mesh, project into screen space
-- Skip any backfacing tris, and skip or clip tris behind near plane
-- Then return list of valid tris
local function getTrisToRaster()

    projectTimeStart = GetCPUTime() -- Timing

    -- Rotate mesh if rotation enabled
    if doModelRotate then fTheta = fTheta + elapsedTime end
	matRotZ = matrixMakeRotationZ(doModelRotateZ and fTheta * 0.5 or 0)
	matRotX = matrixMakeRotationX(doModelRotateX and fTheta or 0)
    matRotY = matrixMakeRotationY(doModelRotateY and fTheta * 0.25 or 0)

    local matTrans = Mat4x4()
    matTrans = matrixMakeTranslation(0, 0, 7.5)

    local matWorld = Mat4x4()
    matWorld = matrixMakeIdentity()
    matWorld = matrixMultiplyMatrix(matRotZ, matRotX)
    matWorld = matrixMultiplyMatrix(matWorld, matRotY)
    matWorld = matrixMultiplyMatrix(matWorld, matTrans)

    -- Get camera rotation matrix from player control
    local vUp = {0, 1, 0, 1}
    local vTarget = {0, 0, 1, 1}
    local matCameraPitch = matrixMakeRotationX(fPitch)
    local matCameraYaw = matrixMakeRotationY(fYaw)
    local matCameraRot = matrixMultiplyMatrix(matCameraPitch, matCameraYaw)
    vLookDir = matrixMultiplyVector(matCameraRot, vTarget)
    vTarget = vectorAdd(vCamera, vLookDir)
    local matCamera = matrixPointAt(vCamera, vTarget, vUp) -- vCamera, vTarget, vUp

    -- Matrix view from camera
    local matView = matrixQuickInverse(matCamera)

    -- Get light direction normal (This shouldn't be calculated per-frame unless the light direction is changing)
    local normalizedLightDir = vectorNormalize(lightDirection)

    -- Build array of arrays to hold projected tri data
    -- May be unreadable but more memory efficient than KV pairs
    local rasterTris = {
        {}, {}, {},     -- P1 XYZ
        {}, {}, {},     -- P2 XYZ
        {}, {}, {},     -- P3 XYZ
        {}, {}, {},     -- T1 UVW
        {}, {}, {},     -- T2 UVW
        {}, {}, {},     -- T3 UVW
        {}, {}, {},     -- Texture, Color, Light
    }

    -- For tris in mesh, project
    for i = 1, loadedMesh[23] do

        -- segmentTimeStart = GetCPUTime()

        -- If triangle has a lazy culling index over 0, skip projection and decrement its index
        if loadedMesh[24][i] > 0 then
            loadedMesh[24][i] = loadedMesh[24][i] - 1
            lazyCulledCount = lazyCulledCount + 1
            goto skipProj
        end

        -- Rotate tri to world matrix
        local triTransformed = FastTriangle()
        triTransformed[1][1] = matrixMultiplyVector(matWorld, {loadedMesh[1][i], loadedMesh[2][i],  loadedMesh[3][i],  loadedMesh[4][i]})
        triTransformed[1][2] = matrixMultiplyVector(matWorld, {loadedMesh[5][i], loadedMesh[6][i],  loadedMesh[7][i],  loadedMesh[8][i]})
        triTransformed[1][3] = matrixMultiplyVector(matWorld, {loadedMesh[9][i], loadedMesh[10][i], loadedMesh[11][i], loadedMesh[12][i]})
        triTransformed[2][1] = {loadedMesh[13][i], loadedMesh[14][i], loadedMesh[15][i]}
        triTransformed[2][2] = {loadedMesh[16][i], loadedMesh[17][i], loadedMesh[18][i]}
        triTransformed[2][3] = {loadedMesh[19][i], loadedMesh[20][i], loadedMesh[21][i]}
        triTransformed[3] = loadedMesh[22][i]

        -- Get normal vector
        local normal = {0, 0, 0}
        local line1 =  {0, 0, 0}
        local line2 =  {0, 0, 0}

        -- Get lines either side of triangle
        line1 = vectorSub(triTransformed[1][2], triTransformed[1][1])
        line2 = vectorSub(triTransformed[1][3], triTransformed[1][1])

        -- Get cross product of lines for triangle surface normal
        normal = vectorCrossProduct(line1, line2)
        normal = vectorNormalize(normal)

        -- Nearplane clipping vectors
        local nearPlane = {0, 0, fNear}
        local nearNormal = {0, 0, 1}

        -- Get ray from triangle to camera
        local vCameraRay = vectorSub(triTransformed[1][1], vCamera)

        -- segmentTimeStartFrameTotal = segmentTimeStartFrameTotal + GetCPUTime() - segmentTimeStart

        -- If back-facing, then skip rendering
        -- Toy with the threshold a bit, since culled faces have a lag before being checked again
        -- Should have more leeway to pad time for the culling index to tick down
        local normalToCamera = vectorDotProduct(normal, vCameraRay)
        if normalToCamera < bfcThreshold then

            -- Get shaded color
            local lightDp = max(min(lightBias + vectorDotProduct(normalizedLightDir, normal), 1), shadeMaximum)
            triTransformed[5] = lightDp

            -- Convert world space -> view space
            local triViewed = FastTriangle()
            triViewed[1][1] = matrixMultiplyVector(matView, triTransformed[1][1])
            triViewed[1][2] = matrixMultiplyVector(matView, triTransformed[1][2])
            triViewed[1][3] = matrixMultiplyVector(matView, triTransformed[1][3])
            triViewed[2] = triTransformed[2]
            triViewed[3] = triTransformed[3]
            triViewed[4] = triTransformed[4]
            triViewed[5] = triTransformed[5]

            if doNormalFlatColoring then triViewed[4] = getColorFromNormal(normal) end

            -- Handle clipping triangles against near plane
            local clippedTris
            local clipped = {}
            clippedTris, clipped[1], clipped[2] = triClipPlane(nearPlane, nearNormal, triViewed)
            for n = 1, clippedTris do

                -- Project triangles from 3D to 2D
                clipped[n][1][1] = matrixMultiplyVector(matProj, clipped[n][1][1])
                clipped[n][1][2] = matrixMultiplyVector(matProj, clipped[n][1][2])
                clipped[n][1][3] = matrixMultiplyVector(matProj, clipped[n][1][3])

                -- Project textures as well
                clipped[n][2][1][1] = clipped[n][2][1][1] / clipped[n][1][1][4]
                clipped[n][2][2][1] = clipped[n][2][2][1] / clipped[n][1][2][4]
                clipped[n][2][3][1] = clipped[n][2][3][1] / clipped[n][1][3][4]
                clipped[n][2][1][2] = clipped[n][2][1][2] / clipped[n][1][1][4]
                clipped[n][2][2][2] = clipped[n][2][2][2] / clipped[n][1][2][4]
                clipped[n][2][3][2] = clipped[n][2][3][2] / clipped[n][1][3][4]
                clipped[n][2][1][3] = 1 / clipped[n][1][1][4]
                clipped[n][2][2][3] = 1 / clipped[n][1][2][4]
                clipped[n][2][3][3] = 1 / clipped[n][1][3][4]

                -- Scale into view
                clipped[n][1][1] = vectorDiv(clipped[n][1][1], clipped[n][1][1][4])
                clipped[n][1][2] = vectorDiv(clipped[n][1][2], clipped[n][1][2][4])
                clipped[n][1][3] = vectorDiv(clipped[n][1][3], clipped[n][1][3][4])

                -- Invert XY
                clipped[n][1][1][1] = -clipped[n][1][1][1]
				clipped[n][1][2][1] = -clipped[n][1][2][1]
				clipped[n][1][3][1] = -clipped[n][1][3][1]
				clipped[n][1][1][2] = -clipped[n][1][1][2]
				clipped[n][1][2][2] = -clipped[n][1][2][2]
				clipped[n][1][3][2] = -clipped[n][1][3][2]

                -- Offset verts into visible normalized space
                local vOffsetView = {1, 1, 0}
                clipped[n][1][1] = vectorAdd(clipped[n][1][1], vOffsetView)
                clipped[n][1][2] = vectorAdd(clipped[n][1][2], vOffsetView)
                clipped[n][1][3] = vectorAdd(clipped[n][1][3], vOffsetView)

                -- Add to rasterize list
                -- This crap is so dumb but its like a 30% cpu gain for heavy tri models
                TInsert(rasterTris[1],  clipped[n][1][1][1] * halfWidth); TInsert(rasterTris[2], clipped[n][1][1][2] * halfHeight); TInsert(rasterTris[3], clipped[n][1][1][3])
                TInsert(rasterTris[4],  clipped[n][1][2][1] * halfWidth); TInsert(rasterTris[5], clipped[n][1][2][2] * halfHeight); TInsert(rasterTris[6], clipped[n][1][2][3])
                TInsert(rasterTris[7],  clipped[n][1][3][1] * halfWidth); TInsert(rasterTris[8], clipped[n][1][3][2] * halfHeight); TInsert(rasterTris[9], clipped[n][1][3][3])
                TInsert(rasterTris[10], clipped[n][2][1][1])
                TInsert(rasterTris[11], clipped[n][2][1][2])
                TInsert(rasterTris[12], clipped[n][2][1][3])
                TInsert(rasterTris[13], clipped[n][2][2][1])
                TInsert(rasterTris[14], clipped[n][2][2][2])
                TInsert(rasterTris[15], clipped[n][2][2][3])
                TInsert(rasterTris[16], clipped[n][2][3][1])
                TInsert(rasterTris[17], clipped[n][2][3][2])
                TInsert(rasterTris[18], clipped[n][2][3][3])
                TInsert(rasterTris[19], triViewed[3])
                TInsert(rasterTris[20], triViewed[4])
                TInsert(rasterTris[21], triViewed[5])
            end
        elseif normalToCamera > bfcLazyThreshold then
            -- Face was backface-culled
            -- Add a value between 1 and 2 to its lazy culling index
            -- As frames tick by, faces with an index value above 0 tick down by one
            -- Only faces with a lazy culling index of 0 move onto projection
            loadedMesh[24][i] = i % 2 + 1
        end
        ::skipProj::
    end
    projectTimeEnd = GetCPUTime()
    return rasterTris
end

-- ============================================================
-- DEBUG
-- ============================================================

local debugCycles = 1; local maxDebugCycles = 30
local projectionTimeTotal = 0; local rasterizeTimeTotal = 0; local segmentTimeTotal = 0

-- Print debug stats to the screen
local function modelDebug()

    projectionTimeTotal = projectionTimeTotal + (projectTimeEnd - projectTimeStart)
    rasterizeTimeTotal = rasterizeTimeTotal + (rasterTrisEnd - rasterTrisStart)
    segmentTimeTotal = segmentTimeTotal + segmentTimeStartFrameTotal
    local projAverage = projectionTimeTotal / debugCycles
    local rastAverage = rasterizeTimeTotal / debugCycles
    local segAverage = segmentTimeTotal / debugCycles

    SetText(1, 1, modelFile, 0xFFFFFF, 0x000000, false)
    SetText(1, 3, string.format("TRIS: %d - VERT: %d", loadedMesh[23], vertCount), 0xFFFFFF, 0x000000, false)
    SetText(1, 5, string.format("DRAWN: %d", trisDrawnLast), 0xFFFFFF, 0x000000, false)
    SetText(1, 7, string.format("Proj: %0.1fms", (projAverage) * 1000), 0xFFFFFF, 0x000000, false)
    SetText(1, 9, string.format("Rast: %0.1fms", (rastAverage) * 1000), 0xFFFFFF, 0x000000, false)
    SetText(1, 11, string.format("LBFC: %d", lazyCulledCount), 0xFFFFFF, 0x000000, false)
    SetText(1, 13, string.format("SEG: %1.1fms", (segAverage) * 1000), 0xFFFFFF, 0x000000, false)

    segmentTimeStartFrameTotal = 0
    lazyCulledCount = 0
    debugCycles = debugCycles + 1
    if debugCycles > maxDebugCycles then
        projectionTimeTotal = projAverage
        rasterizeTimeTotal = rastAverage
        segmentTimeTotal = segAverage
        debugCycles = 2
    end
end

-- ============================================================
-- CONTROL
-- ============================================================

local KEY_UP = "Z"; local KEY_DOWN = "X"
local KEY_FORWARD = "W"; local KEY_BACKWARD = "S"
local KEY_LEFT = "A"; local KEY_RIGHT = "D"
local KEY_TURNLEFT = "LEFT"; local KEY_TURNRIGHT = "RIGHT"
local KEY_TURNUP = "UP"; local KEY_TURNDOWN = "DOWN"
local KEY_QUIT = "Q"
local moveSpeed = 3
local function applyInputControls()

    -- Apply values based on keypress
    if inputManager.isKeyDown(inputManager, KEY_QUIT) then
        return true
    end
    if inputManager.isKeyDown(inputManager, KEY_UP) then
        vCamera[2] = vCamera[2] + (moveSpeed * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_DOWN) then
        vCamera[2] = vCamera[2] - (moveSpeed * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_LEFT) then
        -- right: x = -z and z = x
        local vRight = vectorMul(Vec3D(-vLookDir[3], 0, vLookDir[1]), moveSpeed * elapsedTime)
        vCamera = vectorSub(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_RIGHT) then
        local vRight = vectorMul(Vec3D(-vLookDir[3], 0, vLookDir[1]), moveSpeed * elapsedTime)
        vCamera = vectorAdd(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_FORWARD) then
        local vForward = vectorMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vectorAdd(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_BACKWARD) then
        local vForward = vectorMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vectorSub(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNLEFT) then
        fYaw = fYaw - (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNRIGHT) then
        fYaw = fYaw + (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNUP) then
        fPitch = fPitch - (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNDOWN) then
        fPitch = fPitch + (2 * elapsedTime)
    end
end

-- ============================================================
-- RUN THE DAMN THING
-- ============================================================

local function renderTriangles()
    ClearScreen()
    resetDepthBuffer()
    local rasterTris = getTrisToRaster()
    viewportClipTriangles(rasterTris)
end

local function main()
    ClearScreen()
    createMesh()
    gpu.SetSceneBackground(backgroundColor)
    while true do

        -- update elapsed time
        updateElapsedTime()

        -- Take player's input controls
        inputManager.updateKeypress(inputManager)
        local exit = applyInputControls()
        if exit then
            gpu.ResetToCommandLine()
            package.loaded["chugraph"] = nil
            package.loaded["chugkey"] = nil
            package.loaded["bmpdecoder"] = nil
            break
        end

        -- Clear screen and draw projected triangles
        renderTriangles()

        -- Draw debug, render screen
        modelDebug()
        UpdateScreen()

        -- Reset debug values
        trisDrawnLast = 0
    end
end
main()

print("Projected with Chug3D " .. version)