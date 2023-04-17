//
//  Events.swift
//  Cyte
//
//  From stackoverflow
//

import Foundation
import SwiftUI
import Vision
#if os(macOS)
    import Carbon
    import AppKit
#endif

extension utsname {
    static var sMachine: String {
        var utsname = utsname()
        uname(&utsname)
        return withUnsafePointer(to: &utsname.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }
    static var isAppleSilicon: Bool {
        sMachine == "arm64"
    }
}

func procVisionResult(request: VNRequest, error: Error?, minConfidence: Float = 0.45) -> [(String, CGRect)] {
    guard let observations =
            request.results as? [VNRecognizedTextObservation] else {
        return []
    }
    let recognizedStringsAndRects: [(String, CGRect)] = observations.compactMap { observation in
        // Find the top observation.
        guard let candidate = observation.topCandidates(1).first else { return ("", .zero) }
        if observation.confidence < minConfidence { return ("", .zero) }
        
        // Find the bounding-box observation for the string range.
        let stringRange = candidate.string.startIndex..<candidate.string.endIndex
        let boxObservation = try? candidate.boundingBox(for: stringRange)
        
        // Get the normalized CGRect value.
        let boundingBox = boxObservation?.boundingBox ?? .zero
        
        // Convert the rectangle from normalized coordinates to image coordinates.
        return (candidate.string, boundingBox)
    }
    return recognizedStringsAndRects
}

func getApplicationNameFromBundleID(bundleID: String) -> String? {
#if os(macOS)
    guard let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path(percentEncoded: false)
    else { return bundleID }
    guard let appBundle = Bundle(path: path),
          let executableName = appBundle.executableURL?.lastPathComponent else {
        return bundleID
    }
    return executableName
#else
    return bundleID
#endif
}

extension String {
  /// This converts string to UInt as a fourCharCode
  public var fourCharCodeValue: Int {
    var result: Int = 0
    if let data = self.data(using: String.Encoding.macOSRoman) {
      data.withUnsafeBytes({ (rawBytes) in
        let bytes = rawBytes.bindMemory(to: UInt8.self)
        for i in 0 ..< data.count {
          result = result << 8 + Int(bytes[i])
        }
      })
    }
    return result
  }
}
#if os(macOS)
class HotkeyListener {
  static
  func getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags) -> UInt32 {
    let flags = cocoaFlags.rawValue
    var newFlags: Int = 0

    if ((flags & NSEvent.ModifierFlags.control.rawValue) > 0) {
      newFlags |= controlKey
    }

    if ((flags & NSEvent.ModifierFlags.command.rawValue) > 0) {
      newFlags |= cmdKey
    }

    if ((flags & NSEvent.ModifierFlags.shift.rawValue) > 0) {
      newFlags |= shiftKey;
    }

    if ((flags & NSEvent.ModifierFlags.option.rawValue) > 0) {
      newFlags |= optionKey
    }

    if ((flags & NSEvent.ModifierFlags.capsLock.rawValue) > 0) {
      newFlags |= alphaLock
    }

    return UInt32(newFlags);
  }

  static func register() {
    var hotKeyRef: EventHotKeyRef?
    let modifierFlags: UInt32 =
      getCarbonFlagsFromCocoaFlags(cocoaFlags: NSEvent.ModifierFlags.command)

    let keyCode = kVK_ANSI_Period
    var gMyHotKeyID = EventHotKeyID()

    gMyHotKeyID.id = UInt32(keyCode)

    // Not sure what "swat" vs "htk1" do.
    gMyHotKeyID.signature = OSType("swat".fourCharCodeValue)
    // gMyHotKeyID.signature = OSType("htk1".fourCharCodeValue)

    var eventType = EventTypeSpec()
    eventType.eventClass = OSType(kEventClassKeyboard)
    eventType.eventKind = OSType(kEventHotKeyPressed)

    // Install handler.
    InstallEventHandler(GetApplicationEventTarget(), {
      (nextHanlder, theEvent, userData) -> OSStatus in
      // var hkCom = EventHotKeyID()

      // GetEventParameter(theEvent,
      //                   EventParamName(kEventParamDirectObject),
      //                   EventParamType(typeEventHotKeyID),
      //                   nil,
      //                   MemoryLayout<EventHotKeyID>.size,
      //                   nil,
      //                   &hkCom)

      NSLog("Command + . Pressed!")
//        NSWorkspace.shared.hideOtherApplications()
        NSApplication.shared.activate(ignoringOtherApps: true)

      return noErr
      /// Check that hkCom in indeed your hotkey ID and handle it.
    }, 1, &eventType, nil, nil)

    // Register hotkey.
    let status = RegisterEventHotKey(UInt32(keyCode),
                                     modifierFlags,
                                     gMyHotKeyID,
                                     GetApplicationEventTarget(),
                                     0,
                                     &hotKeyRef)
    assert(status == noErr)    
  }
}
#endif
