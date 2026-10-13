import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// One agent inside a session: where it sits (workspace · tab), what its
// terminal title says, and its state in one right-hand column. Clicking it
// lands on that agent's pane. An agent that wants something (needs you, done)
// washes its whole line in that colour: a dot has to be looked at, a row of
// colour is caught out of the corner of the eye.
Item {
    id: agentRow

    required property var modelData
    required property int index
    required property var herd
    required property var view
    required property var session
    required property int sessionIndex

    readonly property bool wants: Logic.agentWants(modelData.status)
    readonly property bool lit: mouse.containsMouse || view.cursorOnAgent(sessionIndex, index)
    readonly property color tone: herd.stateColor(modelData.status)
    readonly property real pad: Math.round(Kirigami.Units.smallSpacing / 2)

    implicitHeight: line.implicitHeight + pad * 2

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -Kirigami.Units.smallSpacing
        anchors.rightMargin: -Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius
        readonly property color tint: agentRow.wants ? agentRow.tone : Kirigami.Theme.textColor
        readonly property real alpha: agentRow.wants ? (agentRow.lit ? 0.30 : 0.18) : (agentRow.lit ? 0.10 : 0)
        color: Qt.rgba(tint.r, tint.g, tint.b, alpha)
    }

    RowLayout {
        id: line
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: agentRow.pad
        spacing: Kirigami.Units.smallSpacing

        // The dot of the agent that spoke last pulses: opacity only, so the
        // line never moves, and it stops once that agent is answered.
        Rectangle {
            id: dot
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.round(placeLabel.visible ? placeLabel.implicitHeight / 2 - height / 2 : titleLabel.implicitHeight / 2 - height / 2)
            implicitWidth: Math.max(4, Math.round(Kirigami.Units.smallSpacing * 1.5))
            implicitHeight: implicitWidth
            radius: width / 2
            color: agentRow.tone

            SequentialAnimation on opacity {
                running: agentRow.herd.blinking(agentRow.session, agentRow.modelData) && Kirigami.Units.longDuration > 0
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                id: placeLabel
                Layout.fillWidth: true
                visible: text !== ""
                text: Logic.agentPlace(agentRow.modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: agentRow.wants || agentRow.lit ? 1 : 0.8
            }

            PlasmaComponents3.Label {
                id: titleLabel
                Layout.fillWidth: true
                text: Logic.cleanTitle(agentRow.modelData.title)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font: Kirigami.Theme.smallFont
                opacity: agentRow.wants || agentRow.lit ? 0.85 : 0.6
            }
        }

        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignTop
            text: i18n(Logic.agentNote(agentRow.modelData.status))
            textFormat: Text.PlainText
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            // Only the two that are news carry weight.
            font.bold: agentRow.wants
            color: agentRow.tone
        }
    }

    // Last child, above the labels, so it takes the click.
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: agentRow.herd.focusAgent(agentRow.session, agentRow.modelData)
    }
}
