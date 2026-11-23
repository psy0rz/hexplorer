import UIKit
import LinkPresentation
import MapKit

/// A location that the share sheet can send to contacts and to apps that support locations.
///
/// The share sheet gets two items, the same as when Apple Maps shares a pin:
/// - the Apple Maps URL, for apps that accept links (Messages shows it as a map preview),
/// - a `.loc.vcf` vCard file, for apps that accept locations or contacts.
struct SharedCellLocation {
    let name: String
    let latitude: Double
    let longitude: Double

    var appleMapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
            URLQueryItem(name: "q", value: name)
        ]
        return components.url!
    }

    /// Google Maps opens this link in its app when the app is installed, else in the browser.
    var googleMapsURL: URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: String(format: "%.6f,%.6f", latitude, longitude))
        ]
        return components.url!
    }

    var locationVCard: String {
        [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "N:;\(name);;;",
            "FN:\(name)",
            "item1.URL;type=pref:\(appleMapsURL.absoluteString)",
            "item1.X-ABLabel:map url",
            "END:VCARD"
        ].joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the vCard to a temporary `.loc.vcf` file, because share extensions expect a file URL.
    private func writeLocationVCardFile() -> URL? {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).loc.vcf")
        do {
            try Data(locationVCard.utf8).write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    @MainActor
    func presentShareSheet() {
        var activityItems: [Any] = [AppleMapsLinkItemSource(location: self)]
        if let vCardFileURL = writeLocationVCardFile() {
            activityItems.append(vCardFileURL)
        }
        // Apple Maps and Google Maps have no share extension, so they get their own "Open in" actions.
        let openInMapsActivities = [
            OpenLocationActivity(title: "Open in Apple Maps", systemImageName: "map") {
                let mapItem = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
                mapItem.name = name
                mapItem.openInMaps()
            },
            OpenLocationActivity(title: "Open in Google Maps", systemImageName: "globe") {
                UIApplication.shared.open(googleMapsURL)
            }
        ]
        let shareController = UIActivityViewController(activityItems: activityItems, applicationActivities: openInMapsActivities)

        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard var topController = keyWindow?.rootViewController else { return }
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        shareController.popoverPresentationController?.sourceView = topController.view
        topController.present(shareController, animated: true)
    }
}

/// A share sheet action that opens the location in a map app.
private final class OpenLocationActivity: UIActivity {
    private let title: String
    private let systemImageName: String
    private let openLocation: @MainActor () -> Void

    init(title: String, systemImageName: String, openLocation: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImageName = systemImageName
        self.openLocation = openLocation
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("hexplorer.\(title)") }
    override var activityTitle: String? { title }
    override var activityImage: UIImage? { UIImage(systemName: systemImageName) }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override func perform() {
        openLocation()
        activityDidFinish(true)
    }
}

/// Gives the share sheet the Apple Maps URL with a title, so the preview header shows the cell name.
private final class AppleMapsLinkItemSource: NSObject, UIActivityItemSource {
    let location: SharedCellLocation

    init(location: SharedCellLocation) {
        self.location = location
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        location.appleMapsURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        location.appleMapsURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        location.name
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let linkMetadata = LPLinkMetadata()
        linkMetadata.title = location.name
        linkMetadata.originalURL = location.appleMapsURL
        linkMetadata.url = location.appleMapsURL
        return linkMetadata
    }
}
