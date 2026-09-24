import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Plugin Browser on a keybind (Super+Alt+U), the Add Plugin menu row, or
// the bar button, over whatever you were working in. It holds the keyboard for
// as long as it is up. The same surface as nixarchy.devenv's menu: a scrim,
// one card. The card is a share of the screen, drawn at the theme's sizes.
//
//   omarchy-shell shell toggle io.github.olafkfreund.nixarchy-plugin-browser '{}'
//   … '{"id":"crmne.hyprmoncfg"}'   straight to that plugin's details
//   … '{"query":"monitor"}'         with a search typed
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var targetScreen: null

  // ponytail: fixed shares, not a setting; the floor and ceiling follow the
  // theme's base font through Style.space().
  readonly property real widthShare: 0.6
  readonly property real heightShare: 0.7
  readonly property int minCardWidth: Style.space(560)
  readonly property int minCardHeight: Style.space(420)
  readonly property int maxCardWidth: Style.space(960)
  readonly property int maxCardHeight: Style.space(760)

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return null
  }

  // Plugin lifecycle: the host calls open(payloadJson) on summon and close()
  // on hide, and reads `opened` to decide what `toggle` means.
  function open(payloadJson) {
    root.targetScreen = root.focusedScreen()
    view.reset()
    view.applyPayload(Model.parsePayload(payloadJson))
    root.opened = true
  }

  function close() {
    view.dismiss()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "nixarchy-plugin-browser-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) Qt.callLater(function() { view.focusForMode() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // A click away closes, as every summoned surface here does. The card
    // swallows its own clicks so they never reach this.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Model.cardExtent(panel.width, root.widthShare, root.minCardWidth, root.maxCardWidth, Style.gapsOut)
      height: Model.cardExtent(panel.height, root.heightShare, root.minCardHeight, root.maxCardHeight, Style.gapsOut)
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(Style.gapsOut, Math.round((panel.height - height) / 3))
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: frame
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        clip: true

        BrowserView {
          id: view
          anchors.fill: parent
          foreground: Color.foreground
          fontFamily: Style.font.family
          onCloseRequested: root.close()
        }
      }
    }
  }
}
