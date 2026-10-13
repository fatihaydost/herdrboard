pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

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

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.preferredWidth: Kirigami.Units.gridUnit * 23
    Layout.minimumHeight: Kirigami.Units.gridUnit * 8
    Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 30,
                                     Math.max(Kirigami.Units.gridUnit * 8, list.contentHeight + messages.implicitHeight + Kirigami.Units.gridUnit * 3))

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

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                level: 5
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: !full.herd.loaded ? "" : i18n("herdr · %1 · %2",
                                                    i18np("%1 server", "%1 servers", full.herd.runningCount),
                                                    i18np("%1 agent", "%1 agents", full.herd.agentCount))
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh-symbolic"
                icon.width: Kirigami.Units.iconSizes.small
                icon.height: Kirigami.Units.iconSizes.small
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: i18n("Refresh")
                onClicked: full.herd.refresh()
                PlasmaComponents3.ToolTip.text: i18n("Refresh (R)")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

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

                    // InlineMessage renders rich text, so the error goes in escaped.
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        visible: !full.herd.reachable
                        type: Kirigami.MessageType.Error
                        text: Logic.richEscape(full.herd.errorText !== "" ? full.herd.errorText : i18n("Could not reach herdr."))
                    }

                    // A machine that is down has no rows of its own; without this
                    // line it would vanish silently.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        visible: full.unreachable !== ""
                        text: full.unreachable
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.negativeTextColor
                    }
                }

                PlasmaExtras.PlaceholderMessage {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Kirigami.Units.gridUnit
                    visible: full.herd.loaded && full.herd.reachable && full.herd.sessions.length === 0
                    iconName: "utilities-terminal"
                    text: i18n("No herdr sessions")
                }

                PlasmaComponents3.ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: full.herd.sessions.length > 0
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    ListView {
                        id: list
                        clip: true
                        model: full.herd.sessions
                        spacing: Math.round(Kirigami.Units.smallSpacing / 2)
                        boundsBehavior: Flickable.StopAtBounds
                        topMargin: Kirigami.Units.smallSpacing
                        bottomMargin: Kirigami.Units.smallSpacing

                        delegate: SessionItem {
                            width: ListView.view.width - Kirigami.Units.smallSpacing * 2
                            x: Kirigami.Units.smallSpacing
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

            // Swallow clicks meant for the rows underneath.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: full.closeKill()
            }

            Keys.onEscapePressed: event => {
                full.closeKill();
                event.accepted = true;
            }

            ColumnLayout {
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
