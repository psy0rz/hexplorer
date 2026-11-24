# Hexplorer

Hexplorer is an iOS app that tracks where you have been. While you move around, the app records
the locations you visit as [H3](https://h3geo.org) hexagon cells and draws them as a coloured
overlay on the map. You can also put custom flags on the map.

All data stays on the device, in a local SQLite database. You can export and import the database
from the app.

Download Hexplorer from the [App Store](https://apps.apple.com/app/id6761833997).


## Tracking mode

<img width="300"  alt="D13303ED-4D22-4E9A-8908-3B1D7A4E24CE_1_105_c" src="https://github.com/user-attachments/assets/2a3e62c3-be08-42f1-8e6d-bbb5900bc235" />

## Flag editor

<img width="300" alt="1D714B76-B132-427A-88E4-671710A538C4_1_105_c" src="https://github.com/user-attachments/assets/9e20a722-68b6-48be-817d-01333c6e502a" />


## Features

- **Tracking:** records the cells you visit, also when the app is in the background. While
  tracking is on, a Live Activity on the Lock Screen and in the Dynamic Island shows the duration
  and the number of new cells. New cells flash on the map.
- **Display modes:** four modes decide how the map colours each cell:
  | Mode | A cell is denser when |
  |---|---|
  | Time | you were there more recently |
  | Coverage | you explored more of the cell |
  | Visits | you visited it more often |
  | Discovered | you visited it for the first time more recently |

  Each mode has a slider with two thumbs. The thumbs set the borders between the three
  densities: **partial** (outline only), **dense** (light fill) and **full** (strong fill).
- **Cell information:** tap a cell to see its level, size, first and last visit, visit count
  and coverage. From the panel, you can open the cell in Apple Maps, get directions, share the
  location, add a flag, or delete the visits in the cell.
- **Flags:** put a flag with a label, a colour and a priority on the map.
- **Map layers:** select a standard map or a satellite map. Show or hide labels and points of
  interest.
- **Export and import:** save the database to a file, or replace all data with a database file.


## Requirements

- Xcode 26 or later
- iOS 26.0 or later, on iPhone or iPad
- A real device for location tracking. The simulator can only simulate locations.


## Build and run

1. Open `hexplorer.xcodeproj` in Xcode.
2. Select the `hexplorer` target. Open **Signing & Capabilities**.
3. Select your own development team.
4. Do steps 2 and 3 again for the `HexplorerWidgets` target.
5. If necessary, change the bundle identifier of the `hexplorer` target to a unique value.
   Then change the bundle identifier of `HexplorerWidgets` to the same value followed by
   `.HexplorerWidgets`. The widget identifier must start with the app identifier.
6. Select a device and run the app. Xcode resolves the Swift packages automatically.


## Dependencies

| Package | Use |
|---|---|
| [SwiftyH3](https://github.com/pawelmajcher/SwiftyH3) | Swift wrapper for the Uber H3 hexagonal grid |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database access |
| [MKZoomLevel](https://github.com/stleamist/MKZoomLevel) | Linked to the app, but the code does not use it at the moment |


## How it works

### Location tracking

`LocationTracker` uses `CLLocationUpdate.liveUpdates()` and a `CLBackgroundActivitySession`, so
tracking continues in the background.

- The tracker rejects a location with a horizontal accuracy worse than 20 m.
- It converts each location to an H3 cell at resolution 13 (the leaf resolution). A res-13 cell
  has an edge of about 3.5 m.
- It skips a location if it is in the same leaf cell as the previous location.
- It buffers new locations and writes them to the database every second while the app is active,
  and every 60 seconds while the app is not active.

Tracking is on at the first launch. If tracking was on when the app stopped, it starts again at
the next launch. `TrackingLiveActivityController` starts, updates and ends the Live Activity. The
`HexplorerWidgets` extension shows it.

### Data model

`CellStore` keeps the data in `visited.sqlite` in the app's Documents folder.

- **`visitedCell`**: one row for each visited cell. When the app records a leaf cell, it also
  updates all parent cells up to resolution 0. Each row stores:
  - the first and the last visit time,
  - a visit count. A visit counts again only if the last visit was more than 60 seconds ago,
  - the number of visited direct children,
  - the number of visited leaf descendants.
- **`flag`**: user flags with a position, label, colour and priority. `FlagStore` manages them.

The H3 index is a `UInt64`. The database stores it as an `Int64` with the same bit pattern.

### Map rendering

`VisitedHexagonOverlays` draws the visited cells as native MapKit overlays:

1. It selects the H3 resolution from the zoom scale and the latitude, so that a cell edge is
   approximately the same length on the screen (`targetEdgePixels`).
2. It finds all H3 cells of that resolution in the visible area, plus half a screen on each side.
3. It gets the visited cells from the database, and gives each cell a density from the active
   display mode (`FilterState`).
4. It puts each cell into one `MKMultiPolygon` for each layer. There are four layers, from bottom
   to top: **halo** (a dark line below all cells, so the outlines stay visible on light maps),
   **partial**, **dense** and **full**.
5. It replaces only the layers whose cells changed.

When you pan, the app loads cells again only if the visible area moves out of the loaded area,
or the resolution changes.

The **coverage** mode uses an exploration score from 0 to 1:
`log(visitedLeaves) / log(leafCount)`. One straight route through a cell gives about 0.5 at every
resolution. A fully visited cell gives 1.

Other map elements:

- `HexagonHighlightView` draws the selected cell with a yellow glow and a crosshair.
- `NewCellFlashes` flashes the new cells after each database write.
- `MapView` adds a layers button and a follow button. The follow button keeps the user location
  in the center of the map without a change of zoom. The app stores the map position and zoom,
  and restores them at the next launch.

### Flags

Flags are shown as clustered `MKMarkerAnnotationView`s. The priority of a flag controls when it
stays visible:

| Priority | Behaviour |
|---|---|
| Always show | Stays on the map when markers overlap |
| Normal | The default |
| Hide first | Hides first when markers overlap, and shows no label |

Tap a flag to edit it in `FlagEditorPanel`.

### Sharing a cell

`SharedCellLocation` shares the center of the selected cell. The share sheet gets an Apple Maps
link and a `.loc.vcf` location card, the same as Apple Maps. It also has actions to open the
location in Google Maps, Street View, OpenStreetMap and Apple Maps.


## Project structure

### App (`hexplorer/`)

| File | Purpose |
|---|---|
| `hexplorerApp.swift` | App entry point. Starts tracking again if it was on. |
| `ContentView.swift` | Root view: map, buttons, bottom panels, export and import |
| `MapView.swift` | MapKit wrapper: map controls, follow mode, tap handling, flag annotations |
| `VisitedHexagonOverlays.swift` | Resolution selection, density classification and hexagon overlays |
| `HexagonHighlightView.swift` | Highlight of the selected cell |
| `NewCellFlashes.swift` | Flash of newly visited cells |
| `CellStore.swift` | SQLite database for visited cells |
| `FlagStore.swift` | Flag model and storage |
| `LocationTracker.swift` | Location updates and recording |
| `TrackingLiveActivity.swift` | Start, update and end of the tracking Live Activity |
| `SelectedCellState.swift` | State of the selected cell |
| `FilterState.swift` / `FilterOptionsPanel.swift` | Display modes and their slider settings |
| `TwoThumbStopSlider.swift` | Slider with two thumbs on fixed stops |
| `MapLayerSettings.swift` / `MapLayersPanel.swift` | Map style, labels and points of interest |
| `OverlayColors.swift` | Colours and line widths of the overlay layers |
| `CellInfoPanel.swift` / `FlagEditorPanel.swift` | Bottom panels for a cell and for a flag |
| `SharedCellLocation.swift` | Share sheet and "open in" actions for a cell location |

### Widget extension (`HexplorerWidgets/`)

| File | Purpose |
|---|---|
| `HexplorerWidgetsBundle.swift` | Widget extension entry point |
| `TrackingLiveActivity.swift` | Lock Screen and Dynamic Island views of the Live Activity |
| `TrackingActivityAttributes.swift` | Copy of the Live Activity data type. Keep it the same as the type in `hexplorer/TrackingLiveActivity.swift`. |


## License

Copyright (C) 2026 Edwin Eefting

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version. See [LICENSE](LICENSE) for the full text.
