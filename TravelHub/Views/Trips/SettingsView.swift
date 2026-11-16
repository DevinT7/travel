import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(APIKeys.aeroDataBoxKey) private var aeroKey = ""
    @AppStorage(APIKeys.ticketmasterKey) private var tmKey = ""
    @AppStorage(APIKeys.googlePlacesKey) private var googleKey = ""
    @AppStorage(GooglePlacesProvider.problemKey) private var googleProblem = ""

    var body: some View {
        Form {
            Section {
                SecureField("AeroDataBox (RapidAPI) key", text: $aeroKey)
                Link("Get a free key on RapidAPI →", destination: URL(string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox/pricing")!)
                    .font(.footnote)
            } header: {
                keyHeader("Flights", isSet: !aeroKey.isEmpty)
            } footer: {
                Text("Optional. Adds live flight lookup by number, plus terminals, gates, baggage belts and delays (pull down on a trip to refresh). Sign up on RapidAPI, subscribe to AeroDataBox's free Basic plan (400 API units a month), then copy your X-RapidAPI-Key here. You can always paste or type flights without a key.")
            }

            Section {
                SecureField("Ticketmaster Consumer Key", text: $tmKey)
                Link("Get a free key from Ticketmaster Developer →", destination: URL(string: "https://developer-acct.ticketmaster.com/user/register")!)
                    .font(.footnote)
            } header: {
                keyHeader("Events", isSet: !tmKey.isEmpty)
            } footer: {
                Text("Adds concerts, sports and shows happening during your trip to Discover. 5,000 free requests a day.")
            }

            Section {
                SecureField("Google Places API key", text: $googleKey)
                    .onChange(of: googleKey) { googleProblem = "" }
                Link("Get a key from Google Cloud →", destination: URL(string: "https://developers.google.com/maps/documentation/places/web-service/get-api-key")!)
                    .font(.footnote)
            } header: {
                keyHeader("Ratings & Hours", isSet: !googleKey.isEmpty, problem: googleKey.isEmpty ? nil : googleProblem)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if !googleProblem.isEmpty, !googleKey.isEmpty {
                        Text(googleProblem).foregroundStyle(.red)
                    }
                    Text("Adds Google ratings, prices and opening hours to restaurants, cafés, bars, museums, parks and shops in Discover, plus a photo on each place's page. In Google Cloud, turn on “Places API (New)” for your key. Google bills each search after a free monthly allowance; Discover uses one search per category and keeps results for two days.")
                }
            }

            Section("Always on, no key needed") {
                source("map", "Apple Maps", "Restaurants, cafés, bars, museums, parks, shops, travel times")
                source("book.closed", "Wikipedia", "Landmarks and sights with photos and descriptions")
                source("cloud.sun", "Open-Meteo", "Weather forecast for your trip dates")
                source("dollarsign.arrow.circlepath", "ExchangeRate-API", "Currency conversion")
            }

            Section {
            } footer: {
                Text("Keys are stored on this device only.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            #endif
        }
    }

    private func keyHeader(_ title: String, isSet: Bool, problem: String? = nil) -> some View {
        let failing = !(problem ?? "").isEmpty
        return HStack {
            Text(title)
            Spacer()
            Label(failing ? "Not working" : isSet ? "Connected" : "Not set",
                  systemImage: failing ? "exclamationmark.triangle.fill" : isSet ? "checkmark.circle.fill" : "circle.dashed")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(failing ? .orange : isSet ? .green : .secondary)
                .textCase(nil)
        }
    }

    private func source(_ symbol: String, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
