Config = Config or {}

-- ─── Script meta ────────────────────────────────────────────────────
Config.Script = {
    name    = 'Distortionz Reports',
    version = '1.0.3',
}

Config.VersionCheck = {
    enabled      = true,
    checkOnStart = true,
    url          = 'https://raw.githubusercontent.com/Distortionzz/Distortionz_Reports/main/version.json',
}
Config.CurrentVersion = '1.0.3'

-- ─── Notifications ──────────────────────────────────────────────────
Config.Notify = {
    title    = 'Reports',
    resource = 'distortionz_notify',
}

-- ─── Permission gates ───────────────────────────────────────────────
-- Which distortionz_perms tiers can do what.
-- Reads happen against the server-side perms exports — client UI mirrors.
Config.Perms = {
    viewQueue   = 'mod',     -- minimum tier to open the staff queue
    claim       = 'mod',     -- minimum tier to claim a report
    reply       = 'mod',     -- minimum tier to reply to a report
    close       = 'mod',     -- minimum tier to close a report
    reopen      = 'admin',   -- minimum tier to re-open a closed report
    deleteAny   = 'admin',   -- minimum tier to delete a report
    teleportTo  = 'admin',   -- minimum tier to teleport to reporter (planned for v1.1)
}

-- ─── Categories ─────────────────────────────────────────────────────
-- Players pick one when submitting. Affects routing + UI badge color.
Config.Categories = {
    { id = 'bug',       label = 'Bug Report',     color = '#d29922', icon = '🐛' },
    { id = 'player',    label = 'Player Report',  color = '#f85149', icon = '🚨' },
    { id = 'question',  label = 'Question',       color = '#58a6ff', icon = '❓' },
    { id = 'staff',     label = 'Staff Request',  color = '#3fb950', icon = '🛠️' },
    { id = 'other',     label = 'Other',          color = '#7d8590', icon = '💬' },
}

-- ─── Submission rules ───────────────────────────────────────────────
Config.Submission = {
    minSubjectLength    = 5,
    maxSubjectLength    = 80,
    minBodyLength       = 10,
    maxBodyLength       = 2000,
    maxOpenPerPlayer    = 3,    -- player can have N open reports at once
    cooldownBetweenS    = 60,   -- seconds between submissions per player
}

-- ─── Reply rules ────────────────────────────────────────────────────
Config.Reply = {
    maxLength        = 2000,
    cooldownS        = 5,       -- per-player reply cooldown (anti-spam)
}

-- ─── Staff alerts ───────────────────────────────────────────────────
Config.Alerts = {
    -- Notify all online staff (>=mod) when a new report comes in
    newReportToStaff   = true,
    -- Notify the reporter when a staff member replies
    replyToReporter    = true,
    -- Notify the reporter when their report is claimed/closed
    statusToReporter   = true,
    -- Sound the NUI plays on a new alert (file in html/ — leave nil to skip)
    soundFile          = nil,
}

-- ─── Keybinds ───────────────────────────────────────────────────────
Config.Keybinds = {
    -- Default keys; players can rebind via FiveM's Settings → Key Bindings.
    submitMenu = { key = 'F7', label = 'Open Report Form' },
    staffMenu  = { key = 'F6', label = 'Open Staff Queue (staff only)' },
    -- F8 is the FiveM dev console by default — picking F6 to avoid that.
    -- The staff bind is registered for everyone but the server gates the
    -- actual data fetch by tier; non-staff get a "no permission" notify.
}

-- ─── Debug ──────────────────────────────────────────────────────────
Config.Debug = false
