//
//  Browser.swift
//  Cyte
//
//  Created by Shaun Narayan on 7/04/23.
//

import Foundation
#if os(macOS)
import AXSwift

///
/// Use AX API to perform a fragile string comparison for incognito/private browsing
///
func isPrivateContext(context: String) -> Bool {
    if !UserDefaults.standard.bool(forKey: "CYTE_BROWSER") || !checkIsProcessTrusted(prompt: true) {
        return false
    }
    if ["com.apple.Safari", "com.google.Chrome"].contains(context) {
        do {
            let apps = Application.allForBundleID(context)
            for app in apps {
                for window in try app.windows()! {
                    let main = (try window.attribute(.main) as Bool?)
                    let title = (try window.attribute(.title) as String?)
                    if main == true && title != nil && (title!.contains("(Incognito)") || title!.contains("Private Browsing")) {
                        return true
                    }
                }
            }
        } catch { }
    }
    return false
}

func getAddressBarContent(context: String) -> (String?, String?) {
    if !UserDefaults.standard.bool(forKey: "CYTE_BROWSER") || !checkIsProcessTrusted(prompt: true) {
        return (nil, nil)
    }
    let addressBarOffsets = [ "com.apple.Safari": (CGFloat(405), CGFloat(21)), "com.google.Chrome": (CGFloat(180), CGFloat(49))]
    if ["com.apple.Safari", "com.google.Chrome"].contains(context) {
        do {
            let apps = Application.allForBundleID(context)
            let offset = addressBarOffsets[context]!
            for app in apps {
                for window in try app.windows()! {
                    let title = (try window.attribute(.title) as String?)
                    let main = (try window.attribute(.main) as Bool?)
                    let frame = (try window.attribute(.frame) as CGRect?)
                    if (main ?? false) && frame != nil {
                        let elem = try! app.elementAtPosition(Float(frame!.minX + offset.0), Float(frame!.minY + offset.1))
                        var url = (try! elem?.attribute(.value) as String?)
                        if url != nil && url!.count > 0 && !url!.starts(with: "http")  {
                            url = "https://\(url ?? "")"
                        }
                        return (title, url)
                    }
                }
            }
        } catch { }
    }
    return (nil, nil)
}

struct FavIcon {
    enum Size: Int, CaseIterable { case s = 16, m = 32, l = 64, xl = 128, xxl = 256, xxxl = 512 }
    private let domain: String
    init(_ domain: String) { self.domain = domain }
    subscript(_ size: Size) -> URL {
        URL(string:"https://www.google.com/s2/favicons?sz=\(size.rawValue)&domain=\(domain)")!
    }
}
#endif
