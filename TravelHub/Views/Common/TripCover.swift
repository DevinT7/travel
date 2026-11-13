import SwiftUI
import MapKit

/// Full-bleed photo of the destination. Falls back to satellite imagery of the city while
/// the photo loads or when Wikipedia has none.
struct TripCover: View {
    let trip: Trip
    @State private var url: URL?

    var body: some View {
        Color.insetBackground
            .overlay {
                Map(initialPosition: .region(MKCoordinateRegion(center: trip.coordinate, latitudinalMeters: 9000, longitudinalMeters: 9000)),
                    interactionModes: [])
                    .mapStyle(.imagery(elevation: .flat))
                    .allowsHitTesting(false)
                    .opacity(url == nil ? 1 : 0)
            }
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: .init(animation: .easeOut(duration: 0.4))) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                    }
                }
            }
            .clipped()
            .task(id: trip.destinationName) {
                url = CoverPhotos.cached(for: trip.destinationName)
                if url == nil { url = await CoverPhotos.url(for: trip.destinationName) }
            }
    }
}
