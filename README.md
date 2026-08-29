# ali.weather

A cloned Omarchy weather bar widget with Open-Meteo forecasts, wttr.in
location detection, and U.S. National Weather Service observations and alerts.

## Architecture

- `BarWidget.qml` mounts the bar pill and lazy-loads the panel.
- `Panel.qml` coordinates location state, remote requests, and popup presentation.
- `Model.js` contains pure parsing, normalization, and formatting functions.
- `nws-weather.sh` combines the NWS point, station, forecast, and alert APIs.

Location state is owned by `omarchy-weather-location` and stored under
`~/.local/state/omarchy/settings/weather.json`. Automatic location detection
sends the public IP address to wttr.in. Configured coordinates are sent to
wttr.in, Open-Meteo, and, for U.S. locations, weather.gov.

## Checks

Run all dependency-free checks with:

```bash
./check.sh
```

The model tests use Node's built-in test runner. `shellcheck` is run when it is
installed; Bash syntax, JavaScript syntax, and the manifest are always checked.
