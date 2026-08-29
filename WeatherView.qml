import QtQuick
import qs.Commons
import qs.Ui

KeyboardPanel {
  id: panel
  required property var weather
  readonly property var root: weather
  property alias locationText: locationField.text

  function beginLocationEdit(text) {
    locationField.text = text
    locationField.selectAll()
    locationField.forceActiveFocus()
  }

  function focusPanel() {
    keyCatcher.forceActiveFocus()
  }

  anchorItem: root.anchorItem
  owner: root.barIdentity
  bar: root.bar
  open: root.opened
  centerOnBar: true
  focusTarget: keyCatcher
  padding: root.panelPadding
  contentWidth: panel.fittedContentWidth(
    root.naturalInnerWidth + panel.padding * 2
      + Border.left(panel.borderSpec) + Border.right(panel.borderSpec))
  contentHeight: panel.fittedContentHeight(weatherColumn.implicitHeight)

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: root.editingLocation
    onReturnRequested: root.startEditingLocation()
    onCloseRequested: root.close()
    onTabRequested: function(direction) { root.switchPanel(direction) }

    Flickable {
      id: weatherScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: weatherColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: weatherColumn
        width: weatherScroll.width
        spacing: 0

        Item {
          id: currentHeader
          width: parent.width
          height: currentConditionsRow.y + currentConditionsRow.height + root.headerBottomMargin

          Item {
            id: headerTop
            anchors.left: parent.left
            anchors.leftMargin: root.contentPadding
            anchors.right: parent.right
            anchors.rightMargin: root.contentPadding
            anchors.top: parent.top
            anchors.topMargin: root.rowPadding
            height: Math.max(
              locationRow.visible ? locationRow.implicitHeight : 0,
              locationEditorRow.visible ? locationEditorRow.implicitHeight : 0,
              currentIconLabel.implicitHeight)

            Row {
              id: locationRow
              visible: !root.editingLocation
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.columnGap

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.startEditingLocation()
              }
              HoverHandler { cursorShape: Qt.PointingHandCursor }

              TightText {
                text: (root.reportLocation || "Set location").toUpperCase()
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: root.locationSize
                font.bold: true
                font.letterSpacing: 0.8
              }
              TightText {
                text: ""
                color: Qt.darker(root.bar.foreground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: root.locationSize
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              id: locationEditorRow
              visible: root.editingLocation
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.columnGap

              TextField {
                id: locationField
                width: Style.space(240)
                enabled: !root.savingLocation
                placeholderText: "City or ZIP code"
                foreground: root.locationSaveError === "" ? root.bar.foreground : root.bar.urgent
                font.family: root.bar.fontFamily
                maximumLength: 200
                onTextChanged: {
                  if (!root.editingLocation || root.savingLocation) return
                  root.locationSuggestions = []
                  root.locationSuggestionsQuery = ""
                  root.locationSaveError = ""
                  root.scheduleGeocode()
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.cancelEditingLocation()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    if (root.suggestionIndex < root.locationSuggestions.length - 1) root.suggestionIndex++
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    if (root.suggestionIndex > 0) root.suggestionIndex--
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.commitLocation()
                    event.accepted = true
                  }
                }
              }

              Rectangle {
                width: Style.space(20)
                height: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                radius: Math.min(4, Style.cornerRadius)
                color: !root.savingLocation && clearLocationArea.containsMouse
                  ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                Text {
                  anchors.centerIn: parent
                  visible: !root.savingLocation
                  text: "✕"
                  font.family: root.bar.fontFamily
                  color: Qt.darker(root.bar.foreground, 1.35)
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  anchors.centerIn: parent
                  visible: root.savingLocation
                  text: "󰦖"
                  font.family: root.bar.fontFamily
                  color: Qt.darker(root.bar.foreground, 1.35)
                  font.pixelSize: Style.font.bodySmall
                  RotationAnimator on rotation {
                    running: root.savingLocation
                    from: 0; to: 360; duration: 800; loops: Animation.Infinite
                  }
                }
                MouseArea {
                  id: clearLocationArea
                  anchors.fill: parent
                  enabled: !root.savingLocation
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.clearLocation()
                }
              }
            }

            TightText {
              id: currentIconLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.label || "—"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: root.currentIconSize
            }
          }

          Item {
            id: currentConditionsRow
            anchors.left: parent.left
            anchors.leftMargin: root.contentPadding
            anchors.right: parent.right
            anchors.rightMargin: root.contentPadding
            y: headerTop.y + headerTop.height + root.headerRowGap
            height: Math.max(mainTemperatureLabel.implicitHeight, currentDetails.implicitHeight)

            TightText {
              id: mainTemperatureLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.current ? root.reportTempNum + "°" : "—"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: root.mainTemperatureSize
              font.weight: Font.Light
            }
            Column {
              id: currentDetails
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(root.detailsNaturalWidth,
                Math.max(Style.space(100), parent.width - mainTemperatureLabel.implicitWidth - root.itemGap * 2))
              spacing: root.currentDetailsGap

              TightText {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: root.conditionDescription || "Current Conditions"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: root.conditionSize
                font.bold: true
                elide: Text.ElideRight
              }
              TightText {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: "H:" + root.todayTemp("high") + "  L:" + root.todayTemp("low")
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: root.todayHighLowSize
                font.bold: true
              }
            }
          }
        }

        Column {
          visible: root.editingLocation && !root.savingLocation
            && (root.geocodeLoading || root.locationSuggestions.length > 0)
          width: parent.width
          spacing: 0

          Item {
            visible: root.geocodeLoading
            width: parent.width
            height: visible ? searchingRow.implicitHeight + root.rowPadding * 2 : 0

            Row {
              id: searchingRow
              anchors.centerIn: parent
              spacing: root.itemGap

              Text {
                text: "󰦖"
                color: Qt.darker(root.bar.foreground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                RotationAnimator on rotation {
                  running: root.geocodeLoading
                  from: 0; to: 360; duration: 800; loops: Animation.Infinite
                }
              }
              Text {
                text: "Searching…"
                color: Qt.darker(root.bar.foreground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }
            }
          }

          Repeater {
            model: root.locationSuggestions
            Rectangle {
              required property var modelData
              required property int index
              width: parent.width
              height: suggestionRow.implicitHeight + root.rowPadding * 2
              radius: Style.cornerRadius
              color: index === root.suggestionIndex
                ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

              Row {
                id: suggestionRow
                anchors.left: parent.left
                anchors.leftMargin: root.contentPadding
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.itemGap
                Text {
                  text: modelData.name
                  textFormat: Text.PlainText
                  color: index === root.suggestionIndex
                    ? Style.hoverStateColor(root.bar.foreground, Color.accent) : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: modelData.description
                  textFormat: Text.PlainText
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.suggestionIndex = index
                onClicked: root.pickSuggestion(modelData)
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.spacing.hairline
          color: root.bar.foreground
          opacity: 0.22
        }

        Item {
          visible: root.alertsSummary !== ""
          width: parent.width
          height: visible ? alertLabel.implicitHeight + root.rowPadding * 2 : 0
          Text {
            id: alertLabel
            anchors.left: parent.left
            anchors.leftMargin: root.contentPadding
            anchors.right: parent.right
            anchors.rightMargin: root.contentPadding
            anchors.verticalCenter: parent.verticalCenter
            text: "  " + root.alertsSummary
            textFormat: Text.PlainText
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: root.alertSize
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Rectangle {
          visible: root.alertsSummary !== ""
          width: parent.width
          height: visible ? Style.spacing.hairline : 0
          color: root.bar.foreground
          opacity: 0.22
        }

        Item {
          visible: root.hourlyForecast.length > 0
          width: parent.width
          height: visible ? hourlyRow.implicitHeight + root.rowPadding * 2 : 0
          Row {
            id: hourlyRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.columnGap
            Repeater {
              model: root.hourlyForecast
              Column {
                required property var modelData
                width: root.hourCellWidth
                spacing: root.itemGap
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.hourLabel(modelData)
                  color: Qt.darker(root.bar.foreground, 1.35)
                  font.family: root.bar.fontFamily
                  font.pixelSize: root.hourLabelSize
                  font.bold: true
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.hourIcon(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: root.hourIconSize
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.hourTemp(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: root.hourTemperatureSize
                  font.bold: true
                }
              }
            }
          }
        }

        Rectangle {
          visible: root.hourlyForecast.length > 0 && root.forecastDays.length > 0
          width: parent.width
          height: visible ? Style.spacing.hairline : 0
          color: root.bar.foreground
          opacity: 0.22
        }

        Text {
          visible: !root.current
          width: parent.width
          height: visible ? implicitHeight + root.rowPadding * 2 : 0
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: "Fetching forecast…"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Column {
          visible: root.forecastDays.length > 0
          width: parent.width
          spacing: 0
          Repeater {
            model: root.forecastDays
            Item {
              id: dayRow
              required property var modelData
              required property int index
              readonly property real low: root.dayTempNumber(modelData, "min")
              readonly property real high: root.dayTempNumber(modelData, "max")
              readonly property real rangeSpan: Math.max(1, root.forecastRangeMax - root.forecastRangeMin)
              width: parent.width
              height: Math.max(dayNameLabel.implicitHeight, dayIconLabel.implicitHeight,
                lowLabel.implicitHeight, highLabel.implicitHeight, rangeTrack.height) + root.rowPadding * 2

              Text {
                id: dayNameLabel
                anchors.left: parent.left
                anchors.leftMargin: root.contentPadding
                anchors.verticalCenter: parent.verticalCenter
                width: root.dayNameWidth
                text: root.dayName(dayRow.modelData.date).slice(0, 3).toUpperCase()
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: root.dayLabelSize
                font.bold: true
              }
              Text {
                id: dayIconLabel
                anchors.left: dayNameLabel.right
                anchors.leftMargin: root.itemGap
                anchors.verticalCenter: parent.verticalCenter
                width: root.dayIconWidth
                horizontalAlignment: Text.AlignHCenter
                text: root.dayIcon(dayRow.modelData)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: root.dayIconSize
              }
              Text {
                id: lowLabel
                anchors.left: dayIconLabel.right
                anchors.leftMargin: root.itemGap
                anchors.verticalCenter: parent.verticalCenter
                width: root.dayTempWidth
                horizontalAlignment: Text.AlignRight
                text: root.bareTempForDay(dayRow.modelData, "min")
                color: Qt.darker(root.bar.foreground, 1.55)
                font.family: root.bar.fontFamily
                font.pixelSize: root.dayTemperatureSize
                font.bold: true
              }
              Text {
                id: highLabel
                anchors.right: parent.right
                anchors.rightMargin: root.contentPadding
                anchors.verticalCenter: parent.verticalCenter
                width: root.dayTempWidth
                horizontalAlignment: Text.AlignRight
                text: root.bareTempForDay(dayRow.modelData, "max")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: root.dayTemperatureSize
                font.bold: true
              }
              Item {
                id: rangeTrack
                anchors.left: lowLabel.right
                anchors.leftMargin: root.itemGap
                anchors.right: highLabel.left
                anchors.rightMargin: root.itemGap
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(4)
                Rectangle {
                  anchors.fill: parent
                  radius: height / 2
                  color: root.bar.foreground
                  opacity: 0.08
                }
                Rectangle {
                  x: isNaN(dayRow.low) ? 0 : rangeTrack.width * (dayRow.low - root.forecastRangeMin) / dayRow.rangeSpan
                  width: isNaN(dayRow.low) || isNaN(dayRow.high) ? 0
                    : Math.max(Style.space(8), rangeTrack.width * (dayRow.high - dayRow.low) / dayRow.rangeSpan)
                  height: parent.height
                  radius: height / 2
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Color.accent }
                    GradientStop { position: 1; color: root.bar.urgent }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
