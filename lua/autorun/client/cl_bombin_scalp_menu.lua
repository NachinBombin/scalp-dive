if not CLIENT then return end

local col_bg_panel      = Color(0,   0,   0,   255)
local col_section_title = Color(210, 210, 210, 255)
local col_accent        = Color(80,  160, 220, 255)  -- SCALP blue

local SECTION_COLORS = {
    ["NPC Call Settings"]  = Color(60,  120, 200, 120),
    ["Munition Behaviour"] = Color(80,  180, 120, 120),
    ["Dive Attack"]        = Color(200, 60,  40,  120),
    ["Debug"]              = Color(100, 100, 110, 120),
    ["Manual Spawn"]       = Color(140, 80,  200, 120),
}

local function AddColoredCategory(panel, text)
    local bgColor = SECTION_COLORS[text]
    if not bgColor then panel:Help(text) return end

    local cat = vgui.Create("DPanel", panel)
    cat:SetTall(24)
    cat:Dock(TOP)
    cat:DockMargin(0, 8, 0, 4)
    cat.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, bgColor)
        surface.SetDrawColor(0, 0, 0, 35)
        surface.DrawOutlinedRect(0, 0, w, h)
        local textColor = (bgColor.r + bgColor.g + bgColor.b < 200)
            and Color(255, 255, 255, 255)
            or  Color(0,   0,   0,   255)
        draw.SimpleText(text, "DermaDefaultBold", 8, h / 2, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    panel:AddItem(cat)
end

concommand.Add("bombin_spawnscalp", function()
    if not IsValid(LocalPlayer()) then return end
    net.Start("BombinScalp_ManualSpawn")
    net.SendToServer()
end)

hook.Add("AddToolMenuTabs", "BombinScalp_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "BombinScalp_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "SCALP", "SCALP")
end)

hook.Add("PopulateToolMenu", "BombinScalp_ToolMenu", function()
    spawnmenu.AddToolMenuOption(
        "Bombin Support",
        "SCALP",
        "bombin_scalp_settings",
        "SCALP Settings",
        "", "",
        function(panel)
            panel:ClearControls()

            local header = vgui.Create("DPanel", panel)
            header:SetTall(32)
            header:Dock(TOP)
            header:DockMargin(0, 0, 0, 8)
            header.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, col_bg_panel)
                surface.SetDrawColor(col_accent)
                surface.DrawRect(0, h - 2, w, 2)
                draw.SimpleText(
                    "SCALP/Storm Shadow Loitering-Mode Missile Controller",
                    "DermaLarge", 8, h / 2,
                    col_section_title,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
                )
            end
            panel:AddItem(header)

            AddColoredCategory(panel, "NPC Call Settings")
            panel:CheckBox("Enable NPC calls",           "npc_bombinscalp_enabled")
            panel:NumSlider("Call chance (per check)",   "npc_bombinscalp_chance",   0,   1,    2)
            panel:NumSlider("Check interval (seconds)",  "npc_bombinscalp_interval", 1,   60,   0)
            panel:NumSlider("NPC cooldown (seconds)",    "npc_bombinscalp_cooldown", 10,  300,  0)
            panel:NumSlider("Min call distance (HU)",    "npc_bombinscalp_min_dist", 100, 1000, 0)
            panel:NumSlider("Max call distance (HU)",    "npc_bombinscalp_max_dist", 500, 8000, 0)
            panel:NumSlider("Flare → arrival delay (s)", "npc_bombinscalp_delay",    1,   30,   0)

            AddColoredCategory(panel, "Munition Behaviour")
            panel:NumSlider("Lifetime (seconds)",         "npc_bombinscalp_lifetime", 10,  120,  0)
            panel:NumSlider("Orbit speed (HU/s)",         "npc_bombinscalp_speed",    50,  800,  0)
            panel:NumSlider("Orbit radius (HU)",          "npc_bombinscalp_radius",   500, 6000, 0)
            panel:NumSlider("Altitude above ground (HU)", "npc_bombinscalp_height",   500, 8000, 0)

            AddColoredCategory(panel, "Dive Attack")
            panel:NumSlider("Explosion damage",      "npc_bombinscalp_dive_damage", 10,  3000, 0)
            panel:NumSlider("Explosion radius (HU)", "npc_bombinscalp_dive_radius", 50,  3000, 0)

            AddColoredCategory(panel, "Debug")
            panel:CheckBox("Enable debug prints", "npc_bombinscalp_announce")

            AddColoredCategory(panel, "Manual Spawn")
            panel:Button("Spawn SCALP now", "bombin_spawnscalp")
        end
    )
end)
