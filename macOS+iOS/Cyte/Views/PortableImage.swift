//
//  PortableImage.swift
//  Cyte
//
//  Created by Shaun Narayan on 15/04/23.
//

import Foundation
import SwiftUI

struct PortableImage: View {
    @State var uiImage: UIImage
    var body: some View {
#if os(macOS)
        Image(nsImage: uiImage)
#else
        Image(uiImage: uiImage)
#endif
    }
}
