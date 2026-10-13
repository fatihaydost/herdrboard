.pragma library

/*
 * Pure helpers for Herdboard: argument checks, the attention order, labels and
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

// One state for a session row, from its counts: "blocked", "done", "working",
// "idle", or "stopped".
function sessionState(session) {
    if (!session || !session.running) return "stopped";
    if ((session.blocked || 0) > 0) return "blocked";
    if ((session.done || 0) > 0) return "done";
    if ((session.working || 0) > 0) return "working";
    return "idle";
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

// The coloured word on a session row's first line, or "".
function noteLabel(session) {
    if (!session || !session.running) return "";
    if ((session.blocked || 0) > 0) return session.blocked + " needs you";
    if ((session.done || 0) > 0) return session.done + " done";
    if ((session.working || 0) > 0) return session.working + " working";
    return "";
}

function countLabel(session) {
    if (!session) return "";
    if (!session.running) return "stopped";
    const n = session.agents || 0;
    if (n === 0) return "no agents";
    return n === 1 ? "1 agent" : n + " agents";
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

// Where an agent sits: workspace, then tab, whichever exist.
function agentPlace(agent) {
    if (!agent) return "";
    const parts = [];
    if (agent.workspace) parts.push(agent.workspace);
    if (agent.tab) parts.push(agent.tab);
    return parts.join("  ·  ");
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

// For the one place that renders rich text (Kirigami.InlineMessage): every
// character that could start markup becomes an entity.
function richEscape(text) {
    return String(text || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}
