// weather.json holds {"name": ..., "latitude": ..., "longitude": ...} (see
// omarchy-weather-location, which owns the format). Missing, blank, or
// unparseable means the location is auto-detected from the IP address.
function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset

    var coordinates = validCoordinates(data.latitude, data.longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: coordinates ? coordinates.latitude : null,
      longitude: coordinates ? coordinates.longitude : null
    }
  } catch (e) {
    return unset
  }
}

function validCoordinates(latitudeValue, longitudeValue) {
  if (latitudeValue === undefined || latitudeValue === null || latitudeValue === "" ||
      longitudeValue === undefined || longitudeValue === null || longitudeValue === "") return null
  if (typeof latitudeValue === "string" && latitudeValue.replace(/^\s+|\s+$/g, "") === "") return null
  if (typeof longitudeValue === "string" && longitudeValue.replace(/^\s+|\s+$/g, "") === "") return null

  var latitude = Number(latitudeValue)
  var longitude = Number(longitudeValue)
  if (!isFinite(latitude) || !isFinite(longitude)) return null
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null
  return { latitude: latitude, longitude: longitude }
}

// wttr.in path segment for a configured location: exact coordinates when
// both are present, the URL-encoded name as a fallback (hand-edited
// weather.loc files may only carry a name), empty for IP auto-detect.
function wttrLocationQuery(location, latitude, longitude) {
  var coordinates = validCoordinates(latitude, longitude)
  if (coordinates) return coordinates.latitude + "," + coordinates.longitude

  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "" : encodeURIComponent(name)
}

// Open-Meteo geocoding response → suggestion rows for the location picker.
function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var out = []
    for (var i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || !r.name) continue
      var coordinates = validCoordinates(r.latitude, r.longitude)
      if (!coordinates) continue
      var region = [r.admin1, r.country].filter(function(part) { return !!part }).join(", ")
      out.push({
        name: String(r.name),
        description: region,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function locationCommit(text, suggestions, selectedIndex, suggestionsQuery) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "") return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
  var suggestion = choices[index]
  var query = String(suggestionsQuery || "").replace(/^\s+|\s+$/g, "")
  if (suggestion && query === name) return suggestion

  return { name: name, latitude: null, longitude: null }
}

function isFutureForecastDate(dateString, todayString) {
  if (!dateString) return false
  return String(dateString).slice(0, 10) > String(todayString || "")
}

function roundedTemp(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : String(Math.round(n))
}

function celsiusToFahrenheit(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n * 9 / 5) + 32
}

function formatTemp(value, useImperial) {
  if (value === undefined || value === null || value === "") return ""
  return value + "°" + (useImperial ? "F" : "C")
}

function normalizedUnit(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
}

function localeUsesImperial(localeName) {
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
}

function countryUsesImperial(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  if (!country) return null
  if (country === "us" || country === "usa" || country === "united states" || country === "united states of america") return true
  if (country === "liberia" || country === "myanmar" || country === "burma") return true
  return false
}

function countryUsesNws(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  return country === "us" || country === "usa" || country === "united states" || country === "united states of america"
}

function currentSourceReady(reportGeneration, locationGeneration, countryName, nwsFinishedGeneration) {
  if (Number(reportGeneration) !== Number(locationGeneration)) return false
  return !countryUsesNws(countryName) || Number(nwsFinishedGeneration) === Number(locationGeneration)
}

function shouldUseImperial(unitOverride, localeName, countryName) {
  var unit = normalizedUnit(unitOverride)
  if (unit === "imperial") return true
  if (unit === "metric") return false

  var countryPreference = countryUsesImperial(countryName)
  if (countryPreference !== null) return countryPreference

  return localeUsesImperial(localeName)
}

function dayName(dateString, formatter) {
  if (!dateString) return ""
  var d = new Date(dateString + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  if (formatter) return formatter(d)
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
}

function openMeteoForecastDays(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return []

  var result = []
  for (var i = 0; i < daily.time.length && result.length < 4; ++i) {
    var date = daily.time[i]
    if (!isFutureForecastDate(date, todayString)) continue

    var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
    var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
    result.push({
      date: date,
      maxtempC: roundedTemp(maxC),
      mintempC: roundedTemp(minC),
      maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
      mintempF: roundedTemp(celsiusToFahrenheit(minC)),
      openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
    })
  }
  return result
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so the panel can use either source
// interchangeably. Open-Meteo reports metric (°C, km/h).
function openMeteoCurrentCondition(dailyForecastReport) {
  var current = dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null
  if (!current || current.temperature_2m === undefined || current.temperature_2m === null) return null
  return {
    temp_C: roundedTemp(current.temperature_2m),
    temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
    FeelsLikeC: roundedTemp(current.apparent_temperature),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
    windspeedKmph: roundedTemp(current.wind_speed_10m),
    windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
    humidity: roundedTemp(current.relative_humidity_2m),
    openMeteoWeatherCode: current.weather_code,
    isDay: current.is_day,
    source: "Open-Meteo",
    sourceTime: current.time || ""
  }
}

// Prefer a recent, measured NWS station observation for U.S. locations while
// filling fields that stations may omit from Open-Meteo. Observations older
// than 90 minutes are ignored so the model-based fallback stays fresher.
function nwsCurrentCondition(nwsReport, fallback, nowMs) {
  var obs = nwsReport && nwsReport.observation ? nwsReport.observation : null
  if (!obs || obs.temperatureC === undefined || obs.temperatureC === null) return null

  var observedAt = Date.parse(String(obs.timestamp || ""))
  var now = Number(nowMs)
  var age = now - observedAt
  if (!isFinite(observedAt) || !isFinite(now) || age < -5 * 60 * 1000 || age > 90 * 60 * 1000) return null

  var tempC = Number(obs.temperatureC)
  if (!isFinite(tempC)) return null
  var feelsC = obs.heatIndexC
  if (feelsC === undefined || feelsC === null) feelsC = obs.windChillC
  if (feelsC === undefined || feelsC === null) feelsC = fallback ? fallback.FeelsLikeC : tempC

  var windKmh = obs.windSpeedKmh
  if (windKmh === undefined || windKmh === null) windKmh = fallback ? fallback.windspeedKmph : ""
  var humidity = obs.humidity
  if (humidity === undefined || humidity === null) humidity = fallback ? fallback.humidity : ""

  return {
    temp_C: roundedTemp(tempC),
    temp_F: roundedTemp(celsiusToFahrenheit(tempC)),
    FeelsLikeC: roundedTemp(feelsC),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(feelsC)),
    windspeedKmph: roundedTemp(windKmh),
    windspeedMiles: roundedTemp(Number(windKmh) * 0.621371),
    humidity: roundedTemp(humidity),
    openMeteoWeatherCode: fallback ? fallback.openMeteoWeatherCode : null,
    isDay: fallback ? fallback.isDay : null,
    source: "NWS",
    sourceTime: obs.timestamp || "",
    sourceStation: obs.stationName || obs.station || ""
  }
}

function nwsIconForForecast(description, night) {
  var text = String(description || "").toLowerCase()
  if (/thunder/.test(text)) return iconForCode(389, !!night)
  if (/snow|sleet|ice|freez/.test(text)) return iconForCode(338, !!night)
  if (/rain|shower|drizzle/.test(text)) return iconForCode(308, !!night)
  if (/fog|mist|haze/.test(text)) return iconForCode(143, !!night)
  if (/partly|mostly sunny|mostly clear/.test(text)) return iconForCode(116, !!night)
  if (/cloud|overcast/.test(text)) return iconForCode(119, !!night)
  if (/sun|clear|hot/.test(text)) return iconForCode(113, !!night)
  return iconForCode(119, !!night)
}

// Convert NWS 12-hour day/night periods into the same daily shape used by the
// existing three-day forecast row.
function nwsForecastDays(nwsReport, todayString) {
  var periods = nwsReport && nwsReport.forecast && nwsReport.forecast.periods
    ? nwsReport.forecast.periods : []
  var grouped = {}
  var order = []

  for (var i = 0; i < periods.length; ++i) {
    var period = periods[i]
    var date = String(period.startTime || "").slice(0, 10)
    if (!isFutureForecastDate(date, todayString)) continue
    if (!grouped[date]) {
      grouped[date] = { date: date, maxtempC: "", mintempC: "", maxtempF: "", mintempF: "", nwsForecast: "" }
      order.push(date)
    }

    var day = grouped[date]
    var value = Number(period.temperature)
    if (!isFinite(value)) continue
    var c = String(period.temperatureUnit || "F").toUpperCase() === "C" ? value : (value - 32) * 5 / 9
    var f = String(period.temperatureUnit || "F").toUpperCase() === "F" ? value : celsiusToFahrenheit(c)
    if (period.isDaytime) {
      day.maxtempC = roundedTemp(c)
      day.maxtempF = roundedTemp(f)
      day.nwsForecast = period.shortForecast || day.nwsForecast
    } else {
      day.mintempC = roundedTemp(c)
      day.mintempF = roundedTemp(f)
      if (!day.nwsForecast) day.nwsForecast = period.shortForecast || ""
    }
  }

  var result = []
  for (var j = 0; j < order.length && result.length < 4; ++j) {
    var candidate = grouped[order[j]]
    if (candidate.maxtempC !== "" || candidate.mintempC !== "") result.push(candidate)
  }
  return result
}

function nwsHourlyForecast(nwsReport, nowMs) {
  var periods = nwsReport && nwsReport.hourly && nwsReport.hourly.periods
    ? nwsReport.hourly.periods : []
  var result = []
  for (var i = 0; i < periods.length && result.length < 6; ++i) {
    var period = periods[i]
    var timeMs = Date.parse(String(period.startTime || ""))
    if (!isFinite(timeMs) || timeMs <= Number(nowMs)) continue
    var value = Number(period.temperature)
    if (!isFinite(value)) continue
    var c = String(period.temperatureUnit || "F").toUpperCase() === "C" ? value : (value - 32) * 5 / 9
    var f = String(period.temperatureUnit || "F").toUpperCase() === "F" ? value : celsiusToFahrenheit(c)
    result.push({
      time: period.startTime,
      tempC: roundedTemp(c),
      tempF: roundedTemp(f),
      nwsForecast: period.shortForecast || "",
      isDay: period.isDaytime ? 1 : 0
    })
  }
  return result
}

function openMeteoHourlyForecast(dailyForecastReport, nowMs) {
  var hourly = dailyForecastReport && dailyForecastReport.hourly ? dailyForecastReport.hourly : null
  if (!hourly || !hourly.time) return []
  var result = []
  for (var i = 0; i < hourly.time.length && result.length < 6; ++i) {
    var timeMs = Date.parse(String(hourly.time[i] || ""))
    if (!isFinite(timeMs) || timeMs <= Number(nowMs)) continue
    var tempC = hourly.temperature_2m ? hourly.temperature_2m[i] : null
    if (tempC === undefined || tempC === null) continue
    result.push({
      time: hourly.time[i],
      tempC: roundedTemp(tempC),
      tempF: roundedTemp(celsiusToFahrenheit(tempC)),
      openMeteoWeatherCode: hourly.weather_code ? hourly.weather_code[i] : null,
      isDay: hourly.is_day ? hourly.is_day[i] : 1
    })
  }
  return result
}

function hourlyForecast(nwsReport, dailyForecastReport, nowMs) {
  var hours = nwsHourlyForecast(nwsReport, nowMs)
  return hours.length > 0 ? hours : openMeteoHourlyForecast(dailyForecastReport, nowMs)
}

function weatherDescription(current, nwsReport) {
  var obs = nwsReport && nwsReport.observation ? String(nwsReport.observation.description || "") : ""
  if (obs) return obs
  var periods = nwsReport && nwsReport.hourly && nwsReport.hourly.periods ? nwsReport.hourly.periods : []
  if (periods.length && periods[0].shortForecast) return String(periods[0].shortForecast)
  var code = current && current.openMeteoWeatherCode !== undefined ? Number(current.openMeteoWeatherCode) : -1
  if (code === 0) return "Clear"
  if (code === 1) return "Mostly Clear"
  if (code === 2) return "Partly Cloudy"
  if (code === 3) return "Overcast"
  if (code === 45 || code === 48) return "Foggy"
  if (code >= 95) return "Thunderstorms"
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "Rain Showers"
  if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return "Snow Showers"
  return ""
}

function todayHighLow(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return null
  for (var i = 0; i < daily.time.length; ++i) {
    if (String(daily.time[i]).slice(0, 10) !== String(todayString)) continue
    var highC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : null
    var lowC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : null
    return {
      highC: roundedTemp(highC),
      lowC: roundedTemp(lowC),
      highF: roundedTemp(celsiusToFahrenheit(highC)),
      lowF: roundedTemp(celsiusToFahrenheit(lowC))
    }
  }
  return null
}

function alertSummary(alerts) {
  var list = alerts || []
  if (!list.length) return ""
  var first = list[0] && (list[0].event || list[0].headline) ? String(list[0].event || list[0].headline) : "Weather Alert"
  return list.length > 1 ? first + " & " + (list.length - 1) + " More" : first
}

function currentIcon(current, fallback) {
  if (!current) return fallback || ""
  if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0)
  if (current.weatherCode !== undefined && current.weatherCode !== null)
    return iconForCode(current.weatherCode, false)
  return fallback || ""
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
function provisionalCurrentIcon(current, resolvedIcon) {
  return resolvedIcon || currentIcon(current, "")
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
  return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr"
}

function wttrNextForecastDays(report, todayString) {
  var days = report && report.weather ? report.weather : []
  var result = []
  for (var i = 0; i < days.length && result.length < 3; ++i) {
    if (isFutureForecastDate(days[i].date, todayString)) result.push(days[i])
  }
  return result
}

function buildForecastDays(report, dailyForecastReport, nwsReport, todayString) {
  var days = nwsForecastDays(nwsReport, todayString)
  if (days.length > 0) return days
  days = openMeteoForecastDays(dailyForecastReport, todayString)
  return days.length > 0 ? days : wttrNextForecastDays(report, todayString)
}

function bareTempForDay(day, kind, useImperial) {
  if (!day) return ""
  var v = useImperial
    ? (kind === "max" ? day.maxtempF : day.mintempF)
    : (kind === "max" ? day.maxtempC : day.mintempC)
  if (v === undefined || v === null || v === "") return ""
  return v + "°"
}

function dayIcon(day) {
  if (!day) return ""
  if (day.nwsForecast) return nwsIconForForecast(day.nwsForecast, false)
  if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(day.openMeteoWeatherCode)
  if (!day.hourly || day.hourly.length === 0) return ""

  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; ++i) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) {
      bestDist = dist
      best = day.hourly[i]
    }
  }
  return iconForCode(best.weatherCode, false)
}

function hourIcon(hour) {
  if (!hour) return ""
  if (hour.nwsForecast) return nwsIconForForecast(hour.nwsForecast, Number(hour.isDay) === 0)
  if (hour.openMeteoWeatherCode !== undefined && hour.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(hour.openMeteoWeatherCode, Number(hour.isDay) === 0)
  return ""
}

function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return iconForCode(113, night)
  if (c === 1 || c === 2) return iconForCode(116, night)
  if (c === 3) return iconForCode(119, night)
  if (c === 45 || c === 48) return iconForCode(143, night)
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return iconForCode(266, night)
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return iconForCode(308, night)
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return iconForCode(338, night)
  if (c === 95 || c === 96 || c === 99) return iconForCode(389, night)
  return iconForCode(119, night)
}

function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "" : ""
    case 116: return night ? "" : ""
    case 119: case 122: return ""
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "" : ""
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
    case 200: case 386: case 389: case 392: case 395: return ""
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
    case 329: case 332: case 335: case 338: case 371: return ""
    default: return ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLocationFile: parseLocationFile,
    validCoordinates: validCoordinates,
    wttrLocationQuery: wttrLocationQuery,
    parseGeocodingResults: parseGeocodingResults,
    locationCommit: locationCommit,
    isFutureForecastDate: isFutureForecastDate,
    roundedTemp: roundedTemp,
    celsiusToFahrenheit: celsiusToFahrenheit,
    formatTemp: formatTemp,
    normalizedUnit: normalizedUnit,
    localeUsesImperial: localeUsesImperial,
    countryUsesImperial: countryUsesImperial,
    countryUsesNws: countryUsesNws,
    currentSourceReady: currentSourceReady,
    shouldUseImperial: shouldUseImperial,
    dayName: dayName,
    openMeteoForecastDays: openMeteoForecastDays,
    openMeteoCurrentCondition: openMeteoCurrentCondition,
    nwsCurrentCondition: nwsCurrentCondition,
    nwsForecastDays: nwsForecastDays,
    nwsIconForForecast: nwsIconForForecast,
    nwsHourlyForecast: nwsHourlyForecast,
    openMeteoHourlyForecast: openMeteoHourlyForecast,
    hourlyForecast: hourlyForecast,
    weatherDescription: weatherDescription,
    todayHighLow: todayHighLow,
    alertSummary: alertSummary,
    currentIcon: currentIcon,
    provisionalCurrentIcon: provisionalCurrentIcon,
    weatherResponseCompletesSave: weatherResponseCompletesSave,
    wttrNextForecastDays: wttrNextForecastDays,
    buildForecastDays: buildForecastDays,
    bareTempForDay: bareTempForDay,
    dayIcon: dayIcon,
    hourIcon: hourIcon,
    iconForOpenMeteoCode: iconForOpenMeteoCode,
    iconForCode: iconForCode
  }
}
