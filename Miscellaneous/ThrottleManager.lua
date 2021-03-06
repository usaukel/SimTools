-- Throttle Manager 1.2.0
-- E-mail: pilotjohn at gearsdown.com
-- Sounds: http://www.freesound.org/people/milton./packs/5284/
--
-- Manage throttles to provide both forward and reverse thrust
-- on single axes by allowing functionality toggle through dedicated
-- joystick buttons (such as those below the detent on Saitek quadrants).
-- Can be configured to auto-toggle to forward thrust, and in many other ways. 
-- Setup (do steps 2-5 for each throttle to manage):
--
-- 1. Edit "FSUIPC.ini" and add (substitute X for 1 or next # if exists):
--     [Auto]
--     X=Lua ThrottleManager
--
-- 2. In FSX "Settings" "Controls",
--      delete joystick assignment for throttle N
--
-- 3. In FSUIPC "Axis Assignment",
--      "MOVE" "LEVER",
--      select "Send direct to FSUIPC Calibration" 
--      and check "Throttle N"
--
-- 4. In FSUIPC "Joystick Calbiration",
--      on "3 of 11: Separate throttles per engine",
--      check "No reverse Zone",
--      and "Set" "Min" and "Max" for "Throttle N"
--
-- 5. In FSUIPC "Buttons + Switches",
--		"PRESS" "BUTTON",
--		check "Select for FS control",
--		choose "LuaToggle ThrottleManager",
--		and enter "N" for "Paramater"
--
-- 6. If using the delayed toggle mechanism,
--		also configure as above for "Control sent when button released"
--
-- 7. Configure below as desired.

ipc.log("Starting...")

--------------------------------------------------------------------------------
-- Configuration

-- Display start-up banner for a duration, uncomment to enable
-- ipc.display("Throttle Manager for FSUIPC", 3)

throttles = {
  {
    0x310A,                             -- Throttle disconnect offset
    0x40,                               -- Throttle disconnect mask
    0x3330,                             -- Throttle axis offset
    0x333A,                             -- Throttle limit offset
    -16384,                             -- Throttle limit override (J41 reads -4096, but it's really -16384), 0 to disable
    65820, -- 0x088C                    -- Throttle set offset or control (J41 needs control)
    1,                                  -- Throttle toggle flag
    1,                                  -- Throttle forward ratio
    1,                                  -- Throttle reverse ratio
    -256,                               -- Throttle toggle to forward on reverse greater than, 0 to disable
    0,                                  -- Duration of display when throttle toggled, 0 to disable
    "#1 Forward Thrust",                -- Text to display when forward selected, "" to disable
    "#1 Reverse Thrust",                -- Text to display when reverse selected
    "#1 No Reverse Thrust",             -- Text to display when no reverse on aircraft
    0,                                  -- Duration of display when throttle updated
    "#1 Forward Thrust: ",              -- Text to display when reverse set
    "#1 Reverse Thrust: ",              -- Text to display when forward set
    25,                                 -- Volume of sounds when throttle toggled
    315,                                -- Position of sounds when throttle toggled
    "ThrottleManagerF",                 -- Sound to play when forward selected
    "ThrottleManagerR",                 -- Sound to play when reverse selected
    "",                                 -- Sound to play when no reverse on aircraft or failed
	0x32F8,                             -- Reverser failed offset
	16,                                 -- Reverser failed mask
	false,                              -- Starting state (true = reverse)
	nil,								-- Internal, previous value (noise)
	1,									-- Delay in seconds before toggling via button press, see #6 in configuration
	-1,									-- Internal, time when throttle should be toggled
  },
  {
    0x310A,                             -- Throttle disconnect offset
    0x80,                               -- Throttle disconnect mask
    0x3332,                             -- Throttle axis offset
    0x333A,                             -- Throttle limit offset
    -16384,                             -- Throttle limit override (J41 reads -4096, but it's really -16384), 0 to disable
    65821, -- 0x0924,                   -- Throttle set offset or control (J41 needs control)
    2,                                  -- Throttle toggle flag
    1,                                  -- Throttle forward ratio
    1,                                  -- Throttle reverse ratio
    -256,                               -- Throttle toggle to forward on reverse greater than, 0 to disable
    0,                                  -- Duration of display when throttle toggled, 0 to disable
    "#2 Forward Thrust",                -- Text to display when forward selected, "" to disable
    "#2 Reverse Thrust",                -- Text to display when reverse selected
    "#2 No Reverse Thrust",             -- Text to display when no reverse on aircraft
    0,                                  -- Duration of display when throttle updated
    "#2 Forward Thrust: ",              -- Text to display when reverse set
    "#2 Reverse Thrust: ",              -- Text to display when forward set
    25,                                 -- Volume of sounds when throttle toggled
    45,                                 -- Position of sounds when throttle toggled
    "ThrottleManagerF",                 -- Sound to play when forward selected
    "ThrottleManagerR",                 -- Sound to play when reverse selected
    "",                                 -- Sound to play when no reverse on aircraft or failed
	0x32F8,                             -- Reverser failed offset
	32,                                 -- Reverser failed mask
	false,                              -- Starting state (true = reverse)
	nil,								-- Internal, previous value (noise)
	1,									-- Delay in seconds before toggling via button press, see #6 in configuration
	-1,									-- Internal, time when throttle should be toggled
  }
}

throttles_aofs = {}
throttles_flag = {}

--------------------------------------------------------------------------------
-- Callbacks

local last_disconnect = 0;

function throttle_timer(t)
	local now = socket.gettime();
	if (now - last_disconnect > 3) then
		last_disconnect = now
		throttle_disconnect()
	end
	
	local n = table.getn(throttles)
	for i=1,n do
		if (throttles[i][28] > 0 and now - throttles[i][28] > 0) then
			throttles[i][28] = 0; -- signal that throttle was toggled by timer, will be reset by button up
			throttle_toggle(i)
		end
	end
end

function throttle_disconnect()
    for i=1,table.getn(throttles) do
        local dofs = throttles[i][1]
        local mask = throttles[i][2]

        ipc.setbitsUB(dofs, mask)
    end
end

function throttle_toggle_start(flag)
    local i = throttles_flag[flag]
	if (throttles[i][27] > 0) then
		if (throttles[i][28] < 0) then
			throttles[i][28] = socket.gettime() + throttles[i][27]
		else
			throttles[i][28] = -1
		end
	else
		throttle_toggle(i)
	end
	
end

function throttle_toggle(flag)
    local i = throttles_flag[flag]
    local state = throttles[i][25]
    local limit = throttles[i][5]
    local msg = ""
    local snd = ""

    if (limit < 0) then
        if (state == true) then
            msg = throttles[i][12]
            snd = throttles[i][20]
			state = false
        else
            msg = throttles[i][13]
            snd = throttles[i][21]
			state = true
        end
    else
		msg = throttles[i][14]
		snd = throttles[i][22]
		state = false
    end
	
    if (throttles[i][11] > 0 and msg ~= "") then
        ipc.lineDisplay(msg, i)
    end
    if (throttles[i][18] > 0 and snd ~= "") then
        sound.play(snd, 0, throttles[i][18], throttles[i][19])
    end
	
	if (msg ~= "") then
		ipc.log(msg)
	end

	throttles[i][25] = state
end

function throttle_update(aofs, aval)
    local i = throttles_aofs[aofs]
    local limit = throttles[i][5]
    local sofs = throttles[i][6]
    local flag = throttles[i][7]
	local fofs = throttles[i][23]
	local fmsk = throttles[i][24]
    local state = throttles[i][25]
    local pval = throttles[i][26]
    local val = 0
    local msg = ""
    local pct = 0

	throttles[i][28] = -1 -- didn't wait for throttle toggle timer, so reset it
	
    if (pval ~= nil) then
        -- sometimes the second "phantom" event is off by 1
        if ((aval >= pval - 1) and (aval <= pval + 1)) then
            return
        end
    end
    
    if (state == false) then
        val = math.floor(aval * throttles[i][8])
        pct = math.ceil(val * 100 / 16384)
        msg = throttles[i][16]
    else
        val = math.ceil(aval * limit / 16384 * throttles[i][9])
        if (val < limit) then
            val = limit
        end
        if (val > throttles[i][10] and (pval == nil or val > pval)) then
			throttle_toggle(flag)
        end
        pct = math.floor(val * 100 / limit)
        msg = throttles[i][17]
    end

    throttles[i][26] = val

	if (val >= 0 or logic.And(ipc.readUB(fofs), fmsk) == 0) then
		if (sofs <= 65535) then
			ipc.writeSW(sofs, val)
		else
			ipc.control(sofs, val)
		end
	end
	
    if (throttles[i][15] > 0 and msg ~= "") then
        ipc.lineDisplay(msg..pct.."% ", i)
    end    
end

--------------------------------------------------------------------------------
-- Main

require("socket")
sound.path("..\\Modules\\")
event.timer(100, "throttle_timer")

local cn = table.getn(throttles)
local en = ipc.readSW(0xAEC) -- number of engines
if (cn > en) then
    cn = en
end
for i=1,cn do
    local aofs = throttles[i][3]
    local lofs = throttles[i][4]
    local limit = throttles[i][5]
    local flag = throttles[i][7]

    throttles[i][5] = ipc.readSW(lofs)
    if (limit < 0 and throttles[i][5] < 0) then
        throttles[i][5] = limit
    end
    
    throttles_aofs[aofs] = i
    throttles_flag[flag] = i

    event.offset(aofs, "SW", "throttle_update")
    event.flag(flag, "throttle_toggle_start")
end

ipc.log("Done.")
