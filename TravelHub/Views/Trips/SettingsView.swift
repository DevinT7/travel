import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(APIKeys.aeroDataBoxKey) private var aeroKey = ""
    @AppStorage(APIKeys.ticketmasterKey) private var tmKey = ""
    @State private var addedSample = false

    var body: some View {
        Form {
            Section {
                SecureField("AeroDataBox (RapidAPI) key", text: $aeroKey)
                Link("Get a free key on RapidAPI →", destination: URL(string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox/pricing")!)
                    .font(.footnote)
            } header: {
                keyHeader("Flights", isSet: !aeroKey.isEmpty)
            } footer: {
                Text("Used to look up flight numbers: times, terminals, gates and aircraft. The free Basic plan is plenty for personal trips.")
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

            Section("Always on, no key needed") {
                source("map", "Apple Maps", "Restaurants, cafés, bars, museums, parks, shops, travel times")
                source("book.closed", "Wikipedia", "Landmarks and sights with photos and descriptions")
                source("cloud.sun", "Open-Meteo", "Weather forecast for your trip dates")
                source("dollarsign.arrow.circlepath", "ExchangeRate-API", "Currency conversion")
            }

            Section {
                Button(addedSample ? "Sample trip added" : "Add sample Tokyo trip") {
                    SampleData.insertTokyoTrip(into: context)
                    addedSample = true
                }
                .disabled(addedSample)
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

    private func keyHeader(_ title: String, isSet: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(isSet ? "Connected" : "Not set", systemImage: isSet ? "checkmark.circle.fill" : "circle.dashed")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSet ? .green : .secondary)
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
