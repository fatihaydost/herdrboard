pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// One herdr session, laid out as a section: a header line (name, a quiet hint,
// a hairline, and the open / kill or delete buttons, quiet until hover or
// keyboard focus), then one row per agent. Clicking the header opens the
// session; clicking an agent lands on it.
ColumnLayout {
    id: row

    required property var modelData
    required property int index
    required property var herd
    required property var view

    readonly property bool remote: modelData.remote === true
    readonly property bool hasWindow: (modelData.windowId || "") !== ""
    readonly property bool canKill: modelData.running && !remote
    readonly property bool canDelete: !modelData.running && !modelData.isDefault && !remote
    readonly property string sharedWs: Logic.sharedWorkspace(modelData)
    readonly property bool actionsShown: headerMouse.containsMouse || view.cursorOnSession(index)
        || openButton.activeFocus || killButton.activeFocus || deleteButton.activeFocus

    spacing: Math.round(Kirigami.Units.smallSpacing / 2)
    opacity: herd.pending(modelData) ? 0.5 : 1

    // ------------------------------------------------------------ header

    Item {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.herd.openSession(row.modelData)
        }

        RowLayout {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                visible: text !== ""
                text: Logic.machineName(row.modelData)
                textFormat: Text.PlainText
                opacity: 0.6
            }

            PlasmaComponents3.Label {
                // Never squeezed below a readable stub; the hint gives way first.
                Layout.minimumWidth: Math.min(implicitWidth, Kirigami.Units.gridUnit * 6)
                Layout.preferredWidth: implicitWidth
                text: row.modelData.isDefault && !row.remote ? i18n("Shared session") : Logic.sessionLabel(row.modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.weight: Font.DemiBold
                opacity: row.modelData.running ? 0.9 : 0.55
            }

            PlasmaComponents3.Label {
                visible: text !== ""
                text: Logic.sessionHint(row.modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                Layout.minimumWidth: 0
                Layout.preferredWidth: Math.min(implicitWidth, Kirigami.Units.gridUnit * 8)
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }

            // The hairline that makes a header a section, as in Plasma's own
            // list section headers.
            Rectangle {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Kirigami.Units.smallSpacing
                implicitHeight: 1
                color: Kirigami.Theme.textColor
                opacity: 0.15
            }

            PlasmaComponents3.Label {
                visible: text !== ""
                text: i18n(Logic.sessionMeta(row.modelData))
                textFormat: Text.PlainText
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }

            RowLayout {
                spacing: 0
                opacity: row.actionsShown ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                IconButton {
                    id: openButton
                    iconSource: row.hasWindow ? "go-jump-symbolic" : "window-new-symbolic"
                    text: row.hasWindow ? i18n("Show this session's window (O)") : i18n("Open this session (O)")
                    onClicked: row.herd.openSession(row.modelData)
                }

                IconButton {
                    id: killButton
                    visible: row.canKill
                    iconSource: Qt.resolvedUrl("../icons/herdboard-kill-symbolic.svg")
                    hoverColor: Kirigami.Theme.negativeTextColor
                    text: i18n("Kill this server (K)")
                    onClicked: row.view.askKill(row.modelData)
                }

                IconButton {
                    id: deleteButton
                    visible: row.canDelete
                    iconSource: "edit-delete-symbolic"
                    hoverColor: Kirigami.Theme.negativeTextColor
                    text: i18n("Delete this stopped session (X)")
                    onClicked: row.herd.removeSession(row.modelData)
                }
            }
        }
    }

    // ------------------------------------------------------------ body

    // A running server whose snapshot could not be read says so here.
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        visible: text !== ""
        text: row.modelData.error || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.negativeTextColor
    }

    // A stopped session names what it saved, so it can be told apart from a
    // name left over from an afternoon.
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        visible: text !== "" && !row.modelData.error
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
            omitWorkspace: row.sharedWs !== ""
        }
    }
}
