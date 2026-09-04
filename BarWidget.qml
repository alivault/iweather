import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ali.iweather"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function toggleUnit() {
    if (!root.bar || !panelLoader.item) return
    var nextUnit = panelLoader.item.useImperial ? "metric" : "imperial"
    root.bar.run("omarchy bar set ali.iweather unit " + nextUnit)
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.status !== Loader.Error
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  TextMetrics {
    id: reservedLabelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: "󰖐  -100°F"
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: vertical ? -1 : Math.ceil(
      reservedLabelMetrics.advanceWidth + scaledHorizontalMargin * 2)
    labelVisible: vertical
    text: {
      if (!panelLoader.item) return ""
      var icon = panelLoader.item.label || ""
      var temperature = panelLoader.item.reportTempNum || ""
      if (temperature === "") return icon || "󰖐"
      if (icon === "") return temperature + panelLoader.item.tempUnit
      return icon + "  " + temperature + panelLoader.item.tempUnit
    }
    horizontalMargin: 6.5
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""

    Text {
      visible: !button.vertical
      anchors.left: parent.left
      anchors.leftMargin: button.scaledHorizontalMargin
      anchors.verticalCenter: parent.verticalCenter
      text: button.text
      color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      textFormat: Text.PlainText
    }

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.toggleUnit()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
