import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.weather"
  ipcTarget: "omarchy.weather"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    locationFile.reload()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    locationFile.reload()
    root.refresh()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLocation) root.cancelEditingLocation()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  property var dailyForecastReport: null
  property string wttrLocation: ""

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)

  // Keep the previous report visible while the new location loads. The
  // editor remains open with a spinner, so stale data is never presented
  // under the newly configured location label.
  onLocationQueryChanged: {
    if (savingLocation) savingLocationQueryStarted = true
    nwsReport = null
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    Qt.callLater(refresh)
  }

  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.configuredLocationState = Model.parseLocationFile(text())
    onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
  }

  // Finalized layout values from the interactive design pass.
  readonly property int panelPadding: 16
  readonly property int contentPadding: 0
  readonly property int rowPadding: 8
  readonly property int headerRowGap: 8
  readonly property int currentDetailsGap: 8
  readonly property int headerBottomMargin: 20
  readonly property int itemGap: 4
  readonly property int columnGap: 8
  readonly property int cellPadding: 8

  readonly property int mainTemperatureSize: 52
  readonly property int currentIconSize: 24
  readonly property int locationSize: 14
  readonly property int conditionSize: 14
  readonly property int todayHighLowSize: 12
  readonly property int alertSize: 12
  readonly property int hourLabelSize: 12
  readonly property int hourIconSize: 24
  readonly property int hourTemperatureSize: 14
  readonly property int dayLabelSize: 14
  readonly property int dayIconSize: 24
  readonly property int dayTemperatureSize: 14

  FontMetrics {
    id: locationMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.locationSize
    font.bold: true
  }
  FontMetrics {
    id: mainTemperatureMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.mainTemperatureSize
    font.weight: Font.Light
  }
  FontMetrics {
    id: conditionMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.conditionSize
    font.bold: true
  }
  FontMetrics {
    id: highLowMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.todayHighLowSize
    font.bold: true
  }
  FontMetrics {
    id: hourLabelMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.hourLabelSize
    font.bold: true
  }
  FontMetrics {
    id: hourTemperatureMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.hourTemperatureSize
    font.bold: true
  }
  FontMetrics {
    id: dayLabelMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.dayLabelSize
    font.bold: true
  }
  FontMetrics {
    id: dayTemperatureMetrics
    font.family: root.bar.fontFamily
    font.pixelSize: root.dayTemperatureSize
    font.bold: true
  }

  readonly property real hourCellWidth: Math.ceil(Math.max(
    hourLabelMetrics.advanceWidth("10 PM"),
    hourTemperatureMetrics.advanceWidth("-100°"),
    root.hourIconSize
  ) + root.cellPadding * 2)
  readonly property real hourlyNaturalWidth: root.hourCellWidth * 6 + root.columnGap * 5
  readonly property real detailsNaturalWidth: Math.min(Style.space(320), Math.max(
    conditionMetrics.advanceWidth(root.conditionDescription || "Current Conditions"),
    highLowMetrics.advanceWidth("H:" + root.todayTemp("high") + "  L:" + root.todayTemp("low"))
  ))
  readonly property real headerNaturalWidth: Math.max(
    locationMetrics.advanceWidth((root.reportLocation || "").toUpperCase())
      + root.locationSize + root.itemGap + root.currentIconSize,
    mainTemperatureMetrics.advanceWidth(root.current ? root.reportTempNum + "°" : "—")
      + root.itemGap * 2 + root.detailsNaturalWidth,
    Style.space(280)
  )
  readonly property real dayNameWidth: Math.ceil(Math.max(
    dayLabelMetrics.advanceWidth("WED"), dayLabelMetrics.advanceWidth("THU")))
  readonly property real dayTempWidth: Math.ceil(dayTemperatureMetrics.advanceWidth("-100°"))
  readonly property real dayIconWidth: Math.ceil(root.dayIconSize * 1.75)
  readonly property real rangeNaturalWidth: Math.max(Style.space(120), root.hourCellWidth * 2.3)
  readonly property real dailyNaturalWidth: root.dayNameWidth + root.dayIconWidth
    + root.dayTempWidth * 2 + root.rangeNaturalWidth + root.itemGap * 4
  readonly property real naturalInnerWidth: Math.ceil(Math.max(
    root.headerNaturalWidth,
    root.hourlyForecast.length > 0 ? root.hourlyNaturalWidth : 0,
    root.forecastDays.length > 0 ? root.dailyNaturalWidth : 0,
    Style.space(280)
  ) + root.contentPadding * 2)

  // The first read can race shell startup (observed sporadically), leaving a
  // stored location unhonored until the next file write. One delayed reload
  // self-corrects; if the first read was fine it's a no-op, since identical
  // state doesn't change locationQuery and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: {
      locationFile.reload()
      root.refresh()
    }
  }

  property int forecastRetries: 0
  property int dailyForecastRetries: 0

  // Click-to-edit state for the location label.
  property bool editingLocation: false
  property bool savingLocation: false
  property bool savingLocationQueryStarted: false
  property var locationSuggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""

  // Shared hero/bar icon state, updated with each successful weather response.
  property string label: ""
  property var nwsReport: null

  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var wttrCurrent: (report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : null
  readonly property var nwsCurrent: Model.nwsCurrentCondition(nwsReport, openMeteoCurrent, Date.now())
  readonly property var current: nwsCurrent || openMeteoCurrent || wttrCurrent
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()
  readonly property var hourlyForecast: Model.hourlyForecast(nwsReport, dailyForecastReport, Date.now())
  readonly property var todayHighLow: Model.todayHighLow(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  readonly property var activeAlerts: nwsReport && nwsReport.alerts ? nwsReport.alerts : []
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""

  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property string reportLocation:  configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
  readonly property string reportFeels:     current ? formatTemp(useImperial ? current.FeelsLikeF : current.FeelsLikeC) : ""
  readonly property string reportWind:      current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  readonly property string reportHumidity:  current ? (current.humidity + "%") : ""
  readonly property string reportSource: current && current.source
    ? (current.source === "NWS" && current.sourceStation ? "NWS · " + current.sourceStation : current.source)
    : (wttrCurrent ? "wttr.in" : "")
  readonly property string conditionDescription: Model.weatherDescription(current, nwsReport)
  readonly property string alertsSummary: Model.alertSummary(activeAlerts)
  readonly property real forecastRangeMin: forecastRange("min")
  readonly property real forecastRangeMax: forecastRange("max")

  function refresh() {
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    dailyForecastRetries = 0
    if (!forecastProc.running) forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    // With stored coordinates this fetches open-meteo right away — no need
    // to wait for the slow wttr response. Without them it's a no-op until
    // wttr reports the detected area.
    refreshDailyForecast(null)
    if (Model.countryUsesNws(root.reportCountry)) refreshNws(null)
  }

  function refreshNws(sourceReport) {
    if (nwsProc.running) return

    var sourceArea = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0]
      ? sourceReport.nearest_area[0] : root.areaInfo
    var country = sourceArea && sourceArea.country && sourceArea.country[0]
      ? sourceArea.country[0].value : root.reportCountry
    if (!Model.countryUsesNws(country)) {
      root.nwsReport = null
      return
    }

    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      if (!sourceArea) return
      lat = parseFloat(String(sourceArea.latitude || ""))
      lon = parseFloat(String(sourceArea.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return

    nwsProc.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/ali.weather/nws-weather.sh", String(lat), String(lon)]
    nwsProc.running = true
  }

  function refreshDailyForecast(sourceReport) {
    if (dailyForecastProc.running) return

    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      lat = parseFloat(String(area.latitude || ""))
      lon = parseFloat(String(area.longitude || ""))
    }
    if (isNaN(lat) || isNaN(lon)) return

    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&hourly=temperature_2m,weather_code,is_day"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=5"
      + "&timezone=auto"
    dailyForecastProc.command = ["curl", "--proto", "=https", "--max-filesize", "2097152",
      "-fsS", "--max-time", "5", url]
    dailyForecastProc.running = true
  }

  // ---- Location editing. Clicking the location label swaps it for a city or
  //      ZIP search field; picking a geocoded suggestion persists its name and
  //      coordinates through omarchy-weather-location. An empty commit returns
  //      to automatic IP-based location detection.
  function startEditingLocation() {
    editingLocation = true
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
    Qt.callLater(function() {
      locationField.text = root.configuredLocation
      locationField.selectAll()
      locationField.forceActiveFocus()
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    geocodeDebounce.stop()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitLocation() {
    var location = Model.locationCommit(locationField.text, locationSuggestions, suggestionIndex)
    if (location.name === "") {
      clearLocation()
      return
    }
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    persistLocation(location.name, location.latitude, location.longitude)
  }

  function clearLocation() {
    persistLocation("", null, null)
    wttrLocation = ""
    cancelEditingLocation()
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode() {
    var query = locationField.text.trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "--proto", "=https", "--max-filesize", "2097152",
      "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  function buildForecastDays() {
    return Model.buildForecastDays(report, dailyForecastReport, nwsReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function openMeteoForecastDays() {
    return Model.openMeteoForecastDays(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function wttrNextForecastDays() {
    return Model.wttrNextForecastDays(report, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function isFutureForecastDate(dateString) {
    return Model.isFutureForecastDate(dateString, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  }

  function roundedTemp(value) {
    return Model.roundedTemp(value)
  }

  function celsiusToFahrenheit(value) {
    return Model.celsiusToFahrenheit(value)
  }

  function formatTemp(value) {
    return Model.formatTemp(value, useImperial)
  }

  function dayName(dateString) {
    return Model.dayName(dateString, function(date) { return Qt.formatDate(date, "dddd") })
  }

  // Bare degree value (no unit letter), used in the forecast row.
  function bareTempForDay(day, kind) {
    return Model.bareTempForDay(day, kind, useImperial)
  }

  // Representative icon for a forecast day: the hourly entry nearest noon.
  function dayIcon(day) {
    return Model.dayIcon(day)
  }

  function hourIcon(hour) {
    return Model.hourIcon(hour)
  }

  function hourTemp(hour) {
    if (!hour) return ""
    var value = useImperial ? hour.tempF : hour.tempC
    return value === undefined || value === null || value === "" ? "" : value + "°"
  }

  function hourLabel(hour) {
    if (!hour || !hour.time) return ""
    return Qt.formatTime(new Date(hour.time), "h AP")
  }

  function todayTemp(kind) {
    if (!todayHighLow) return "—"
    var key = kind + (useImperial ? "F" : "C")
    var value = todayHighLow[key]
    return value === undefined || value === null || value === "" ? "—" : value + "°"
  }

  function dayTempNumber(day, kind) {
    if (!day) return NaN
    var key = kind === "max" ? (useImperial ? "maxtempF" : "maxtempC") : (useImperial ? "mintempF" : "mintempC")
    return parseFloat(String(day[key]))
  }

  function forecastRange(kind) {
    var best = kind === "min" ? Infinity : -Infinity
    for (var i = 0; i < forecastDays.length; ++i) {
      var low = dayTempNumber(forecastDays[i], "min")
      var high = dayTempNumber(forecastDays[i], "max")
      if (kind === "min") {
        if (!isNaN(low)) best = Math.min(best, low)
        if (!isNaN(high)) best = Math.min(best, high)
      } else {
        if (!isNaN(low)) best = Math.max(best, low)
        if (!isNaN(high)) best = Math.max(best, high)
      }
    }
    return isFinite(best) ? best : 0
  }

  function iconForOpenMeteoCode(code) {
    return Model.iconForOpenMeteoCode(code)
  }

  // Mirrors omarchy-weather-icon's wttr.in code → nerd-font glyph mapping.
  function iconForCode(code, night) {
    return Model.iconForCode(code, night)
  }

  Process {
    id: forecastProc
    command: ["curl", "--proto", "=https", "--max-filesize", "2097152",
      "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.report = parsed
          if (!root.hasConfiguredCoordinates)
            root.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
          root.forecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation()
          // Stored coordinates already drove the fast open-meteo fetch from
          // refresh(); only auto-detect needs the area wttr reported.
          if (isNaN(parseFloat(String(root.configuredLocationState.latitude))))
            root.refreshDailyForecast(parsed)
          root.refreshNws(parsed)
        } catch (e) {
          // Keep last-good report visible, but try again shortly.
          root.scheduleForecastRetry()
        }
      }
    }
  }

  // wttr.in can be slow or flaky, especially for a location it hasn't
  // cached yet. Retry a few times before leaving it to the refresh timer.
  function scheduleForecastRetry() {
    if (forecastRetries >= 3) return
    forecastRetries++
    forecastRetryTimer.restart()
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running) forecastProc.running = true
  }

  // With configured coordinates this fetch is the only thing that updates the
  // bar icon, so a dropped response (e.g. waking before the network is back)
  // must retry rather than wait out the refresh timer with a stale icon.
  function scheduleDailyForecastRetry() {
    if (dailyForecastRetries >= 3) return
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }

  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }

  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleDailyForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          var parsedCurrent = Model.openMeteoCurrentCondition(parsed)
          root.dailyForecastReport = parsed
          root.label = Model.currentIcon(parsedCurrent, root.label)
          root.dailyForecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
            root.finishSavingLocation()
        } catch (e) {
          // Keep last-good daily forecast visible, but try again shortly.
          root.scheduleDailyForecastRetry()
        }
      }
    }
  }

  Process {
    id: nwsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        try {
          root.nwsReport = JSON.parse(raw)
          root.label = Model.currentIcon(root.current, root.label)
        } catch (e) {
          // Keep the last NWS report and continue using Open-Meteo as needed.
        }
      }
    }
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  Process {
    id: locationSaveProc
    onExited: function(exitCode) {
      if (exitCode !== 0 || !root.savingLocation) return

      // FileView handles changed locations. Explicitly refresh here too so
      // saving the already-active location cannot strand the spinner.
      locationFile.reload()
      if (!root.savingLocationQueryStarted) {
        root.savingLocationQueryStarted = true
        root.forecastRetries = 0
        root.dailyForecastRetries = 0
        forecastProc.running = false
        dailyForecastProc.running = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: locationProc
    command: ["curl", "--proto", "=https", "--max-filesize", "65536",
      "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        root.wttrLocation = raw.split(",")[0]
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function edit(): void { root.openFromHotkey(); root.startEditingLocation() }
  }

  KeyboardPanel {
    id: panel
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

          // Current conditions header.
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
                HoverHandler {
                  cursorShape: Qt.PointingHandCursor
                }

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
                  foreground: root.bar.foreground
                  font.family: root.bar.fontFamily
                  onTextChanged: if (root.editingLocation && !root.savingLocation) geocodeDebounce.restart()

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
                    rotation: 0
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

          // Geocoding suggestions expand directly under the location header.
          Column {
            visible: root.editingLocation && !root.savingLocation && root.locationSuggestions.length > 0
            width: parent.width
            spacing: 0

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

          // Six upcoming hourly periods.
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

          // Four-day forecast with relative low/high range bars.
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

}
