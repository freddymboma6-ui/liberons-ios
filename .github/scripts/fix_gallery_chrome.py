from pathlib import Path
p = Path('Liberons/ProtectedLibraryView.swift')
s = p.read_text()

s = s.replace(
    'ForEach(items) { CloudPhotoPage(item: $0, language: language, billing: billing).tag($0.id) }',
    'ForEach(items) { CloudPhotoPage(item: $0, language: language, billing: billing, chromeVisible: $chromeVisible).tag($0.id) }'
)

s = s.replace(
    '.buttonStyle(.plain)\n          .padding(.trailing, current?.mediaType.lowercased().contains("video") == true ? 72 : 0)',
    '.buttonStyle(.plain)'
)

s = s.replace(
    '@ObservedObject var billing: CloudStorageSummary\n    @State private var image: UIImage?',
    '@ObservedObject var billing: CloudStorageSummary\n    @Binding var chromeVisible: Bool\n    @State private var image: UIImage?'
)

s = s.replace(
    'ProtectedVideoSurface(player: player)\n\n                    HStack(spacing: 54) {',
    '''ProtectedVideoSurface(player: player)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) {
                                chromeVisible.toggle()
                            }
                        }

                    HStack(spacing: 54) {'''
)

s = s.replace(
    '''                    }

                    VStack {
                        Spacer()''',
    '''                    }
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(chromeVisible)
                    .animation(.easeOut(duration: 0.18), value: chromeVisible)

                    VStack {
                        Spacer()''',
    1
)

needle = '''                        .padding(.bottom, 14)
                    }
                }
                .onAppear {'''
replacement = '''                        .padding(.bottom, 14)
                    }
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(chromeVisible)
                    .animation(.easeOut(duration: 0.18), value: chromeVisible)
                }
                .onAppear {'''
if needle not in s:
    raise SystemExit('video timeline anchor not found')
s = s.replace(needle, replacement, 1)

if 'padding(.trailing, current?.mediaType.lowercased().contains("video") == true ? 72 : 0)' in s:
    raise SystemExit('ellipsis is still offset from the right edge')
if 'CloudPhotoPage(item: $0, language: language, billing: billing, chromeVisible: $chromeVisible)' not in s:
    raise SystemExit('binding was not wired')
if '@Binding var chromeVisible: Bool' not in s:
    raise SystemExit('CloudPhotoPage binding missing')

p.write_text(s)
