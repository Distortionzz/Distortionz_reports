-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ Distortionz Reports — client                                     ║
-- ║                                                                  ║
-- ║ Routes commands + keybinds → NUI. Listens for staff alerts +     ║
-- ║ reporter notifications. UI gating mirrors the server perms       ║
-- ║ check via distortionz_perms client cache (UI-only — server is    ║
-- ║ always authoritative).                                           ║
-- ╚══════════════════════════════════════════════════════════════════╝

local nuiOpen = false

-- ─── Helpers ────────────────────────────────────────────────────────
local function Notify(message, notifyType, duration, title)
    notifyType = notifyType or 'primary'
    duration   = duration or 5000
    title      = title or Config.Notify.title
    if notifyType == 'inform' then notifyType = 'info' end
    if GetResourceState(Config.Notify.resource) == 'started' then
        exports[Config.Notify.resource]:Notify(message, notifyType, duration, title)
        return
    end
    lib.notify({
        title = title, description = message, type = notifyType, duration = duration,
    })
end

RegisterNetEvent('distortionz_reports:client:notify', function(message, notifyType, duration, title)
    Notify(message, notifyType, duration, title)
end)

local function isStaffCached()
    if GetResourceState('distortionz_perms') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports.distortionz_perms:IsAtLeastCached(Config.Perms.viewQueue)
    end)
    return ok and result == true
end

-- Force a fresh tier fetch from the perms server. Used before showing
-- a "no permission" toast — the local perms cache can be stale on
-- first connect (perms client refreshes after a 2s warmup), so we
-- avoid yelling at the player over a startup race.
local function isStaffFresh()
    if GetResourceState('distortionz_perms') ~= 'started' then return false end
    pcall(function() exports.distortionz_perms:RefreshTier() end)
    return isStaffCached()
end

local function setNuiOpen(open)
    nuiOpen = open
    SetNuiFocus(open, open)
    SetNuiFocusKeepInput(false)
end

-- ─── NUI bootstrap (push categories + tier on open) ────────────────
-- Use the fresh check so the Staff Queue tab visibility is correct
-- even on first connect. Costs one perms callback round-trip per UI open.
local function bootstrapPayload()
    return {
        categories = Config.Categories,
        submission = Config.Submission,
        reply      = Config.Reply,
        isStaff    = isStaffFresh(),
    }
end

-- ─── Open commands (server + keybinds drive these) ─────────────────
RegisterNetEvent('distortionz_reports:client:openSubmit', function()
    setNuiOpen(true)
    SendNUIMessage({ action = 'open', view = 'submit', boot = bootstrapPayload() })
end)

RegisterNetEvent('distortionz_reports:client:openQueue', function()
    -- isStaffFresh forces a perms refresh before deciding — handles
    -- the startup race where the perms client cache is still 'none'
    -- because the initial 2s warmup hasn't completed yet.
    if not isStaffFresh() then
        Notify('You do not have permission to open the queue.', 'error')
        return
    end
    setNuiOpen(true)
    SendNUIMessage({ action = 'open', view = 'queue', boot = bootstrapPayload() })
end)

-- ─── New report alerts (staff-side toast) ──────────────────────────
RegisterNetEvent('distortionz_reports:client:newReportAlert', function(data)
    -- Optionally play the configured sound
    if Config.Alerts.soundFile then
        SendNUIMessage({ action = 'sound', file = Config.Alerts.soundFile })
    end
    Notify(('New #%d (%s) — %s'):format(data.id, data.category, data.subject),
        'inform', 6000, 'New Report')
end)

-- ─── Live updates (refresh open UI views) ──────────────────────────
RegisterNetEvent('distortionz_reports:client:queueDirty', function()
    if not nuiOpen then return end
    SendNUIMessage({ action = 'queueDirty' })
end)

RegisterNetEvent('distortionz_reports:client:reportThreadDirty', function(reportId)
    if not nuiOpen then return end
    SendNUIMessage({ action = 'threadDirty', reportId = reportId })
end)

RegisterNetEvent('distortionz_reports:client:reportUpdated', function()
    if not nuiOpen then return end
    SendNUIMessage({ action = 'queueDirty' })
end)

-- ═══════════════════════════════════════════════════════════════════
-- ─── NUI callbacks (UI → server bridges) ───────────────────────────
-- ═══════════════════════════════════════════════════════════════════

RegisterNUICallback('close', function(_, cb)
    setNuiOpen(false)
    SendNUIMessage({ action = 'closed' })
    cb({ ok = true })
end)

RegisterNUICallback('submit', function(data, cb)
    local result = lib.callback.await('distortionz_reports:cb:submit', false, {
        category = data.category, subject = data.subject, body = data.body,
    })
    cb(result or { ok = false, reason = 'No response.' })
end)

RegisterNUICallback('listMine', function(_, cb)
    cb(lib.callback.await('distortionz_reports:cb:listMine', false) or {})
end)

RegisterNUICallback('listQueue', function(_, cb)
    cb(lib.callback.await('distortionz_reports:cb:listQueue', false) or {})
end)

RegisterNUICallback('open', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:openReport', false, tonumber(data.id)) or {})
end)

RegisterNUICallback('reply', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:reply', false, {
        reportId = tonumber(data.reportId), body = data.body,
    }) or { ok = false, reason = 'No response.' })
end)

RegisterNUICallback('claim', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:claim', false, tonumber(data.id)) or {})
end)

RegisterNUICallback('unclaim', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:unclaim', false, tonumber(data.id)) or {})
end)

RegisterNUICallback('closeReport', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:close', false, tonumber(data.id)) or {})
end)

RegisterNUICallback('reopen', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:reopen', false, tonumber(data.id)) or {})
end)

RegisterNUICallback('delete', function(data, cb)
    cb(lib.callback.await('distortionz_reports:cb:delete', false, tonumber(data.id)) or {})
end)

-- ─── Keybinds ───────────────────────────────────────────────────────
RegisterCommand('+distortionz_reports_submit', function()
    TriggerEvent('distortionz_reports:client:openSubmit')
end, false)
RegisterCommand('-distortionz_reports_submit', function() end, false)

RegisterCommand('+distortionz_reports_queue', function()
    -- Soft check; server gates the actual data fetch
    TriggerEvent('distortionz_reports:client:openQueue')
end, false)
RegisterCommand('-distortionz_reports_queue', function() end, false)

RegisterKeyMapping('+distortionz_reports_submit',
    Config.Keybinds.submitMenu.label or 'Open Report Form',
    'keyboard', Config.Keybinds.submitMenu.key or 'F7')

RegisterKeyMapping('+distortionz_reports_queue',
    Config.Keybinds.staffMenu.label or 'Open Staff Queue',
    'keyboard', Config.Keybinds.staffMenu.key or 'F8')

-- ─── ESC closes UI ─────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)
        if nuiOpen then
            if IsControlJustReleased(0, 200) then   -- ESC
                setNuiOpen(false)
                SendNUIMessage({ action = 'closed' })
            end
        else
            Wait(500)
        end
    end
end)

-- ─── Cleanup on resource stop ──────────────────────────────────────
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if nuiOpen then SetNuiFocus(false, false) end
end)
