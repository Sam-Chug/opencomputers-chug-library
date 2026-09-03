-- ============================================================
-- CREDITS:
-- The code here was originally built following a tutorial by Javidx9 on YouTube
-- "Code-It-Yourself! 3D Graphics Engine" -> https://youtu.be/ih20l3pJoeU
-- Since then, it has been heavily re-writtem and optimized for a low-memory lua environment.
-- ============================================================

local component = require("component")
local shell = require("shell")
local _, ops = shell.parse(...)
local computer = require("computer")
local version = "0.4.0a"

-- Graphics Library
local gpu = require("chugraph")
gpu.SetMainGPU(component.gpu, "doubleHeight", true, true)

-- BMP Loader
local bmp = require("chugbmp")

-- Input manager
local inputManager = require("chugkey")

-- ============================================================
-- RENDER CONFIGS
-- ============================================================

-- Rendering styles
local doDrawTextured = true             -- TODO: There is no real setting for this
local drawNormalColor = false           -- Flat-fill triangle with the RGB color of its face normal XYZ
local drawDepthBuffer = false           -- Draw depth value at each pixel of each triangle
local drawShaded = false                -- Shade based on triangle face normal relation to light direction
local drawFlatShade = false             -- Draw greyscale flat-filled triangle with lighting based on light direction
local drawWireFrame = false             -- Draw wireframe of mesh
local drawDepthBlend = false            -- Blend the render into the background using depth buffer values
local doUserControl = true              -- Render the scene with/without user control, affects performance greatly

-- Rendering fluff
local backgroundColor = 0x00DBFF        -- Color of the background in the scene
local depthFadeDist = 0.4               -- Square depth value by this value when blending colors into the background
local bfcThreshold = 0.0                -- Cull any face whos dot product against camera normal is above this
local lightDirection = {0.1, 0.1, -1}   -- [Sunlight-ish](0.3, 1, 0) | [Topdown-ish](0.1, 0.1, -1)
local shadeMaximum = 5 / 16             -- Maximum darkness in the most shaded areas
local lightBias = 0.3                   -- Softens faces that are 90 degrees offset to light direction
local fNear = 0.25                      -- Near plane distance
local fFar = 1000                       -- Far plane distance
local fFov = 90                         -- Field of view
local modelFile = "teapot.obj"          -- Default loaded model, pretty much just for debugging

-- TODO: This is getting quite lengthy, it would be nice to read more complex settings from a setup file
local function setUserOptions()
    -- load model from input filename
    if ops.model ~= nil then
        if string.find(ops.model, ".obj") == nil then
            modelFile = ops.model .. ".obj"
        else modelFile = ops.model end
    end
    if ops.back ~= nil then
        backgroundColor = ops.back + 0
    end
    if ops.u then doUserControl = false end
    if ops.n then drawNormalColor = true end
    if ops.d then drawDepthBuffer = true end
    if ops.s then drawShaded = true end
    if ops.b then drawDepthBlend = true end
    if ops.f then drawFlatShade = true end
    if ops.w then drawWireFrame = true end
end
setUserOptions()

-- ============================================================
-- LUA NONSENSE
-- ============================================================

local cos, sin, tan = math.cos, math.sin, math.tan
local min, max, abs, modulo = math.min, math.max, math.abs, math.fmod
local GetCPUTime = os.clock

local ClearScreen, UpdateScreen = gpu.ClearScreen, gpu.UpdateScreen
local SetText, SetPixel = gpu.SetText, gpu.SetPixel
local DrawTriangle = gpu.DrawTriangle
local GetGreyscaleColor, GetShadedColor, BlendColor = gpu.GetGreyscaleColor, gpu.GetShadedColor, gpu.BlendColor
local ColorFromRGB1 = gpu.ClosestValidHexFromRGB1

local TInsert = table.insert; local TRemove = table.remove
local TablePack, TableUnpack, StringPack, StringUnpack = table.pack, table.unpack, string.pack, string.unpack

-- ============================================================
-- DEFAULT TEXTURES & MODELS
-- ============================================================

-- Default cube, if no meshes are able to load
local defaultCubeOBJ = {
    "v -0.5 0.5 0.5", "v -0.5 -0.5 0.5", "v -0.5 0.5 -0.5", "v -0.5 -0.5 -0.5",
    "v 0.5 0.5 0.5", "v 0.5 -0.5 0.5", "v 0.5 0.5 -0.5", "v 0.5 -0.5 -0.5",
    "vt 0.875 0.5", "vt 0.625 0.75", "vt 0.625 0.5", "vt 0.375 1", "vt 0.375 0.75", "vt 0.625 0", "vt 0.375 0.25",
    "vt 0.375 0", "vt 0.375 0.5", "vt 0.125 0.75", "vt 0.125 0.5", "vt 0.625 0.25", "vt 0.875 0.75", "vt 0.625 1",
    "f 5/1 3/2 1/3", "f 3/2 8/4 4/5", "f 7/6 6/7 8/8", "f 2/9 8/10 6/11", "f 1/3 4/5 2/9", "f 5/12 2/9 6/7",
    "f 5/1 7/13 3/2", "f 3/2 7/14 8/4", "f 7/6 5/12 6/7", "f 2/9 4/5 8/10", "f 1/3 3/2 4/5", "f 5/12 1/3 2/9"
}

-- Default texture
local missingTex = {
    {0xFF00FF, 0x2D2D2D, 0xFF00FF, 0x2D2D2D},
    {0x2D2D2D, 0xFF00FF, 0x2D2D2D, 0xFF00FF},
    {0xFF00FF, 0x2D2D2D, 0xFF00FF, 0x2D2D2D},
    {0x2D2D2D, 0xFF00FF, 0x2D2D2D, 0xFF00FF},
}

-- ============================================================
-- .OBJ MESH LOADING
-- ============================================================

-- Check if file exists
local function fileExists(filename)
    local f = io.open(filename, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local vertPackS = "fffB"
local uvPackS = "ffB"
local indPackS = "I2I2I2"

-- Load .obj from file at filenam, parse vertex/face data and build a list of triangles from it
-- Hamfisted to work with both importing a file and a mesh string
local function getMeshFromString(filename, meshData, loadFile)
    local verts, uvs, vInd, uInd = {}, {}, {}, {}
    local pointData = {}
    local hasUvs = false

    local lines = {}
    if loadFile then
        for line in io.lines(filename) do
            TInsert(lines, line)
        end
    else
        lines = meshData
    end

    for i = 1, #lines do
        local data = {}
        for item in lines[i]:gmatch("%S+") do
            TInsert(data, item)
        end
        if data == nil or data[1] == nil then goto continue end

        -- Vertex position
        if data[1] == "v" then
            TInsert(verts, StringPack(vertPackS, tonumber(data[2]), tonumber(data[3]), tonumber(data[4]), 1))

        -- TODO: Vertex normals, could do shading eventually
        elseif data[1] == "vn" then
            -- Do nothing... for now....

        -- UVs
        elseif data[1] == "vt" then
            hasUvs = true
            TInsert(uvs, StringPack(uvPackS, tonumber(data[2]), tonumber(data[3]), 1))

        -- Face data
        elseif data[1] == "f" then

            -- Check if face data packs other information inside
            local _, parts = data[2]:gsub("/", "")

            -- If more information than points given, then parse it
            if parts == 1 then
                -- Vertex/UV

                pointData = {}
                for j = 1, 3 do
                    for item in data[1 + j]:gmatch("%d+") do
                        TInsert(pointData, tonumber(item))
                    end
                end

                TInsert(vInd, StringPack(indPackS, pointData[1], pointData[3], pointData[5]))
                TInsert(uInd, StringPack(indPackS, pointData[2], pointData[4], pointData[6]))

            elseif parts == 2 then
                -- Vertex/UV/Vertex-Normal

                pointData = {}
                for j = 1, 3 do
                    for item in data[1 + j]:gmatch("%d+") do
                        TInsert(pointData, tonumber(item))
                    end
                end

                TInsert(vInd, StringPack(indPackS, pointData[1], pointData[4], pointData[7]))
                TInsert(uInd, StringPack(indPackS, pointData[2], pointData[5], pointData[8]))

            -- Otherwise, just grab the verts
            else
                TInsert(vInd, StringPack(indPackS, tonumber(data[2]), tonumber(data[3]), tonumber(data[4])))
                TInsert(uInd, StringPack(indPackS, 1, 2, 3))
            end
        end
        data, lines[i] = nil, nil
        ::continue::
    end
    -- If no UVs loaded, then make a list of dummy coordinates to index into
    if not hasUvs then
        uvs = {StringPack(uvPackS, 0, 0, 1), StringPack(uvPackS, 0, 1, 1), StringPack(uvPackS, 1, 1, 1)}
    end
    pointData = nil
    return verts, uvs, vInd, uInd
end

-- ============================================================
-- STRUCT FUNCTIONS
-- ============================================================

-- Add one vector to another
local function vAdd(v1, v2)
    return {v1[1] + v2[1], v1[2] + v2[2], v1[3] + v2[3], 1}
end

-- Subtract one vector from another
local function vSub(v1, v2)
    return {v1[1] - v2[1], v1[2] - v2[2], v1[3] - v2[3], 1}
end

-- Multiply vector by a value K
local function vMul(v1, k)
    return {v1[1] * k, v1[2] * k, v1[3] * k, 1}
end

-- Divide vector by a value K
local function vDiv(v1, k)
    return {v1[1] / k, v1[2] / k, v1[3] / k, 1}
end

-- Get dot product of two input vectors
local function vDotProduct(v1, v2)
    return v1[1] * v2[1] + v1[2] * v2[2] + v1[3] * v2[3]
end

-- Normalize vector between -1 and 1
local function vNormalize(v)
    local l = vDotProduct(v, v) ^ -0.5
    return {v[1] * l, v[2] * l, v[3] * l, 1}
end

-- Get cross product of two input vectors
local function vCrossProduct(v1, v2)
    local v = {0, 0, 0, 1}
    v[1] = v1[2] * v2[3] - v1[3] * v2[2]
    v[2] = v1[3] * v2[1] - v1[1] * v2[3]
    v[3] = v1[1] * v2[2] - v1[2] * v2[1]
    return v
end

-- Get position at which vector intersects plane
local lineStartToEnd, lineToIntersect = {0, 0, 0, 0}, {0, 0, 0, 0}
local function vIntersectPlane(planeDP, ad, bd, lineStart, lineEnd)
    local t = (planeDP - ad) / (bd - ad)
    lineStartToEnd = vSub(lineEnd, lineStart)
    lineToIntersect = vMul(lineStartToEnd, t)
    return vAdd(lineStart, lineToIntersect), t
end

local insidePi, outsidePi, insideTi, outsideTi = {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}
local nInsideP, nOutsideP = 0, 0

-- Test if triangle clips plane, return clipped triangles if so
local function triClipPlane(planeDP, planeN, inTri)

    local function dist(p)
        return planeN[1] * p[1] + planeN[2] * p[2] + planeN[3] * p[3] - planeDP
    end

    -- Calculate if point lies inside or outside of the clipping plane
    -- Save index of vertex in inTri instead of the entire vertex
    nInsideP, nOutsideP = 0, 0
    for i = 1, 3 do
        if dist(inTri[1][i]) >= 0 then
            nInsideP = nInsideP + 1
            insidePi[nInsideP] = i
            insideTi[nInsideP] = i
        else
            nOutsideP = nOutsideP + 1
            outsidePi[nOutsideP] = i
            outsideTi[nOutsideP] = i
        end
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
        local outTri1 = {{inTri[1][insidePi[1]], {0, 0, 0, 1}, {0, 0, 0, 1}}, {{inTri[2][insideTi[1]][1], inTri[2][insideTi[1]][2], inTri[2][insideTi[1]][3]}, {0, 0, 1}, {0, 0, 1}}}

        local t
        local lsDP = vDotProduct(inTri[1][insidePi[1]], planeN)
        outTri1[1][2], t = vIntersectPlane(
            planeDP,
            lsDP, vDotProduct(inTri[1][outsidePi[1]], planeN),
            inTri[1][insidePi[1]], inTri[1][outsidePi[1]]
        )
        outTri1[2][2][1] = t * (inTri[2][outsideTi[1]][1] - inTri[2][insideTi[1]][1]) + inTri[2][insideTi[1]][1]
        outTri1[2][2][2] = t * (inTri[2][outsideTi[1]][2] - inTri[2][insideTi[1]][2]) + inTri[2][insideTi[1]][2]
        outTri1[2][2][3] = t * (inTri[2][outsideTi[1]][3] - inTri[2][insideTi[1]][3]) + inTri[2][insideTi[1]][3]

        outTri1[1][3], t = vIntersectPlane(
            planeDP,
            lsDP, vDotProduct(inTri[1][outsidePi[2]], planeN),
            inTri[1][insidePi[1]], inTri[1][outsidePi[2]]
        )
        outTri1[2][3][1] = t * (inTri[2][outsideTi[2]][1] - inTri[2][insideTi[1]][1]) + inTri[2][insideTi[1]][1]
        outTri1[2][3][2] = t * (inTri[2][outsideTi[2]][2] - inTri[2][insideTi[1]][2]) + inTri[2][insideTi[1]][2]
        outTri1[2][3][3] = t * (inTri[2][outsideTi[2]][3] - inTri[2][insideTi[1]][3]) + inTri[2][insideTi[1]][3]

        planeDP, lsDP = nil, nil
        return 1, outTri1

    -- One point outside plane, return two smaller tris
    elseif nInsideP == 2 and nOutsideP == 1 then

        -- Triangle needs to be clipped, one pointing lies outside
        local outTri1 = {{inTri[1][insidePi[1]], inTri[1][insidePi[2]], {0, 0, 0, 1}}, {inTri[2][insideTi[1]], inTri[2][insideTi[2]], {0, 0, 1}}}
        local outTri2 = {{{0, 0, 0, 1}, {0, 0, 0, 1}, {0, 0, 0, 1}}, {{0, 0, 1}, {0, 0, 1}, {0, 0, 1}}}

        local t
        local leDP = vDotProduct(inTri[1][outsidePi[1]], planeN)
        outTri1[1][3], t = vIntersectPlane(
            planeDP,
            vDotProduct(inTri[1][insidePi[1]], planeN), leDP,
            inTri[1][insidePi[1]], inTri[1][outsidePi[1]]
        )
        outTri1[2][3][1] = t * (inTri[2][outsideTi[1]][1] - inTri[2][insideTi[1]][1]) + inTri[2][insideTi[1]][1]
        outTri1[2][3][2] = t * (inTri[2][outsideTi[1]][2] - inTri[2][insideTi[1]][2]) + inTri[2][insideTi[1]][2]
        outTri1[2][3][3] = t * (inTri[2][outsideTi[1]][3] - inTri[2][insideTi[1]][3]) + inTri[2][insideTi[1]][3]

        outTri2[1][1] = {inTri[1][insidePi[2]][1], inTri[1][insidePi[2]][2], inTri[1][insidePi[2]][3], inTri[1][insidePi[2]][4]}
        outTri2[2][1] = {inTri[2][insideTi[2]][1], inTri[2][insideTi[2]][2], inTri[2][insideTi[2]][3]}

        outTri2[1][2] = {outTri1[1][3][1], outTri1[1][3][2], outTri1[1][3][3], outTri1[1][3][4]}
        outTri2[2][2] = {outTri1[2][3][1], outTri1[2][3][2], outTri1[2][3][3]}
        outTri2[1][3], t = vIntersectPlane(
            planeDP,
            vDotProduct(inTri[1][insidePi[2]], planeN), leDP,
            inTri[1][insidePi[2]], inTri[1][outsidePi[1]]
        )
        outTri2[2][3][1] = t * (inTri[2][outsideTi[1]][1] - inTri[2][insideTi[2]][1]) + inTri[2][insideTi[2]][1]
        outTri2[2][3][2] = t * (inTri[2][outsideTi[1]][2] - inTri[2][insideTi[2]][2]) + inTri[2][insideTi[2]][2]
        outTri2[2][3][3] = t * (inTri[2][outsideTi[1]][3] - inTri[2][insideTi[2]][3]) + inTri[2][insideTi[2]][3]

        planeDP, leDP = nil, nil
        return 2, outTri1, outTri2
    end
    return 0
end

-- Return vector i multiplied by matrix m
local function mMultiplyVector(m, i)
    local v = {0, 0, 0, 0}
    v[1] = i[1] * m[1][1] + i[2] * m[2][1] + i[3] * m[3][1] + i[4] * m[4][1]
	v[2] = i[1] * m[1][2] + i[2] * m[2][2] + i[3] * m[3][2] + i[4] * m[4][2]
	v[3] = i[1] * m[1][3] + i[2] * m[2][3] + i[3] * m[3][3] + i[4] * m[4][3]
	v[4] = i[1] * m[1][4] + i[2] * m[2][4] + i[3] * m[3][4] + i[4] * m[4][4]
    return v
end

-- Set vector i multiplied by matrix m into table reference v
local function mMultiplyVectorR(v, m, i)
    v[1] = i[1] * m[1][1] + i[2] * m[2][1] + i[3] * m[3][1] + i[4] * m[4][1]
	v[2] = i[1] * m[1][2] + i[2] * m[2][2] + i[3] * m[3][2] + i[4] * m[4][2]
	v[3] = i[1] * m[1][3] + i[2] * m[2][3] + i[3] * m[3][3] + i[4] * m[4][3]
	v[4] = i[1] * m[1][4] + i[2] * m[2][4] + i[3] * m[3][4] + i[4] * m[4][4]
end

local function mMakeIdentity()
    return {{1, 0, 0, 0}, {0, 1, 0, 0,}, {0, 0, 1, 0}, {0, 0, 0, 1}}
end

-- Get rotation matrix at X angle angleRad
local function mMakeRotationX(angleRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = 1
	matrix[2][2] = cos(angleRad * 0.5)
	matrix[2][3] = sin(angleRad * 0.5)
	matrix[3][2] = -sin(angleRad * 0.5)
	matrix[3][3] = cos(angleRad * 0.5)
	matrix[4][4] = 1
    return matrix
end

-- Get rotation matrix at Y angle angleRad
local function mMakeRotationY(angleRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = cos(angleRad)
	matrix[1][3] = sin(angleRad)
	matrix[3][1] = -sin(angleRad)
	matrix[2][2] = 1
	matrix[3][3] = cos(angleRad)
	matrix[4][4] = 1
    return matrix
end

-- Get rotation matrix at Z angle angleRad
local function mMakeRotationZ(angleRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = cos(angleRad)
	matrix[1][2] = sin(angleRad)
	matrix[2][1] = -sin(angleRad)
	matrix[2][2] = cos(angleRad)
	matrix[3][3] = 1
	matrix[4][4] = 1
    return matrix
end

-- Get matrix translated to values x, y, z
local function mMakeTranslation(x, y, z)
    return {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {x, y, z, 1}}
end

-- Create projection matrix from input FOV, aspect ratio, near and far distance
local degToRad = 0.5 / 180 * 3.14159
local function mMakeProjection(fFovDegrees, fAspectRatio, inFNear, inFFar)
    local fFovRad = 1 / tan(fFovDegrees * degToRad)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = fAspectRatio * fFovRad
    matrix[2][2] = fFovRad
    matrix[3][3] = inFFar / (inFFar - inFNear)
	matrix[4][3] = (-inFFar * inFNear) / (inFFar - inFNear)
	matrix[3][4] = 1
	matrix[4][4] = 0
    return matrix
end

-- Multiply matrix m1 by matrix m2
local function mMultiplyMatrix(m1, m2)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    for c = 1, 4 do
        for r = 1, 4 do
            matrix[r][c] = m1[r][1] * m2[1][c] + m1[r][2] * m2[2][c] + m1[r][3] * m2[3][c] + m1[r][4] * m2[4][c]
        end
    end
    return matrix
end

local function mPointAt(pos, target, up)
    local newForward = vSub(target, pos)
    newForward = vNormalize(newForward)

    local a = vMul(newForward, vDotProduct(up, newForward))
    local newUp = vSub(up, a)
    newUp = vNormalize(newUp)

    local newRight = vCrossProduct(newUp, newForward)

    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
    matrix[1][1] = newRight[1];  	matrix[1][2] = newRight[2];	    matrix[1][3] = newRight[3];	    matrix[1][4] = 0
	matrix[2][1] = newUp[1];	    matrix[2][2] = newUp[2];	    matrix[2][3] = newUp[3];		matrix[2][4] = 0
	matrix[3][1] = newForward[1];	matrix[3][2] = newForward[2];	matrix[3][3] = newForward[3];	matrix[3][4] = 0
	matrix[4][1] = pos[1];			matrix[4][2] = pos[2];			matrix[4][3] = pos[3];			matrix[4][4] = 1
	return matrix;
end

-- Return inverse of matrix m
local function mQuickInverse(m)
    local matrix = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
	matrix[1][1] = m[1][1]; matrix[1][2] = m[2][1]; matrix[1][3] = m[3][1]; matrix[1][4] = 0
	matrix[2][1] = m[1][2]; matrix[2][2] = m[2][2]; matrix[2][3] = m[3][2]; matrix[2][4] = 0
	matrix[3][1] = m[1][3]; matrix[3][2] = m[2][3]; matrix[3][3] = m[3][3]; matrix[3][4] = 0
	matrix[4][1] = -(m[4][1] * matrix[1][1] + m[4][2] * matrix[2][1] + m[4][3] * matrix[3][1])
	matrix[4][2] = -(m[4][1] * matrix[1][2] + m[4][2] * matrix[2][2] + m[4][3] * matrix[3][2])
	matrix[4][3] = -(m[4][1] * matrix[1][3] + m[4][2] * matrix[2][3] + m[4][3] * matrix[3][3])
	matrix[4][4] = 1
	return matrix;
end

-- ============================================================
-- RUNTIME
-- ============================================================

local loadedMeshes = {}
local loadedTextures = {{name = "missingTex", w = #missingTex, h = #missingTex[1], tex = missingTex}}
local sceneMeshes = {}

local matProj, matRotY, matRotZ, matRotX
local vCamera, vLookDir = {0, 0, 0}, {0, 0, 0}
local fTheta, fYaw, fPitch = 0, 0, 0
local nLightDir

local screenWidth, screenHeight, halfWidth, halfHeight
local trisDrawnLast = 0

local elapsedTime = 0.1
local timeLast, nowTime = computer.uptime(), computer.uptime()

-- Get elapsed time per-frame for mesh rotation, if needed
local function updateElapsedTime()
    nowTime = computer.uptime()
    elapsedTime = nowTime - timeLast
    timeLast = nowTime
end

-- Near plane and viewspace offset
local nearPlane, nearNormal, vsOffset = {0, 0, fNear}, {0, 0, 1}, {1, 1, 0}

-- Reusable dot products
local vsLeftDP, vsRightDP, vsTopDP, vsBottomDP, nearDP

-- Load mesh from file and prepare it for rendering
local function loadSceneMeshes()

    -- Precalculate some commonly used variables
    nLightDir = vNormalize(lightDirection)
    screenWidth = gpu.GetScreenWidth(); screenHeight = gpu.GetScreenHeight()
    halfWidth = 0.5 * screenWidth; halfHeight = 0.5 * screenHeight
    matProj = mMakeProjection(fFov, gpu.GetAspectRatio(), fNear, fFar)

    -- Viewspace and near plane dot products for clipping triangles
    vsLeftDP = vDotProduct({1, 0, 0}, {1, 0, 0})
    vsRightDP = vDotProduct({screenWidth + 1, 0, 0}, {-1, 0, 0})
    vsTopDP = vDotProduct({0, 0, 0}, {0, 1, 0})
    vsBottomDP = vDotProduct({0, screenHeight, 0}, {0, -1, 0})
    nearDP = vDotProduct(nearPlane, nearNormal)

    -- TODO: For meshes in scene:
    -- Load each mesh into loadedMeshes

    -- Load model from filename, if bmp exists with the same name, load it as well
    if fileExists(modelFile) then

        -- TODO: Replace 1 with i in loop
        loadedMeshes[1] = {vert = {}, uv = {}, vInd = {}, uInd = {}, tex = 1}
        loadedMeshes[1].vert, loadedMeshes[1].uv, loadedMeshes[1].vInd, loadedMeshes[1].uInd = getMeshFromString(modelFile, nil, true)

        -- TODO: Check if texture name matches already loaded texture
        local texString = modelFile:gsub(".obj", ".bmp")
        local loadedTex, issue = bmp.ParseBMP(texString)
        if loadedTex ~= false then
            loadedTextures[2] = {name = texString, w = #loadedTex, h = #loadedTex[1], tex = loadedTex}
            loadedMeshes[1].tex = 2
        else print(issue) end

    -- If specified model file doesn't exist, use the cube
    else
        modelFile = "default-cube-fallback"
        loadedMeshes[1] = {vert = {}, uv = {}, vInd = {}, uInd = {}, tex = 1}
        loadedMeshes[1].verts, loadedMeshes[1].uvs, loadedMeshes[1].vInd, loadedMeshes[1].uInd = getMeshFromString(nil, defaultCubeOBJ, false)
    end

    -- Get tricount
    loadedMeshes[1].triCount = #loadedMeshes[1].vInd
    loadedMeshes[1].vertCount = #loadedMeshes[1].vert

    -- TODO: End loop, now spawn objects in scene

    -- TODO: For objects to be placed in scene:
    sceneMeshes[1] = {mesh = 1, parent = nil, children = {}, position = {0, 0, 7.5}, rotation = {0, 0, 0}}
    -- sceneMeshes[2] = {mesh = 1, parent = nil, children = {}, position = {0, 3, 3}, rotation = {0, 0.9, 0}}
    -- sceneMeshes[3] = {mesh = 1, parent = nil, children = {}, position = {0, 6, 3}, rotation = {0, -20, 0}}
end

-- ============================================================
-- 3D COLORS & TEXTURES
-- ============================================================

-- TODO: Optimize/fix oob errors
local depthBuffer = {}
local function resetDepthBuffer()
    depthBuffer = {}
end

-- TODO: Redo with barycentric coordinates
local function getUVCoordinateColor(u, v)
    local uColor = ((u * 256) // 1) * 65536
    local vColor = ((v * 256) // 1) * 256
    return min(max(uColor + vColor, 0), 0xFFFFFF)
end

-- Get color from xyz value of face normal
local function getColorFromNormal(normal)
    -- Offset it for prettier colors
    local fixed = vAdd(vMul(normal, 0.5), {0.5, 0.5, 0.5})
    return ColorFromRGB1(fixed[1], fixed[2], fixed[3])
end

-- Get color of pixel at texture with UV coordinates
-- TODO: Bilinear filtering?
local function uvSampleTexture(u, v, texIndex)
    local texWidth = loadedTextures[texIndex].w
    local texHeight = loadedTextures[texIndex].h
    u, v = v, u
    u = 1 - u
    u = ((u * texWidth) + 1) // 1
    v = ((v * texHeight) + 1) // 1
    u = min(max(u, 1), texWidth)
    v = min(max(v, 1), texHeight)
    return loadedTextures[texIndex].tex[v][u]
end

-- Draw triangle based on cl args
local function drawTexturedTriangle(x, y, tri, texU, texV, texW)
    -- TODO: More of these should be combinable
    -- Also should be re-ordered based on whatever is most commonly used? Or just rewritten more elegantly

    -- Greyscale depth buffer
    if drawDepthBuffer then
        SetPixel(x, y, GetGreyscaleColor(texW))

    -- Blend texture color into the background
    elseif drawDepthBlend then
        local sampleColor = uvSampleTexture(texU / texW, texV / texW, tri[3])
        if drawShaded then
            sampleColor = GetShadedColor(sampleColor, tri[5])
        end
        SetPixel(x, y, BlendColor(backgroundColor, sampleColor, texW ^ depthFadeDist))

    -- RGB according to surface normals
    elseif drawNormalColor then
        SetPixel(x, y, tri[4])

    -- Shade texture based on angle to specified light source
    elseif drawFlatShade then
        SetPixel(x, y, GetGreyscaleColor(tri[5]))

    -- Texture with shading based on per-triangle lighting
    elseif drawShaded then
        local sampleColor = uvSampleTexture(texU / texW, texV / texW, tri[3])
        SetPixel(x, y, GetShadedColor(sampleColor, tri[5]))

    -- Just texture
    else
        SetPixel(x, y, uvSampleTexture(texU / texW, texV / texW, tri[3]))
    end
end

-- ============================================================
-- PROJECTION & RENDERING
-- ============================================================

-- This seems kind of dumb
local texU, texV, texW
local daxStep, dbxStep
local du1Step, du2Step
local dv1Step, dv2Step
local dw1Step, dw2Step
local y1Delta, y2Delta, ax, bx
local texSu, texEu, texSv, texEv, texSw, texEw
local dx2, dx1, dy2, dy1, du2, du1, dv2, dv1, dw2, dw1

-- Draw projected triangle to the screen
local function texturedTriangle(p, u, tri)

    p[1][1] = p[1][1] // 1;  p[2][1] = p[2][1] // 1;  p[3][1] = p[3][1] // 1
    p[1][2] = p[1][2] // 1;  p[2][2] = p[2][2] // 1;  p[3][2] = p[3][2] // 1

    if (p[2][2] < p[1][2]) then
        p[1][1], p[2][1] = p[2][1], p[1][1]
        p[1][2], p[2][2] = p[2][2], p[1][2]
        u[1][1], u[2][1] = u[2][1], u[1][1]
        u[1][2], u[2][2] = u[2][2], u[1][2]
        u[1][3], u[2][3] = u[2][3], u[1][3]
    end
    if (p[3][2] < p[1][2]) then
        p[1][1], p[3][1] = p[3][1], p[1][1]
        p[1][2], p[3][2] = p[3][2], p[1][2]
        u[1][1], u[3][1] = u[3][1], u[1][1]
        u[1][2], u[3][2] = u[3][2], u[1][2]
        u[1][3], u[3][3] = u[3][3], u[1][3]
    end
    if (p[3][2] < p[2][2]) then
        p[2][1], p[3][1] = p[3][1], p[2][1]
        p[2][2], p[3][2] = p[3][2], p[2][2]
        u[2][1], u[3][1] = u[3][1], u[2][1]
        u[2][2], u[3][2] = u[3][2], u[2][2]
        u[2][3], u[3][3] = u[3][3], u[2][3]
    end

    dx1 = p[2][1] - p[1][1]
    dy1 = p[2][2] - p[1][2]
    du1 = u[2][1] - u[1][1]
    dv1 = u[2][2] - u[1][2]
    dw1 = u[2][3] - u[1][3]

    dx2 = p[3][1] - p[1][1]
    dy2 = p[3][2] - p[1][2]
    du2 = u[3][1] - u[1][1]
    dv2 = u[3][2] - u[1][2]
    dw2 = u[3][3] - u[1][3]

    texU, texV, texW = 0, 0, 0
    daxStep = 0; dbxStep = 0
    du1Step = 0; du2Step = 0
    dv1Step = 0; dv2Step = 0
    dw1Step = 0; dw2Step = 0

    daxStep = dx1 / abs(dy1)
    dbxStep = dx2 / abs(dy2)
    du1Step = du1 / abs(dy1)
    dv1Step = dv1 / abs(dy1)
    dw1Step = dw1 / abs(dy1)
    du2Step = du2 / abs(dy2)
    dv2Step = dv2 / abs(dy2)
    dw2Step = dw2 / abs(dy2)

    for i = p[1][2], p[2][2] do

        y1Delta = i - p[1][2]
        ax = (p[1][1] + y1Delta * daxStep) // 1
        bx = (p[1][1] + y1Delta * dbxStep) // 1

        -- Starting value
        texSu = u[1][1] + y1Delta * du1Step
        texSv = u[1][2] + y1Delta * dv1Step
        texSw = u[1][3] + y1Delta * dw1Step

        -- Ending value
        texEu = u[1][1] + y1Delta * du2Step
        texEv = u[1][2] + y1Delta * dv2Step
        texEw = u[1][3] + y1Delta * dw2Step

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

    dx1 = p[3][1] - p[2][1]
    dy1 = p[3][2] - p[2][2]
    du1 = u[3][1] - u[2][1]
    dv1 = u[3][2] - u[2][2]
    dw1 = u[3][3] - u[2][3]

    daxStep = dx1 / abs(dy1)
    dbxStep = dx2 / abs(dy2)
    du1Step = 0; dv1Step = 0
    du1Step = du1 / abs(dy1)
    dv1Step = dv1 / abs(dy1)
    dw1Step = dw1 / abs(dy1)

    for i = p[2][2], p[3][2] do

        y1Delta = i - p[1][2]
        y2Delta = i - p[2][2]
        ax = (p[2][1] + y2Delta * daxStep) // 1
        bx = (p[1][1] + y1Delta * dbxStep) // 1

        -- Starting value
        texSu = u[2][1] + y2Delta * du1Step
        texSv = u[2][2] + y2Delta * dv1Step
        texSw = u[2][3] + y2Delta * dw1Step

        -- Ending value
        texEu = u[1][1] + y1Delta * du2Step
        texEv = u[1][2] + y1Delta * dv2Step
        texEw = u[1][3] + y1Delta * dw2Step

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

local rasterizeStart; local rasterizeCumulative = 0
local testTri, vClipped = {}, {}
local planeTopN, planeBotN, planeLeftN, planeRightN = {0, 1, 0}, {0, -1, 0}, {1, 0, 0}, {-1, 0, 0}

-- Clip each triangle against each side of the viewport
-- After clipping, rasterize each triangle
local function viewportClipTriangle(rasterTris)

    -- Check if any points are outside of screenspace
    local nNewTriangles = 1
    if rasterTris[1][1][1][1] < 1 or rasterTris[1][1][1][1] > screenWidth then goto clipTri end
    if rasterTris[1][1][2][1] < 1 or rasterTris[1][1][2][1] > screenWidth then goto clipTri end
    if rasterTris[1][1][3][1] < 1 or rasterTris[1][1][3][1] > screenWidth then goto clipTri end
    if rasterTris[1][1][1][2] < 1 or rasterTris[1][1][1][2] > screenHeight then goto clipTri end
    if rasterTris[1][1][2][2] < 1 or rasterTris[1][1][2][2] > screenHeight then goto clipTri end
    if rasterTris[1][1][3][2] < 1 or rasterTris[1][1][3][2] > screenHeight then goto clipTri end
    goto skipClip

    -- If points exist outside of screenspace, clip triangles against sides of viewport
    ::clipTri::
    for p = 1, 4 do

        local nTrisToAdd = 0
        while nNewTriangles > 0 do

            testTri = {rasterTris[1][1], rasterTris[1][2]}
            nNewTriangles = nNewTriangles - 1
            nTrisToAdd = 1

            -- Check against each plane of the viewport
            -- Before sending to clip, make sure at least one point actually lies outside of that viewport plane
            vClipped = {testTri}
            if p == 1 then
                -- Top
                if testTri[1][1][2] < 1 or testTri[1][2][2] < 1 or testTri[1][3][2] < 1 then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsTopDP, planeTopN, testTri)
                end
			elseif p == 2 then
                -- Bottom
                if testTri[1][1][2] > screenHeight or testTri[1][2][2] > screenHeight or testTri[1][3][2] > screenHeight then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsBottomDP, planeBotN, testTri)
                end
            elseif p == 3 then
                -- Left
                if testTri[1][1][1] < 1 or testTri[1][2][1] < 1 or testTri[1][3][1] < 1 then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsLeftDP, planeLeftN, testTri)
                end
			elseif p == 4 then
                -- Right
                if testTri[1][1][1] > screenWidth or testTri[1][2][1] > screenWidth or testTri[1][3][1] > screenWidth then
                    nTrisToAdd, vClipped[1], vClipped[2] = triClipPlane(vsRightDP, planeRightN, testTri)
                end
            end

            -- If no clipping occurred, just add triangle
            for w = 1, nTrisToAdd do
                TInsert(rasterTris, {vClipped[w][1], vClipped[w][2], rasterTris[1][3], rasterTris[1][4], rasterTris[1][5]})
            end

            TRemove(rasterTris, 1)
            vClipped = nil
            testTri = nil
        end
        nNewTriangles = #rasterTris
    end
    ::skipClip::

    -- Rasterize triangles based on what was specified in the cl args
    rasterizeStart = GetCPUTime() -- Timing
    for i = 1, nNewTriangles do

        -- Draw wireframe
        if drawWireFrame then
            DrawTriangle(rasterTris[i][1], 0xFFFFFF)

        -- Draw with texture
        elseif doDrawTextured then
            texturedTriangle(rasterTris[i][1], rasterTris[i][2], rasterTris[i])
        end

        -- Debug
        trisDrawnLast = trisDrawnLast + 1
    end
    rasterTris = nil
    rasterizeCumulative = rasterizeCumulative + (GetCPUTime() - rasterizeStart)
end

local projectionStart; local projCumulative = 0
local segmentTimeStart; local segmentCumulative = 0
local pClipped, nPClipped = {}, 0
local normal, line1, line2 = {0, 0, 0}, {0, 0, 0}, {0, 0, 0}

-- Get camera rotation matrix from player control
local function getViewMatrix()
    local vUp, vTarget = {0, 1, 0, 1}, {0, 0, 1, 1}
    local matCameraPitch = mMakeRotationX(fPitch)
    local matCameraYaw = mMakeRotationY(fYaw)
    local matCameraRot = mMultiplyMatrix(matCameraPitch, matCameraYaw)
    vLookDir = mMultiplyVector(matCameraRot, vTarget)
    vTarget = vAdd(vCamera, vLookDir)
    local matCamera = mPointAt(vCamera, vTarget, vUp) -- vCamera, vTarget, vUp
    return mQuickInverse(matCamera)
end

-- Project verts, and then triangles from loaded mesh data
-- Each triangle gets sent into the rasterizer
local function rasterizeMesh(matView, sceneMesh)

    -- Rotate mesh in scene
    -- if doModelRotate then fTheta = fTheta + elapsedTime end
    matRotX = mMakeRotationX(sceneMesh.rotation[1])
    matRotY = mMakeRotationY(sceneMesh.rotation[2])
	matRotZ = mMakeRotationZ(sceneMesh.rotation[3])

    -- Translate model in scene
    local matTrans = mMakeTranslation(sceneMesh.position[1], sceneMesh.position[2], sceneMesh.position[3])

    -- Build mesh rotation matrix, handles if mesh is rotating
    local matWorld = mMakeIdentity()
    matWorld = mMultiplyMatrix(matRotZ, matRotX)
    matWorld = mMultiplyMatrix(matWorld, matRotY)
    matWorld = mMultiplyMatrix(matWorld, matTrans)

    -- First, project vertices
    local meshRef = loadedMeshes[sceneMesh.mesh]
    local vInd, uInd
    local pVert = {}
    local vsVert = {}
    for i = 1, loadedMeshes[sceneMesh.mesh].vertCount do
        pVert[i], vsVert[i] = {0, 0, 0, 1}, {0, 0, 0, 1}
        mMultiplyVectorR(pVert[i], matWorld, TablePack(StringUnpack(vertPackS, meshRef.vert[i])))
        mMultiplyVectorR(vsVert[i], matView, pVert[i])
    end

    -- Then use projected vertices to construct and 
    for i = 1, loadedMeshes[sceneMesh.mesh].triCount do
        projectionStart = GetCPUTime()

        -- Unpack vertex and uv indices
        vInd = TablePack(StringUnpack(indPackS, meshRef.vInd[i]))
        uInd = TablePack(StringUnpack(indPackS, meshRef.uInd[i]))

        -- Get face normal
        line1 = vSub(pVert[vInd[2]], pVert[vInd[1]])
        line2 = vSub(pVert[vInd[3]], pVert[vInd[1]])
        normal = vCrossProduct(line1, line2)
        normal = vNormalize(normal)

        -- Compare face normal against camera normal for backface culling
        local vCameraRay = vSub(pVert[vInd[1]], vCamera)
        local normalToCamera = vDotProduct(normal, vCameraRay)

        projCumulative = projCumulative + (GetCPUTime() - projectionStart)
        if normalToCamera < bfcThreshold then
            projectionStart = GetCPUTime()

            -- Get amount of shade relative to light normal, and find normal color if needed
            local lightDp = max(min(lightBias + vDotProduct(nLightDir, normal), 1), shadeMaximum)
            local tColor = 0x000000
            if drawNormalColor then tColor = getColorFromNormal(normal) end

            -- Check if triangle needs to be near-plane clipped
            if vsVert[vInd[1]][3] < fNear or
               vsVert[vInd[2]][3] < fNear or
               vsVert[vInd[3]][3] < fNear then

                -- If so, clip it
                nPClipped, pClipped[1], pClipped[2] = triClipPlane(nearDP, nearNormal, {
                    {vsVert[vInd[1]],
                     vsVert[vInd[2]],
                     vsVert[vInd[3]]},
                    {TablePack(StringUnpack(uvPackS, meshRef.uv[uInd[1]])),
                     TablePack(StringUnpack(uvPackS, meshRef.uv[uInd[2]])),
                     TablePack(StringUnpack(uvPackS, meshRef.uv[uInd[3]]))}
                })
            else
                -- Otherwise, skip clip
                nPClipped = 1
                pClipped[1] = {
                    {vsVert[vInd[1]],
                     vsVert[vInd[2]],
                     vsVert[vInd[3]]},
                    {TablePack(StringUnpack(uvPackS, meshRef.uv[uInd[1]])),
                     TablePack(StringUnpack(uvPackS, meshRef.uv[uInd[2]])),
                     TablePack(StringUnpack(uvPackS, meshRef.uv[uInd[3]]))}
                }
            end

            projCumulative = projCumulative + (GetCPUTime() - projectionStart) -- Timing point end
            for n = 1, nPClipped do
                projectionStart = GetCPUTime()

                -- Project points and uvs from 3D to 2D
                pClipped[n][1][1] = mMultiplyVector(matProj, pClipped[n][1][1])
                pClipped[n][1][2] = mMultiplyVector(matProj, pClipped[n][1][2])
                pClipped[n][1][3] = mMultiplyVector(matProj, pClipped[n][1][3])
                pClipped[n][2][1][1] = pClipped[n][2][1][1] / pClipped[n][1][1][4]
                pClipped[n][2][2][1] = pClipped[n][2][2][1] / pClipped[n][1][2][4]
                pClipped[n][2][3][1] = pClipped[n][2][3][1] / pClipped[n][1][3][4]
                pClipped[n][2][1][2] = pClipped[n][2][1][2] / pClipped[n][1][1][4]
                pClipped[n][2][2][2] = pClipped[n][2][2][2] / pClipped[n][1][2][4]
                pClipped[n][2][3][2] = pClipped[n][2][3][2] / pClipped[n][1][3][4]
                pClipped[n][2][1][3] = 1 / pClipped[n][1][1][4]
                pClipped[n][2][2][3] = 1 / pClipped[n][1][2][4]
                pClipped[n][2][3][3] = 1 / pClipped[n][1][3][4]

                -- Scale into view
                pClipped[n][1][1] = vDiv(pClipped[n][1][1], pClipped[n][1][1][4])
                pClipped[n][1][2] = vDiv(pClipped[n][1][2], pClipped[n][1][2][4])
                pClipped[n][1][3] = vDiv(pClipped[n][1][3], pClipped[n][1][3][4])

                -- Invert XY
                pClipped[n][1][1][1] = -pClipped[n][1][1][1]
				pClipped[n][1][2][1] = -pClipped[n][1][2][1]
				pClipped[n][1][3][1] = -pClipped[n][1][3][1]
				pClipped[n][1][1][2] = -pClipped[n][1][1][2]
				pClipped[n][1][2][2] = -pClipped[n][1][2][2]
				pClipped[n][1][3][2] = -pClipped[n][1][3][2]

                -- Offset verts into visible normalized space
                pClipped[n][1][1] = vAdd(pClipped[n][1][1], vsOffset)
                pClipped[n][1][2] = vAdd(pClipped[n][1][2], vsOffset)
                pClipped[n][1][3] = vAdd(pClipped[n][1][3], vsOffset)
                pClipped[n][1][1][1] = pClipped[n][1][1][1] * halfWidth
                pClipped[n][1][2][1] = pClipped[n][1][2][1] * halfWidth
                pClipped[n][1][3][1] = pClipped[n][1][3][1] * halfWidth
                pClipped[n][1][1][2] = pClipped[n][1][1][2] * halfHeight
                pClipped[n][1][2][2] = pClipped[n][1][2][2] * halfHeight
                pClipped[n][1][3][2] = pClipped[n][1][3][2] * halfHeight

                -- Copy texture over
                pClipped[n][3] = meshRef.tex
                pClipped[n][4] = tColor
                pClipped[n][5] = lightDp

                -- Send triangle to be viewport clipped and then rendered
                projCumulative = projCumulative + (GetCPUTime() - projectionStart)
                viewportClipTriangle({pClipped[n]})
                pClipped[n] = nil
            end
        end
    end
end

-- ============================================================
-- DEBUG
-- ============================================================

local debugCycles, maxDebugCycles = 1, 30
local projectionTimeTotal, rasterizeTimeTotal, segmentTimeTotal = 0, 0, 0
local debugFG, debugBG = 0xFFFFFF, 0x000000

-- Print debug stats to the screen
local function modelDebug()
    projectionTimeTotal = projectionTimeTotal + projCumulative
    rasterizeTimeTotal = rasterizeTimeTotal + rasterizeCumulative
    segmentTimeTotal = segmentTimeTotal + segmentCumulative
    local projAverage = projectionTimeTotal / debugCycles
    local rastAverage = rasterizeTimeTotal / debugCycles
    local segAverage = segmentTimeTotal / debugCycles

    SetText(1, 1, modelFile, debugFG, debugBG, false)
    SetText(1, 3, string.format("TRIS: %d - VERT: %d", loadedMeshes[1].triCount, loadedMeshes[1].vertCount), debugFG, debugBG, false)
    SetText(1, 5, string.format("DRAWN: %d", trisDrawnLast), debugFG, debugBG, false)
    SetText(1, 7, string.format("Proj: %0.1fms", (projAverage) * 1000), debugFG, debugBG, false)
    SetText(1, 9, string.format("Rast: %0.1fms", (rastAverage) * 1000), debugFG, debugBG, false)

    segmentCumulative = 0
    projCumulative = 0
    rasterizeCumulative = 0
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

local KEY_FORWARD, KEY_LEFT, KEY_BACKWARD, KEY_RIGHT = "W", "A", "S", "D"
local KEY_UP, KEY_DOWN, KEY_QUIT = "Z", "X", "Q"
local KEY_TURNLEFT, KEY_TURNRIGHT, KEY_TURNUP, KEY_TURNDOWN = "LEFT", "RIGHT", "UP", "DOWN"
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
        local vRight = vMul({-vLookDir[3], 0, vLookDir[1]}, moveSpeed * elapsedTime)
        vCamera = vSub(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_RIGHT) then
        local vRight = vMul({-vLookDir[3], 0, vLookDir[1]}, moveSpeed * elapsedTime)
        vCamera = vAdd(vCamera, vRight)
    end
    if inputManager.isKeyDown(inputManager, KEY_FORWARD) then
        local vForward = vMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vAdd(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_BACKWARD) then
        local vForward = vMul(vLookDir, moveSpeed * elapsedTime)
        vCamera = vSub(vCamera, vForward)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNLEFT) then
        fYaw = fYaw - (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNRIGHT) then
        fYaw = fYaw + (2 * elapsedTime)
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNUP) then
        fPitch = fPitch - (2 * elapsedTime) -- TODO: These change the speed of translation
    end
    if inputManager.isKeyDown(inputManager, KEY_TURNDOWN) then
        fPitch = fPitch + (2 * elapsedTime)
    end
end

-- ============================================================
-- RUN THE DAMN THING
-- ============================================================

-- TODO: Mesh Instancing
-- New data structure:
    -- loadedMesh becomes meshInstance
    -- New table "loadedMeshData" as an array of loaded vertex + uv + tri sets
    -- New table "sceneMeshes" -> array of meshInstance

    -- meshInstance table gains new values:
        -- "meshData" -> reference to some loaded vertex + uv + tri set (see below)
        -- "parent" -> points towards another meshInstance for position/rotation inheritance
        -- "children" -> array of child element references for this instance
        -- "position" -> XYZ values to translate the mesh during projection
        -- "rotation" -> XYZ values to rotate the mesh during projection

    -- meshInstance table removes values:
        -- vertex + uv data gets moved to loadedMeshData
        -- Projected verts shouldn't be saved, just used during rasterizeMesh() and then disposed

-- New scene-setting format:
    -- If no format set, load scene as it is now (mesh with no translation or rotation)
    -- File specifying a scene's data can be passed through arguments:
        -- Meshes to load
        -- Position of meshes
        -- Functions to apply to loaded meshes (translation + rotation)

-- TODO: Packaging Refactor
-- This needs to be usable from other scripts:
    -- Move chugraph instance to main()
    -- main() should only activate if some argument is passed
    -- New script to demo 3d graphics in the same way as chug3d does now, with arguments and such
    -- Should work with the above instancing refactor
    -- Most of the functions in chug3d are helpers, and do not need to be accessible outside of the script
    -- renderTriangles() becomes RenderTriangles(), and handles rendering triangles
        -- Remove ClearScreen() from RenderTriangles()
    -- Things to move:
        -- DepthBuffer should be moved to chugraph for future shader functionality
        -- SetPixelXYZ would be an example of a SetPixel that respects and sets the DepthBuffer in chugraph

local function renderTriangles()
    ClearScreen()
    resetDepthBuffer()

    local viewMat = getViewMatrix()
    for i = 1, #sceneMeshes do
        rasterizeMesh(viewMat, sceneMeshes[i])
    end
end

local function main()
    ClearScreen()
    loadSceneMeshes()
    gpu.SetSceneBackground(backgroundColor)

    -- Force garbage collection before starting
    for i = 1, 10 do os.sleep(0) end

    while true do

        -- Update elapsed time
        updateElapsedTime()

        local exit = applyInputControls()
        if exit then
            gpu.ResetToCommandLine()
            package.loaded["chugraph"] = nil
            package.loaded["chugkey"] = nil
            package.loaded["chugbmp"] = nil
            break
        end

        -- Clear screen and draw projected triangles
        renderTriangles()

        -- Draw debug, render screen
        modelDebug()
        UpdateScreen()

        -- Reset debug values
        trisDrawnLast = 0

        -- Take player's input controls (yielding)
        if doUserControl then inputManager.updateKeypress(inputManager) end
    end
end
main()

print("Projected with Chug3D " .. version)