# TravelHub

An all-in-one travel companion for iPhone, iPad and Mac, built in SwiftUI. Add your flights and hotel, find things to do where you're going, and build a day-by-day plan.

## What's in it

| Tab | What it does |
|---|---|
| **Trip** | A map of your flight routes, boarding-pass style flight cards (times in each airport's local zone, terminal, gate, baggage belt, delays), where you're staying, the weather forecast for your dates, local time and difference from home, a currency converter, and what's up next. |
| **Discover** | A "For You" page with a featured sight and a row for each category (Sights, Food, Cafés, Museums & Arts, Outdoors, Nightlife, Shopping, Events), plus a grid or map view per category and search. Tap **+** to save an idea, or open a place to see its photo or Look Around street view, map, distance from your hotel, directions, website and Apple Maps place card. |
| **Plan** | A day strip (Day 1, Day 2, …) and a timeline that mixes your plans, flights and hotel check-in/out. It shows the travel time between stops (walking or transit) and flags gaps that are too tight. Each day's stops appear as numbered pins on a map. An **Ideas** tray holds things you've saved but haven't given a time. |
| **Trips** | Switch between trips or create new ones. You can also switch from the title menu on any tab. |

All plan times are shown in the **destination's** time zone. Flight times are shown in each airport's own zone.

On iPhone the tabs sit in a bottom tab bar. On iPad and Mac they become a sidebar, and Plan shows the timeline and map side by side.

## Where the data comes from

| Data | Source | Key? | Cost |
|---|---|---|---|
| Flight lookup by number | [AeroDataBox](https://rapidapi.com/aedbx-aedbx/api/aerodatabox) via RapidAPI | Yes | Free Basic plan |
| Concerts, sports, shows | [Ticketmaster Discovery API](https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/) | Yes | Free, 5,000 calls/day |
| Restaurants, cafés, bars, museums, parks, shops, search | Apple MapKit (`MKLocalSearch`) | No | Free |
| Landmarks with photos and descriptions | Wikipedia geosearch, ranked by article length | No | Free |
| Travel time between stops, Look Around, place cards | Apple MapKit | No | Free |
| Weather | [Open-Meteo](https://open-meteo.com) | No | Free |
| Exchange rates | [open.er-api.com](https://www.exchangerate-api.com/docs/free) | No | Free |

Without any keys, everything except flight lookup and Events works. Add the keys in **Settings**: the gear on the Trips tab on iPhone, or **TravelHub → Settings…** (⌘,) on Mac. Keys are stored on the device.

## Running it

Requires Xcode 26+. Targets iOS 18+ and macOS 15+.

```bash
brew install xcodegen
```

```bash
xcodegen generate && open TravelHub.xcodeproj
```

Pick the **TravelHub** scheme, then an iPhone simulator or **My Mac**. On the welcome screen, **Explore a sample trip** loads a demo Tokyo trip with made-up flights, clearly marked as a sample.

`project.yml` is the source of truth for the Xcode project. Regenerate after adding or removing files.

## Project layout

```
TravelHub/
  App/        App entry, tab/sidebar shell, trip switcher, welcome screen
  Models/     SwiftData models (Trip, FlightSegment, Stay, PlanItem) and DiscoverItem
  Services/   AeroDataBox, Wikipedia, Apple Maps, Ticketmaster, weather, currency, directions, sample data
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

- Live Activity and widget for the next flight: countdown, gate and delay.
- Background refresh of flight status, with notifications for gate changes and delays.
- Import confirmation emails or PDFs (flights and hotels) with on-device text recognition.
- Share a trip with travel companions through CloudKit sharing.
- Reorder a day's stops by drag and drop to get a shorter route.
