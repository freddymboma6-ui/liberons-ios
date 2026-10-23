from pathlib import Path

p = Path("Liberons/ProtectedLibraryView.swift")
s = p.read_text()

old = '''    @State private var videoDuration: Double = 0
    @State private var videoObserver: Any?
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }'''
new = '''    @State private var videoDuration: Double = 0
    @State private var videoObserver: Any?
    @State private var isVideoMuted = false
    private var isVideo: Bool { item.mediaType.lowercased().contains("video") }'''
if old not in s:
    raise SystemExit("video state block not found")
s = s.replace(old, new, 1)

old = '''            if isVideo, let player {
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
new = '''            if isVideo, let player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.isMuted = isVideoMuted
                        player.play()
                        isVideoPlaying = true
                        installVideoProgressObserver(on: player)
                    }
                    .onDisappear {
                        player.pause()
                        isVideoPlaying = false
                        removeVideoProgressObserver()
                    }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isVideoMuted.toggle()
                            player.isMuted = isVideoMuted
                        } label: {
                            Image(systemName: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.52), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.text(isVideoMuted ? "Unmute video" : "Mute video", isVideoMuted ? "Activer le son" : "Couper le son"))
                    }
                    .padding(.trailing, 14)
                    .padding(.top, 86)
                    Spacer()
                }
            }'''
if old not in s:
    raise SystemExit("VideoPlayer block not found")
s = s.replace(old, new, 1)

p.write_text(s)
