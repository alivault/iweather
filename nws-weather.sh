#!/bin/bash

# Fetch official U.S. station observations, forecasts, and alerts for a point.
# A failure produces no JSON so the QML caller keeps its Open-Meteo fallback.

set -euo pipefail

latitude=${1:?latitude required}
longitude=${2:?longitude required}
user_agent="iWeather/1.0 (+https://github.com/alivault/ali.weather)"
curl_args=(--proto '=https' --max-filesize 2097152 -fsS --max-time 8
  -H "User-Agent: $user_agent" -H "Accept: application/geo+json")

require_nws_url() {
  [[ $1 == https://api.weather.gov/* ]] || {
    printf 'Refusing unexpected NWS URL: %s\n' "$1" >&2
    return 1
  }
}

points=$(curl "${curl_args[@]}" "https://api.weather.gov/points/$latitude,$longitude")
stations_url=$(jq -er '.properties.observationStations' <<<"$points")
forecast_url=$(jq -er '.properties.forecast' <<<"$points")
hourly_url=$(jq -er '.properties.forecastHourly' <<<"$points")

require_nws_url "$stations_url"
require_nws_url "$forecast_url"
require_nws_url "$hourly_url"

stations=$(curl "${curl_args[@]}" "$stations_url")
observation=null

# NWS orders this collection by suitability for the forecast grid point. Use
# the first nearby station with a valid temperature rather than failing when
# one station has a temporarily incomplete report.
while IFS=$'\t' read -r station_id station_name; do
  [[ -n $station_id ]] || continue
  if latest=$(curl "${curl_args[@]}" "https://api.weather.gov/stations/$station_id/observations/latest" 2>/dev/null); then
    if jq -e '.properties.temperature.value | numbers' >/dev/null 2>&1 <<<"$latest"; then
      observation=$(jq -c \
        --arg station "$station_id" \
        --arg stationName "$station_name" '
          .properties | {
            station: $station,
            stationName: $stationName,
            timestamp,
            description: (.textDescription // ""),
            temperatureC: .temperature.value,
            heatIndexC: .heatIndex.value,
            windChillC: .windChill.value,
            humidity: .relativeHumidity.value,
            windSpeedKmh: .windSpeed.value
          }
        ' <<<"$latest")
      break
    fi
  fi
done < <(jq -r '.features[:6][] | [.properties.stationIdentifier, .properties.name] | @tsv' <<<"$stations")

forecast=$(curl "${curl_args[@]}" "$forecast_url")
hourly=$(curl "${curl_args[@]}" "$hourly_url")
alerts=$(curl "${curl_args[@]}" \
  "https://api.weather.gov/alerts/active?point=$latitude,$longitude" 2>/dev/null || printf '{"features":[]}')
source_url="https://forecast.weather.gov/MapClick.php?lat=$latitude&lon=$longitude"

jq -n \
  --argjson observation "$observation" \
  --argjson forecast "$(jq -c '{generatedAt: .properties.generatedAt, periods: .properties.periods}' <<<"$forecast")" \
  --argjson hourly "$(jq -c '{generatedAt: .properties.generatedAt, periods: .properties.periods}' <<<"$hourly")" \
  --argjson alerts "$(jq -c '[.features[].properties | {
    event, headline, severity, urgency,
    description: (.description // ""),
    instruction: (.instruction // ""),
    sent, expires
  }]' <<<"$alerts")" \
  --arg sourceUrl "$source_url" \
  '{observation: $observation, forecast: $forecast, hourly: $hourly, alerts: $alerts, sourceUrl: $sourceUrl}'
