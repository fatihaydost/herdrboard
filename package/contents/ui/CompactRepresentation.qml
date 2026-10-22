import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Tray / panel icon with a badge: red with the number of agents waiting on
// you, a green dot when work finished unseen, an amber dot while something is
// busy, and gone when every agent is idle: then there is nothing to say. Colours come from the colour scheme.
MouseArea {
    id: compact

    // The PlasmoidItem (main.qml) that owns the data.
    required property var herd

    signal activated

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    activeFocusOnTab: true

    Accessible.name: i18n("Herdrboard")
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
        id: icon
        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/herdrboard-symbolic.svg")
        isMask: true
        color: Kirigami.Theme.textColor
        active: compact.containsMouse
        // Cannot reach herdr: step back, like a disconnected device.
        opacity: compact.herd.reachable ? 1 : 0.5
    }

    // The glyph is drawn as a centred square; the badge sits on its empty
    // top-right pane (centre at 11.06/16, 4.94/16 of herdrboard-symbolic.svg).
    readonly property real glyph: Math.min(width, height)
    readonly property real glyphX: (width - glyph) / 2
    readonly property real glyphY: (height - glyph) / 2

    // A mark in the icon's empty pane, small enough to leave the icon readable
    // at 22 px. Only "needs you" carries a number (how many agents wait on
    // you, the one count worth reading at that size); done and working are a
    // plain dot. Server and agent totals live in the tooltip.
    Rectangle {
        id: badge
        readonly property string label: compact.herd.badgeCount
        visible: compact.herd.reachable && compact.herd.badgeState !== "" && compact.width >= Kirigami.Units.iconSizes.small
        // A dot fits inside the pane; a count needs more room to stay legible,
        // so it spills over the pane's frame evenly.
        height: label !== ""
            ? Math.max(Math.round(compact.glyph * 0.42), 8)
            : Math.max(Math.round(compact.glyph * 0.26), 5)
        width: Math.max(height, countLabel.implicitWidth + Kirigami.Units.smallSpacing)
        x: Math.round(compact.glyphX + compact.glyph * 0.6914 - width / 2)
        y: Math.round(compact.glyphY + compact.glyph * 0.3086 - height / 2)
        radius: height / 2
        color: compact.herd.stateColor(compact.herd.badgeState)
        // A rim in the panel's own background keeps the mark apart from the
        // glyph it sits on.
        border.width: 1
        border.color: Kirigami.Theme.backgroundColor

        PlasmaComponents3.Label {
            id: countLabel
            anchors.centerIn: parent
            visible: badge.label !== ""
            text: badge.label.length > 2 ? "99+" : badge.label
            textFormat: Text.PlainText
            color: Kirigami.Theme.backgroundColor
            font.pixelSize: Math.max(Math.round(badge.height * 0.72), 7)
            font.bold: true
        }
    }
}
