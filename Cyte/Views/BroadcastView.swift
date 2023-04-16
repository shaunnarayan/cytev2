//
//  BroadcastView.swift
//  Cyte
//
//  Created by Shaun Narayan on 16/04/23.
//

import Foundation
import SwiftUI
import ReplayKit
import UIKit

struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
        picker.preferredExtension = "io.cyte.ios.Extension"
        picker.showsMicrophoneButton = false
        return picker
    }
    
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
    }
}
