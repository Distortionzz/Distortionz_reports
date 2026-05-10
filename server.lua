-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ Distortionz Reports — server                                     ║
-- ║                                                                  ║
-- ║ All report state lives in MySQL. This file owns the callbacks,   ║
-- ║ permission checks (delegated to distortionz_perms), and          ║
-- ║ broadcasts to staff/reporters.                                   ║
-- ╚══════════════════════════════════════════════════════════════════╝

-- ─── State ──────────────────────────────────────────────────────────
local lastSubmissionAt = {}    -- src -> ms timestamp
local lastReplyAt      = {}    -- src -> ms timestamp

-- ─── Helpers ────────────────────────────────────────────────────────
local function Debug(...)
    if Config.Debug then
        print(('[reports:server] %s'):format(table.concat({...}, ' ')))
    end
end

local function getPlayer(src)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if not ok then return nil end
    return p
end

local function getCitizenId(src)
    local p = getPlayer(src)
    if not p or not p.PlayerData then return nil end
    return p.PlayerData.citizenid
end

local function getDisplayName(src)
    local p = getPlayer(src)
    if not p or not p.PlayerData then return ('Player %d'):format(src) end
    local cs = p.PlayerData.charinfo
    if cs and cs.firstname and cs.lastname then
        return ('%s %s'):format(cs.firstname, cs.lastname)
    end
    return p.PlayerData.name or ('Player %d'):format(src)
end

local function notify(src, message, notifyType, duration, title)
    notifyType = notifyType or 'primary'
    duration   = duration or 5000
    title      = title or Config.Notify.title
    if GetResourceState(Config.Notify.resource) == 'started' then
        TriggerClientEvent('distortionz_reports:client:notify', src, message, notifyType, duration, title)
        return
    end
    TriggerClientEvent('ox_lib:notify', src, {
        title = title, description = message, type = notifyType, duration = duration,
    })
end

-- ─── Permission shortcut ────────────────────────────────────────────
local function isAtLeast(src, requiredTier)
    local ok, result = pcall(function()
        return exports.distortionz_perms:IsAtLeast(src, requiredTier)
    end)
    if not ok then return false end
    return result == true
end

-- ─── Validation ─────────────────────────────────────────────────────
local function isCategoryValid(id)
    for _, c in ipairs(Config.Categories) do
        if c.id == id then return true end
    end
    return false
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- ─── Broadcast helpers ─────────────────────────────────────────────
local function broadcastStaffNew(report)
    if not Config.Alerts.newReportToStaff then return end
    local players = GetPlayers()
    for _, sid in ipairs(players) do
        local s = tonumber(sid)
        if s and isAtLeast(s, Config.Perms.viewQueue) then
            TriggerClientEvent('distortionz_reports:client:newReportAlert', s, {
                id       = report.id,
                category = report.category,
                subject  = report.subject,
                reporter = report.reporter_name,
            })
            notify(s, ('New %s from %s — #%d'):format(report.category, report.reporter_name, report.id),
                'inform', 6000, 'New Report')
        end
    end
end

local function findOnlineByCid(cid)
    if not cid then return nil end
    local players = GetPlayers()
    for _, sid in ipairs(players) do
        local s = tonumber(sid)
        if s and getCitizenId(s) == cid then return s end
    end
    return nil
end

local function notifyReporter(reporterCid, message, notifyType)
    local s = findOnlineByCid(reporterCid)
    if not s then return end
    notify(s, message, notifyType or 'inform', 6000, 'Your Report')
    TriggerClientEvent('distortionz_reports:client:reportUpdated', s)
end

-- ═══════════════════════════════════════════════════════════════════
-- ─── Callbacks ─────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════

-- Submit a new report
lib.callback.register('distortionz_reports:cb:submit', function(src, payload)
    if type(payload) ~= 'table' then
        return { ok = false, reason = 'Bad payload.' }
    end
    local cid = getCitizenId(src)
    if not cid then return { ok = false, reason = 'Could not resolve citizenid.' } end

    -- Cooldown
    local now = GetGameTimer()
    if lastSubmissionAt[src] and (now - lastSubmissionAt[src]) < (Config.Submission.cooldownBetweenS * 1000) then
        local left = math.ceil((Config.Submission.cooldownBetweenS * 1000 - (now - lastSubmissionAt[src])) / 1000)
        return { ok = false, reason = ('On cooldown — %ds left.'):format(left) }
    end

    -- Open report cap
    local openCount = DB.CountOpenForPlayer(cid)
    if openCount >= Config.Submission.maxOpenPerPlayer then
        return { ok = false, reason = ('You already have %d open reports.'):format(openCount) }
    end

    -- Validate
    local category = trim(payload.category)
    local subject  = trim(payload.subject)
    local body     = trim(payload.body)
    if not isCategoryValid(category) then
        return { ok = false, reason = 'Invalid category.' }
    end
    if #subject < Config.Submission.minSubjectLength or #subject > Config.Submission.maxSubjectLength then
        return { ok = false, reason = ('Subject must be %d–%d chars.'):format(
            Config.Submission.minSubjectLength, Config.Submission.maxSubjectLength) }
    end
    if #body < Config.Submission.minBodyLength or #body > Config.Submission.maxBodyLength then
        return { ok = false, reason = ('Body must be %d–%d chars.'):format(
            Config.Submission.minBodyLength, Config.Submission.maxBodyLength) }
    end

    local reporterName = getDisplayName(src)
    local id = DB.CreateReport(cid, reporterName, category, subject, body)
    if not id then return { ok = false, reason = 'DB insert failed.' } end

    lastSubmissionAt[src] = now
    Debug(('submit src=%d cid=%s id=%d cat=%s'):format(src, cid, id, category))

    -- Alert staff
    broadcastStaffNew({
        id = id, category = category, subject = subject, reporter_name = reporterName,
    })

    return { ok = true, id = id }
end)

-- List my own reports (player view)
lib.callback.register('distortionz_reports:cb:listMine', function(src)
    local cid = getCitizenId(src)
    if not cid then return {} end
    return DB.ListPlayerReports(cid, 50)
end)

-- List the staff queue
lib.callback.register('distortionz_reports:cb:listQueue', function(src)
    if not isAtLeast(src, Config.Perms.viewQueue) then return nil end
    return DB.ListOpenReports(100)
end)

-- Open a single report (with reply thread). Reporter sees their own,
-- staff sees any.
lib.callback.register('distortionz_reports:cb:openReport', function(src, reportId)
    reportId = tonumber(reportId)
    if not reportId then return nil end
    local cid = getCitizenId(src)
    if not cid then return nil end

    local report = DB.GetReport(reportId)
    if not report then return nil end

    local isStaff = isAtLeast(src, Config.Perms.viewQueue)
    if (not isStaff) and report.citizenid ~= cid then
        return nil
    end

    return {
        report  = report,
        replies = DB.GetReportReplies(reportId),
        isStaff = isStaff,
    }
end)

-- Claim a report
lib.callback.register('distortionz_reports:cb:claim', function(src, reportId)
    reportId = tonumber(reportId)
    if not reportId or not isAtLeast(src, Config.Perms.claim) then
        return { ok = false, reason = 'Insufficient permission.' }
    end
    local report = DB.GetReport(reportId)
    if not report then return { ok = false, reason = 'Report not found.' } end
    if report.status ~= 'open' then
        return { ok = false, reason = ('Already %s.'):format(report.status) }
    end

    local cid = getCitizenId(src)
    DB.ClaimReport(reportId, cid, getDisplayName(src))

    if Config.Alerts.statusToReporter then
        notifyReporter(report.citizenid, ('Your report #%d was claimed by %s.'):format(reportId, getDisplayName(src)))
    end
    -- Push update to all staff currently viewing the queue
    TriggerClientEvent('distortionz_reports:client:queueDirty', -1)
    return { ok = true }
end)

-- Unclaim
lib.callback.register('distortionz_reports:cb:unclaim', function(src, reportId)
    reportId = tonumber(reportId)
    if not reportId or not isAtLeast(src, Config.Perms.claim) then
        return { ok = false, reason = 'Insufficient permission.' }
    end
    local report = DB.GetReport(reportId)
    if not report or report.status ~= 'claimed' then
        return { ok = false, reason = 'Not currently claimed.' }
    end
    -- Only the claimer or an admin+ can unclaim
    local cid = getCitizenId(src)
    if report.claimed_by_cid ~= cid and not isAtLeast(src, 'admin') then
        return { ok = false, reason = "Only the claimer or admin+ can unclaim." }
    end
    DB.UnclaimReport(reportId)
    TriggerClientEvent('distortionz_reports:client:queueDirty', -1)
    return { ok = true }
end)

-- Close
lib.callback.register('distortionz_reports:cb:close', function(src, reportId)
    reportId = tonumber(reportId)
    if not reportId or not isAtLeast(src, Config.Perms.close) then
        return { ok = false, reason = 'Insufficient permission.' }
    end
    local report = DB.GetReport(reportId)
    if not report then return { ok = false, reason = 'Report not found.' } end

    DB.CloseReport(reportId, getCitizenId(src))
    if Config.Alerts.statusToReporter then
        notifyReporter(report.citizenid, ('Your report #%d was closed by %s.'):format(reportId, getDisplayName(src)))
    end
    TriggerClientEvent('distortionz_reports:client:queueDirty', -1)
    return { ok = true }
end)

-- Reopen
lib.callback.register('distortionz_reports:cb:reopen', function(src, reportId)
    reportId = tonumber(reportId)
    if not reportId or not isAtLeast(src, Config.Perms.reopen) then
        return { ok = false, reason = 'Insufficient permission.' }
    end
    local report = DB.GetReport(reportId)
    if not report or report.status ~= 'closed' then
        return { ok = false, reason = 'Report is not closed.' }
    end
    DB.ReopenReport(reportId)
    if Config.Alerts.statusToReporter then
        notifyReporter(report.citizenid, ('Your report #%d was re-opened.'):format(reportId))
    end
    TriggerClientEvent('distortionz_reports:client:queueDirty', -1)
    return { ok = true }
end)

-- Delete (admin+)
lib.callback.register('distortionz_reports:cb:delete', function(src, reportId)
    reportId = tonumber(reportId)
    if not reportId or not isAtLeast(src, Config.Perms.deleteAny) then
        return { ok = false, reason = 'Insufficient permission.' }
    end
    DB.DeleteReport(reportId)
    TriggerClientEvent('distortionz_reports:client:queueDirty', -1)
    return { ok = true }
end)

-- Reply (reporter or staff)
lib.callback.register('distortionz_reports:cb:reply', function(src, payload)
    if type(payload) ~= 'table' then return { ok = false, reason = 'Bad payload.' } end
    local reportId = tonumber(payload.reportId)
    local body     = trim(payload.body)
    if not reportId or body == '' then return { ok = false, reason = 'Missing fields.' } end
    if #body > Config.Reply.maxLength then
        return { ok = false, reason = ('Reply too long (>%d chars).'):format(Config.Reply.maxLength) }
    end

    local now = GetGameTimer()
    if lastReplyAt[src] and (now - lastReplyAt[src]) < (Config.Reply.cooldownS * 1000) then
        return { ok = false, reason = 'Slow down.' }
    end

    local cid = getCitizenId(src)
    if not cid then return { ok = false, reason = 'Could not resolve citizenid.' } end

    local report = DB.GetReport(reportId)
    if not report then return { ok = false, reason = 'Report not found.' } end
    if report.status == 'closed' then
        return { ok = false, reason = 'Report is closed.' }
    end

    local isStaff = isAtLeast(src, Config.Perms.reply)
    local isOwner = (report.citizenid == cid)
    if not (isStaff or isOwner) then
        return { ok = false, reason = 'Not your report.' }
    end

    local role = isStaff and 'staff' or 'reporter'
    local replyId = DB.AddReply(reportId, cid, getDisplayName(src), role, body)
    lastReplyAt[src] = now

    -- Notify the other side
    if role == 'staff' and Config.Alerts.replyToReporter then
        notifyReporter(report.citizenid, ('Staff replied to your report #%d.'):format(reportId))
    elseif role == 'reporter' then
        -- Ping any staff currently viewing this report (broadcast; client filters)
        TriggerClientEvent('distortionz_reports:client:reportThreadDirty', -1, reportId)
        -- Toast online staff that this report has new activity
        local players = GetPlayers()
        for _, sid in ipairs(players) do
            local s = tonumber(sid)
            if s and isAtLeast(s, Config.Perms.viewQueue) then
                notify(s, ('Reporter replied to #%d.'):format(reportId), 'inform', 5000, 'Report Activity')
            end
        end
    end

    -- Always tell the relevant viewers to refresh their thread
    TriggerClientEvent('distortionz_reports:client:reportThreadDirty', -1, reportId)
    return { ok = true, replyId = replyId }
end)

-- ─── Cleanup on disconnect ─────────────────────────────────────────
AddEventHandler('playerDropped', function()
    lastSubmissionAt[source] = nil
    lastReplyAt[source]      = nil
end)

-- ─── /report command (opens UI directly) ───────────────────────────
RegisterCommand('report', function(src)
    if src == 0 then print('Run /report from in-game.'); return end
    TriggerClientEvent('distortionz_reports:client:openSubmit', src)
end, false)

RegisterCommand('reports', function(src)
    if src == 0 then print('Run /reports from in-game.'); return end
    if not isAtLeast(src, Config.Perms.viewQueue) then
        notify(src, 'You do not have permission to open the report queue.', 'error')
        return
    end
    TriggerClientEvent('distortionz_reports:client:openQueue', src)
end, false)

-- ─── Startup banner ────────────────────────────────────────────────
CreateThread(function()
    Wait(500)
    print(('^5[distortionz_reports:server]^7 v%s loaded — categories=%d')
        :format(Config.Script.version or '?', #Config.Categories))
end)
