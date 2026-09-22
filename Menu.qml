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
// one card, the view drawn larger so it reads from a distance.
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

  readonly property real uiScale: 1.45
  readonly property int viewWidth: Style.space(680)

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
      width: Math.min(Math.round(root.viewWidth * root.uiScale) + card.contentLeftInset + card.contentRightInset,
                      Math.round(panel.width * 0.9))
      height: Math.min(Math.round(view.implicitHeight * root.uiScale) + card.contentTopInset + card.contentBottomInset,
                       Math.round(panel.height * 0.85))
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
          // Laid out at its natural size, then drawn uiScale times larger;
          // input is mapped through the same transform, so clicks still land.
          width: frame.width / root.uiScale
          height: frame.height / root.uiScale
          scale: root.uiScale
          transformOrigin: Item.TopLeft
          foreground: Color.foreground
          fontFamily: Style.font.family
          onCloseRequested: root.close()
        }
      }
    }
  }
}
