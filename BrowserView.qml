import QtQuick
import Quickshell
import qs.Commons
import "Model.js" as Model

// Everything you can press: the search, the list, a plugin's details with its
// audit and NixOS verdicts, the install question, and the shortcut sheet. It
// draws the BrowserState singleton; Menu.qml hosts it full-screen.
//
// Every piece of text that came from the marketplace or from an audit report
// is drawn with Text.PlainText: a plugin description can never become markup.
FocusScope {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Color.muted

  implicitWidth: Style.space(680)
  implicitHeight: Style.space(520)

  signal closeRequested()

  // ------------------------------------------------------------------ state
  property string mode: "list"          // list | detail
  property string query: ""             // what is typed
  property string appliedQuery: ""      // what the list shows (80 ms later)
  property int cursor: 0
  property var selected: null           // the row open in details
  property bool helpOpen: false
  property bool confirmOpen: false

  readonly property var visibleRows: Model.filterRows(BrowserState.rows, appliedQuery)
  readonly property var cursorRow: cursor >= 0 && cursor < visibleRows.length ? visibleRows[cursor] : null
  readonly property bool reportIsFor: selected !== null && BrowserState.reportFor === selected.id
  readonly property var reportLines: reportIsFor ? Model.reportLines(BrowserState.report) : []

  onVisibleRowsChanged: cursor = Math.min(cursor, Math.max(0, visibleRows.length - 1))

  Timer {
    id: filterDelay
    interval: 80
    onTriggered: { root.appliedQuery = root.query; root.cursor = 0 }
  }

  // ------------------------------------------------------------- lifecycle
  function reset() {
    root.mode = "list"
    root.selected = null
    root.helpOpen = false
    root.confirmOpen = false
    search.text = ""
    root.appliedQuery = ""
    root.cursor = 0
    BrowserState.ensureCatalog()
  }
  function dismiss() {
    root.helpOpen = false
    root.confirmOpen = false
  }
  function focusForMode() {
    if (root.mode === "detail") detailKeys.forceActiveFocus()
    else search.forceActiveFocus()
  }
  // Payload from `omarchy-shell shell toggle <id> '<json>'`.
  function applyPayload(p) {
    if (p.query) { search.text = p.query; root.appliedQuery = p.query }
    if (p.id) {
      var row = BrowserState.rowFor(p.id)
      // The catalog may still be loading: open with what we know about it.
      root.openDetails(row || { id: p.id, name: p.id, author: "", category: "", stars: 0, tags: [],
                                badge: "unverified", description: "", repo: "", installCommand: "",
                                installAvailable: false })
    }
  }

  // --------------------------------------------------------------- actions
  // Keys that act on the list act on what was typed, not on what the 80 ms
  // debounce has shown so far: typing "monitor" and pressing Enter at once
  // used to open the top row of the unfiltered list (found in G1 on razer).
  function commitFilter() {
    if (!filterDelay.running) return
    filterDelay.stop()
    root.appliedQuery = root.query
    root.cursor = 0
  }
  function move(delta) {
    root.commitFilter()
    if (root.visibleRows.length === 0) return
    root.cursor = Math.max(0, Math.min(root.visibleRows.length - 1, root.cursor + delta))
    list.positionViewAtIndex(root.cursor, ListView.Contain)
  }
  function openDetails(row) {
    if (!row || !Model.isSafeId(row.id)) return
    root.selected = row
    root.mode = "detail"
    root.confirmOpen = false
    report.contentY = 0
    if (!(BrowserState.reportFor === row.id && BrowserState.report)) BrowserState.audit(row.id)
    BrowserState.preview(row)
    Qt.callLater(root.focusForMode)
  }
  function back() {
    root.mode = "list"
    root.confirmOpen = false
    Qt.callLater(root.focusForMode)
  }
  function scrollReport(dy) {
    report.contentY = Math.max(0, Math.min(Math.max(0, report.contentHeight - report.height),
                                           report.contentY + dy * Style.space(40)))
  }

  // Keys the whole view shares; true when handled.
  function commonKey(event) {
    if (root.helpOpen) {
      if (event.key === Qt.Key_Escape || event.text === "?" || event.key === Qt.Key_Q) root.helpOpen = false
      return true
    }
    if (event.text === "?") { root.helpOpen = true; return true }
    return false
  }

  // ------------------------------------------------------------------ view
  Column {
    id: column
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header: what this is, and how much of the catalog is shown.
    Item {
      width: parent.width
      height: title.implicitHeight
      Text {
        id: title
        text: Model.Glyph.plugin + "  Plugin Browser"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: title.verticalCenter
        textFormat: Text.PlainText
        text: BrowserState.loading ? "loading the catalog…"
              : BrowserState.catalogError !== "" ? BrowserState.catalogError
              : root.visibleRows.length + " of " + BrowserState.rows.length + " plugins   ? keys"
        color: BrowserState.catalogError !== "" ? Color.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideLeft
        width: parent.width - title.implicitWidth - Style.spacing.lg
        horizontalAlignment: Text.AlignRight
      }
    }

    // ------------------------------------------------------------ list mode
    Rectangle {
      visible: root.mode === "list"
      width: parent.width
      height: search.implicitHeight + Style.spacing.md * 2
      radius: Style.spacing.sm
      color: Color.menu.selectedBackground

      TextInput {
        id: search
        anchors.fill: parent
        anchors.margins: Style.spacing.md
        color: root.foreground
        selectionColor: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        clip: true
        onTextChanged: { root.query = text; filterDelay.restart() }

        Text {
          visible: search.text.length === 0
          text: Model.Glyph.search + "  Search plugins by name, author, tag, category"
          color: root.dim
          font: search.font
        }

        Keys.onPressed: function(event) {
          if (root.commonKey(event)) { event.accepted = true; return }
          var ctrl = event.modifiers & Qt.ControlModifier
          if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J)) { root.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K)) { root.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_PageDown) { root.move(10); event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { root.move(-10); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitFilter(); root.openDetails(root.cursorRow); event.accepted = true }
          else if (ctrl && event.key === Qt.Key_R) { BrowserState.loadCatalog(true); event.accepted = true }
          else if (event.key === Qt.Key_Escape) {
            if (search.text.length > 0) search.text = ""
            else root.closeRequested()
            event.accepted = true
          }
        }
      }
    }

    ListView {
      id: list
      visible: root.mode === "list"
      width: parent.width
      height: parent.height - y - footer.height - Style.spacing.md
      clip: true
      model: root.visibleRows
      currentIndex: root.cursor
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        id: rowItem
        required property var modelData
        required property int index
        width: ListView.view.width
        height: rowText.implicitHeight + Style.spacing.sm * 2
        radius: Style.spacing.xs
        color: index === root.cursor ? Color.menu.selectedBackground : "transparent"

        Text {
          id: rowText
          anchors.left: parent.left
          anchors.right: stars.left
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: Model.badgeGlyph(rowItem.modelData.badge) + "  " + rowItem.modelData.name
                + "  —  " + rowItem.modelData.author
                + (rowItem.modelData.category ? "   " + rowItem.modelData.category : "")
          color: rowItem.index === root.cursor ? Color.menu.selectedText : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          id: stars
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Model.Glyph.star + " " + rowItem.modelData.stars
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { root.cursor = rowItem.index; root.openDetails(rowItem.modelData) }
        }
      }
    }

    // ---------------------------------------------------------- detail mode
    FocusScope {
      id: detailKeys
      visible: root.mode === "detail"
      width: parent.width
      height: parent.height - y - footer.height - Style.spacing.md

      Keys.onPressed: function(event) {
        if (root.commonKey(event)) { event.accepted = true; return }
        var id = root.selected ? root.selected.id : ""
        if (root.confirmOpen) {
          if (event.key === Qt.Key_Y) { root.confirmOpen = false; BrowserState.install(id) }
          else if (event.key === Qt.Key_N || event.key === Qt.Key_Escape) root.confirmOpen = false
          event.accepted = true
          return
        }
        switch (event.key) {
          case Qt.Key_Escape: case Qt.Key_Left: case Qt.Key_Backspace: root.back(); break
          case Qt.Key_A: BrowserState.audit(id); break
          case Qt.Key_E: BrowserState.agent(id, "explain"); break
          case Qt.Key_F: BrowserState.agent(id, "fix"); break
          case Qt.Key_I: if (!BrowserState.installing) root.confirmOpen = true; break
          case Qt.Key_C: BrowserState.copy(root.selected.installCommand); break
          case Qt.Key_O: BrowserState.openRepo(root.selected.repo); break
          case Qt.Key_J: case Qt.Key_Down: root.scrollReport(1); break
          case Qt.Key_K: case Qt.Key_Up: root.scrollReport(-1); break
          default: return
        }
        event.accepted = true
      }

      Flickable {
        id: report
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: detail.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: detail
          width: report.width
          spacing: Style.spacing.sm

          // The marketplace thumbnail, from a local file catalog.sh verified.
          // Keyed on the open plugin so a quick move never shows another
          // plugin's picture; decoded at most 720x405 whatever the file
          // claims; takes no space until it is ready.
          Image {
            id: preview
            readonly property bool mine: root.selected !== null
                                         && BrowserState.previewFor === root.selected.id
                                         && BrowserState.previewPath !== ""
            source: mine ? "file://" + BrowserState.previewPath : ""
            sourceSize: Qt.size(720, 405)
            width: parent.width
            height: status === Image.Ready ? Math.min(width * 405 / 720, Style.space(260)) : 0
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            asynchronous: true
            cache: false
            smooth: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.selected ? Model.badgeGlyph(root.selected.badge) + "  " + root.selected.name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.selected ? [root.selected.id, root.selected.author, root.selected.category,
                                   Model.Glyph.star + " " + root.selected.stars]
                                  .filter(function(s) { return s !== "" }).join("   ·   ") : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.selected ? root.selected.description : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.selected && root.selected.repo ? root.selected.repo : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle { width: parent.width; height: Math.max(1, Style.space(1)); color: root.dim; opacity: 0.4 }

          Text {
            width: parent.width
            visible: BrowserState.auditing && root.selected !== null && BrowserState.auditingFor === root.selected.id
            textFormat: Text.PlainText
            text: "Auditing in a sandbox… (clone, pin, scan)"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            visible: root.reportIsFor && BrowserState.auditError !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: BrowserState.auditError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.reportLines
            delegate: Text {
              required property var modelData
              width: detail.width - leftPadding
              leftPadding: modelData.indent * Style.spacing.lg
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: modelData.text
              color: modelData.tone === "bad" ? Color.urgent
                     : modelData.tone === "warn" ? Color.accent
                     : modelData.tone === "dim" ? root.dim : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: modelData.indent === 0 && modelData.tone !== "dim"
            }
          }
          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.selected && BrowserState.installFor === root.selected.id
                  ? (BrowserState.installing ? "Installing (disabled)…" : BrowserState.installOutput) : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // Footer: the keys that matter where you are, or the install question.
    Text {
      id: footer
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.confirmOpen && root.selected
            ? "Install " + root.selected.name + " (disabled)?   y  yes    n  no"
            : root.mode === "detail"
              ? "a audit   e explain   f fix   i install   c copy   o repo   Esc back   ? keys"
              : "↑↓ move   Enter details   Ctrl+R refresh   Esc close   ? keys"
      color: root.confirmOpen ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  ShortcutSheet {
    anchors.fill: parent
    visible: root.helpOpen
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
}
