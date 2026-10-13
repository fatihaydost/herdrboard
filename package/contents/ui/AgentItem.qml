import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// One agent inside a session. What it is doing (its terminal title) is the
// first line; its kind and where it sits are the quieter second line. State is
// said once, on the right: a filled pill for the two states that want you
// (needs you, done), plain quiet text for working and ready. Rows that want
// you also carry a light wash of that colour, so they are caught out of the
// corner of the eye. Clicking lands on that agent's pane.
Item {
    id: agentRow

    required property var modelData
    required property int index
    required property var herd
    required property var view
    required property var session
    required property int sessionIndex
    // The session header already names the workspace every agent shares.
    property bool omitWorkspace: false

    readonly property string status: modelData.status
    readonly property bool wants: Logic.agentWants(status)
    readonly property bool lit: mouse.containsMouse || view.cursorOnAgent(sessionIndex, index)
    readonly property color tone: herd.stateColor(status)

    implicitHeight: line.implicitHeight + Kirigami.Units.smallSpacing * 2

    Accessible.role: Accessible.Button
    Accessible.name: Logic.cleanTitle(modelData.title) + ", " + Logic.agentNote(status)

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        readonly property color tint: agentRow.wants ? agentRow.tone : Kirigami.Theme.textColor
        readonly property real alpha: agentRow.wants ? (agentRow.lit ? 0.22 : 0.13) : (agentRow.lit ? 0.08 : 0)
        color: Qt.rgba(tint.r, tint.g, tint.b, alpha)
    }

    RowLayout {
        id: line
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: Kirigami.Units.iconSizes.smallMedium
            source: "utilities-terminal-symbolic"
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: 0.7
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: Logic.cleanTitle(agentRow.modelData.title)
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: Logic.agentDetail(agentRow.modelData, agentRow.omitWorkspace)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }

        // The two states that want you: a pill. The newest one to start
        // asking breathes (opacity only), so the sound herdr played has a
        // face; it stops once that agent is answered.
        Rectangle {
            id: pill
            Layout.alignment: Qt.AlignVCenter
            visible: agentRow.wants
            implicitWidth: pillLabel.implicitWidth + Kirigami.Units.smallSpacing * 3
            implicitHeight: pillLabel.implicitHeight + Kirigami.Units.smallSpacing
            radius: height / 2
            color: Qt.rgba(agentRow.tone.r, agentRow.tone.g, agentRow.tone.b, 0.22)

            PlasmaComponents3.Label {
                id: pillLabel
                anchors.centerIn: parent
                text: i18n(Logic.agentNote(agentRow.status))
                textFormat: Text.PlainText
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: true
                color: agentRow.tone
            }

            SequentialAnimation on opacity {
                running: agentRow.herd.blinking(agentRow.session, agentRow.modelData) && Kirigami.Units.longDuration > 0
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        // Working and ready stay quiet: small text, no fill.
        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignVCenter
            visible: !agentRow.wants
            text: i18n(Logic.agentNote(agentRow.status))
            textFormat: Text.PlainText
            font: Kirigami.Theme.smallFont
            color: agentRow.status === "working" ? agentRow.tone : Kirigami.Theme.disabledTextColor
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: agentRow.herd.focusAgent(agentRow.session, agentRow.modelData)
    }
}
