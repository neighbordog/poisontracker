-- Init Addon
PoisonTracker = LibStub("AceAddon-3.0"):NewAddon("PoisonTracker", "AceBucket-3.0")

--
-- # Constants
--

local VERSION = "0.1.4"

-- Trackable poisons and their meta data
local ICONT = {
    ["Deadly Poison"] = {
        image = "132290",
        shortname = "dp"
    },
    ["Crippling Poison"] = {
        image = "132274",
        shortname = "cp"
    },
    ["Wound Poison"] = {
        image = "134197",
        shortname = "wp"
    },
    ["Leeching Poison"] = {
        image = "538440",
        shortname = "lp"
    }
}

--
-- # Helpers
--

-- https://stackoverflow.com/questions/2705793/how-to-get-number-of-entries-in-a-lua-table
local function TableLength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

local function TimeToSeconds(T)
    return math.floor(T - GetTime())
end

--
-- # Addon
--

PoisonTracker.frame = CreateFrame("Frame")

--
-- ## When addon first loads
--
function PoisonTracker:OnInitialize()
    self:InitDB()

    local options = {
      name = "PoisonTracker",
      type = 'group',
      args = {
          poisons = {
              name = "Poisons",
              desc = "Enable/disable tracking for single poisons",
              type= "group",
              args = {
                  deadly_poison = {
                    name = "Track Deadly Poison",
                    desc = "Enables / disables tracking for Deadly Poison",
                    type = "toggle",
                    set = function(info,val) self.db.profile.dp = val end,
                    get = function(info) return self.db.profile.dp  end
                  },
                  crippling_poison = {
                    name = "Track Crippling Poison",
                    desc = "Enables / disables tracking for Crippling Poison",
                    type = "toggle",
                    set = function(info,val) self.db.profile.cp = val end,
                    get = function(info) return self.db.profile.cp  end
                  },
                  leeching_poison = {
                    name = "Track Leeching Poison",
                    desc = "Enables / disables tracking for Leeching Poison",
                    type = "toggle",
                    set = function(info,val) self.db.profile.lp = val end,
                    get = function(info) return self.db.profile.lp  end
                  },
                  wound_poison = {
                    name = "Track Wound Poison",
                    desc = "Enables / disables tracking for Wound Poison",
                    type = "toggle",
                    set = function(info,val) self.db.profile.wp = val end,
                    get = function(info) return self.db.profile.wp  end
                  },
              }
          },
          config = {
            name = "Configuration",
            desc = "Global configuration",
            type = "group",
            args = {
                threshold = {
                    name = "Notification Treshold",
                    desc = "Sets the threshold when the notification will be displayed",
                    type = "input",
                    set = function(info,val) self.db.profile.threshold = val end,
                    get = function(info) return self.db.profile.threshold  end
                },
                icon_size = {
                    name = "Icon Size",
                    desc = "The size of the displayed ability icons (integer)",
                    type = "input",
                    set = function(info,val)
                        self.db.profile.icon_size = val
                        self:Reset()
                    end,
                    get = function(info) return self.db.profile.icon_size  end
                },
                lock = {
                    name = "Lock Position",
                    desc = "Locks and unlocks the position of the GUI",
                    type = "toggle",
                    set = function(info,val)
                        if val then
                            lock_val = false
                        else
                            lock_val = true
                        end

                        self.db.profile.lock = lock_val
                        self:ToggleMovable(lock_val)
                    end,
                    get = function(info)
                        if self.db.profile.lock then
                            return false
                        else
                            return true
                        end
                    end
                },
                reset = {
                    name = "Reset Position",
                    desc = "Resets position of the GUI",
                    type = "execute",
                    func = function()
                        self.db.profile.pos_x = nil
                        self.db.profile.pos_y = nil

                        self:RestorePosition()
                        self:SavePosition()
                    end
                }
            }
          },
      },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("PoisonTracker", options, {"PoisonTracker", "pt"})
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("PoisonTracker", "PoisonTracker")
end

--
-- ## Initializes DB
--
function PoisonTracker:InitDB()
    local defaults = {
        profile = {
            dp = true,
            cp = true,
            wp = false,
            lp = false,
            threshold = "10",
            icon_size = "60",
        }
    }

    self.db = LibStub("AceDB-3.0"):New("PoisonTracker", defaults, true)
end

--
-- ## When Addon enables or player starts/reloads game
--
function PoisonTracker:OnEnable()
    self.icons = {}

    -- Ver. 0.1.2 - Added new option for icon size, set default for legacy users
    if(self.db.profile.icon_size == nil) then
        self.db.profile.icon_size = "60"
    end

    -- Ver. 0.1.3 - Added new option for icon size, set default for legacy users
    if(self.db.profile.lock == nil) then
        self.db.profile.lock = true
    end

    -- Initialize main container frame
    self.base = CreateFrame("Frame", nil, UIParent)

    self.base:SetHeight(tonumber(self.db.profile.icon_size))
    self.base:SetWidth(tonumber(self.db.profile.icon_size))

    self:RestorePosition()

    self.base:SetFrameStrata("HIGH")

    self:ToggleMovable(self.db.profile.lock)
    self.base:RegisterForDrag("LeftButton")
    self.base:SetScript("OnDragStart", self.base.StartMoving)
    self.base:SetScript("OnDragStop", function(this)
        self:SavePosition()
        this:StopMovingOrSizing()
	end)

    -- Get current class
    class, classFileName, classIndex = UnitClass("player")

    -- Stop execution if player is not rogue
    if classIndex ~= 4 then
        return false
    end

    -- Get current spec
    self.spec = GetSpecialization()

    -- Update spec when user changes talent
    self:RegisterBucketEvent("PLAYER_SPECIALIZATION_CHANGED", 1, function()
        self.spec = GetSpecialization()
    end)

    -- Fire tick when buffs on player change
    self:RegisterBucketEvent("UNIT_AURA", 1, "Tick")

    -- Fire tick every frame update
    self.frame:SetScript("OnUpdate", function() self:Tick() end)
end

--
-- ## Checks if player is in right settings and fires tracker function for every poison
--
function PoisonTracker:Tick()
    local inCity = IsResting()

    -- Hide UI and cancel execution if user is in a city or in the right spec
    if (inCity == true) or self.spec ~= 1 then
        for k,v in pairs(self.icons) do
            v.frame:Hide()
        end
        return false
    end

    -- track deadly poision
    if self.db.profile.dp then
        self:Track("Deadly Poison")
    elseif self.icons["Deadly Poison"] then
        self:Reset()
    end

    -- track crippling poision
    if self.db.profile.cp then
        self:Track("Crippling Poison")
    elseif self.icons["Crippling Poison"] then
        self:Reset()
    end

    -- track leeching poision
    if self.db.profile.lp then
        self:Track("Leeching Poison")
    elseif self.icons["Leeching Poison"] then
        self:Reset()
    end

    -- track wound poision
    if self.db.profile.wp then
        self:Track("Wound Poison")
    elseif self.icons["Wound Poison"] then
        self:Reset()
    end
end

--
-- ## Tracks a poison
--
function PoisonTracker:Track(name)
    local aura = {UnitAura("player", name)};

    if aura[1] then
        local time_remaining = TimeToSeconds(aura[7])

        if time_remaining < tonumber(self.db.profile.threshold) then
            self:DrawIcon(name, math.floor(time_remaining) .. " sec", .5)
        elseif self.icons[name] ~= nil and self.icons[name].frame:GetAlpha() > 0 then
            self.icons[name].frame:SetAlpha(0)
        end
    else
        self:DrawIcon(name, nil, 1)
    end
end

--
-- ## Draws or updates an icon into the main container
--
function PoisonTracker:DrawIcon(name, label, opacity)
    if self.icons[name] == nil then
        local frame = CreateFrame("Frame", nil, self.base)
        frame:SetWidth(tonumber(self.db.profile.icon_size))
        frame:SetHeight(tonumber(self.db.profile.icon_size))

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    	label:SetPoint("BOTTOMLEFT")
    	label:SetPoint("BOTTOMRIGHT")
    	label:SetJustifyH("CENTER")
    	label:SetJustifyV("CENTER")
    	label:SetHeight(tonumber(self.db.profile.icon_size))

        local image = frame:CreateTexture("BACKGROUND")
        image:SetWidth(tonumber(self.db.profile.icon_size))
        image:SetHeight(tonumber(self.db.profile.icon_size))
        image:SetTexture(ICONT[name]["image"])
        image:SetPoint("TOP", 0, 0)

        frame:SetPoint("CENTER")

        icon = {
    		label = label,
    		image = image,
    		frame = frame
    	}

        self.icons[name] = icon
        self:ResizeBase()
    else
        icon = self.icons[name]
    end

    if icon.frame:IsVisible() == false then
        icon.frame:Show()
    end

    icon.frame:SetAlpha(opacity)
    icon.label:SetText(label)

    self.icons[name] = icon

    return icon
end

--
-- ## Reset UI
--
function PoisonTracker:Reset()
    for k,v in pairs(self.icons) do
        v.image:Hide()
        v.label:Hide()
        v.frame:Hide()
    end

    self.icons = {}
end

--
-- ## Returns the icon size with the gutter margin
--
function PoisonTracker:IconSize()
    return tonumber(self.db.profile.icon_size) + 5
end

--
-- ## Save position of GUI
--
function PoisonTracker:SavePosition()
    local x, y = self.base:GetCenter() -- Elsia: This is clean code straight from ckknight's pitbull

    self.db.profile.pos_x = x - GetScreenWidth() / 2
    self.db.profile.pos_y = y - GetScreenHeight() / 2
end

--
-- ## Restore position of GUI
--
function PoisonTracker:RestorePosition()
    if self.db.profile.pos_x ~= nil and self.db.profile.pos_y ~= nil then
        self.base:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.pos_x, self.db.profile.pos_y )
    else
        self.base:SetPoint("CENTER", UIParent, 0,0)
    end
end

--
-- ## Resize size of main container
--
function PoisonTracker:ResizeBase()
    local c = TableLength(self.icons)
    self.base:SetWidth((c * self:IconSize()) - 5)
    self.base:SetHeight(tonumber(self.db.profile.icon_size))

    local i = 0

    for k,v in pairs(self.icons) do
        local size = self:IconSize() * i
        v.frame:SetPoint("TOPLEFT", size, 0)
        i = i+1
    end
end

--
-- ## Lock and unlock the GUI
--
function PoisonTracker:ToggleMovable(val)
    self.base:SetMovable(val)
    self.base:EnableMouse(val)
end
