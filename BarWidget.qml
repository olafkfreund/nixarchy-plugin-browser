import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button for the plugin browser. A click toggles the full-screen Plugin
// Browser (Menu.qml, the same surface as Super+Alt+U and the Add Plugin menu
// row); a right click opens the terminal TUI, `omarchy-plugin-browser`. This
// widget stays a thin launcher: it parses no plugin data itself.
//
// Nothing is looked up on PATH and no shell string is built: the terminal is an
// absolute path, the scripts are this plugin's own checkout run by an absolute
// bash, the argv is fixed, and the child gets a fixed system PATH.
//
// Updates (docs/update-alerts.md): lib/update.sh checks the published version
// on load and every six hours (cached, one small request). When a newer one is
// out, a dot appears on the button and the next click opens a small popup with
// what changed and an Update… button; Later hides that version and the click
// goes back to opening the browser.
BarWidget {
  id: root
  moduleName: "io.github.olafkfreund.nixarchy-plugin-browser"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string home: Quickshell.env("HOME") || ""
  // This file's folder as a plain path. Qt.resolvedUrl gives a file:// URL.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property var childEnv: ({ "PATH": "/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/" + (Quickshell.env("USER") || "") + "/bin" })

  function launch() {
    if (updatePopup.open) updatePopup.open = false
    Quickshell.execDetached({
      command: Model.toggleArgv(root.moduleName),
      environment: root.childEnv,
      workingDirectory: root.home
    })
  }
  function launchTui() {
    if (updatePopup.open) updatePopup.open = false
    Quickshell.execDetached({
      command: Model.tuiArgv(root.pluginDir),
      environment: root.childEnv,
      workingDirectory: root.home
    })
  }

  // ---- updates ----------------------------------------------------------------
  property string version: ""
  property var updateInfo: null
  readonly property bool updateAvailable: !!updateInfo && updateInfo.update_available === true
                                          && updateInfo.dismissed !== updateInfo.latest
  readonly property bool updateMismatch: !!updateInfo && updateInfo.mismatch === true
  // Installed from a Nix store path (programs.nixarchy.plugins): no .git, so
  // `omarchy plugin update` cannot work; the flake lock is the update path.
  readonly property bool nixInstall: !!updateInfo && updateInfo.git_managed === false
  // What the alert is about: the newer version, or "mismatch". Update… and Later
  // hide that key only, so the next version (or a new mismatch) shows again.
  readonly property string updateKey: updateAvailable ? String(updateInfo.latest) : (updateMismatch ? "mismatch" : "")
  property string updateHiddenKey: ""
  readonly property bool updatePending: updateKey !== "" && updateKey !== updateHiddenKey

  FileView {
    path: root.pluginDir + "/manifest.json"
    printErrors: false
    onLoaded: {
      try { root.version = String(JSON.parse(text()).version || "") } catch (e) { root.version = "" }
      root.checkUpdates()
    }
  }
  function checkUpdates() {
    if (root.setting("update_check", true) === false || updateProc.running) return
    updateProc.command = ["/run/current-system/sw/bin/bash", root.pluginDir + "/lib/update.sh", "check", root.version]
    updateProc.running = true
  }
  Process {
    id: updateProc
    environment: root.childEnv
    stdout: StdioCollector { id: updateOut; waitForEnd: true }
    onExited: function(code) { try { root.updateInfo = JSON.parse(String(updateOut.text || "")) } catch (e) { root.updateInfo = null } }
  }
  Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; onTriggered: root.checkUpdates() }
  function runUpdate() {
    root.updateHiddenKey = root.updateKey
    updatePopup.open = false
    Quickshell.execDetached({
      command: ["/run/current-system/sw/bin/bash", root.pluginDir + "/lib/update.sh", "run", root.updateAvailable ? "all" : "install"],
      environment: root.childEnv,
      workingDirectory: root.home
    })
  }
  function dismissUpdate() {
    root.updateHiddenKey = root.updateKey
    updatePopup.open = false
    if (root.updateAvailable && root.updateInfo.latest)
      Quickshell.execDetached({
        command: ["/run/current-system/sw/bin/bash", root.pluginDir + "/lib/update.sh", "dismiss", String(root.updateInfo.latest)],
        environment: root.childEnv,
        workingDirectory: root.home
      })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""                    // nf-fa-puzzle_piece
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Browse & audit plugins (Super+Alt+U) · right-click: terminal" + (root.updateAvailable ? " · Plugin Browser " + root.updateInfo.latest + " is available" : (root.updateMismatch ? " · finish updating" : ""))
    onPressed: function(b) {
      if (b === Qt.RightButton) root.launchTui()
      else if (root.updatePending) updatePopup.open = !updatePopup.open
      else root.launch()
    }
    Rectangle {
      visible: root.updatePending
      anchors.top: parent.top; anchors.right: parent.right
      anchors.margins: Style.space(3)
      width: Style.space(6); height: width; radius: width / 2
      color: Color.accent
    }
  }

  // ---- update popup (docs/update-alerts.md) -----------------------------------
  PopupCard {
    id: updatePopup
    anchorItem: button
    bar: root.bar
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(updateCol.implicitHeight)
    Column {
      id: updateCol
      width: parent.width
      spacing: Style.space(4)
      Text {
        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: root.updateAvailable
              ? "Plugin Browser " + root.updateInfo.latest + " is available (you have " + root.version + ")"
              : "Finish updating Plugin Browser"
        color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
      }
      Repeater {
        model: root.updateAvailable && Array.isArray(root.updateInfo.notes) ? root.updateInfo.notes.slice(0, 4) : []
        delegate: Text {
          required property var modelData
          width: updateCol.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
          text: "•  " + modelData
          color: Color.popups.text; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }
      Text {
        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: root.updateAvailable
              ? (root.nixInstall
                 ? "Installed through Nix: update with nix flake update nixarchy-plugin-browser and rebuild."
                 : "Update opens a terminal: omarchy plugin update shows the changes and asks, then install.sh relinks the commands (asks first), then offers a shell restart.")
              : "Run install.sh once so the linked commands match. It only relinks this plugin's commands."
        color: Color.popups.text; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption
      }
      Item { width: 1; height: Style.space(2) }
      Row {
        spacing: Style.space(4)
        Button { visible: !root.nixInstall; text: root.updateAvailable ? "Update…" : "Finish update…"; bordered: true; foreground: Color.accent; onClicked: root.runUpdate() }
        Button { text: "Later"; bordered: true; foreground: Color.popups.text; onClicked: root.dismissUpdate() }
        Button { text: "Browse plugins"; foreground: Color.popups.text; onClicked: root.launch() }
      }
    }
  }
}
