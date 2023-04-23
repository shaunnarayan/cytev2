//
//  View.swift
//  Cyte
//
//  Created by Shaun Narayan on 9/04/23.
//

import Foundation
import AVKit
import SwiftUI
import KeychainSwift
import RNCryptor

///
/// Helper function to open finder pinned to the supplied episode
///
func revealEpisode(episode: CyteEpisode) {
    let url = urlForEpisode(start: episode.start, title: episode.title)
#if os(macOS)
    NSWorkspace.shared.activateFileViewerSelecting([url])
#else
    openFile(path: url)
#endif
}

func openFile(path: URL) {
#if os(macOS)
    NSWorkspace.shared.open(path)
#else
    UIApplication.shared.open(path)
#endif
}

extension Date {
    var dayOfYear: Int {
        return Calendar.current.ordinality(of: .day, in: .year, for: self)!
    }
}

struct StackedShape: Shape {
    let shapes: [AnyShape]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for shape in shapes {
            path.addPath(shape.path(in: rect))
        }
        return path
    }
}

extension View {
    func cutout<S: Shape>(_ shapes: [S]) -> some View {
        let anyShapes = shapes.map(AnyShape.init)
        return self.clipShape(StackedShape(shapes: anyShapes), style: FillStyle(eoFill: true))
    }
}

extension CGRect: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(minX)
        hasher.combine(minY)
        hasher.combine(maxX)
        hasher.combine(maxY)
    }
}

extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}

func secondsToReadable(seconds: Double) -> String {
    var (hr,  minf) = modf(seconds / 3600)
    let (min, secf) = modf(60 * minf)
    let days = Int(hr / 24)
    hr -= (Double(days) * 24.0)
    var res = ""
    if days > 0 {
        res += "\(days) days, "
    }
    if hr > 0 {
        res += "\(Int(hr)) hours, "
    }
    if min > 0 {
        res += "\(Int(min)) minutes, "
    }
    res += "\(Int(60 * secf)) seconds"
    return res
}

#if os(macOS)
extension NSImage {
    ///
    /// This is used as a background color for contexts related to an app, like chart axis etc
    ///
    var averageColor: Color? {
        if self.tiffRepresentation == nil { return nil }
        guard let inputImage = CIImage(data: self.tiffRepresentation!) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Color(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, opacity: Double(bitmap[3]) / 255)
    }
}
typealias UIImage = NSImage
#else
extension UIImage {
    ///
    /// This is used as a background color for contexts related to an app, like chart axis, etc
    ///
    var averageColor: Color? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(x: inputImage.extent.origin.x, y: inputImage.extent.origin.y, z: inputImage.extent.size.width, w: inputImage.extent.size.height)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]) else { return nil }
        guard let outputImage = filter.outputImage else { return nil }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        return Color(red: Double(bitmap[0]) / 255, green: Double(bitmap[1]) / 255, blue: Double(bitmap[2]) / 255, opacity: Double(bitmap[3]) / 255)
    }
    
    func imageWith(newSize: CGSize) -> UIImage {
        let image = UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
            
        return image.withRenderingMode(renderingMode)
    }
}

extension Bundle {
    public var icon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)?.imageWith(newSize: CGSize(width: 24, height: 24))
        }
        return nil
    }
}

#endif

class BundleCache: ObservableObject {
    @Published var bundleImageCache: [String: UIImage] = [:]
    @Published var bundleColorCache : Dictionary<String, Color> = ["": Color.gray]
    @Published var bundleNameCache : Dictionary<String, String> = [:]
    @Published var id: UUID = UUID()
    
    func getColor(bundleID: String) -> Color? {
        if bundleColorCache[bundleID] != nil {
            return bundleColorCache[bundleID]!
        }
        return Color.gray
    }
    
    func getName(bundleID: String) -> String {
        if bundleNameCache[bundleID] != nil {
            return bundleNameCache[bundleID]!
        }
        return getApplicationNameFromBundleID(bundleID: bundleID) ?? bundleID
    }
    
    func setCache(bundleID: String, image: UIImage, bundleName: String? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                self.bundleImageCache[bundleID] = image
                self.bundleColorCache[bundleID] = self.bundleImageCache[bundleID]!.averageColor
                self.bundleNameCache[bundleID] = bundleName
                id = UUID()
            }
        }
    }
    
    struct ITunesResponseResults: Codable {
        public let artworkUrl512: URL
        public let trackName: String
        public let bundleId: String
    }
    
    struct ITunesResponse: Codable {
        /// ID of the model to use. Currently, only gpt-3.5-turbo and gpt-3.5-turbo-0301 are supported.
        public let results: [ITunesResponseResults]
    }
    
    func getIcon(bundleID: String) -> UIImage {
        if bundleImageCache[bundleID] != nil {
            return bundleImageCache[bundleID]!
        }
#if os(macOS)
        guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false)
        else {
            URLSession.shared.dataTask(with: FavIcon(bundleID)[.m]) { (data, response, error) in
                guard let imageData = data else { return }
                self.setCache(bundleID: bundleID, image: UIImage(data:imageData)!)
            }.resume()
            return UIImage()
        }
        
        guard FileManager.default.fileExists(atPath: path)
        else { return UIImage() }
        
        let icon = NSWorkspace.shared.icon(forFile: path)
        Task {
            setCache(bundleID: bundleID, image: icon)
        }
        return icon
#else
        URLSession.shared.dataTask(with: URL(string: "http://itunes.apple.com/lookup?bundleId=\(bundleID)")!) { (data, response, error) in
            if error != nil {
                return
            }
            do {
                if let data = data {
                    let res: ITunesResponse = try JSONDecoder().decode(ITunesResponse.self, from: data)
                    if res.results.count > 0 {
                        let result = res.results.first
                        if result != nil {
                            URLSession.shared.dataTask(with: result!.artworkUrl512) { (data, response, error) in
                                guard let imageData = data else { return }
                                let img = UIImage(data:imageData)!
                                self.setCache(bundleID: bundleID, image: img.imageWith(newSize: CGSize(width: 24, height: 24)), bundleName: result!.trackName)
                            }.resume()
                        }
                    } else {
                        self.setCache(bundleID: bundleID, image: Bundle.main.icon! )
                    }
                }
            } catch {
                self.setCache(bundleID: bundleID, image: Bundle.main.icon! )
            }
        }.resume()
        return UIImage()
#endif
    }
}

class DecryptedAVAssetLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    var data: Data?
    
    func update(encryptedURL: URL) {
        let enc = encryptedURL.absoluteString.starts(with: "decrypted://") ? URL(string: String(encryptedURL.absoluteString.dropFirst("decrypted://".count)))! : encryptedURL
        let encryptedData = try! Data(contentsOf: enc)
        data = try! decryptData(encryptedData)
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if (loadingRequest.contentInformationRequest != nil) {
            loadingRequest.contentInformationRequest!.contentType = AVFileType.mp4.rawValue
            loadingRequest.contentInformationRequest!.contentLength = Int64(data!.count)
            loadingRequest.contentInformationRequest!.isByteRangeAccessSupported = true
//            loadingRequest.contentInformationRequest!.isEntireLengthAvailableOnDemand = true
        }

        if loadingRequest.dataRequest!.requestsAllDataToEndOfResource {
            loadingRequest.dataRequest?.respond(with: data![loadingRequest.dataRequest!.currentOffset...])
        } else {
            if (loadingRequest.contentInformationRequest != nil) {
                loadingRequest.dataRequest!.respond(with: Data(data![Data.Index(loadingRequest.dataRequest!.requestedOffset)..<loadingRequest.dataRequest!.requestedLength]))
            } else {
                loadingRequest.dataRequest?.respond(with: Data( data![loadingRequest.dataRequest!.currentOffset..<loadingRequest.dataRequest!.currentOffset+Int64(loadingRequest.dataRequest!.requestedLength)]))
            }
        }
        loadingRequest.finishLoading()
        return true
    }
    
    private func decryptData(_ data: Data) throws -> Data {
        let defaults = UserDefaults(suiteName: "group.io.cyte.ios")!
        if !defaults.bool(forKey: "CYTE_ENCRYPTION") {
            return data
        }
        
        let keychain = KeychainSwift()
        let encryptionKey = keychain.getData("CYTE_ENCRYPTION_KEY")!
        let hmacKey = keychain.getData("CYTE_ENCRYPTION_HMAC_KEY")!
        
        let decryptor = RNCryptor.DecryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey)
        let plaintext: Data = try! decryptor.decrypt(data: data)
        return plaintext
    }
    
}
