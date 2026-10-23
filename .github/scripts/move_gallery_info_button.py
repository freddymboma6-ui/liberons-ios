from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
s=s.replace('    @State private var isVideoMuted = false\n','')
s=s.replace('                        player.isMuted = isVideoMuted\n','')
custom='''

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
                }'''
s=s.replace(custom,'')
old='''          Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56) }.buttonStyle(.plain).padding(.trailing, 54)'''
new='''          Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56) }.buttonStyle(.plain).offset(y: 64)'''
if old not in s: raise SystemExit('current info button line not found')
s=s.replace(old,new,1)
if 'isVideoMuted' in s or 'speaker.slash.fill' in s: raise SystemExit('duplicate custom audio control still present')
p.write_text(s)
