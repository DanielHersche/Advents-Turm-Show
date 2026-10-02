-- Turm-Show Adventskerzen
-- Ablauf pro Zeitfenster: Intro (einmal) -> Loop (nahtlos, bis Fensterende) -> Outro (einmal) -> schwarz.
-- Welcher Kerzen-Satz (K1..K4) laeuft und wann, entscheidet der Dienst "service".
-- Er meldet dem Node nur eine Zahl: 0 = keine Show, 1..4 = Show mit Satz K1..K4.
-- Optional: Vier-Ecken-Korrektur (Corner Pin) fuer die schraege Projektion auf den Turm.

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

----------------------------------------------------------------------------
-- Vier-Ecken-Korrektur (aus dem Paket "Eckenkorrektur" uebernommen)
----------------------------------------------------------------------------
local shader = resource.create_shader[[
    #ifdef GL_ES
    precision highp float;
    #endif
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 Color;
    uniform vec3 r0;
    uniform vec3 r1;
    uniform vec3 r2;
    uniform float soft;
    uniform float gain;
    void main() {
        // TexCoord hat den Ursprung unten links (y nach oben).
        // Die Eckwerte sind wie im Messraster gemeint: Ursprung oben links, y nach unten.
        vec3 p = vec3(TexCoord.x, 1.0 - TexCoord.y, 1.0);
        float w = dot(r2, p);
        vec2 s = vec2(dot(r0, p), dot(r1, p)) / w;
        float m = smoothstep(0.0, soft, s.x) * smoothstep(0.0, soft, s.y)
                * smoothstep(0.0, soft, 1.0 - s.x) * smoothstep(0.0, soft, 1.0 - s.y);
        if (w <= 0.0) m = 0.0;
        vec4 c = texture2D(Texture, clamp(vec2(s.x, 1.0 - s.y), 0.0, 1.0));
        gl_FragColor = vec4(c.rgb * gain * m, 1.0) * Color;
    }
]]

local function homography(q)
    local x0, y0, x1, y1, x2, y2, x3, y3 = unpack(q)
    local sx, sy = x0 - x1 + x2 - x3, y0 - y1 + y2 - y3
    local dx1, dx2, dy1, dy2 = x1 - x2, x3 - x2, y1 - y2, y3 - y2
    local den = dx1 * dy2 - dx2 * dy1
    if math.abs(den) < 1e-9 then return nil end
    local g = (sx * dy2 - dx2 * sy) / den
    local h = (dx1 * sy - sx * dy1) / den
    local a, b, c = x1 - x0 + g * x1, x3 - x0 + h * x3, x0
    local d, e, f = y1 - y0 + g * y1, y3 - y0 + h * y3, y0
    local m = {
        e - f * h, c * h - b, b * f - c * e,
        f * g - d, a - c * g, c * d - a * f,
        d * h - e * g, b * g - a * h, a * e - b * d,
    }
    local cx, cy = (x0 + x1 + x2 + x3) / 4, (y0 + y1 + y2 + y3) / 4
    if m[7] * cx + m[8] * cy + m[9] < 0 then
        for i = 1, 9 do m[i] = -m[i] end
    end
    return m
end

local IDENT = {1,0,0, 0,1,0, 0,0,1}
local H = IDENT
local soft, gain = 0.002, 1.0

local function warped(draw_fn)
    shader:use{
        r0 = {H[1], H[2], H[3]},
        r1 = {H[4], H[5], H[6]},
        r2 = {H[7], H[8], H[9]},
        soft = soft,
        gain = gain,
    }
    draw_fn()
    shader:deactivate()
end

local messraster = resource.load_image("messraster.png")
local pruefraster = resource.load_image("pruefraster.png")

----------------------------------------------------------------------------
-- Einstellungen
----------------------------------------------------------------------------
local fade = 1.0          -- Ueberblendung in Sekunden
local loop_len = 0        -- Laenge des Loop-Films in Sekunden (0 = Outro sofort, mit Ueberblendung)
local rotation = 0
local corner = false
local use_snapshot = false
local anzeige = "play"    -- play | measure | check | both
local sets = {}           -- sets[n] = {intro = file|nil, loop = file|nil, outro = file|nil}
local sets_sig = nil

local want = 0            -- vom Dienst: 0 = keine Show, 1..4 = Satz

----------------------------------------------------------------------------
-- Wiedergabe-Zustand
----------------------------------------------------------------------------
-- idle -> intro -> loop -> ending -> outro -> idle
-- (ohne Intro direkt idle -> loop, ohne Outro loop -> fadeout -> idle)
local state = "idle"
local set_idx = 0
local cur, nxt, prev = nil, nil, nil
local fade_start, fade_len = 0, 0
local loop_t0 = 0
local switch_at = 0

local function dispose(obj)
    if obj then obj:dispose() end
end

local function reset()
    dispose(cur); dispose(nxt); dispose(prev)
    cur, nxt, prev = nil, nil, nil
    state, set_idx = "idle", 0
end

local function load(file, looped, paused)
    return resource.load_video{
        file = file:copy(),
        looped = looped,
        paused = paused,
        audio = false,
    }
end

local function vstate(obj)
    local ok, st = pcall(obj.state, obj)
    if not ok then return "error" end
    return st
end

local function ready(obj)
    return obj and vstate(obj) ~= "loading"
end

local function done(obj)
    local st = vstate(obj)
    return st == "finished" or st == "error"
end

local function start(obj)
    if obj.start then pcall(obj.start, obj) end
end

-- neuen Film nach vorne holen, alten waehrend der Ueberblendung darunter behalten
local function bring_front(obj, len, now)
    dispose(prev)
    prev = cur
    cur = obj
    fade_start, fade_len = now, len
end

util.data_mapper{
    prog = function(value)
        want = tonumber(value) or 0
    end,
}

util.json_watch("config.json", function(c)
    fade = math.max(0, tonumber(c.fade) or 1.0)
    loop_len = math.max(0, tonumber(c.loop_length) or 0)
    rotation = tonumber(c.rotation) or 0
    corner = c.corner and true or false
    use_snapshot = c.snapshot and true or false
    anzeige = c.anzeige or "play"
    soft = math.max(tonumber(c.soft) or 0.002, 0.00001)
    gain = tonumber(c.gain) or 1.0
    H = homography{
        c.ol_x or 0, c.ol_y or 0, c.or_x or 1, c.or_y or 0,
        c.ur_x or 1, c.ur_y or 1, c.ul_x or 0, c.ul_y or 1,
    } or IDENT

    local new, sig = {}, {}
    for n = 1, 4 do
        local s = {}
        for _, part in ipairs{"intro", "loop", "outro"} do
            local r = c["k" .. n .. "_" .. part]
            -- nur Videos zaehlen; das Platzhalterbild empty.png heisst "nicht gesetzt"
            if type(r) == "table" and r.type == "video" and r.asset_name then
                s[part] = resource.open_file(r.asset_name)
                sig[#sig + 1] = r.asset_name
            else
                sig[#sig + 1] = "-"
            end
        end
        new[n] = s
    end
    sig = table.concat(sig, "|")
    -- Nur bei geaenderten Filmen neu starten, nicht beim Nachstellen der Ecken
    if sig ~= sets_sig then
        reset()
        sets_sig = sig
    end
    sets = new
end)

----------------------------------------------------------------------------
-- Ablaufsteuerung
----------------------------------------------------------------------------
local function begin_show(n, now)
    local s = sets[n]
    set_idx = n
    if s.intro then
        cur = load(s.intro, false, false)
        nxt = load(s.loop, true, true)     -- Loop pausiert vorladen, startet nahtlos nach dem Intro
        fade_start, fade_len = now, 0
        state = "intro"
    else
        cur = load(s.loop, true, false)
        fade_start, fade_len = now, fade   -- ohne Intro sanft einblenden
        loop_t0 = now
        state = "loop"
    end
end

local function begin_end(now)
    local s = sets[set_idx]
    if s and s.outro then
        nxt = load(s.outro, false, true)
        if loop_len > 0 then
            -- bis zum naechsten Loop-Ende weiterlaufen, dann hart schneiden
            local n = math.max(1, math.ceil((now - loop_t0) / loop_len))
            switch_at = loop_t0 + n * loop_len
            if switch_at - now < 1.0 then switch_at = switch_at + loop_len end
        else
            switch_at = now
        end
        state = "ending"
    else
        bring_front(nil, fade, now)          -- ohne Outro ausblenden
        state = "fadeout"
    end
end

local function tick(now)
    if prev and now - fade_start >= fade_len then
        dispose(prev)
        prev = nil
    end

    if state == "idle" then
        if want > 0 and sets[want] and sets[want].loop then
            begin_show(want, now)
        end

    elseif state == "intro" then
        if done(cur) and ready(nxt) then
            start(nxt)
            dispose(cur)
            cur, nxt = nxt, nil
            fade_start, fade_len = now, 0
            loop_t0 = now
            state = "loop"
        end

    elseif state == "loop" then
        if want ~= set_idx then
            begin_end(now)
        end

    elseif state == "ending" then
        if now >= switch_at and ready(nxt) then
            start(nxt)
            bring_front(nxt, loop_len > 0 and 0 or fade, now)
            nxt = nil
            state = "outro"
        end

    elseif state == "outro" then
        if done(cur) then
            dispose(cur); dispose(prev)
            cur, prev = nil, nil
            state, set_idx = "idle", 0
        end

    elseif state == "fadeout" then
        if not prev then
            state, set_idx = "idle", 0
        end
    end
end

----------------------------------------------------------------------------
-- Zeichnen
----------------------------------------------------------------------------
local function layers(now)
    local t = 1
    if fade_len > 0 then
        t = math.min(1, math.max(0, (now - fade_start) / fade_len))
    end
    local list = {}
    if prev then
        list[#list + 1] = {prev, cur and 1 or (1 - t)}
    end
    if cur and ready(cur) then
        list[#list + 1] = {cur, t}
    end
    return list
end

local function apply_rotation()
    local w, h = WIDTH, HEIGHT
    if rotation == 90 then
        gl.translate(WIDTH, 0)
        gl.rotate(90, 0, 0, 1)
        w, h = HEIGHT, WIDTH
    elseif rotation == 180 then
        gl.translate(WIDTH, HEIGHT)
        gl.rotate(180, 0, 0, 1)
    elseif rotation == 270 then
        gl.translate(0, HEIGHT)
        gl.rotate(270, 0, 0, 1)
        w, h = HEIGHT, WIDTH
    end
    return w, h
end

function node.render()
    gl.clear(0, 0, 0, 1)
    local now = sys.now()
    tick(now)

    if anzeige == "measure" then
        messraster:draw(0, 0, WIDTH, HEIGHT)
        return
    end

    local list = layers(now)

    if corner then
        local function content()
            if anzeige ~= "check" then
                for _, l in ipairs(list) do
                    l[1]:draw(0, 0, WIDTH, HEIGHT, l[2])
                end
            end
            if anzeige == "check" then
                pruefraster:draw(0, 0, WIDTH, HEIGHT)
            elseif anzeige == "both" then
                pruefraster:draw(0, 0, WIDTH, HEIGHT, 0.5)
            end
        end
        if use_snapshot then
            -- Ausweichweg: erst normal zeichnen, dann das Gesamtbild verzerren
            content()
            local snap = resource.create_snapshot()
            gl.clear(0, 0, 0, 1)
            warped(function() snap:draw(0, 0, WIDTH, HEIGHT) end)
            snap:dispose()
        else
            warped(content)
        end
    else
        gl.pushMatrix()
        local w, h = apply_rotation()
        if anzeige ~= "check" then
            for _, l in ipairs(list) do
                util.draw_correct(l[1], 0, 0, w, h, l[2])
            end
        end
        if anzeige == "check" then
            util.draw_correct(pruefraster, 0, 0, w, h)
        elseif anzeige == "both" then
            util.draw_correct(pruefraster, 0, 0, w, h, 0.5)
        end
        gl.popMatrix()
    end
end
