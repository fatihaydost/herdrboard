.pragma library

/*
 * Pure helpers for Herdrboard: argument checks, the attention order, labels and
 * the navigation list. Nothing in here touches QML or i18n, so it runs under
 * node (tests/logic.test.js).
 */

// POSIX single-quote escaping: wrap in '...', turn every ' into '\''.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

// Names, pane ids and machine ids come back from herdr and go straight back
// out as arguments. The script checks them too; this is the near end of the
// same fence.
function validName(name) {
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(String(name));
}

function validPane(pane) {
    return /^[A-Za-z0-9_-]{1,32}:[A-Za-z0-9_-]{1,32}$/.test(String(pane));
}

function validMachine(id) {
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(String(id));
}

// The command line for one script call. Every argument is checked and quoted;
// returns "" when something does not have the right shape.
function actionCommand(script, action, session, extra) {
    if (!session || !validName(session.name))
        return "";
    const remote = session.remote === true;
    if (remote && !validMachine(session.machineId))
        return "";
    const args = [action, session.name];
    if (extra !== undefined && extra !== "")
        args.push(extra);
    if (remote)
        args.push(session.machineId);
    return "bash " + shellQuote(script) + " " + args.map(shellQuote).join(" ");
}

// A session's identity: two machines can both have a "default".
function rowKey(session) {
    return String(session.machineId || "") + "\u0000" + String(session.name);
}

// Pane ids are scoped to one server, so machine and session are part of it.
function agentKey(session, pane) {
    return rowKey(session) + "\u0000" + String(pane);
}

// Waiting beats finished beats busy beats ready, wherever a session or the
// whole herd has to be summed up in one state.
function attentionRank(status) {
    if (status === "blocked") return 0;
    if (status === "done") return 1;
    if (status === "working") return 2;
    if (status === "idle") return 3;
    return 4;
}

function agentWants(status) {
    return status === "blocked" || status === "done";
}

// The tray badge: "" (no badge: nothing is running or every agent is idle),
// otherwise the loudest state across the herd.
function badgeState(counts) {
    if (!counts || !(counts.running > 0)) return "";
    if ((counts.blocked || 0) > 0) return "blocked";
    if ((counts.done || 0) > 0) return "done";
    if ((counts.working || 0) > 0) return "working";
    return "";
}

// "idle" is herdr's word for the ordinary resting state; it reads like a
// fault, so it is shown as "ready".
function agentNote(status) {
    if (status === "blocked") return "needs you";
    if (status === "done") return "done";
    if (status === "working") return "working";
    if (status === "idle") return "ready";
    return "unknown";
}

// herdr's own name for the shared session reads like a setting rather than a
// place. On another machine that session takes the machine's name.
function sessionLabel(session) {
    if (!session) return "";
    if (session.isDefault && session.remote === true)
        return session.machineLabel || session.sshTarget || session.name;
    if (session.isDefault) return "Shared session";
    return String(session.name);
}

// The dim prefix in front of a remote session's name. Local rows get none.
function machineName(session) {
    if (!session || session.remote !== true || session.isDefault) return "";
    return session.machineLabel || session.sshTarget || "";
}

// Only where the agent lines are not already saying it: a stopped session names
// what it saved, an empty server says so.
function subtitleFor(session) {
    if (!session) return "";
    if (session.running && (session.agentList || []).length > 0) return "";
    const projects = session.projects || [];
    if (projects.length > 0) return projects.join("  ·  ");
    return session.running ? "no workspaces yet" : "nothing saved";
}

// herdr puts a spinner glyph in front of a working agent's title, so the text
// would jitter left and right. Leading symbols are dropped.
function cleanTitle(title) {
    const s = String(title || "").trim();
    const stripped = s.replace(/^[^0-9A-Za-zÀ-ɏ]+/, "").trim();
    return stripped !== "" ? stripped : s;
}

// The machines that did not answer the last poll, as one line, or "".
function unreachableText(machines) {
    const names = [];
    for (let i = 0; i < (machines || []).length; i++) {
        const m = machines[i];
        if (m.ok === true) continue;
        let label = m.label || m.target || m.id;
        if (m.error && m.error !== "" && m.error !== "unreachable")
            label += " (" + m.error + ")";
        names.push(label);
    }
    return names.length === 0 ? "" : "unreachable: " + names.join(", ");
}

// What the arrow keys walk: every agent in drawing order, plus one row for a
// session with no agents so it stays reachable from the keyboard.
function navRows(sessions) {
    const rows = [];
    for (let i = 0; i < (sessions || []).length; i++) {
        const agents = sessions[i].agentList || [];
        if (agents.length === 0) {
            rows.push({ sessionIndex: i, agentIndex: -1 });
            continue;
        }
        for (let j = 0; j < agents.length; j++)
            rows.push({ sessionIndex: i, agentIndex: j });
    }
    return rows;
}

// A nav row's identity: the cursor holds on to this, not to an index that a
// poll can shift onto another session.
function navKey(sessions, row) {
    if (!row) return "";
    const session = sessions[row.sessionIndex];
    if (row.agentIndex < 0) return rowKey(session);
    return agentKey(session, ((session.agentList || [])[row.agentIndex] || {}).pane);
}

// Where the cursor goes after the list changed: back onto the row it was on;
// if that agent is gone, its session's first row; if the session is gone too,
// the same place, clamped. -1 stays -1.
function followCursor(sessions, key, index) {
    const rows = navRows(sessions);
    if (index < 0 || key === "") return Math.min(index, rows.length - 1);
    let sameSession = -1;
    for (let i = 0; i < rows.length; i++) {
        if (navKey(sessions, rows[i]) === key) return i;
        const sk = rowKey(sessions[rows[i].sessionIndex]);
        if (sameSession < 0 && (key === sk || key.indexOf(sk + "\u0000") === 0)) sameSession = i;
    }
    return sameSession >= 0 ? sameSession : Math.min(index, rows.length - 1);
}

// Where the cursor starts when the popup opens: the agent that wants the most.
function bestRow(sessions, rows) {
    let best = -1;
    let bestRank = 99;
    for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        if (r.agentIndex < 0) continue;
        const agent = (sessions[r.sessionIndex].agentList || [])[r.agentIndex];
        const rank = attentionRank(agent ? agent.status : "");
        if (rank < bestRank) {
            bestRank = rank;
            best = i;
        }
    }
    return best >= 0 ? best : (rows.length > 0 ? 0 : -1);
}

// Which agent started asking since the previous poll, for the blinking dot.
// `before` is the previous poll's set of wanting agent keys. Returns
// { wanting, fresh } where fresh is the key of the newest one ("" for none;
// a tie on state_change_seq goes to the first drawn).
function attention(sessions, before) {
    const wanting = {};
    let fresh = null;
    for (let i = 0; i < (sessions || []).length; i++) {
        const session = sessions[i];
        const agents = session.agentList || [];
        for (let j = 0; j < agents.length; j++) {
            if (!agentWants(agents[j].status)) continue;
            const key = agentKey(session, agents[j].pane);
            wanting[key] = true;
            if (before && before[key]) continue;
            if (fresh === null || (agents[j].seq || 0) > fresh.seq)
                fresh = { key: key, seq: agents[j].seq || 0 };
        }
    }
    return { wanting: wanting, fresh: fresh ? fresh.key : "" };
}

// The workspace every agent in a session sits in, when they all share one
// (and there is at least one agent): then it is said once, on the session's
// header, instead of on every row.
function sharedWorkspace(session) {
    const agents = (session && session.agentList) || [];
    if (agents.length === 0) return "";
    const ws = agents[0].workspace || "";
    for (let i = 1; i < agents.length; i++)
        if ((agents[i].workspace || "") !== ws) return "";
    return ws;
}

// An agent's quiet second line: its kind, then where it sits. The workspace is
// left out when the session header already names it.
function agentDetail(agent, omitWorkspace) {
    if (!agent) return "";
    const parts = [];
    if (agent.kind) parts.push(agent.kind);
    if (agent.workspace && !omitWorkspace) parts.push(agent.workspace);
    if (agent.tab) parts.push(agent.tab);
    return parts.join(" · ");
}

// The dim hint after a session's name: herdr's own name for the shared session,
// and the workspace its agents share.
function sessionHint(session) {
    if (!session) return "";
    const parts = [];
    if (session.isDefault && session.remote !== true) parts.push("default");
    const ws = sharedWorkspace(session);
    if (ws) parts.push(ws);
    return parts.join(" · ");
}

// What the session header says on its right, when its agents are not already
// saying it.
function sessionMeta(session) {
    if (!session) return "";
    if (!session.running) return "stopped";
    if ((session.agentList || []).length === 0 && !session.error) return "no agents";
    return "";
}

// The badge's text: a number only when agents wait on you (the one count worth
// reading at 22 px); a plain dot for done and working.
function badgeText(counts) {
    return badgeState(counts) === "blocked" ? String(counts.blocked) : "";
}

// Nothing to list: no server running and no named session saved.
function herdEmpty(sessions) {
    for (let i = 0; i < (sessions || []).length; i++)
        if (sessions[i].running || !sessions[i].isDefault) return false;
    return true;
}
