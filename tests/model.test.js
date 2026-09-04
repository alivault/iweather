const test = require("node:test")
const assert = require("node:assert/strict")

const model = require("../Model.js")

test("validCoordinates accepts boundaries and rejects malformed values", () => {
  assert.deepEqual(model.validCoordinates(90, -180), { latitude: 90, longitude: -180 })
  assert.deepEqual(model.validCoordinates("40.7", "-74"), { latitude: 40.7, longitude: -74 })

  for (const values of [
    [91, 0], [0, 181], ["", 0], [" ", 0], [Infinity, 0], ["north", 0]
  ]) {
    assert.equal(model.validCoordinates(values[0], values[1]), null)
  }
})

test("parseLocationFile preserves a name but drops invalid coordinates", () => {
  assert.deepEqual(
    model.parseLocationFile('{"name":"  Example  ","latitude":999,"longitude":999}'),
    { name: "Example", latitude: null, longitude: null }
  )
  assert.deepEqual(model.parseLocationFile("not json"), { name: "", latitude: null, longitude: null })
})

test("geocoding results include only valid coordinate pairs", () => {
  const results = model.parseGeocodingResults(JSON.stringify({ results: [
    { name: "Valid", admin1: "Region", country: "Country", latitude: 10, longitude: 20 },
    { name: "Invalid", latitude: 999, longitude: 20 }
  ] }))

  assert.deepEqual(results, [{
    name: "Valid",
    description: "Region, Country",
    latitude: 10,
    longitude: 20
  }])
})

test("locationCommit does not apply suggestions from an older query", () => {
  const suggestion = { name: "Old result", latitude: 1, longitude: 2 }
  assert.deepEqual(
    model.locationCommit("New query", [suggestion], 0, "Old query"),
    { name: "New query", latitude: null, longitude: null }
  )
  assert.equal(model.locationCommit("Old query", [suggestion], 0, "Old query"), suggestion)
})

test("NWS observations must be recent and cannot be far in the future", () => {
  const now = Date.parse("2026-01-01T00:00:00Z")
  const report = timestamp => ({ observation: { temperatureC: 20, timestamp } })

  assert.equal(model.nwsCurrentCondition(report("2099-01-01T00:00:00Z"), null, now), null)
  assert.equal(model.nwsCurrentCondition(report("2025-12-31T22:00:00Z"), null, now), null)
  assert.equal(model.nwsCurrentCondition(report("2025-12-31T23:30:00Z"), null, now).source, "NWS")
})

test("current conditions wait for the final source on initial load", () => {
  assert.equal(model.currentSourceReady(-1, 2, "United States", -1), false)
  assert.equal(model.currentSourceReady(2, 2, "United States", -1), false)
  assert.equal(model.currentSourceReady(2, 2, "United States", 2), true)
  assert.equal(model.currentSourceReady(2, 2, "Norway", -1), true)
})

test("weather API coordinates and location names are encoded safely", () => {
  assert.equal(model.wttrLocationQuery("ignored", 40.7, -74), "40.7,-74")
  assert.equal(model.wttrLocationQuery("New York/Manhattan", null, null), "New%20York%2FManhattan")
})

test("NWS alert text unwraps prose while preserving paragraphs", () => {
  assert.equal(
    model.formatAlertText(" First line\nsecond line. \n\n Next paragraph.\r\n"),
    "First line second line.\n\nNext paragraph."
  )
  assert.equal(model.formatAlertText(" \n\t"), "")
})
