-- ============================================================================
-- hyprland.lua — Lua migration of the former hyprland.conf
-- ----------------------------------------------------------------------------
-- Requires Hyprland >= 0.55 (hyprlang is deprecated in favour of Lua).
-- When this file exists it is loaded INSTEAD OF hyprland.conf; the two are
-- never mixed. The choice is made once, at Hyprland startup — so edits here
-- take effect on the NEXT Hyprland startup, NOT on `hyprctl reload`.
--
-- Migration notes / deviations from the old .conf:
--   * Cursor env (XCURSOR_*/HYPRCURSOR_*) is intentionally NOT re-emitted here.
--     home.pointerCursor in home/z.nix (Bibata-Modern-Ice, size 24) is now the
--     single source of the cursor theme + size for the whole session.
--   * The monitor output names are declared ONCE as locals (primary/secondary)
--     and reused for the monitor defs AND the workspace pins, so a rename can't
--     drift. This also fixes the old bug where workspaces 1/2/3 (and hyprpaper)
--     pinned to an output that is never defined — they now pin to the
--     real primary via `primary`.
--   * Constructs whose clean hl.* form is not confirmed for 0.55 are emitted
--     via the hyprctl shell-out escape hatch (there is no raw-hyprlang keyword
--     from Lua): the `[workspace special:…] cmd` spawn prefixes and the
--     fullscreen mode dispatchers (0 = true fullscreen, 1 = maximize).
-- ============================================================================


------------------
---- MONITORS ----
------------------

-- Real primary output is DP-1 (the 240Hz panel). Declared once, reused below.
local primary   = "DP-1"      -- 2560x1440@240 main display
local secondary = "HDMI-A-2"  -- Dell P2219H (hypridle disables this overnight)

-- Pin positions so the layout survives hypridle disabling HDMI-A-2 overnight
-- (the Dell hotplug-cycles in DPMS standby; see hypridle.conf).
-- 240Hz needs an HBR3/DP1.4 link; falls back to 144Hz while the link is HBR2.
hl.monitor({ output = primary,   mode = "2560x1440@240", position = "0x0",    scale = 1 })
hl.monitor({ output = secondary, mode = "1920x1080@60",  position = "2560x0", scale = 1 })
-- Disable the phantom Unknown-1 output. `disabled` is a confirmed hl.monitor
-- field in 0.55 (see hl.meta.lua HL.MonitorSpec), so this is declarative — no
-- hyprctl shim needed.
hl.monitor({ output = "Unknown-1", disabled = true })


---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "kitty"
local fileManager = "ranger"                                -- kept for parity (unused directly)
local menu        = "rofi -show drun"                       -- old launcher script wasn't saved; plain rofi
local browser     = "firefox"
local pass        = "1password --ozone-platform-hint=wayland"


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- (Cursor env deliberately omitted — owned by home.pointerCursor in z.nix.)


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 0,

        col = {
            active_border   = "rgba(33ccffee)",
            inactive_border = "rgba(595959aa)",
        },

        resize_on_border = true,
        allow_tearing    = false,

        layout = "dwindle",
    },

    decoration = {
        rounding = 5,

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,   -- rgba(1a1a1aee)
        },

        blur = {
            enabled  = false,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- bezier = myBezier, 0.05, 0.9, 0.1, 1.05
hl.curve("myBezier", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6,  bezier = "default" })

hl.config({
    dwindle = {
        -- pseudotile option removed in this version; the "pseudo" dispatcher still works
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

-- replacement for the removed no_gaps_when_only = 1:
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout = "us",

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll = false,
        },
    },
})

-- (gestures block removed: reworked out of Hyprland in 0.51, no touchpad here)


------------------
---- LAYER RULES ----
------------------

hl.layer_rule({ match = { namespace = "waybar" }, blur         = true })
hl.layer_rule({ match = { namespace = "waybar" }, blur_popups  = true })
hl.layer_rule({ match = { namespace = "waybar" }, ignore_alpha = 0.2 })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({ match = { class = "^(1Password)$" }, float = true })
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Pin the first three workspaces to the primary output (was the never-defined
-- output in the old config — a silent no-op; now correctly the real primary via `primary`).
hl.workspace_rule({ workspace = "1", monitor = primary })
hl.workspace_rule({ workspace = "2", monitor = primary })
hl.workspace_rule({ workspace = "3", monitor = primary })


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + K",      hl.dsp.window.close())
hl.bind(mainMod .. " + END",    hl.dsp.exit())
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
-- fullscreen mode dispatchers via escape hatch (mode 1 = maximize keeps bar/gaps;
-- mode 0 = true fullscreen). The hl.dsp.window.fullscreen `mode` values are not
-- confirmed for 0.55, so shell out to preserve exact behaviour.
hl.bind(mainMod .. " + F",         hl.dsp.exec_cmd("hyprctl dispatch fullscreen 1"))  -- maximize
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("hyprctl dispatch fullscreen 0"))  -- true fullscreen
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + J",     hl.dsp.layout("togglesplit"))  -- dwindle
hl.bind(mainMod .. " + B",     hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + L",     hl.dsp.exec_cmd("hyprlock"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9];
-- move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10  -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through existing workspaces with mainMod + scroll (only mouse_up bound)
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })


-----------------------------
---- SPECIAL WORKSPACES  ----
-----------------------------

-- Homogeneous toggle+spawn scratchpads. Each row generates two binds:
--   SUPER + <key>          -> toggle the special workspace
--   SUPER + SHIFT + <key>  -> spawn <cmd> into that special workspace
-- Rows with prewarm=true are also pre-spawned (silent) at startup.
-- Spawn/prewarm use the hyprctl escape hatch because the `[workspace special:…]`
-- exec prefix has no confirmed clean hl.dsp form.
local scratchpads = {
    { key = "BACKSPACE", name = "terminal",  cmd = terminal,               prewarm = true  },
    { key = "ESCAPE",    name = "btop",      cmd = terminal .. " btop",     prewarm = true  },
    { key = "R",         name = "ranger",    cmd = terminal .. " ranger",   prewarm = true  },
    { key = "A",         name = "audio",     cmd = "pavucontrol",           prewarm = false },
    { key = "P",         name = "1password", cmd = pass,                    prewarm = false },
}

for _, s in ipairs(scratchpads) do
    hl.bind(mainMod .. " + " .. s.key, hl.dsp.workspace.toggle_special(s.name))
    hl.bind(mainMod .. " + SHIFT + " .. s.key,
        hl.dsp.exec_cmd("hyprctl dispatch exec '[workspace special:" .. s.name .. "] " .. s.cmd .. "'"))
end

-- Magic workspace (scratchpad) — odd one out: SHIFT moves the active window in,
-- it does not spawn. Kept explicit.
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Config-editor scratchpads — spawn-only (no toggle, no prewarm). The Hyprland
-- one now opens hyprland.lua (this file), since the .conf is gone.
local configEditors = {
    { key = "H", ws = "hconf", cmd = terminal .. " nvim ~/nixos/home/dotfiles/hypr/hyprland.lua" },
    { key = "N", ws = "nconf", cmd = terminal .. " nvim ~/nixos" },
    { key = "A", ws = "aconf", cmd = terminal .. " nvim ~/nixos/home/dotfiles/fish/aliases.fish" },
}
for _, e in ipairs(configEditors) do
    hl.bind(mainMod .. " + ALT + " .. e.key,
        hl.dsp.exec_cmd("hyprctl dispatch exec '[workspace special:" .. e.ws .. "] " .. e.cmd .. "'"))
end

-- Power off, in a throwaway special workspace
hl.bind(mainMod .. " + CTRL + END",
    hl.dsp.exec_cmd("hyprctl dispatch exec '[workspace special:off] " .. terminal .. " sudo shutdown now'"))

-- Screenshots -> clipboard (region / full screen)
hl.bind("PRINT",         hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd("grim - | wl-copy"))


-- TEMPORARY (wtype snippets)
hl.bind("CTRL + SHIFT + PERIOD",       hl.dsp.exec_cmd('wtype "‣"'))
hl.bind("CTRL + SHIFT + RIGHT",        hl.dsp.exec_cmd('wtype "→"'))
hl.bind("CTRL + SHIFT + bracketleft",  hl.dsp.exec_cmd('wtype "/user/yr"'))
hl.bind("CTRL + SHIFT + bracketright", hl.dsp.exec_cmd('wtype "/user/mo"'))
hl.bind("CTRL + SHIFT + Y",            hl.dsp.exec_cmd('wtype "Yearly → "'))
hl.bind("CTRL + SHIFT + M",            hl.dsp.exec_cmd('wtype "Monthly → "'))
hl.bind("CTRL + SHIFT + 0",            hl.dsp.exec_cmd('wtype ".00"'))
hl.bind("CTRL + SHIFT + MINUS",        hl.dsp.exec_cmd('wtype "───"'))


-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar & swaync & hyprpaper")
    -- 1Password in the tray; must be running for the SSH agent socket to exist
    hl.exec_cmd("1password --silent")

    -- Pre-warm the scratchpads that want it (silent, into their special ws).
    for _, s in ipairs(scratchpads) do
        if s.prewarm then
            hl.exec_cmd("hyprctl dispatch exec '[workspace special:" .. s.name .. " silent] " .. s.cmd .. "'")
        end
    end
end)
