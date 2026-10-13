import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Tray / panel icon with the running-server count on a badge. The badge is
// red when an agent is waiting on you, green when work finished unseen, amber
// while something is busy, and gone when every agent is idle: then there is
// nothing to say. Colours come from the colour scheme.
MouseArea {
    id: compact

    // The PlasmoidItem (main.qml) that owns the data.
    required property var herd

    signal activated

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    activeFocusOnTab: true

    Accessible.name: i18n("Herdboard")
    Accessible.description: compact.herd.toolTipSubText
    Accessible.role: Accessible.Button

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton)
            compact.herd.refresh();
        else
            compact.activated();
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Enter || event.key === Qt.Key_Return || event.key === Qt.Key_Select) {
            compact.activated();
            event.accepted = true;
        }
    }

    Kirigami.Icon {
        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/herdboard-symbolic.svg")
        isMask: true
        color: Kirigami.Theme.textColor
        active: compact.containsMouse
        // Cannot reach herdr: step back, like a disconnected device.
        opacity: compact.herd.reachable ? 1 : 0.5
    }

    Rectangle {
        id: badge
        visible: compact.herd.reachable && compact.herd.badgeState !== "" && compact.width >= Kirigami.Units.iconSizes.small
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(Math.round(compact.height * 0.5), Kirigami.Units.iconSizes.small * 0.75)
        width: Math.max(height, countLabel.implicitWidth + Kirigami.Units.smallSpacing)
        radius: height / 2
        color: compact.herd.stateColor(compact.herd.badgeState)
        // A rim in the panel's own background keeps the badge apart from the
        // glyph it sits on.
        border.width: 1
        border.color: Kirigami.Theme.backgroundColor

        PlasmaComponents3.Label {
            id: countLabel
            anchors.centerIn: parent
            text: compact.herd.runningCount > 99 ? "99+" : compact.herd.runningCount
            textFormat: Text.PlainText
            color: Kirigami.Theme.backgroundColor
            font.pixelSize: Math.max(Math.round(badge.height * 0.7), 7)
            font.bold: true
        }
    }
}
