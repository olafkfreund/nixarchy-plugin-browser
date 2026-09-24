import QtQuick
import qs.Commons
import "Model.js" as Model

// The `?` overlay: the keys in Model.SHORTCUTS. The view matches keys itself
// (BrowserView.qml) and the footer is its own string, so keep all three in
// step. Esc, ? or q closes it; ↑ ↓ j k PgUp PgDn scroll it (BrowserView's
// commonKey).
Rectangle {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property alias flick: flick            // BrowserView scrolls it

  // Opens at the top, however it was left.
  onVisibleChanged: if (visible) flick.contentY = 0

  color: Color.popups.background
  radius: Style.spacing.sm

  // Swallow clicks so they do not reach the list underneath.
  MouseArea { anchors.fill: parent }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.margins: Style.spacing.lg
    clip: true
    contentWidth: width
    contentHeight: rows.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: rows
      width: flick.width
      spacing: Style.spacing.xs

      Text {
        text: "Keys"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Repeater {
        model: Model.SHORTCUTS
        delegate: Row {
          required property var modelData
          required property int index
          spacing: Style.spacing.lg
          topPadding: index > 0 && Model.SHORTCUTS[index - 1].group !== modelData.group ? Style.spacing.md : 0

          Text {
            width: Style.space(130)
            text: modelData.group
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            opacity: index === 0 || Model.SHORTCUTS[index - 1].group !== modelData.group ? 1 : 0
          }
          Text {
            width: Style.space(240)
            text: modelData.keys
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            width: rows.width - Style.space(130) - Style.space(240) - 2 * Style.spacing.lg
            text: modelData.what
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
