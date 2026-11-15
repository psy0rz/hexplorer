# Hexplorer

Hexplorer is an iOS app that tracks where you have been. While you move around, the app records
the locations you visit as [H3](https://h3geo.org) hexagon cells and draws them as a coloured
overlay on a satellite map. You can also put custom flags on the map.

All data stays on the device, in a local SQLite database. You can export and import the database
from the app.

## Requirements

- Xcode 26 or later
- iOS 26.0 or later
- A real device for location tracking (the simulator can only simulate locations)

## Build and run

1. Open `hexplorer.xcodeproj` in Xcode.
2. Select the `hexplorer` target. Open **Signing & Capabilities**.
3. Select your own development team.
4. If necessary, change the bundle identifier to a unique value.
5. Select a device and run the app. Xcode resolves the Swift packages automatically.

## Dependencies

| Package | Use |
|---|---|
| [SwiftyH3](https://github.com/pawelmajcher/SwiftyH3) | Swift wrapper for the Uber H3 hexagonal grid |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database access |
| [MKZoomLevel](https://github.com/stleamist/MKZoomLevel) | Zoom level helpers for MapKit |

## How it works

### Location tracking

`LocationTracker` uses `CLLocationUpdate.liveUpdates()` and a `CLBackgroundActivitySession`, so
tracking continues in the background. Each location is converted to an H3 cell at resolution 13
(the leaf resolution). The tracker skips a location if it is in the same leaf cell as the previous
one. It buffers new locations and writes them to the database every second.

### Data model

`CellStore` keeps the data in `visited.sqlite` in the app's Documents folder.

- **`visitedCell`**: one row for each visited cell. When the app records a leaf cell, it also
  updates all parent cells up to resolution 0. Each row stores visit times, a visit count, the
  number of visited direct children and the number of visited leaf descendants.
- **`flag`**: user flags with a position, label, colour and priority. `FlagStore` manages them.

### Map rendering

- `MapView` wraps an `MKMapView` with a satellite map style.
- `HexagonOverlay` is a single overlay that covers the whole world.
- `HexagonOverlayRenderer` draws the visited cells for each map tile. It selects the H3 resolution
  from the zoom level, so that a cell edge is approximately 20 screen points long.
- Each cell is drawn in one of three tiers: **partial**, **dense** or **full**. The active filter
  (`FilterState`) decides the tier. You can classify by visited children, by the last visit time,
  or by the number of visited leaves.
- `HexagonHighlightView` draws the selected cell. `CellInfoPanel` shows the cell statistics.

### Flags

Flags are shown as clustered `MKMarkerAnnotationView`s. The priority of a flag controls when it
stays visible during clustering. Tap a flag to edit it in `FlagEditorPanel`.

## Project structure

| File | Purpose |
|---|---|
| `hexplorerApp.swift` | App entry point |
| `ContentView.swift` | Root view: map, controls and bottom panels |
| `MapView.swift` | MapKit wrapper, overlay, annotations and tap handling |
| `HexagonOverlay.swift` / `HexagonOverlayRenderer.swift` | Hexagon overlay and drawing |
| `HexagonHighlightView.swift` | Highlight of the selected cell |
| `CellStore.swift` | SQLite database for visited cells |
| `FlagStore.swift` | Flag storage |
| `LocationTracker.swift` | Location updates and recording |
| `SelectedCellState.swift` | State of the selected cell |
| `FilterState.swift` / `FilterOptionsPanel.swift` | Tier classification settings |
| `OverlayColors.swift` | Colours for the three tiers |
| `CellInfoPanel.swift` / `FlagEditorPanel.swift` | Bottom panels |

## License

Copyright (C) 2026 Edwin Eefting

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE) for the full text.
