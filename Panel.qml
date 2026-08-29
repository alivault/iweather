import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ali.weather"
  ipcTarget: "ali.weather"
  manageIpc: false

  property var anchorItem: null
  readonly property string nwsScriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("nws-weather.sh")).replace(/^file:\/\//, ""))

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    locationFile.reload()
    root.refresh()
  }

  function openFromHotkey() {
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
  property int reportGeneration: -1
  property var dailyForecastReport: null
  property string wttrLocation: ""

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({ name: "", latitude: null, longitude: null })
  readonly property string configuredLocation: configuredLocationState.name
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)
  property int locationGeneration: 0

  // Keep the previous report visible while the new location loads. The
  // editor remains open with a spinner, so stale data is never presented
  // under the newly configured location label.
  onLocationQueryChanged: {
    locationGeneration++
    if (savingLocation) savingLocationQueryStarted = true
    nwsReport = null
    nwsFinishedGeneration = -1
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    nwsProc.running = false
    locationProc.running = false
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
  property bool geocodeLoading: false
  property string locationSuggestionsQuery: ""
  property string locationSaveError: ""

  // Shared hero/bar icon state, updated with each successful weather response.
  property string label: ""
  property var nwsReport: null
  property int nwsFinishedGeneration: -1

  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property var configuredCoordinates: Model.validCoordinates(configuredLocationState.latitude, configuredLocationState.longitude)
  readonly property bool hasConfiguredCoordinates: configuredCoordinates !== null
  property double currentTimeMs: Date.now()
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  readonly property var wttrCurrent: (report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : null
  readonly property var nwsCurrent: Model.nwsCurrentCondition(nwsReport, openMeteoCurrent, currentTimeMs)
  readonly property bool currentSourceReady: Model.currentSourceReady(
    reportGeneration, locationGeneration, reportCountry, nwsFinishedGeneration)
  readonly property var current: currentSourceReady ? (nwsCurrent || openMeteoCurrent || wttrCurrent) : null
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  readonly property var forecastDays: buildForecastDays()
  readonly property var hourlyForecast: Model.hourlyForecast(nwsReport, dailyForecastReport, currentTimeMs)
  readonly property var todayHighLow: Model.todayHighLow(dailyForecastReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  readonly property var activeAlerts: nwsReport && nwsReport.alerts ? nwsReport.alerts : []
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""

  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.min(1440, Math.max(1,
    parseInt(setting("refreshMinutes", 15), 10) || 15))

  readonly property string reportLocation:  configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  readonly property string reportTempNum:   current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  readonly property string tempUnit:        "°" + (useImperial ? "F" : "C")
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
    if (!forecastProc.running) {
      forecastProc.requestGeneration = root.locationGeneration
      forecastProc.running = true
    }
    if (root.locationQuery === "" && !locationProc.running) locationProc.running = true
    // With stored coordinates this fetches open-meteo right away — no need
    // to wait for the slow wttr response. Without them it's a no-op until
    // wttr reports the detected area.
    refreshDailyForecast(null)
    if (root.reportGeneration === root.locationGeneration && Model.countryUsesNws(root.reportCountry))
      refreshNws(null)
  }

  function refreshNws(sourceReport) {
    if (nwsProc.running) return

    var sourceArea = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0]
      ? sourceReport.nearest_area[0] : root.areaInfo
    var country = sourceArea && sourceArea.country && sourceArea.country[0]
      ? sourceArea.country[0].value : root.reportCountry
    if (!Model.countryUsesNws(country)) {
      root.nwsReport = null
      root.nwsFinishedGeneration = root.locationGeneration
      return
    }

    var coordinates = Model.validCoordinates(root.configuredLocationState.latitude, root.configuredLocationState.longitude)
    if (!coordinates) {
      if (!sourceArea) return
      coordinates = Model.validCoordinates(sourceArea.latitude, sourceArea.longitude)
    }
    if (!coordinates) {
      root.nwsFinishedGeneration = root.locationGeneration
      return
    }

    nwsProc.requestGeneration = root.locationGeneration
    nwsProc.command = [root.nwsScriptPath,
      String(coordinates.latitude), String(coordinates.longitude)]
    nwsProc.running = true
  }

  function refreshDailyForecast(sourceReport) {
    if (dailyForecastProc.running) return

    var coordinates = Model.validCoordinates(root.configuredLocationState.latitude, root.configuredLocationState.longitude)
    if (!coordinates) {
      var area = sourceReport && sourceReport.nearest_area && sourceReport.nearest_area[0] ? sourceReport.nearest_area[0] : root.areaInfo
      if (!area) return
      coordinates = Model.validCoordinates(area.latitude, area.longitude)
    }
    if (!coordinates) return

    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(coordinates.latitude))
      + "&longitude=" + encodeURIComponent(String(coordinates.longitude))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&hourly=temperature_2m,weather_code,is_day"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=5"
      + "&timezone=auto"
    dailyForecastProc.command = ["curl", "--proto", "=https", "--max-filesize", "2097152",
      "-fsS", "--max-time", "5", url]
    dailyForecastProc.requestGeneration = root.locationGeneration
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
    locationSuggestionsQuery = ""
    locationSaveError = ""
    geocodeLoading = false
    suggestionIndex = 0
    Qt.callLater(function() {
      weatherView.beginLocationEdit(root.configuredLocation)
    })
  }

  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    locationSuggestionsQuery = ""
    locationSaveError = ""
    geocodePendingQuery = ""
    geocodeLoading = false
    geocodeDebounce.stop()
    Qt.callLater(function() { weatherView.focusPanel() })
  }

  function commitLocation() {
    var location = Model.locationCommit(weatherView.locationText, locationSuggestions,
      suggestionIndex, locationSuggestionsQuery)
    if (location.name === "") {
      clearLocation()
      return
    }
    savingLocation = true
    savingLocationQueryStarted = false
    locationSaveError = ""
    persistLocation(location.name, location.latitude, location.longitude)
  }

  function clearLocation() {
    savingLocation = true
    savingLocationQueryStarted = false
    locationSaveError = ""
    persistLocation("", null, null)
    wttrLocation = ""
  }

  function pickSuggestion(suggestion) {
    if (!suggestion) return
    savingLocation = true
    savingLocationQueryStarted = false
    locationSaveError = ""
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  function finishSavingLocation() {
    if (savingLocation && savingLocationQueryStarted) cancelEditingLocation()
  }

  function persistLocation(name, latitude, longitude) {
    var coordinates = Model.validCoordinates(latitude, longitude)
    locationSaveProc.targetQuery = Model.wttrLocationQuery(name,
      coordinates ? coordinates.latitude : null, coordinates ? coordinates.longitude : null)
    if (name && coordinates)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name,
        coordinates.latitude + "," + coordinates.longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode() {
    var query = weatherView.locationText.trim().slice(0, 200)
    if (query.length < 2) {
      locationSuggestions = []
      geocodePendingQuery = ""
      geocodeLoading = false
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    if (geocodePendingQuery === "") return
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "--proto", "=https", "--max-filesize", "2097152",
      "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  function scheduleGeocode() {
    var query = weatherView.locationText.trim().slice(0, 200)
    if (query.length < 2) {
      geocodePendingQuery = ""
      geocodeLoading = false
      geocodeDebounce.stop()
      return
    }
    geocodePendingQuery = query
    geocodeLoading = true
    geocodeDebounce.restart()
  }

  function buildForecastDays() {
    return Model.buildForecastDays(report, dailyForecastReport, nwsReport, Qt.formatDate(new Date(), "yyyy-MM-dd"))
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

  Process {
    id: forecastProc
    property int requestGeneration: -1
    command: ["curl", "--proto", "=https", "--max-filesize", "2097152",
      "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (forecastProc.requestGeneration !== root.locationGeneration) return
        var raw = String(text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.report = parsed
          root.reportGeneration = forecastProc.requestGeneration
          if (!root.hasConfiguredCoordinates)
            root.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
          root.forecastRetries = 0
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation()
          // Stored coordinates already drove the fast open-meteo fetch from
          // refresh(); only auto-detect needs the area wttr reported.
          if (!root.hasConfiguredCoordinates)
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
    onTriggered: {
      if (forecastProc.running) return
      forecastProc.requestGeneration = root.locationGeneration
      forecastProc.running = true
    }
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
    property int requestGeneration: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (dailyForecastProc.requestGeneration !== root.locationGeneration) return
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
    property int requestGeneration: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (nwsProc.requestGeneration !== root.locationGeneration) return
        var raw = String(text || "").trim()
        if (!raw) {
          root.nwsFinishedGeneration = nwsProc.requestGeneration
          return
        }
        try {
          root.nwsReport = JSON.parse(raw)
          root.label = Model.currentIcon(root.current, root.label)
        } catch (e) {
          // Keep the last NWS report and continue using Open-Meteo as needed.
        }
        root.nwsFinishedGeneration = nwsProc.requestGeneration
      }
    }
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var currentQuery = root.editingLocation ? weatherView.locationText.trim().slice(0, 200) : ""
        if (currentQuery !== "" && currentQuery === root.geocodeActiveQuery) {
          root.locationSuggestions = Model.parseGeocodingResults(text)
          root.locationSuggestionsQuery = currentQuery
          root.suggestionIndex = 0
        }
        if (root.geocodePendingQuery !== root.geocodeActiveQuery) {
          Qt.callLater(root.startGeocode)
        } else {
          root.geocodeLoading = false
        }
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
    property string targetQuery: ""
    onExited: function(exitCode) {
      if (!root.savingLocation) return
      if (exitCode !== 0) {
        root.savingLocation = false
        root.savingLocationQueryStarted = false
        root.locationSaveError = "Could not save location"
        return
      }

      // FileView handles changed locations. Explicitly refresh here too so
      // saving the already-active location cannot strand the spinner.
      locationFile.reload()
      if (locationSaveProc.targetQuery === root.locationQuery && !root.savingLocationQueryStarted) {
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

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.currentTimeMs = Date.now()
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

  WeatherView {
    id: weatherView
    weather: root
  }

}
