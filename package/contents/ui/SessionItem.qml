pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// One herdr session: a state dot, its name (bold when a window already shows
// it), what its loudest agent is doing, every agent inside it, and two
// buttons: open/focus, and kill (running) or delete (stopped). Clicking the
// row opens the session; clicking an agent line lands on that agent.
Item {
    id: row

    required property var modelData
    required property int index
    required property var herd
    required property var view

    readonly property bool remote: modelData.remote === true
    readonly property string sessionState: Logic.sessionState(modelData)
    readonly property bool active: rowMouse.containsMouse || view.cursorOnSession(index)
    readonly property bool canKill: modelData.running && !remote
    readonly property bool canDelete: !modelData.running && !modelData.isDefault && !remote

    implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2
    opacity: herd.pending(modelData) ? 0.4 : 1

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        color: row.active ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06) : "transparent"
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.herd.openSession(row.modelData)
    }

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing * 2

        // The session's own state at a glance, from its loudest agent.
        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.round(nameLabel.implicitHeight / 2 - height / 2)
            implicitWidth: Math.round(Kirigami.Units.smallSpacing * 2)
            implicitHeight: implicitWidth
            radius: width / 2
            color: row.herd.stateColor(row.sessionState)
            opacity: row.modelData.running ? 1 : 0.5
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    visible: text !== ""
                    text: Logic.machineName(row.modelData)
                    textFormat: Text.PlainText
                    opacity: 0.6
                }

                PlasmaComponents3.Label {
                    id: nameLabel
                    Layout.fillWidth: true
                    text: row.modelData.isDefault && !row.remote ? i18n("Shared session") : Logic.sessionLabel(row.modelData)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    // A session a window already shows is one you switch to;
                    // one without still has to be opened.
                    font.bold: (row.modelData.windowId || "") !== ""
                    opacity: row.modelData.running ? 1 : 0.6
                }

                PlasmaComponents3.Label {
                    readonly property string note: Logic.noteLabel(row.modelData)
                    text: note !== "" ? note : Logic.countLabel(row.modelData)
                    textFormat: Text.PlainText
                    font: Kirigami.Theme.smallFont
                    color: note !== "" ? row.herd.stateColor(row.sessionState) : Kirigami.Theme.disabledTextColor
                }
            }

            // The server is running but its snapshot could not be read: say so
            // on this row instead of showing it as empty.
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: row.modelData.error || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.negativeTextColor
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text !== "" && !(row.modelData.error)
                text: Logic.subtitleFor(row.modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }

            Repeater {
                model: row.modelData.agentList || []

                delegate: AgentItem {
                    Layout.fillWidth: true
                    herd: row.herd
                    view: row.view
                    session: row.modelData
                    sessionIndex: row.index
                }
            }
        }

        // Faint until the row is under the pointer or the cursor.
        RowLayout {
            Layout.alignment: Qt.AlignTop
            spacing: 0
            opacity: row.active ? 1 : 0.35

            IconButton {
                iconSource: "window-new-symbolic"
                text: (row.modelData.windowId || "") !== "" ? i18n("Focus this session (O)") : i18n("Open this session (O)")
                onClicked: row.herd.openSession(row.modelData)
            }

            // One destructive slot: a running server is killed, a stopped
            // session deleted, never both. Remote rows leave it empty, and so
            // does the stopped shared session.
            Item {
                implicitWidth: killButton.implicitWidth
                implicitHeight: killButton.implicitHeight

                IconButton {
                    id: killButton
                    anchors.fill: parent
                    visible: row.canKill
                    iconSource: Qt.resolvedUrl("../icons/herdboard-kill-symbolic.svg")
                    hoverColor: Kirigami.Theme.negativeTextColor
                    text: i18n("Kill this server (K)")
                    onClicked: row.view.askKill(row.modelData)
                }

                IconButton {
                    anchors.fill: parent
                    visible: row.canDelete
                    iconSource: "edit-delete-symbolic"
                    hoverColor: Kirigami.Theme.negativeTextColor
                    text: i18n("Delete this stopped session (X)")
                    onClicked: row.herd.removeSession(row.modelData)
                }
            }
        }
    }
}
