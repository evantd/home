local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Track which panes have had bells ring
local bell_panes = {}

-- Track Amp waiting status per pane: { last_status = string, acknowledged = bool }
-- "acknowledged" is set true when the user focuses the tab while it's in the
-- current ampStatus state. It resets to false whenever ampStatus transitions
-- (e.g. when the plugin writes 'working' on agent.start and then 'waiting' on
-- agent.end). This means each new "waiting" event surfaces ⏳ exactly once,
-- and focusing the tab clears it until the next agent.end.
local amp_panes = {}

wezterm.on('bell', function(window, pane)
  bell_panes[pane:pane_id()] = true
end)

wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
  local title = tab.active_pane.title
  local pane_id = tab.active_pane.pane_id

  -- Track Amp status transitions on every render.
  local user_vars = tab.active_pane.user_vars
  local current_amp = user_vars and user_vars.ampStatus or nil
  local state = amp_panes[pane_id]
  if not state then
    state = { last_status = current_amp, acknowledged = false }
    amp_panes[pane_id] = state
  elseif state.last_status ~= current_amp then
    state.last_status = current_amp
    state.acknowledged = false
  end
  if tab.is_active then
    state.acknowledged = true
  end

  -- Clear bell state when tab is focused
  if tab.is_active then
    bell_panes[pane_id] = nil
    return title
  end

  -- Bell takes priority (means "needs input")
  if bell_panes[pane_id] then
    return {
      { Foreground = { Color = "#ff6600" }},
      { Text = "🔔 " .. title },
    }
  end

  -- Amp plugin signals "waiting for user" via OSC 1337 SetUserVar=ampStatus=waiting.
  -- Show ⏳ only for unacknowledged waiting transitions, so focusing the tab
  -- clears the indicator until the next agent.end fires.
  if current_amp == 'waiting' and not state.acknowledged then
    return {
      { Foreground = { Color = "#aaaaaa" }},
      { Text = "⏳ " .. title },
    }
  end

  return title
end)

-- Appearance
config.color_scheme = "Chalk"
config.font = wezterm.font("Rec Mono Duotone")
config.font_size = 12.0

-- Terminal
config.term = "wezterm"
config.enable_kitty_keyboard = true

-- Hyperlink rules
config.hyperlink_rules = {
  -- Linkify things that look like URLs
  {
    regex = "\\b\\w+://(?:[\\w.-]+)\\.[a-z]{2,15}\\S*\\b",
    format = "$0",
  },
  -- Linkify email addresses
  {
    regex = "\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b",
    format = "mailto:$0",
  },
  -- file:// URI
  {
    regex = "\\bfile://\\S*\\b",
    format = "$0",
  },
  -- Make Jira ticket numbers clickable (e.g., GNAVS-2465)
  {
    regex = "\\b([A-Z]+-\\d+)\\b",
    format = "https://indeed.atlassian.net/browse/$1",
  },
}

return config
