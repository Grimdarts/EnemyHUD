--[[
EnemyHUD: target HP bar in a Vana'diel-style frame, with the monster's level, who it is targeting,
a cast/readying bar and debuff icons with timers.

Based on enemybar by Mike McKee (BSD) and the debuff tracking of Debuffed by Xathe (BSD).
Status icons are extracted from the game's status icon DAT, ROM\119\57 (tools\extract_status_icons.py);
rounded corner/cap textures come from tools\enemyhud_textures.py.

Commands: //ehud check (toggle auto-check for levels), //ehud center, //ehud save, //ehud hide | show
Drag the frame with the mouse to move it; the spot is saved.
--]]

_addon.name = 'EnemyHUD'
_addon.author = 'Someonesmall (with Claude); enemybar by mmckee, Debuffed by Xathe'
_addon.version = '1.3.0'
_addon.commands = {'ehud', 'enemyhud'}

config = require('config')
images = require('images')
texts = require('texts')
packets = require('packets')
res = require('resources')
require('tables')
require('sets')

defaults = {}
defaults.pos = {x = -1, y = 60}   -- x = -1 centers it
defaults.width = 400
defaults.auto_check = true        -- quietly /check new monsters so the level can be shown
defaults.max_debuffs = 10
defaults.icon_size = 14         -- buff/debuff icon size
defaults.hp_yellow = 50           -- bar turns yellow at or below this HP%
defaults.hp_red = 25              -- and red at or below this
defaults.name_font = 'Georgia'
defaults.name_size = 11
defaults.small_font = 'Georgia'
defaults.small_size = 9

settings = config.load(defaults)

-- Palette (Vana'diel classic); the panel navy and gold are also baked into the corner textures
local PANEL = {215, 29, 42, 68}
local GOLD = {255, 184, 154, 85}
local TRACK = {255, 15, 23, 41}
local PARCHMENT = {244, 227, 181}
local MUTED = {176, 160, 120}
local HP_GREEN = {95, 179, 90}
local HP_YELLOW = {227, 192, 74}
local HP_RED = {208, 69, 63}
local CAST = {233, 196, 106}
local TOT_BAR = {90, 150, 230}

local PAD = 10
local ICON = settings.icon_size
local ICON_ROW = ICON + 18   -- icon, timer text and gap
local CORNER = 6       -- panel corner radius, must match enemyhud_textures.py
local path = windower.addon_path
local icon_dir = path..'icons/'

local function image(texture, color, draggable)
    return images.new({
        color = {alpha = color[1], red = color[2], green = color[3], blue = color[4]},
        texture = {path = path..texture, fit = true},
        size = {width = 1, height = 1},
        pos = {x = 0, y = 0},
        draggable = draggable or false,
    })
end

local function rect(color, draggable)
    return image('white.png', color, draggable)
end

local function set_rect(r, x, y, w, h)
    r:pos(x, y)
    r:size(math.max(w, 0), h)
end

-- Pill-shaped bar: rounded caps on both ends and a stretched middle, works at any length
local Pill = {}
Pill.__index = Pill

local function pill(color)
    return setmetatable({l = image('cap_l.png', color), m = rect(color), r = image('cap_r.png', color)}, Pill)
end

function Pill:set(x, y, w, h)
    if w <= 0 then
        self.empty = true
        self:hide()
        return
    end
    self.empty = false
    local cap = math.min(math.floor(h / 2), math.floor(w / 2))
    set_rect(self.l, x, y, cap, h)
    set_rect(self.m, x + cap, y, w - 2 * cap, h)
    set_rect(self.r, x + w - cap, y, cap, h)
end

function Pill:color(r, g, b)
    self.l:color(r, g, b); self.m:color(r, g, b); self.r:color(r, g, b)
end

function Pill:show()
    if self.empty then return end
    self.l:show(); self.m:show(); self.r:show()
end

function Pill:hide()
    self.l:hide(); self.m:hide(); self.r:hide()
end

local function label(font, size, italic)
    return texts.new('', {
        pos = {x = 0, y = 0},
        text = {font = font, size = size, red = PARCHMENT[1], green = PARCHMENT[2], blue = PARCHMENT[3],
                stroke = {width = 1, alpha = 180, red = 0, green = 0, blue = 0}},
        bg = {visible = false},
        flags = {draggable = false, italic = italic or false},
    })
end

-- Rounded panel: corner textures, edge bands with a gold line, and a draggable middle
local white = {255, 255, 255, 255}
local frame = {
    tl = image('corner_tl.png', white), tr = image('corner_tr.png', white),
    bl = image('corner_bl.png', white), br = image('corner_br.png', white),
    top = rect(PANEL), bottom = rect(PANEL),
    top_line = rect(GOLD), bottom_line = rect(GOLD), left_line = rect(GOLD), right_line = rect(GOLD),
}
local middle = rect(PANEL, true)

local hp_frame, hp_track = pill(GOLD), pill(TRACK)
local hp_trail = pill({140, 255, 255, 255})
local hp_fill = pill({255, HP_GREEN[1], HP_GREEN[2], HP_GREEN[3]})
local cast_track, cast_fill = pill(TRACK), pill({255, CAST[1], CAST[2], CAST[3]})
local tot_track, tot_fill = pill(TRACK), pill({255, TOT_BAR[1], TOT_BAR[2], TOT_BAR[3]})
local name_text = label(settings.name_font, settings.name_size)
local hpp_text = label(settings.name_font, settings.name_size)
local cast_text = label(settings.small_font, settings.small_size, true)
local cast_time = label(settings.small_font, settings.small_size)
local tot_text = label(settings.small_font, settings.small_size)
-- Icon slots shared by the buff row and the debuff row; each icon sits on a tinted tile
local SLOTS = settings.max_debuffs * 2
local BUFF_TILE = {150, 70, 150, 80}
local DEBUFF_TILE = {150, 160, 50, 50}
local tiles, icons, timers = {}, {}, {}
for i = 1, SLOTS do
    tiles[i] = rect(BUFF_TILE)
end
for i = 1, SLOTS do
    -- fit = false, or every new icon is drawn at the PNG's 32x32 instead of icon_size
    icons[i] = images.new({size = {width = ICON, height = ICON}, texture = {fit = false}, draggable = false,
                           color = {alpha = 255, red = 255, green = 255, blue = 255}})
    timers[i] = label(settings.small_font, settings.small_size - 1)
end

local primitives = {middle, hp_frame, hp_track, hp_trail, hp_fill, name_text, hpp_text}
for _, part in pairs(frame) do primitives[#primitives + 1] = part end
local cast_parts = {cast_track, cast_fill, cast_text, cast_time}
local tot_parts = {tot_track, tot_fill, tot_text}

-- State
local levels = {}          -- [mob index] = level, -1 when impossible to gauge
local check_pending = {}   -- [mob id] = os.clock() of an auto-check we sent
local check_tries = {}     -- [mob id] = auto-checks sent (gives up after 3, e.g. out of range)
local icon_paths = {}      -- [slot] = texture currently set, so it only changes when needed
local saved = {x = settings.pos.x, y = settings.pos.y}
local casting = {}         -- [mob id] = {name, start, duration}
local debuffed = {}        -- [mob id] = {[status id] = {spell, applied, ends}} (ends nil = no known duration)
local buffed = {}          -- [mob id] = {[status id] = {applied, ends}}, effects monsters give themselves or each other
local aggro = {}           -- [mob id] = id of whoever it last attacked, cast on or used a TP move on
local player_id = 0
local trail_width = 0
local visible = false
local user_hidden = false  -- //ehud hide (e.g. while the map is open); not saved
local origin = {x = 0, y = 0}

local function anchor()
    local x = settings.pos.x
    if x < 0 then x = math.floor(windower.get_windower_settings().ui_x_res / 2 - settings.width / 2) end
    return x, settings.pos.y
end

local function show_all(list, on)
    for _, p in ipairs(list) do
        if on then p:show() else p:hide() end
    end
end

local function hide_debuffs(from)
    for i = from, SLOTS do
        tiles[i]:hide()
        icons[i]:hide()
        timers[i]:hide()
    end
end

local function hide_hud()
    show_all(primitives, false)
    show_all(cast_parts, false)
    show_all(tot_parts, false)
    hide_debuffs(1)
    visible = false
end

local function hp_color(hpp)
    if hpp <= settings.hp_red then return HP_RED end
    if hpp <= settings.hp_yellow then return HP_YELLOW end
    return HP_GREEN
end

local function in_party(id)
    for _, member in pairs(windower.ffxi.get_party() or {}) do
        if type(member) == 'table' and member.mob and member.mob.id == id then return true end
    end
    return false
end

-- Pets (avatars, wyverns, automatons) can share the monster spawn type, so rule out party members' pets
local function is_party_pet(mob)
    for _, member in pairs(windower.ffxi.get_party() or {}) do
        if type(member) == 'table' and member.mob and member.mob.pet_index == mob.index then return true end
    end
    return false
end

local function is_enemy(mob)
    return mob ~= nil and mob.spawn_type == 16 and not is_party_pet(mob)
end

local function claim_color(target)
    if target.hpp == 0 then return {155, 155, 155} end
    if not target.is_npc or target.claim_id == 0 then return PARCHMENT end
    if target.claim_id == player_id or in_party(target.claim_id) then return {255, 170, 160} end
    return {190, 160, 255}
end

-- Enemy's target: who it last acted on, else the game's own target field
local function enemy_target(target)
    if not is_enemy(target) then return nil end
    local mob = aggro[target.id] and windower.ffxi.get_mob_by_id(aggro[target.id])
    if not mob and target.target_index and target.target_index > 0 then
        mob = windower.ffxi.get_mob_by_index(target.target_index)
    end
    if mob and mob.id ~= target.id and mob.hpp > 0 then return mob end
end

local function relation_color(mob)
    if mob.id == player_id then return {255, 120, 110} end                -- you have hate
    local pet = windower.ffxi.get_mob_by_target('pet')
    if pet and pet.id == mob.id then return {150, 230, 150} end           -- your pet / avatar
    if in_party(mob.id) then return {120, 220, 255} end
    return PARCHMENT
end

local function format_time(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

-- Level: from /check results (ours or the player's) and widescan
local function auto_check(target)
    if not settings.auto_check or not is_enemy(target) or levels[target.index] then return end
    local now = os.clock()
    local tries = check_tries[target.id] or 0
    if tries >= 3 or (check_pending[target.id] and now - check_pending[target.id] < 5) then return end
    check_pending[target.id], check_tries[target.id] = now, tries + 1
    packets.inject(packets.new('outgoing', 0x0DD, {['Target'] = target.id, ['Target Index'] = target.index, ['Check Type'] = 0}))
end

local function level_text(target)
    if not is_enemy(target) then return '' end
    local lv = levels[target.index]
    local shown = lv == nil and '--' or lv < 0 and '??' or tostring(lv)
    return ('  \\cs(%d,%d,%d)Lv.%s\\cr'):format(MUTED[1], MUTED[2], MUTED[3], shown)
end

-- Debuffs: spells use Debuffed's overwrite rules and spell durations; abilities, blood pacts,
-- weapon skills and added effects have no duration in the game data, so they show without a timer
local APPLIED = S{82, 127, 141, 203, 236, 237, 242, 243, 267, 268, 269, 270, 271, 272, 277, 278, 279, 320, 645, 754, 755, 804}
local DAMAGE_SPELL = S{2, 252}
local ADDED_EFFECT = S{160, 164}
local UNTIMED_LIMIT = 300   -- seconds an untimed icon may stay if no wear-off message arrives
local GAINED = S{186, 194, 205, 230, 266, 280, 319}   -- "<target> gains the effect of <status>"
local DISPELLED = S{159, 168, 341, 342, 343, 344, 647, 805, 806}   -- "<target>'s <status> effect disappears"
local DAMAGE = S{1, 2, 67, 110, 185, 252, 264, 317, 352, 353, 576, 577}   -- "<target> takes <n> points of damage"
local SLEEP = S{2, 19, 193}   -- sleep, sleep, Lullaby

-- Sleep breaks on damage, and the game sends no wear-off message for that
local function wake(target)
    if not debuffed[target] then return end
    for status in pairs(SLEEP) do debuffed[target][status] = nil end
end

local function apply_debuff(target, effect, spell_id)
    debuffed[target] = debuffed[target] or {}
    local spell = spell_id and res.spells[spell_id]
    if spell then
        for status, entry in pairs(debuffed[target]) do
            local old = entry.spell and res.spells[entry.spell]
            if old then
                for _, id in ipairs(old.overwrites or {}) do
                    if id == spell_id then return end   -- a stronger version is already on
                end
                for _, id in ipairs(spell.overwrites or {}) do
                    if id == entry.spell then debuffed[target][status] = nil end
                end
            end
        end
    end
    local now = os.clock()
    local duration = spell and spell.status == effect and spell.duration or nil
    debuffed[target][effect] = {spell = spell_id, applied = now, ends = duration and now + duration}
end

local function remove_effect(target, status)
    if debuffed[target] then debuffed[target][status] = nil end
    if buffed[target] then buffed[target][status] = nil end
end

-- Buffs: effects a monster gains from itself or another monster (spell buffs keep their duration)
local function track_buffs(act)
    for _, t in ipairs(act.targets) do
        local victim = windower.ffxi.get_mob_by_id(t.id)
        if is_enemy(victim) then
            for _, a in ipairs(t.actions) do
                if (GAINED:contains(a.message) or APPLIED:contains(a.message)) and res.buffs[a.param] then
                    local spell = act.category == 4 and res.spells[act.param]
                    local duration = spell and spell.status == a.param and spell.duration or nil
                    local now = os.clock()
                    buffed[t.id] = buffed[t.id] or {}
                    buffed[t.id][a.param] = {applied = now, ends = duration and now + duration}
                end
            end
        end
    end
end

-- Dispels, erases and steals take the effect off whichever row it was in
local function track_removals(act)
    for _, t in ipairs(act.targets) do
        for _, a in ipairs(t.actions) do
            if DISPELLED:contains(a.message) then remove_effect(t.id, a.param) end
            if a.add_effect_message and DISPELLED:contains(a.add_effect_message) then remove_effect(t.id, a.add_effect_param) end
        end
    end
end

local function track_debuffs(act)
    local actor = windower.ffxi.get_mob_by_id(act.actor_id)
    if is_enemy(actor) then   -- monsters acting on monsters give buffs, not debuffs
        track_buffs(act)
        return
    end
    for _, t in ipairs(act.targets) do
        local victim = windower.ffxi.get_mob_by_id(t.id)
        if is_enemy(victim) then
            for _, a in ipairs(t.actions) do
                if DAMAGE:contains(a.message) and a.param > 0 then wake(t.id) end
                local spell = act.category == 4 and res.spells[act.param]
                if spell and DAMAGE_SPELL:contains(a.message) and spell.status then
                    apply_debuff(t.id, spell.status, act.param)
                elseif APPLIED:contains(a.message) and res.buffs[a.param] then
                    apply_debuff(t.id, a.param, spell and act.param or nil)
                end
                if a.add_effect_message and ADDED_EFFECT:contains(a.add_effect_message) and res.buffs[a.add_effect_param] then
                    apply_debuff(t.id, a.add_effect_param, nil)
                end
            end
        end
    end
end

windower.register_event('action', function(act)
    local first = act.targets[1] and act.targets[1].actions[1]
    if not first then return end

    -- Melee, TP moves, spell finish and cast/readying start all name who the monster is after
    if S{1, 4, 7, 8, 11}:contains(act.category) and act.targets[1].id ~= act.actor_id then
        local actor, victim = windower.ffxi.get_mob_by_id(act.actor_id), windower.ffxi.get_mob_by_id(act.targets[1].id)
        if is_enemy(actor) and victim and not is_enemy(victim) then
            aggro[act.actor_id] = victim.id
        end
    end
    -- A monster that attacks, casts or readies a TP move is awake, whatever woke it
    if S{1, 4, 7, 8, 11}:contains(act.category) then wake(act.actor_id) end

    if act.category == 8 then                       -- spell casting start / interrupt
        if act.param == 24931 and res.spells[first.param] then
            local spell = res.spells[first.param]
            casting[act.actor_id] = {name = spell.en, start = os.clock(), duration = spell.cast_time or 0}
        else
            casting[act.actor_id] = nil
        end
    elseif act.category == 7 then                   -- monster ability readying / interrupt
        if act.param == 24931 then
            local ability = res.monster_abilities[first.param] or res.weapon_skills[first.param]
            casting[act.actor_id] = {name = ability and ability.en or 'TP move', start = os.clock(), duration = 0}
        else
            casting[act.actor_id] = nil
        end
    elseif act.category == 4 or act.category == 11 or act.category == 3 then
        casting[act.actor_id] = nil
    end

    -- Finished actions that can land a debuff: weapon skill, spell, JA, TP move, pet ability, dance, rune
    if S{1, 3, 4, 6, 11, 13, 14, 15}:contains(act.category) then
        track_debuffs(act)
        track_removals(act)
    end
end)

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if id == 0x029 then
        local target = data:unpack('I', 0x09)
        local param_1 = data:unpack('I', 0x0D)
        local target_index = data:unpack('H', 0x17)
        local message = data:unpack('H', 0x19) % 32768

        if message >= 170 and message <= 178 then
            levels[target_index] = param_1 > 2147483647 and -1 or param_1
        elseif message == 249 then
            levels[target_index] = -1
        end
        if (message >= 170 and message <= 178 or message == 249) and check_pending[target] then
            check_pending[target] = nil
            return true   -- our own quiet check: keep it out of the chat log
        end

        if S{6, 20, 113, 406, 605, 646}:contains(message) then       -- died
            debuffed[target], buffed[target], casting[target], aggro[target] = nil, nil, nil, nil
        elseif S{64, 204, 206, 350, 531}:contains(message) then       -- wore off
            remove_effect(target, param_1)
        end
    elseif id == 0x0F4 then                          -- widescan entry
        local index, level = data:unpack('H', 0x05), data:byte(0x07)
        if level and level > 0 then levels[index] = level end
    end
end)

-- Drawing
local function layout(x, y, height)
    local w, r = settings.width, CORNER
    set_rect(frame.tl, x, y, r, r)
    set_rect(frame.tr, x + w - r, y, r, r)
    set_rect(frame.bl, x, y + height - r, r, r)
    set_rect(frame.br, x + w - r, y + height - r, r, r)
    set_rect(frame.top, x + r, y, w - 2 * r, r)
    set_rect(frame.bottom, x + r, y + height - r, w - 2 * r, r)
    set_rect(frame.top_line, x + r, y, w - 2 * r, 1)
    set_rect(frame.bottom_line, x + r, y + height - 1, w - 2 * r, 1)
    set_rect(middle, x + 1, y + r, w - 2, height - 2 * r)   -- inside the gold side lines
    set_rect(frame.left_line, x, y + r, 1, height - 2 * r)
    set_rect(frame.right_line, x + w - 1, y + r, 1, height - 2 * r)
    name_text:pos(x + PAD, y + 5)
    hp_frame:set(x + PAD, y + 28, w - 2 * PAD, 11)
    hp_track:set(x + PAD + 1, y + 29, w - 2 * PAD - 2, 9)
end

-- Effects still on a mob, soonest to expire first (untimed last); drops expired ones
local function current_effects(store, id, now)
    local list = {}
    for status, entry in pairs(store[id] or {}) do
        local left = entry.ends and entry.ends - now
        if (left and left > -1) or (not left and now - entry.applied < UNTIMED_LIMIT) then
            list[#list + 1] = {status = status, left = left}
        else
            store[id][status] = nil
        end
    end
    table.sort(list, function(a, b) return (a.left or math.huge) < (b.left or math.huge) end)
    return list
end

-- One row of icons on tinted tiles; returns the next free slot
local function draw_icon_row(list, slot, x, row, tile)
    for i, d in ipairs(list) do
        if i > settings.max_debuffs or slot > SLOTS then break end
        local icon = icon_dir..d.status..'.png'
        local ix = x + PAD + (i - 1) * (ICON + 8)
        if icon_paths[slot] ~= icon then
            icons[slot]:path(icon)
            icon_paths[slot] = icon
        end
        set_rect(tiles[slot], ix - 2, row, ICON + 4, ICON + 3)   -- stops just above the timer text
        tiles[slot]:color(tile[2], tile[3], tile[4])
        tiles[slot]:alpha(tile[1])
        tiles[slot]:show()
        icons[slot]:pos(ix, row + 2)
        icons[slot]:show()
        timers[slot]:text(d.left and format_time(d.left) or '')
        local tw = timers[slot]:extents() or 0
        timers[slot]:pos(ix + math.floor((ICON - tw) / 2), row + ICON + 3)
        timers[slot]:show()
        slot = slot + 1
    end
    return slot
end

local function render()
    local target = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t')
    if not target or user_hidden then
        if visible then hide_hud() end
        return
    end

    -- Follow the frame if it was dragged (the middle piece sits 1 right of and CORNER below the corner)
    local px, py = middle:pos()
    if visible and (px - 1 ~= origin.x or py - CORNER ~= origin.y) then
        settings.pos.x, settings.pos.y = px - 1, py - CORNER
    end
    local x, y = anchor()

    local now = os.clock()
    local cast = casting[target.id]
    if cast and cast.duration > 0 and now - cast.start > cast.duration + 1 then cast = nil; casting[target.id] = nil end
    if cast and cast.duration == 0 and now - cast.start > 6 then cast = nil; casting[target.id] = nil end

    local buffs = current_effects(buffed, target.id, now)
    local debuffs = current_effects(debuffed, target.id, now)

    local tot = enemy_target(target)
    local height = 46 + (tot and 16 or 0) + (cast and 18 or 0) + (#buffs > 0 and ICON_ROW or 0) + (#debuffs > 0 and ICON_ROW or 0)
    layout(x, y, height)
    origin.x, origin.y = x, y

    -- Name, level, HP
    local c = claim_color(target)
    name_text:text(('\\cs(%d,%d,%d)%s\\cr%s'):format(c[1], c[2], c[3], target.name, level_text(target)))
    hpp_text:text(('%d%%'):format(target.hpp))
    local hw = hpp_text:extents()
    hpp_text:pos(x + settings.width - PAD - (hw or 0), y + 5)

    local inner = settings.width - 2 * PAD - 2
    local fill = math.floor(inner * target.hpp / 100)
    local player = windower.ffxi.get_player()
    if fill >= trail_width or not (player and player.in_combat) then
        trail_width = fill
    else
        trail_width = trail_width + math.floor((fill - trail_width) * 0.1)
    end
    local hc = hp_color(target.hpp)
    hp_fill:color(hc[1], hc[2], hc[3])
    hp_trail:set(x + PAD + 1, y + 29, trail_width, 9)
    hp_fill:set(x + PAD + 1, y + 29, fill, 9)
    show_all(primitives, true)

    -- Who the enemy is after: name colored by who it is (red = you), with their HP
    local row = y + 46
    if tot then
        local rc = relation_color(tot)
        local who = tot.id == player_id and 'You' or tot.name
        tot_text:text(('\\cs(%d,%d,%d)Targeting\\cr  \\cs(%d,%d,%d)%s\\cr'):format(MUTED[1], MUTED[2], MUTED[3],
            rc[1], rc[2], rc[3], who))
        tot_text:pos(x + PAD, row - 4)
        local track_w = 120
        local track_x = x + settings.width - PAD - track_w
        tot_track:set(track_x, row + 2, track_w, 5)
        tot_fill:set(track_x, row + 2, math.floor(track_w * tot.hpp / 100), 5)
        show_all(tot_parts, true)
        row = row + 16
    else
        show_all(tot_parts, false)
    end

    -- Cast / readying bar
    if cast then
        cast_text:text(cast.name)
        cast_text:pos(x + PAD, row - 2)
        local track_x, track_w = x + PAD + 150, settings.width - 2 * PAD - 150 - 40
        cast_track:set(track_x, row + 4, track_w, 4)
        if cast.duration > 0 then
            local done = math.min(1, (now - cast.start) / cast.duration)
            cast_fill:set(track_x, row + 4, math.floor(track_w * done), 4)
            cast_time:text(('%.1fs'):format(math.max(0, cast.duration - (now - cast.start))))
        else
            cast_fill:set(track_x, row + 4, track_w, 4)   -- TP move: no known duration
            cast_time:text('')
        end
        cast_time:pos(x + settings.width - PAD - 34, row - 2)
        show_all(cast_parts, true)
        row = row + 18
    else
        show_all(cast_parts, false)
    end

    -- Buffs on their own row (green tiles), then debuffs (red tiles), each icon with its timer
    local slot = 1
    if #buffs > 0 then
        slot = draw_icon_row(buffs, slot, x, row, BUFF_TILE)
        row = row + ICON_ROW
    end
    if #debuffs > 0 then
        slot = draw_icon_row(debuffs, slot, x, row, DEBUFF_TILE)
    end
    hide_debuffs(slot)

    visible = true
    auto_check(target)
end

windower.register_event('prerender', render)

local function save_pos()
    if settings.pos.x ~= saved.x or settings.pos.y ~= saved.y then
        config.save(settings, 'all')
        saved.x, saved.y = settings.pos.x, settings.pos.y
    end
end

windower.register_event('mouse', function(type)
    if type == 2 and visible then   -- left button released: keep a dragged position
        local px, py = middle:pos()
        if px - 1 ~= origin.x or py - CORNER ~= origin.y then
            settings.pos.x, settings.pos.y = px - 1, py - CORNER
        end
        save_pos()
    end
end)

windower.register_event('load', 'login', function()
    local player = windower.ffxi.get_player()
    player_id = player and player.id or 0
end)

windower.register_event('zone change', 'logout', function()
    levels, check_pending, check_tries, casting, debuffed, buffed, aggro = {}, {}, {}, {}, {}, {}, {}
    hide_hud()
end)

windower.register_event('unload', function()
    config.save(settings, 'all')
end)

windower.register_event('addon command', function(cmd)
    cmd = cmd and cmd:lower() or ''
    if cmd == 'check' then
        settings.auto_check = not settings.auto_check
        windower.add_to_chat(207, 'EnemyHUD: auto-check for levels '..(settings.auto_check and 'on' or 'off'))
        config.save(settings, 'all')
    elseif cmd == 'center' then
        settings.pos.x = -1
        config.save(settings, 'all')
    elseif cmd == 'save' then
        config.save(settings, 'all')
    elseif cmd == 'hide' or cmd == 'show' then
        user_hidden = cmd == 'hide'
    else
        windower.add_to_chat(207, 'EnemyHUD: //ehud check | center | save | hide | show   (drag the frame to move it)')
    end
end)
