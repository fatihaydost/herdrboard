pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "logic.js" as Logic

// The popup: every session, every agent inside it, and the one question asked
// before a server is killed.
//
// Keys: Up/Down walk the agents, Enter lands on the one under the cursor,
// O opens its session, K kills its server (asks first), X deletes a stopped
// session, R refreshes.
PlasmaExtras.Representation {
    id: full

    // The PlasmoidItem (main.qml) that owns the data and the actions.
    required property var herd

    // Keyboard cursor over navRows; shown after the first key press.
    property int cursor: -1
    property bool keyboardActive: false
    // The session the kill dialog is asking about, while it is open.
    property var killTarget: null

    readonly property var rows: Logic.navRows(herd.sessions)
    readonly property string unreachable: Logic.unreachableText(herd.machines)
    readonly property bool notInstalled: herd.errorText === "herdr is not installed"

    // A fixed size, as Plasma's own tray applets use: the popup does not
    // resize under the pointer every time an agent appears or finishes.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    collapseMarginsHint: true
    focus: true

    function sessionAt(index) {
        const r = index >= 0 && index < rows.length ? rows[index] : null;
        return r ? herd.sessions[r.sessionIndex] : null;
    }

    function agentAt(index) {
        const r = index >= 0 && index < rows.length ? rows[index] : null;
        if (!r || r.agentIndex < 0)
            return null;
        return (herd.sessions[r.sessionIndex].agentList || [])[r.agentIndex] || null;
    }

    function cursorOnSession(sessionIndex) {
        const r = keyboardActive && cursor >= 0 && cursor < rows.length ? rows[cursor] : null;
        return r !== null && r.sessionIndex === sessionIndex;
    }

    function cursorOnAgent(sessionIndex, agentIndex) {
        const r = keyboardActive && cursor >= 0 && cursor < rows.length ? rows[cursor] : null;
        return r !== null && r.sessionIndex === sessionIndex && r.agentIndex === agentIndex;
    }

    function moveCursor(delta) {
        if (rows.length === 0)
            return;
        if (!keyboardActive || cursor < 0) {
            keyboardActive = true;
            cursor = Logic.bestRow(herd.sessions, rows);
        } else {
            cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta));
        }
        list.positionViewAtIndex(rows[cursor].sessionIndex, ListView.Contain);
    }

    function activateCursor() {
        const session = sessionAt(cursor);
        if (!session)
            return;
        const agent = agentAt(cursor);
        if (agent)
            herd.focusAgent(session, agent);
        else
            herd.openSession(session);
    }

    // Killing is the one action that cannot be undone: the server goes and so
    // does everything running inside it. The question opens on Cancel, because
    // a dialog that destroys something on a reflexive Enter trains the reflex.
    function askKill(session) {
        if (!session || !session.running || session.remote === true || !Logic.validName(session.name))
            return;
        killTarget = session;
        // Tab reason: the focus ring shows which button Enter will press.
        cancelButton.forceActiveFocus(Qt.TabFocusReason);
    }

    function closeKill() {
        killTarget = null;
        keys.forceActiveFocus();
    }

    function confirmKill() {
        const session = killTarget;
        closeKill();
        herd.killSession(session);
    }

    Connections {
        target: full.herd
        function onExpandedChanged() {
            if (full.herd.expanded) {
                full.killTarget = null;
                full.keyboardActive = false;
                full.cursor = -1;
                keys.forceActiveFocus();
            }
        }
        function onSessionsChanged() {
            if (full.cursor > full.rows.length - 1)
                full.cursor = full.rows.length - 1;
        }
    }

    // In the system tray the tray draws the heading (title, refresh from the
    // contextual actions, configure, pin), and this one hides itself; on the
    // desktop it shows the title and the same actions. Plasma's own pattern.
    header: PlasmaExtras.BasicPlasmoidHeading {}

    contentItem: Item {
        // Holds the list's keys; the dialog takes focus while it is open.
        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (full.killTarget !== null)
                    return;
                const session = full.sessionAt(full.cursor);
                switch (event.key) {
                case Qt.Key_Up:
                case Qt.Key_Down:
                    full.moveCursor(event.key === Qt.Key_Up ? -1 : 1);
                    event.accepted = true;
                    return;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (full.keyboardActive) {
                        full.activateCursor();
                        event.accepted = true;
                    }
                    return;
                case Qt.Key_O:
                    if (session && full.keyboardActive) {
                        full.herd.openSession(session);
                        event.accepted = true;
                    }
                    return;
                case Qt.Key_K:
                    if (session && full.keyboardActive) {
                        full.askKill(session);
                        event.accepted = true;
                    }
                    return;
                case Qt.Key_X:
                case Qt.Key_Delete:
                    if (session && full.keyboardActive) {
                        full.herd.removeSession(session);
                        event.accepted = true;
                    }
                    return;
                case Qt.Key_R:
                case Qt.Key_F5:
                    full.herd.refresh();
                    event.accepted = true;
                    return;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                ColumnLayout {
                    id: messages
                    Layout.fillWidth: true
                    spacing: 0

                    // A machine that is down has no rows of its own; without this
                    // line it would vanish silently.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        Layout.topMargin: Kirigami.Units.largeSpacing
                        visible: full.unreachable !== ""
                        text: full.unreachable
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.negativeTextColor
                    }
                }

                // One sentence and one way forward for each state with nothing
                // to list.
                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Kirigami.Units.gridUnit
                    visible: full.herd.loaded && !full.herd.reachable && full.notInstalled
                    iconName: "utilities-terminal"
                    text: i18n("herdr is not installed")
                    helpfulAction: Action {
                        icon.name: "internet-services"
                        text: i18n("Get herdr")
                        onTriggered: Qt.openUrlExternally("https://herdr.dev")
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Kirigami.Units.gridUnit
                    visible: full.herd.loaded && !full.herd.reachable && !full.notInstalled
                    iconName: "dialog-warning"
                    text: i18n("Cannot reach herdr")
                    explanation: full.herd.errorText
                    helpfulAction: Action {
                        icon.name: "view-refresh"
                        text: i18n("Try Again")
                        onTriggered: full.herd.refresh()
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Kirigami.Units.gridUnit
                    visible: full.herd.loaded && full.herd.reachable && Logic.herdEmpty(full.herd.sessions)
                    iconName: "utilities-terminal"
                    text: i18n("No herdr server is running")
                    helpfulAction: Action {
                        icon.name: "list-add"
                        text: i18n("New Session")
                        onTriggered: full.herd.openSession({ name: "default", isDefault: true, running: false, remote: false })
                    }
                }

                PlasmaComponents3.ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: full.herd.reachable && !Logic.herdEmpty(full.herd.sessions)
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    ListView {
                        id: list
                        clip: true
                        model: full.herd.sessions
                        // Sessions breathe apart more than the agents inside one.
                        spacing: Kirigami.Units.largeSpacing * 2
                        boundsBehavior: Flickable.StopAtBounds
                        topMargin: Kirigami.Units.largeSpacing
                        bottomMargin: Kirigami.Units.largeSpacing

                        delegate: SessionItem {
                            width: ListView.view.width - Kirigami.Units.largeSpacing * 2
                            x: Kirigami.Units.largeSpacing
                            herd: full.herd
                            view: full
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------- kill dialog

        Rectangle {
            id: confirm
            anchors.fill: parent
            z: 10
            visible: full.killTarget !== null
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)

            // Swallow clicks meant for the rows underneath; a click outside the
            // question itself cancels it.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: mouse => {
                    const p = mapToItem(dialogBody, mouse.x, mouse.y);
                    if (!dialogBody.contains(p))
                        full.closeKill();
                }
            }

            Keys.onEscapePressed: event => {
                full.closeKill();
                event.accepted = true;
            }

            ColumnLayout {
                id: dialogBody
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                spacing: Kirigami.Units.largeSpacing

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    text: full.killTarget ? i18n("Kill the server for %1?", Logic.sessionLabel(full.killTarget)) : ""
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.8
                    text: i18n("Nothing running inside it is asked to stop first.")
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaComponents3.Button {
                        id: cancelButton
                        text: i18n("Cancel")
                        icon.name: "dialog-cancel"
                        KeyNavigation.right: killConfirmButton
                        KeyNavigation.tab: killConfirmButton
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()
                        onClicked: full.closeKill()
                    }

                    PlasmaComponents3.Button {
                        id: killConfirmButton
                        text: i18n("Kill")
                        icon.name: "edit-bomb"
                        KeyNavigation.left: cancelButton
                        KeyNavigation.tab: cancelButton
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()
                        onClicked: full.confirmKill()
                    }
                }
            }
        }
    }
}
