//
//  Export.swift
//  Cyte
//
//  Created by Shaun Narayan on 30/03/23.
//

import Foundation
import AVKit

///
/// Build up a composition with references to the assets for supplied episodes
/// Scale based on requested length, optionally apply watermark, and trigger export
/// The exporter is returned to the caller so it can track progress and cancel if needed
///
func makeTimelapse(episodes: [Episode], timelapse_len_seconds: Int = 60, reveal: Bool = true) async -> AVAssetExportSession {
    let movie = AVMutableComposition()
    let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
//    let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

    var export_title: String = ""
    var sum_seconds: Double = 0.0
    for episode in episodes {
        let url = urlForEpisode(start: episode.start, title: episode.title)
        export_title += episode.title ?? ""
        
        let asset = AVURLAsset(url: url)
        do {
            let assetDuration = try await asset.load(.duration)
    //        let assetAudioTrack = asset.tracks(withMediaType: .audio).first!
            let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first
            if assetVideoTrack != nil {
                let assetRange = CMTimeRangeMake(start: CMTime.zero, duration:assetDuration )
                let at = CMTime(value: CMTimeValue(sum_seconds), timescale: 1)
                
                try videoTrack?.insertTimeRange(assetRange, of: assetVideoTrack!, at: at)
                //            try audioTrack?.insertTimeRange(assetRange, of: assetAudioTrack, at: at)
                sum_seconds += assetDuration.seconds
            }
        } catch {}   
    }
    
    export_title = "\(export_title.hashValue).mov"
    movie.scaleTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: movie.duration), toDuration: CMTime(value: CMTimeValue(timelapse_len_seconds), timescale: 1))
    
    //create exporter
    let outputMovieURL: URL = homeDirectory().appendingPathComponent("Exports").appendingPathComponent(export_title)
    do {
        try FileManager.default.createDirectory(at: outputMovieURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        if FileManager.default.fileExists(atPath: outputMovieURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: outputMovieURL)
        }
    } catch { log.error("Failed to create export dir") }
    
    let exporter = AVAssetExportSession(asset: movie,
                                   presetName: AVAssetExportPresetHighestQuality)
    //configure exporter
    exporter?.outputURL = outputMovieURL
    exporter?.outputFileType = .mov
//    exporter?.videoComposition = videoComposition
    let _ = exporter?.exportAsynchronously() {
        DispatchQueue.main.async {
            if let error = exporter?.error {
                log.error("failed \(error.localizedDescription)")
            } else {
                if reveal {
                    if FileManager.default.fileExists(atPath: outputMovieURL.path(percentEncoded: false)) {
#if os(macOS)
                        NSWorkspace.shared.activateFileViewerSelecting([outputMovieURL])
#endif
                        log.info("movie has been exported to \(outputMovieURL)")
                    }
                }
            }
        }
    }
    
    return exporter!
}
