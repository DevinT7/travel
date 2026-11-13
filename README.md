# TravelHub

An all-in-one travel companion for iPhone, iPad and Mac, built in SwiftUI. Add your flights and hotel, find things to do where you're going, and build a day-by-day plan.

## What's in it

| Tab | What it does |
|---|---|
| **Trip** | A map of your flight routes, boarding-pass style flight cards (times in each airport's local zone, terminal, gate, baggage belt, delays), where you're staying, the weather forecast for your dates, local time and difference from home, a currency converter, and what's up next. |
| **Discover** | A "For You" page with a featured sight and a row for each category (Sights, Food, Cafés, Museums & Arts, Outdoors, Nightlife, Shopping, Events), plus a grid or map view per category and search. Tap **+** to save an idea, or open a place to see its photo or Look Around street view, map, distance from your hotel, directions, website and Apple Maps place card. |
| **Plan** | A day strip (Day 1, Day 2, …) and a timeline that mixes your plans, flights and hotel check-in/out. It shows the travel time between stops (walking or transit) and flags gaps that are too tight. Each day's stops appear as numbered pins on a map. An **Ideas** tray holds things you've saved but haven't given a time. |
| **Trips** | Switch between trips or create new ones. You can also switch from the title menu on any tab. |

**Live Activities (iPhone):** a flight leaving within 4 hours appears on the Lock Screen and in the Dynamic Island when you open the app, or tap **Track Live on Lock Screen** under any flight in the next day. It counts down to departure, shows terminal and gate (and baggage belt after landing), and fills a progress bar during the flight. The app updates it when flight status refreshes; between refreshes the countdowns run on their own. With an AeroDataBox key, iOS also wakes the app in the background (usually every 15–60 minutes, at the system's discretion) from two hours before departure until landing, so delays and gate changes reach the Lock Screen without opening the app. Background refresh must be on (Settings → General → Background App Refresh); it doesn't run in the Simulator.

All plan times are shown in the **destination's** time zone. Flight times are shown in each airport's own zone.

On iPhone the tabs sit in a bottom tab bar. On iPad and Mac they become a sidebar, and Plan shows the timeline and map side by side.

## Design

The look follows the patterns shared by the highest-rated trip apps (TripIt, Tripsy, Wanderlog, Reis): native iOS surfaces, the system font, and one warm orange accent.

- **Native surfaces:** grouped gray background (black in dark mode) with rounded white cards, inset dividers and standard list styles.
- **Trip page:** the destination's photo fades into the page, with the trip name and "Leaves in 9 days · 8-day trip" centered beneath and round quick actions (Flight, Stay, Activity, Discover).
- **Compact itinerary:** each plan is one row (colored circle icon, title and place, time on the right), with travel time as a quiet line between stops. The day map opens from the toolbar on iPhone and sits beside the list on iPad and Mac.
- **Discover:** Apple Maps-style category circles, photo cards for sights and events, and grouped lists for restaurants, cafés and other places.
- **Welcome:** a live 3D globe from Apple Maps satellite imagery.

Colors live in `Views/Common/Theme.swift`; shared pieces (cards, circle icons, quick actions, section headers) are in `Views/Common/Components.swift`.

## Where the data comes from

| Data | Source | Key? | Cost |
|---|---|---|---|
| Flight lookup by number | [AeroDataBox](https://rapidapi.com/aedbx-aedbx/api/aerodatabox) via RapidAPI | Yes | Free Basic plan |
| Concerts, sports, shows | [Ticketmaster Discovery API](https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/) | Yes | Free, 5,000 calls/day |
| Restaurants, cafés, bars, museums, parks, shops, search | Apple MapKit (`MKLocalSearch`) | No | Free |
| Landmarks with photos and descriptions | Wikipedia geosearch, ranked by article length | No | Free |
| Travel time between stops, Look Around, place cards | Apple MapKit | No | Free |
| Destination cover photos | Wikipedia lead image | No | Free |
| Weather | [Open-Meteo](https://open-meteo.com) | No | Free |
| Exchange rates | [open.er-api.com](https://www.exchangerate-api.com/docs/free) | No | Free |

Without any keys, everything except live flight lookup and Events works. You can still add flights without a key:

- **Paste:** paste an airline confirmation email or text into Add Flight → Paste. The flight numbers, airport codes, dates and times are read on the device (no network call for the text itself), airports are looked up with Apple Maps, and times are converted with each airport's time zone. Flights already in the trip are skipped.
- **Enter:** type the flight number, airport codes and local times.

### Setting up live flight lookup (AeroDataBox)

1. Go to the [AeroDataBox listing on RapidAPI](https://rapidapi.com/aedbx-aedbx/api/aerodatabox/pricing) and sign up or log in.
2. Subscribe to the free **Basic** plan (400 API units a month, 1 request a second).
3. Open any endpoint on the listing and copy the **X-RapidAPI-Key** value shown in the request headers.
4. In TravelHub, open **Settings** (the gear on the Trips tab, or ⌘, on Mac) and paste it into **AeroDataBox (RapidAPI) key**.

Add Flight then opens on **Look Up**, and pulling down on a trip refreshes every real flight with terminals, gates, baggage belts and delays — including flights you pasted or typed in. Add the keys in **Settings**: the gear on the Trips tab on iPhone, or **TravelHub → Settings…** (⌘,) on Mac. Keys are stored on the device.

## Running it

Requires Xcode 26+. Targets iOS 18+ and macOS 15+.

```bash
brew install xcodegen
```

```bash
xcodegen generate && open TravelHub.xcodeproj
```

Pick the **TravelHub** scheme, then an iPhone simulator or **My Mac**. Create a trip from the welcome screen, then add flights by pasting a confirmation, typing them in, or looking them up by number.

### On your iPhone

`project.yml` signs with a personal development team (`DEVELOPMENT_TEAM`); change it to your own team ID if you're building elsewhere. With the phone connected and Developer Mode on, pick it as the run destination in Xcode, or from the command line:

```bash
xcodebuild -project TravelHub.xcodeproj -scheme TravelHub -destination 'id=<device UDID>' -allowProvisioningUpdates build
```

The first time, iOS asks you to trust the developer: **Settings → General → VPN & Device Management → Apple Development → Trust**. Apps signed with a free personal team expire after 7 days; rebuild to renew. API keys are per device, so add them again in the app's Settings on the phone.

`project.yml` is the source of truth for the Xcode project. Regenerate after adding or removing files.

## Project layout

```
TravelHub/
  App/        App entry, tab/sidebar shell, trip switcher, welcome screen
  Models/     SwiftData models (Trip, FlightSegment, Stay, PlanItem) and DiscoverItem
  Services/   AeroDataBox, Wikipedia, Apple Maps, Ticketmaster, weather, currency, directions, airports, confirmation parsing
  Views/
    Common/   Theme colors, cards, chips, image tiles, empty states
    Trip/     Dashboard, route map, flight card, add flight, stays, weather and local info
    Discover/ Discover page, cards, detail sheet, view model
    Plan/     Day timeline, day map, ideas tray, plan item editor
    Trips/    Trips list, new trip, settings
```

## Syncing between iPhone and Mac (iCloud)

The models already follow CloudKit's rules: every property has a default, relationships are optional, and nothing is marked unique. To turn sync on:

1. In Xcode, select your Apple developer team under **Signing & Capabilities**.
2. Add the **iCloud** capability with **CloudKit** and create a container, for example `iCloud.com.devint.travelhub`.
3. Add **Background Modes → Remote notifications** on iOS.
4. In `TravelHubApp.swift`, change `cloudKitDatabase: .none` to `.automatic`.

## Ideas for next steps

- Home Screen widget for the next flight.
- Push-driven Live Activity updates for minute-by-minute changes (needs a small server polling AeroDataBox and sending ActivityKit pushes).
- Background refresh of flight status, with notifications for gate changes and delays.
- Import confirmation emails or PDFs (flights and hotels) with on-device text recognition.
- Share a trip with travel companions through CloudKit sharing.
- Reorder a day's stops by drag and drop to get a shorter route.
