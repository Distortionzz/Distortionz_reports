/* ════════════════════════════════════════════════════════════════════
   Distortionz Reports — NUI controller
   ════════════════════════════════════════════════════════════════════ */

(function () {
    'use strict';

    // ─── State ──────────────────────────────────────────────────────
    const state = {
        boot: null,                  // { categories, submission, reply, isStaff }
        currentView: 'submit',
        selectedCategory: null,
        currentReportId: null,
        currentReport: null,
        queueFilter: 'all',
        previousView: 'submit',      // for back button from thread
    };

    const RESOURCE = (window.GetParentResourceName && window.GetParentResourceName()) || 'distortionz_reports';

    // ─── DOM refs ──────────────────────────────────────────────────
    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

    const root          = $('#root');
    const closeBtn      = $('#closeBtn');
    const tabs          = $$('.tab');
    const views         = $$('.view');
    const categoryGrid  = $('#categoryGrid');
    const submitForm    = $('#submitForm');
    const subjectInput  = $('#subjectInput');
    const bodyInput     = $('#bodyInput');
    const subjectCount  = $('#subjectCount');
    const bodyCount     = $('#bodyCount');
    const submitError   = $('#submitError');
    const submitBtn     = $('#submitBtn');
    const mineList      = $('#mineList');
    const queueList     = $('#queueList');
    const queueCount    = $('#queueCount');
    const refreshQueueBtn = $('#refreshQueueBtn');
    const categoryFilter  = $('#categoryFilter');
    const backBtn       = $('#backBtn');
    const threadId      = $('#threadId');
    const threadCat     = $('#threadCat');
    const threadStatus  = $('#threadStatus');
    const threadSubject = $('#threadSubject');
    const threadReporter= $('#threadReporter');
    const threadCreated = $('#threadCreated');
    const threadActions = $('#threadActions');
    const threadBody    = $('#threadBody');
    const replyForm     = $('#replyForm');
    const replyInput    = $('#replyInput');
    const replyCount    = $('#replyCount');
    const toastEl       = $('#toast');
    const confirmModal  = $('#confirmModal');
    const confirmTitle  = $('#confirmTitle');
    const confirmMsg    = $('#confirmMessage');
    const confirmOk     = $('#confirmOk');
    const confirmCancel = $('#confirmCancel');

    // ─── Utilities ──────────────────────────────────────────────────
    function postNui(action, data) {
        return fetch(`https://${RESOURCE}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).then(r => r.json()).catch(() => ({ ok: false, reason: 'NUI fetch failed' }));
    }

    function findCategory(id) {
        if (!state.boot || !state.boot.categories) return null;
        return state.boot.categories.find(c => c.id === id) || null;
    }

    function fmtDate(s) {
        if (!s) return '—';
        // MySQL TIMESTAMP comes back as "YYYY-MM-DD HH:MM:SS" or ISO-ish
        const d = new Date(s.replace ? s.replace(' ', 'T') : s);
        if (isNaN(d.getTime())) return s;
        const now = new Date();
        const diffMs = now - d;
        const diffMin = Math.floor(diffMs / 60000);
        if (diffMin < 1)  return 'just now';
        if (diffMin < 60) return `${diffMin}m ago`;
        const diffH = Math.floor(diffMin / 60);
        if (diffH < 24) return `${diffH}h ago`;
        const diffD = Math.floor(diffH / 24);
        if (diffD < 7)  return `${diffD}d ago`;
        return d.toLocaleDateString();
    }

    function escapeHtml(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    // ─── In-NUI toast (replaces alert) ─────────────────────────────
    // CRITICAL: never use window.alert / window.confirm in NUI — they
    // hard-hang CEF in FiveM and force an alt+f4 to recover.
    let toastTimer = null;
    function showToast(message, type) {
        if (!toastEl) return;
        toastEl.textContent = message;
        toastEl.className = 'toast ' + (type || 'info');
        // Force reflow so the transition fires when we add .show
        // eslint-disable-next-line no-unused-expressions
        void toastEl.offsetWidth;
        toastEl.classList.add('show');
        if (toastTimer) clearTimeout(toastTimer);
        toastTimer = setTimeout(() => {
            toastEl.classList.remove('show');
            // Hide fully after the fade-out transition
            setTimeout(() => { if (!toastEl.classList.contains('show')) toastEl.classList.add('hidden'); }, 200);
        }, 4000);
        toastEl.classList.remove('hidden');
    }

    // ─── In-NUI confirm (replaces window.confirm) ──────────────────
    // Returns a promise that resolves true/false.
    let confirmResolver = null;
    function showConfirm(title, message, confirmLabel) {
        return new Promise((resolve) => {
            confirmTitle.textContent = title || 'Are you sure?';
            confirmMsg.textContent   = message || '';
            confirmOk.textContent    = confirmLabel || 'Confirm';
            confirmModal.classList.remove('hidden');
            // Reflow so .show triggers the transition
            void confirmModal.offsetWidth;
            confirmModal.classList.add('show');
            confirmResolver = resolve;
        });
    }
    function resolveConfirm(value) {
        confirmModal.classList.remove('show');
        setTimeout(() => confirmModal.classList.add('hidden'), 180);
        if (confirmResolver) {
            const r = confirmResolver; confirmResolver = null;
            r(value);
        }
    }
    confirmOk.addEventListener('click',     () => resolveConfirm(true));
    confirmCancel.addEventListener('click', () => resolveConfirm(false));
    // ESC inside the modal cancels it (without closing the whole panel)
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (confirmModal && confirmModal.classList.contains('show')) {
            e.stopPropagation();
            resolveConfirm(false);
        }
    });

    // ─── View switching ────────────────────────────────────────────
    function setView(name) {
        state.currentView = name;
        views.forEach(v => v.classList.toggle('active', v.dataset.view === name));
        tabs.forEach(t => t.classList.toggle('active', t.dataset.view === name));

        if (name === 'mine')   loadMine();
        if (name === 'queue')  loadQueue();
    }

    tabs.forEach(t => t.addEventListener('click', () => {
        const target = t.dataset.view;
        if (target) {
            state.previousView = target === 'thread' ? state.previousView : target;
            setView(target);
        }
    }));

    closeBtn.addEventListener('click', () => postNui('close'));

    backBtn.addEventListener('click', () => {
        state.currentReportId = null;
        state.currentReport = null;
        setView(state.previousView || 'queue');
    });

    // ─── Submit view ───────────────────────────────────────────────
    function renderCategories() {
        categoryGrid.innerHTML = '';
        const cats = (state.boot && state.boot.categories) || [];
        cats.forEach(c => {
            const card = document.createElement('div');
            card.className = 'cat-card';
            card.dataset.cat = c.id;
            card.style.color = c.color;
            card.innerHTML = `<span class="cat-icon">${c.icon || '•'}</span><span class="cat-label">${escapeHtml(c.label)}</span>`;
            card.addEventListener('click', () => {
                state.selectedCategory = c.id;
                $$('.cat-card', categoryGrid).forEach(el => el.classList.toggle('selected', el === card));
            });
            categoryGrid.appendChild(card);
        });
    }

    function renderQueueFilter() {
        // Keep "All" + add one chip per category
        categoryFilter.innerHTML = '<button class="filter active" data-cat="all">All</button>';
        const cats = (state.boot && state.boot.categories) || [];
        cats.forEach(c => {
            const btn = document.createElement('button');
            btn.className = 'filter';
            btn.dataset.cat = c.id;
            btn.style.borderColor = c.color;
            btn.textContent = c.label;
            categoryFilter.appendChild(btn);
        });
        $$('.filter', categoryFilter).forEach(b => b.addEventListener('click', () => {
            state.queueFilter = b.dataset.cat;
            $$('.filter', categoryFilter).forEach(x => x.classList.toggle('active', x === b));
            renderQueue();
        }));
    }

    subjectInput.addEventListener('input', () => { subjectCount.textContent = subjectInput.value.length; });
    bodyInput.addEventListener('input',    () => { bodyCount.textContent    = bodyInput.value.length;    });

    submitForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        submitError.textContent = '';

        if (!state.selectedCategory) {
            submitError.textContent = 'Pick a category.';
            return;
        }
        const subject = subjectInput.value.trim();
        const body    = bodyInput.value.trim();
        const limits  = (state.boot && state.boot.submission) || {};
        if (subject.length < (limits.minSubjectLength || 5)) {
            submitError.textContent = `Subject too short (min ${limits.minSubjectLength || 5}).`;
            return;
        }
        if (body.length < (limits.minBodyLength || 10)) {
            submitError.textContent = `Body too short (min ${limits.minBodyLength || 10}).`;
            return;
        }

        submitBtn.disabled = true;
        const result = await postNui('submit', {
            category: state.selectedCategory,
            subject, body,
        });
        submitBtn.disabled = false;

        if (!result.ok) {
            submitError.textContent = result.reason || 'Submit failed.';
            return;
        }

        // Reset + bounce to "My Reports"
        submitForm.reset();
        subjectCount.textContent = '0';
        bodyCount.textContent    = '0';
        state.selectedCategory   = null;
        $$('.cat-card', categoryGrid).forEach(el => el.classList.remove('selected'));
        setView('mine');
    });

    // ─── My Reports list ───────────────────────────────────────────
    async function loadMine() {
        const rows = await postNui('listMine');
        renderList(mineList, rows || [], { isStaff: false });
    }

    // ─── Queue ─────────────────────────────────────────────────────
    let cachedQueue = [];
    async function loadQueue() {
        if (!state.boot || !state.boot.isStaff) return;
        const rows = await postNui('listQueue');
        cachedQueue = Array.isArray(rows) ? rows : [];
        const openN = cachedQueue.filter(r => r.status === 'open').length;
        queueCount.textContent = openN;
        queueCount.dataset.count = openN;
        renderQueue();
    }
    function renderQueue() {
        const filtered = state.queueFilter === 'all'
            ? cachedQueue
            : cachedQueue.filter(r => r.category === state.queueFilter);
        renderList(queueList, filtered, { isStaff: true });
    }
    refreshQueueBtn.addEventListener('click', loadQueue);

    function renderList(container, rows, opts) {
        container.innerHTML = '';
        if (!rows || rows.length === 0) {
            container.innerHTML = '<div class="empty-state">Nothing here yet.</div>';
            return;
        }
        rows.forEach(r => {
            const cat = findCategory(r.category) || { label: r.category, color: '#7d8590', icon: '•' };
            const row = document.createElement('div');
            row.className = 'report-row';
            row.dataset.id = r.id;

            const claimedNote = r.claimed_by_name ? ` • claimed by ${escapeHtml(r.claimed_by_name)}` : '';
            const reporterNote = opts.isStaff && r.reporter_name ? ` • ${escapeHtml(r.reporter_name)}` : '';

            row.innerHTML = `
                <div class="row-top">
                    <span class="row-id">#${r.id}</span>
                    <span class="row-cat" style="background: ${cat.color}22; color: ${cat.color};">${cat.icon || ''} ${escapeHtml(cat.label)}</span>
                    <span class="row-status ${r.status}">${r.status}</span>
                </div>
                <div class="row-subject">${escapeHtml(r.subject)}</div>
                <div class="row-meta">${fmtDate(r.created_at)}${reporterNote}${claimedNote}</div>
            `;
            row.addEventListener('click', () => openThread(r.id));
            container.appendChild(row);
        });
    }

    // ─── Thread view ───────────────────────────────────────────────
    async function openThread(id) {
        const result = await postNui('open', { id });
        if (!result || !result.report) {
            showToast('Could not open report.', 'error');
            return;
        }
        state.currentReportId = id;
        state.currentReport   = result;
        renderThread(result);
        setView('thread');
    }

    function renderThread(data) {
        const r = data.report;
        const cat = findCategory(r.category) || { label: r.category, color: '#7d8590' };
        threadId.textContent      = `#${r.id}`;
        threadCat.textContent     = cat.label;
        threadCat.style.background = cat.color + '22';
        threadCat.style.color      = cat.color;
        threadStatus.textContent  = r.status;
        threadStatus.className    = `thread-status ${r.status}`;
        threadSubject.textContent = r.subject;
        threadReporter.textContent = r.reporter_name;
        threadCreated.textContent = fmtDate(r.created_at);

        // Action buttons depend on staff vs reporter + status
        threadActions.innerHTML = '';
        if (data.isStaff) {
            if (r.status === 'open') {
                addAction('Claim',   'primary', () => actOnReport('claim'));
                addAction('Close',   'ghost',   () => actOnReport('closeReport'));
            } else if (r.status === 'claimed') {
                addAction('Unclaim', 'ghost',   () => actOnReport('unclaim'));
                addAction('Close',   'ghost',   () => actOnReport('closeReport'));
            } else if (r.status === 'closed') {
                addAction('Reopen',  'ghost',   () => actOnReport('reopen'));
            }
            addAction('Delete', 'danger small', async () => {
                const ok = await showConfirm(
                    `Delete report #${r.id}?`,
                    'This permanently removes the report and every reply on it. There is no undo.',
                    'Delete'
                );
                if (!ok) return;
                const res = await postNui('delete', { id: r.id });
                if (res.ok) {
                    state.currentReportId = null;
                    setView(state.previousView || 'queue');
                    showToast(`Report #${r.id} deleted.`, 'success');
                } else {
                    showToast(res.reason || 'Delete failed.', 'error');
                }
            });
        }

        // Render the body — original message first as a "message" too
        threadBody.innerHTML = '';
        appendMessage({
            author_name: r.reporter_name,
            author_role: 'reporter',
            body: r.body,
            created_at: r.created_at,
        }, true);

        (data.replies || []).forEach(rep => appendMessage(rep, false));

        // Scroll to bottom
        requestAnimationFrame(() => { threadBody.scrollTop = threadBody.scrollHeight; });

        // Reply form: hide if closed
        replyForm.style.display = r.status === 'closed' ? 'none' : 'block';
    }

    function addAction(label, cls, onClick) {
        const b = document.createElement('button');
        b.className = `btn ${cls}`;
        b.textContent = label;
        b.addEventListener('click', onClick);
        threadActions.appendChild(b);
    }

    function appendMessage(msg, isOriginal) {
        const el = document.createElement('div');
        el.className = `message ${msg.author_role || 'staff'}${isOriginal ? ' original' : ''}`;
        el.innerHTML = `
            <div class="message-bubble">${escapeHtml(msg.body)}</div>
            <div class="message-meta">${escapeHtml(msg.author_name || 'Unknown')} • ${fmtDate(msg.created_at)}</div>
        `;
        threadBody.appendChild(el);
    }

    async function actOnReport(action) {
        const id = state.currentReportId;
        if (!id) return;
        const res = await postNui(action, { id });
        if (!res.ok) {
            showToast(res.reason || 'Action failed.', 'error');
            return;
        }
        // Refresh thread + list
        openThread(id);
        if (state.boot && state.boot.isStaff) loadQueue();
    }

    // ─── Reply ─────────────────────────────────────────────────────
    replyInput.addEventListener('input', () => { replyCount.textContent = replyInput.value.length; });

    replyForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const body = replyInput.value.trim();
        if (body.length === 0) return;
        const id = state.currentReportId;
        if (!id) return;

        const res = await postNui('reply', { reportId: id, body });
        if (!res.ok) {
            showToast(res.reason || 'Reply failed.', 'error');
            return;
        }
        replyInput.value = '';
        replyCount.textContent = '0';
        openThread(id);
    });

    // ─── Inbound messages from Lua ─────────────────────────────────
    window.addEventListener('message', (event) => {
        const msg = event.data || {};

        if (msg.action === 'open') {
            state.boot = msg.boot || {};
            // Show/hide the staff queue tab based on cached perms
            const staffTab = $('.tab.staff-only');
            if (staffTab) staffTab.classList.toggle('show', !!state.boot.isStaff);
            renderCategories();
            renderQueueFilter();
            root.classList.remove('hidden');
            setView(msg.view || 'submit');
            return;
        }

        if (msg.action === 'closed') {
            root.classList.add('hidden');
            return;
        }

        if (msg.action === 'queueDirty') {
            // Refresh queue if open + reload current thread if viewing one
            if (state.currentView === 'queue' && state.boot && state.boot.isStaff) loadQueue();
            if (state.currentView === 'mine') loadMine();
            return;
        }

        if (msg.action === 'threadDirty') {
            if (state.currentView === 'thread' && state.currentReportId === msg.reportId) {
                openThread(state.currentReportId);
            }
            return;
        }

        if (msg.action === 'sound' && msg.file) {
            try {
                const a = new Audio(msg.file);
                a.volume = 0.4;
                a.play().catch(() => {});
            } catch (_) { /* swallow */ }
            return;
        }
    });

    // Hide on load — wait for 'open' from Lua
    root.classList.add('hidden');
})();
