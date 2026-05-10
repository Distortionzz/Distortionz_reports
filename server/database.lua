-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ Distortionz Reports — database layer                             ║
-- ╚══════════════════════════════════════════════════════════════════╝

DB = DB or {}

-- ─── Schema ─────────────────────────────────────────────────────────
local SCHEMA_REPORTS = [[
CREATE TABLE IF NOT EXISTS distortionz_reports_tickets (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    citizenid       VARCHAR(50) NOT NULL,
    reporter_name   VARCHAR(100) NOT NULL,
    category        VARCHAR(32) NOT NULL,
    subject         VARCHAR(120) NOT NULL,
    body            TEXT NOT NULL,
    status          ENUM('open', 'claimed', 'closed') NOT NULL DEFAULT 'open',
    claimed_by_cid  VARCHAR(50) NULL,
    claimed_by_name VARCHAR(100) NULL,
    closed_by_cid   VARCHAR(50) NULL,
    closed_at       TIMESTAMP NULL DEFAULT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_citizenid (citizenid),
    INDEX idx_category (category),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

local SCHEMA_REPLIES = [[
CREATE TABLE IF NOT EXISTS distortionz_reports_replies (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    report_id   INT UNSIGNED NOT NULL,
    author_cid  VARCHAR(50) NOT NULL,
    author_name VARCHAR(100) NOT NULL,
    author_role ENUM('reporter', 'staff') NOT NULL,
    body        TEXT NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_report (report_id, created_at),
    CONSTRAINT fk_report FOREIGN KEY (report_id)
        REFERENCES distortionz_reports_tickets(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await(SCHEMA_REPORTS, {})
        MySQL.query.await(SCHEMA_REPLIES, {})
    end)
    if not ok then
        print(('^1[distortionz_reports] ^7DB schema bootstrap FAILED: %s'):format(tostring(err)))
        return
    end
    print('^2[distortionz_reports]^7 DB schema verified.')
end)

-- ─── Reports CRUD ───────────────────────────────────────────────────
function DB.CreateReport(citizenid, reporterName, category, subject, body)
    local res = MySQL.insert.await([[
        INSERT INTO distortionz_reports_tickets
            (citizenid, reporter_name, category, subject, body)
        VALUES (?, ?, ?, ?, ?)
    ]], { citizenid, reporterName, category, subject, body })
    return tonumber(res)
end

function DB.GetReport(reportId)
    local rows = MySQL.query.await(
        'SELECT * FROM distortionz_reports_tickets WHERE id = ? LIMIT 1',
        { reportId }
    )
    return rows and rows[1] or nil
end

function DB.GetReportReplies(reportId)
    return MySQL.query.await(
        'SELECT id, author_cid, author_name, author_role, body, created_at FROM distortionz_reports_replies WHERE report_id = ? ORDER BY created_at ASC',
        { reportId }
    ) or {}
end

function DB.ListOpenReports(limit)
    return MySQL.query.await([[
        SELECT id, citizenid, reporter_name, category, subject, status,
               claimed_by_name, created_at, updated_at
        FROM distortionz_reports_tickets
        WHERE status IN ('open', 'claimed')
        ORDER BY
            CASE status WHEN 'open' THEN 0 ELSE 1 END,
            created_at DESC
        LIMIT ?
    ]], { limit or 100 }) or {}
end

function DB.ListPlayerReports(citizenid, limit)
    return MySQL.query.await([[
        SELECT id, category, subject, status, claimed_by_name, created_at, updated_at
        FROM distortionz_reports_tickets
        WHERE citizenid = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { citizenid, limit or 50 }) or {}
end

function DB.CountOpenForPlayer(citizenid)
    local rows = MySQL.query.await(
        "SELECT COUNT(*) AS n FROM distortionz_reports_tickets WHERE citizenid = ? AND status IN ('open', 'claimed')",
        { citizenid }
    )
    return rows and rows[1] and tonumber(rows[1].n) or 0
end

function DB.ClaimReport(reportId, staffCid, staffName)
    MySQL.query.await([[
        UPDATE distortionz_reports_tickets
        SET status = 'claimed', claimed_by_cid = ?, claimed_by_name = ?
        WHERE id = ? AND status = 'open'
    ]], { staffCid, staffName, reportId })
end

function DB.UnclaimReport(reportId)
    MySQL.query.await([[
        UPDATE distortionz_reports_tickets
        SET status = 'open', claimed_by_cid = NULL, claimed_by_name = NULL
        WHERE id = ? AND status = 'claimed'
    ]], { reportId })
end

function DB.CloseReport(reportId, staffCid)
    MySQL.query.await([[
        UPDATE distortionz_reports_tickets
        SET status = 'closed', closed_by_cid = ?, closed_at = NOW()
        WHERE id = ?
    ]], { staffCid, reportId })
end

function DB.ReopenReport(reportId)
    MySQL.query.await([[
        UPDATE distortionz_reports_tickets
        SET status = 'open', closed_by_cid = NULL, closed_at = NULL
        WHERE id = ?
    ]], { reportId })
end

function DB.DeleteReport(reportId)
    MySQL.query.await('DELETE FROM distortionz_reports_tickets WHERE id = ?', { reportId })
end

function DB.AddReply(reportId, authorCid, authorName, authorRole, body)
    local res = MySQL.insert.await([[
        INSERT INTO distortionz_reports_replies
            (report_id, author_cid, author_name, author_role, body)
        VALUES (?, ?, ?, ?, ?)
    ]], { reportId, authorCid, authorName, authorRole, body })
    -- Bump the ticket's updated_at so it sorts correctly
    MySQL.query.await('UPDATE distortionz_reports_tickets SET updated_at = NOW() WHERE id = ?', { reportId })
    return tonumber(res)
end
