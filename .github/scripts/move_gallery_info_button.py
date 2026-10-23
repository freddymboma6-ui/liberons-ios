from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
old='''            if isVideo, let player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                        isVideoPlaying = true
                        installVideoProgressObserver(on: player)
                    }
                    .onDisappear {
                        player.pause()
                        isVideoPlaying = false
                        removeVideoProgressObserver()
                    }
            }'''
new='''            if isVideo, let player {
                ZStack {
                    ProtectedVideoSurface(player: player)

                    HStack(spacing: 54) {
                        Button {
                            let target = max(0, videoCurrentTime - 10)
                            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 31, weight: .medium))
                                .foregroundStyle(.white)
                        }

                        Button {
                            if player.rate > 0 {
                                player.pause()
                                isVideoPlaying = false
                            } else {
                                player.play()
                                isVideoPlaying = true
                            }
                        } label: {
                            Image(systemName: isVideoPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 82, height: 82)
                                .background(.black.opacity(0.42), in: Circle())
                        }

                        Button {
                            let duration = max(videoDuration, videoCurrentTime + 10)
                            let target = min(duration, videoCurrentTime + 10)
                            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 31, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Text(protectedVideoTime(videoCurrentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                            Slider(
                                value: Binding(
                                    get: { min(videoCurrentTime, max(videoDuration, 0.01)) },
                                    set: { value in
                                        videoCurrentTime = value
                                        player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
                                    }
                                ),
                                in: 0...max(videoDuration, 0.01)
                            )
                            .tint(.white)
                            Text("−" + protectedVideoTime(max(0, videoDuration - videoCurrentTime)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                }
                .onAppear {
                    player.play()
                    isVideoPlaying = true
                    installVideoProgressObserver(on: player)
                }
                .onDisappear {
                    player.pause()
                    isVideoPlaying = false
                    removeVideoProgressObserver()
                }
            }'''
if old not in s: raise SystemExit('VideoPlayer block not found')
s=s.replace(old,new,1)
anchor='''    @MainActor private func load() async {'''
helper='''    private func protectedVideoTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

'''
idx=s.find(anchor, s.find('private struct CloudPhotoPage'))
if idx < 0: raise SystemExit('CloudPhotoPage load anchor not found')
s=s[:idx]+helper+s[idx:]
marker='''private struct ProtectedZoomablePhoto: View {'''
surface='''private struct ProtectedVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ProtectedPlayerLayerView {
        let view = ProtectedPlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: ProtectedPlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class ProtectedPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
}

'''
if marker not in s: raise SystemExit('zoomable photo marker not found')
s=s.replace(marker,surface+marker,1)
if 'VideoPlayer(player:' in s: raise SystemExit('native VideoPlayer still present')
p.write_text(s)
