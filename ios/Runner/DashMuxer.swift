import AVFoundation
import Flutter

/// Muxes a DASH episode's separately-downloaded fMP4 tracks (one video-only,
/// one audio-only) into a single playable MP4 via AVFoundation, with no
/// re-encode (passthrough export).
///
/// DASH usually serves video and audio as two independent fragmented-MP4
/// files; each plays on its own but neither is the whole episode. This joins
/// them into one file. `audioPath` may be nil (a muxed-A/V manifest), in which
/// case the video track alone is rewritten.
///
/// Returns true on success; false on any failure so Dart can fall back.
enum DashMuxer {
  static func mux(videoPath: String, audioPath: String?, outputPath: String) -> Bool {
    let videoAsset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
    guard let videoTrack = videoAsset.tracks(withMediaType: .video).first else {
      return false
    }

    let composition = AVMutableComposition()
    guard
      let compVideo = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else { return false }

    do {
      try compVideo.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoAsset.duration),
        of: videoTrack,
        at: .zero
      )
      compVideo.preferredTransform = videoTrack.preferredTransform
    } catch {
      return false
    }

    if let audioPath = audioPath, FileManager.default.fileExists(atPath: audioPath) {
      let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
      if let audioTrack = audioAsset.tracks(withMediaType: .audio).first,
         let compAudio = composition.addMutableTrack(
           withMediaType: .audio,
           preferredTrackID: kCMPersistentTrackID_Invalid
         ) {
        // Audio is best-effort: a video that plays is far better than a mux
        // that fails because one audio range was short.
        try? compAudio.insertTimeRange(
          CMTimeRange(start: .zero, duration: audioAsset.duration),
          of: audioTrack,
          at: .zero
        )
      }
    }

    let outURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: outURL)

    guard
      let export = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetPassthrough
      )
    else { return false }
    export.outputURL = outURL
    export.outputFileType = .mp4

    let semaphore = DispatchSemaphore(value: 0)
    var ok = false
    export.exportAsynchronously {
      ok = export.status == .completed
      semaphore.signal()
    }
    semaphore.wait()
    if !ok {
      try? FileManager.default.removeItem(at: outURL)
    }
    return ok
  }
}
