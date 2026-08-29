import QtQuick

// A single-line Text whose item geometry follows the painted glyph bounds
// instead of the font's full ascent/descent line box. This is the Qt Quick
// equivalent of CSS text-box trimming for layout purposes.
Item {
  id: root

  property alias text: label.text
  property alias color: label.color
  property alias font: label.font
  property alias horizontalAlignment: label.horizontalAlignment
  property alias elide: label.elide

  readonly property rect inkBounds: metrics.tightBoundingRect(label.text)

  implicitWidth: label.implicitWidth
  implicitHeight: Math.ceil(Math.max(0, inkBounds.height))

  FontMetrics {
    id: metrics
    font: label.font
  }

  Text {
    id: label
    width: root.width
    textFormat: Text.PlainText
    // FontMetrics coordinates are relative to the baseline. Move the Text's
    // baseline so the top of its ink bounds starts at y=0 in this item.
    y: -baselineOffset - root.inkBounds.y
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
  }
}
