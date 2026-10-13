import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// A flat icon-only button whose icon can be a theme name or one of the
// package's own monochrome SVGs, tinted with the colour scheme either way.
PlasmaComponents3.ToolButton {
    id: button

    property string iconSource: ""
    property color iconColor: Kirigami.Theme.textColor
    property color hoverColor: iconColor
    // The keyboard cursor sits on this button.
    property bool cursorOn: false

    display: PlasmaComponents3.AbstractButton.IconOnly
    Accessible.name: text

    PlasmaComponents3.ToolTip.text: text
    PlasmaComponents3.ToolTip.visible: hovered
    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

    contentItem: Item {
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: Kirigami.Units.iconSizes.small
            source: button.iconSource
            isMask: true
            color: button.hovered || button.visualFocus || button.cursorOn ? button.hoverColor : button.iconColor
        }
    }
}
