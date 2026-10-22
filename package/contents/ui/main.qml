pragma ComponentBehavior: Bound

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "logic.js" as Logic

// herdr sessions in the system tray: how many servers are running, what every
// agent inside them is doing, and one click to open or focus one.
//
// All the work is done by contents/scripts/herdrboard-sessions, which prints
// JSON; this item polls it, holds the result and sends it commands.
//
// Session names, workspace labels and agent titles are external text, so every
// Text that shows them is PlainText: rich text would load an <img src=...>.
PlasmoidItem {
    id: root

    // Always in the visible part of the tray. Never NeedsAttention: the tray
    // answers that by bouncing the whole icon, which is too loud for "an agent
    // finished". The badge colour carries the signal instead.
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: Qt.resolvedUrl("../icons/herdrboard-symbolic.svg")

    readonly property string script: decodeURIComponent(Qt.resolvedUrl("../scripts/herdrboard-sessions").toString().replace(/^file:\/\//, ""))

    // ------------------------------------------------------------- state

    property var sessions: []
    property var machines: []
    property int runningCount: 0
    property int agentCount: 0
    property int blockedCount: 0
    property int doneCount: 0
    property int workingCount: 0
    property bool loaded: false
    property bool reachable: true
    property string errorText: ""

    // The session the script is acting on, so its row can dim.
    property string pendingKey: ""
    property bool listBusy: false
    // A refresh asked for while a poll is running (after an action, on opening
    // the popup) is owed one more poll, not dropped.
    property bool listAgain: false
    property bool actionBusy: false
    // Requests that arrived while another action was running, run in order:
    // keeping only the latest let a confirmed kill vanish behind a later click.
    property var queuedActions: []

    // The agent that started asking since the previous poll blinks, so the
    // sound herdr played has a face. The first poll only sets the baseline.
    property string attentionKey: ""
    property var wantingBefore: ({})
    property bool attentionPrimed: false

    readonly property string badgeState: Logic.badgeState({
        running: runningCount, blocked: blockedCount, done: doneCount, working: workingCount
    })
    readonly property string badgeCount: Logic.badgeText({
        running: runningCount, blocked: blockedCount, done: doneCount, working: workingCount
    })

    function stateColor(state) {
        if (state === "blocked")
            return Kirigami.Theme.negativeTextColor;
        if (state === "done")
            return Kirigami.Theme.positiveTextColor;
        if (state === "working")
            return Kirigami.Theme.neutralTextColor;
        return Kirigami.Theme.disabledTextColor;
    }

    toolTipMainText: i18n("Herdrboard")
    toolTipSubText: {
        if (!reachable)
            return errorText !== "" ? errorText : i18n("Could not reach herdr");
        if (!loaded)
            return "";
        const parts = [i18np("%1 herdr server", "%1 herdr servers", runningCount),
                       i18np("%1 agent", "%1 agents", agentCount)];
        if (blockedCount > 0)
            parts.push(i18n("%1 waiting on you", blockedCount));
        if (doneCount > 0)
            parts.push(i18n("%1 finished", doneCount));
        return parts.join(", ");
    }
    toolTipTextFormat: Text.PlainText

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 12

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    // ------------------------------------------------------------- polling

    Exec {
        id: exec
    }

    function refresh() {
        if (listBusy) {
            listAgain = true;
            return;
        }
        listBusy = true;
        // The window lookup (which session already has a window: its open
        // button raises it) only matters while the list is on screen.
        const cmd = "bash " + Logic.shellQuote(script) + " list" + (expanded ? "" : " --no-windows");
        exec.run(cmd, (code, stdout, stderr) => {
            listBusy = false;
            applyPayload(stdout);
            if (listAgain) {
                listAgain = false;
                refresh();
            }
        });
    }

    function applyPayload(text) {
        // Any answer ends the wait, a failed one too: the popup's "cannot reach"
        // placeholders only show once something has come back.
        loaded = true;
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            reachable = false;
            errorText = i18n("Unexpected output from herdrboard-sessions");
            return;
        }
        reachable = data.ok === true;
        errorText = data.error || "";
        if (!reachable)
            return;
        const list = data.sessions || [];
        const att = Logic.attention(list, wantingBefore);
        if (attentionKey !== "" && !att.wanting[attentionKey])
            attentionKey = "";
        if (att.fresh !== "" && attentionPrimed)
            attentionKey = att.fresh;
        wantingBefore = att.wanting;
        attentionPrimed = true;

        sessions = list;
        machines = data.machines || [];
        runningCount = data.running || 0;
        agentCount = data.agents || 0;
        blockedCount = data.blocked || 0;
        doneCount = data.done || 0;
        workingCount = data.working || 0;
    }

    // Polled rather than subscribed: herdr has one event socket per server, and
    // a tray count can be a few seconds old. Faster while the popup is open,
    // and while the badge is showing something (needs you, done, working):
    // that is the only time its colour can go stale on its own. An idle herd
    // cannot change until you change it.
    Timer {
        interval: root.expanded ? 3000 : (root.badgeState !== "" ? 5000 : 20000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // A killed server leaves the list and a new window takes a moment to
    // register its agents: one beat after an action, look again.
    Timer {
        id: settleTimer
        interval: 400
        onTriggered: root.refresh()
    }

    onExpandedChanged: {
        if (root.expanded)
            root.refresh();
    }

    // ------------------------------------------------------------- actions

    function run(action, session, extra) {
        if (actionBusy) {
            queuedActions = queuedActions.concat([{ action: action, session: session, extra: extra }]);
            return;
        }
        const cmd = Logic.actionCommand(script, action, session, extra);
        if (cmd === "")
            return;
        actionBusy = true;
        pendingKey = Logic.rowKey(session);
        exec.run(cmd, (code, stdout, stderr) => {
            actionBusy = false;
            pendingKey = "";
            try {
                const res = JSON.parse(stdout);
                if (res.ok !== true && res.error)
                    console.warn("herdrboard:", action, "failed:", res.error);
            } catch (e) {
                console.warn("herdrboard:", action, "gave unexpected output");
            }
            settleTimer.restart();
            if (queuedActions.length > 0) {
                const next = queuedActions[0];
                queuedActions = queuedActions.slice(1);
                run(next.action, next.session, next.extra);
            }
        });
    }

    // Focus the window already showing this session, or open one. The popup
    // closes: it is in the way of the window just asked for.
    function openSession(session) {
        if (!session || !Logic.validName(session.name))
            return;
        run("open", session);
        expanded = false;
    }

    // One step further in: the agent's pane is focused inside the server first,
    // so the window comes up on that piece of work. That also marks a "done"
    // agent as seen.
    function focusAgent(session, agent) {
        if (!session || !agent)
            return;
        if (!Logic.validPane(agent.pane)) {
            openSession(session);
            return;
        }
        run("focus", session, agent.pane);
        expanded = false;
    }

    // Killing is the one action that cannot be taken back, so the popup asks
    // first (FullRepresentation). Remote servers are never ended from here.
    function killSession(session) {
        if (!session || !session.running || session.remote === true)
            return;
        run("kill", session);
    }

    // A stopped session's directory is thrown away, so the popup asks first
    // too. The shared session is herdr's own and is never deleted from here.
    function removeSession(session) {
        if (!session || session.isDefault || session.running || session.remote === true)
            return;
        run("delete", session);
    }

    function pending(session) {
        return session !== null && session !== undefined && pendingKey !== "" && pendingKey === Logic.rowKey(session);
    }

    function blinking(session, agent) {
        return attentionKey !== "" && session && agent && Logic.agentKey(session, agent.pane) === attentionKey;
    }

    // ------------------------------------------------------------- views

    compactRepresentation: CompactRepresentation {
        herd: root
        onActivated: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {
        herd: root
    }
}
