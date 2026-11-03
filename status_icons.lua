--[[
Status icon extraction for EnemyHUD, so players don't need Python.

Reads the game's status icon DAT (ROM\119\57, or an XIPivot overlay of it) and writes one PNG per
status id into icons\, e.g. 2.png = Sleep. Same output as tools\extract_status_icons.py.

The DAT holds 640 entries of 0x1800 bytes. Entry N is status id N: a 32x32 bitmap whose
BITMAPINFOHEADER sits at 0x295, rows bottom-up, either 32-bit BGRA or 8-bit with a 256-color BGRA
palette. Game icons use alpha 0..0x80 (doubled here); XI-View's use the full 0..0xFF.
PNGs are written uncompressed (stored deflate block), which needs no zlib.
--]]

local bit = require('bit')

local status_icons = {}

local ENTRY = 0x1800
local HEADER_AT = 0x295
local PIXELS_AT = HEADER_AT + 40
local SIZE = 32
local ROW = SIZE * 4

local byte, char, sub = string.byte, string.char, string.sub
local band, bxor, rshift, bnot = bit.band, bit.bxor, bit.rshift, bit.bnot

local function u16(s, at) local a, b = byte(s, at + 1, at + 2) return a + b * 0x100 end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 0x10000 end

local crc_table = {}
for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
        c = band(c, 1) == 1 and bxor(0xEDB88320, rshift(c, 1)) or rshift(c, 1)
    end
    crc_table[n] = c
end

local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = bxor(crc_table[band(bxor(c, byte(s, i)), 0xFF)], rshift(c, 8))
    end
    return bnot(c)
end

local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + byte(s, i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function be32(n)
    return char(band(rshift(n, 24), 0xFF), band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF))
end

local function chunk(kind, data)
    return be32(#data)..kind..data..be32(crc32(kind..data))
end

local function png(raw)
    local len = #raw   -- 32 rows of 129 bytes, well under one stored block's 65535
    local zlib = '\120\1\1'..char(len % 256, math.floor(len / 256), 255 - len % 256, 255 - math.floor(len / 256))
        ..raw..be32(adler32(raw))
    return '\137PNG\r\n\26\n'
        ..chunk('IHDR', be32(SIZE)..be32(SIZE)..'\8\6\0\0\0')
        ..chunk('IDAT', zlib)
        ..chunk('IEND', '')
end

-- BGRA pixels (bottom-up) to PNG scanlines (top-down RGBA, filter byte 0); nil if fully transparent
local function scanlines(bgra)
    local max_alpha = 0
    for i = 4, #bgra, 4 do
        local a = byte(bgra, i)
        if a > max_alpha then max_alpha = a end
    end
    if max_alpha == 0 then return nil end
    local scale = max_alpha <= 0x80 and 2 or 1
    local rows = {}
    for y = SIZE - 1, 0, -1 do
        local src = sub(bgra, y * ROW + 1, (y + 1) * ROW)
        rows[#rows + 1] = '\0'..src:gsub('(.)(.)(.)(.)', function(b, g, r, a)
            return r..g..b..char(math.min(255, byte(a) * scale))
        end)
    end
    return table.concat(rows)
end

local function entry_pixels(entry)
    if u32(entry, HEADER_AT) ~= 40 or u32(entry, HEADER_AT + 4) ~= SIZE or u32(entry, HEADER_AT + 8) ~= SIZE then
        return nil
    end
    local bpp = u16(entry, HEADER_AT + 14)
    if bpp == 32 then
        return sub(entry, PIXELS_AT + 1, PIXELS_AT + SIZE * ROW)
    elseif bpp == 8 then
        local palette = {}
        for i = 0, 255 do
            palette[char(i)] = sub(entry, PIXELS_AT + i * 4 + 1, PIXELS_AT + i * 4 + 4)
        end
        return (sub(entry, PIXELS_AT + 1024 + 1, PIXELS_AT + 1024 + SIZE * SIZE):gsub('.', palette))
    end
end

local function exists(file)
    local f = io.open(file, 'rb')
    if f then f:close() end
    return f ~= nil
end

-- XIPivot overlays (in priority order) that replace the status icon DAT
local function pivot_overlays()
    local pivot = windower.windower_path..'addons/XIPivot/'
    local f = io.open(pivot..'data/settings.xml', 'r')
    if not f then return {} end
    local list = f:read('*a'):match('<overlays>(.-)</overlays>') or ''
    f:close()
    local found = {}
    for name in list:gmatch('[^,]+') do
        name = name:match('^%s*(.-)%s*$')
        local dat = pivot..'data/DATs/'..name..'/ROM/119/57.DAT'
        if name ~= '' and exists(dat) then found[#found + 1] = {dat = dat, label = 'XIPivot overlay '..name} end
    end
    return found
end

-- The DAT to read: a given DAT file or FFXI folder, else the first XIPivot overlay, else the game's own
function status_icons.find_dat(given)
    if given and given ~= '' then
        given = given:gsub('"', ''):gsub('\\', '/')
        local dat = given:lower():match('%.dat$') and given or given:gsub('/$', '')..'/ROM/119/57.DAT'
        return exists(dat) and dat or nil, dat
    end
    local overlay = pivot_overlays()[1]
    if overlay then return overlay.dat, overlay.label end
    local dat = windower.ffxi_path:gsub('\\', '/'):gsub('/$', '')..'/ROM/119/57.DAT'
    return exists(dat) and dat or nil, dat
end

-- Writes <out_dir><id>.png for every icon in the DAT; returns the count, or nil and an error
function status_icons.extract(dat, out_dir)
    local f, err = io.open(dat, 'rb')
    if not f then return nil, err end
    local data = f:read('*a')
    f:close()
    if #data < ENTRY then return nil, dat..' is not a status icon DAT' end
    local written = 0
    for id = 0, math.floor(#data / ENTRY) - 1 do
        local pixels = entry_pixels(sub(data, id * ENTRY + 1, (id + 1) * ENTRY))
        local raw = pixels and scanlines(pixels)
        if raw then
            local out, werr = io.open(out_dir..id..'.png', 'wb')
            if not out then return nil, werr end
            out:write(png(raw))
            out:close()
            written = written + 1
        end
    end
    return written
end

return status_icons
