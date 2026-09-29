# Bowling League (SwiftUI + SwiftData, iPhone and iPad)

Built from the "Saturday Night Special" spreadsheet (Doubles&Eliminator tab).

## What it does
- **Home** (first tab, where the app opens): leaderboard for active bowlers by Average, High Game, High Series
  or 200 Games, with a Liquid Glass podium for the top three.
- **Bowlers**: every bowler with average and handicap at a glance,
  sorted by average. iPad shows a sortable table (average, handicap, games,
  high game, high series); iPhone shows a compact list. Tap for stats from every night bowled
  (games, average, high game, high series, 200+ games, history). Each history
  night shows who they doubled with; tap it to open that night scrolled to
  their games.
- **Profiles**: each bowler can have a photo (Photos picker, stored downscaled);
  otherwise they get a colored initials avatar.
- **Roster changes**: add bowlers any time. "Remove" moves a bowler to Former
  Bowlers, keeping their history; "Add Back" restores them, and "Delete
  Forever" erases them and their scores.
- **Nights**: pick who's bowling, enter games 1–3. Each row shows average,
  series handicap and Total With Handicap, like the sheet.
- **In-game mode** (bowling-figure button on a night): score ball by ball as
  the night is bowled. Tap the pins that fell on the pin deck, or tap a quick
  count (-, 1–9, X, /). The 10-frame sheet fills in with marks and running
  totals, it moves to the next bowler after each frame, Undo steps back across
  bowlers, and a finished game becomes that bowler's score
  (`Logic/GameSheet.swift`). Typed scores only accept 0–300.
- **Doubles**: pair everyone (blind draw or high-with-low), then teams rank
  by combined Total With Handicap. An odd bowler out is listed separately.
- **Eliminator**: handicapped game-by-game cut. Half the field, rounded up
  to the nearest even number, moves on after games 1 and 2 (25 → 14 → 8).
  Game 3's top 3 cash with 14 to 19 entrants, top 4 with 20 to 25 (cutoff in Settings).
  Ties at a cut all move on. Entry is a per-bowler toggle.
- **Spreadsheet data**: loaded automatically the first time the app opens on
  an empty league (and still offered on the empty Home and Bowlers screens) —
  the Saturday Night Special spreadsheet (`Models/SeedData.swift`): all 42 bowlers
  and averages, plus a Sep 26 night with the 29 bowlers on the sheet, the games
  entered so far, the 27 eliminator entrants and the 13 Island castaways.
- **Island**: the season-long survivor game from the sheet's Island tab.
  High handicap series among castaways wins immunity for next week. Low
  series (immunity holder excluded) is kicked off and goes swimming. A
  swimmer gets back on by bowling the night's highest series, otherwise
  they're out for the season. "Record Island Results" applies it.
- **Settings**: handicap base/percent and when the eliminator pays 4 places.
- **Look**: rounded type, a lane-light orange accent, a bowling lane (maple
  boards, arrows, dots and pins) drawn behind every screen (`Views/Theme.swift`), glass stat tiles, glass
  score pills that glow gold for 200+ games, and date badges on nights.
- **Layout**: iOS 26 Liquid Glass `TabView` (Home, Bowlers, Nights, Settings, Search).
  On iPad the tab bar becomes a sidebar (`.sidebarAdaptable`); on iPhone it
  shrinks while you scroll.

Handicap is the sheet's formula: `MAX(0, ROUNDDOWN((230 − average) × 0.8) × 3)`
for the series, a third of that per game (223 → 5/game, 15/series; 240 → 0).

## Data model
- `Bowler`: name, average, photo, isActive, Island status → many `Entry`
- `Night`: title, date, islandRecorded → many `Entry`
- `Entry`: bowler + night, average snapshot, game1–3, doublesTeam, inEliminator

Pure logic (no SwiftUI) lives in `Logic/` and is covered by `BowlingLeagueTests`.

## Put it in Xcode (26 or newer, iOS / iPadOS 26)
1. File › New › Project › iOS App. Name it `BowlingLeague`, Interface SwiftUI,
   Storage None, Testing System "Swift Testing". Keep iPhone and iPad as
   supported destinations and set the deployment target to 26.0.
2. Delete the generated `BowlingLeagueApp.swift` and `ContentView.swift`.
3. Drag the `BowlingLeague/` folder's contents into the app target and
   `BowlingLeagueTests/LeagueLogicTests.swift` into the test target.
4. Run. ⌘U runs the tests.

Not compiled yet on this side (no Swift toolchain here), so expect a small
fix or two on first build.
