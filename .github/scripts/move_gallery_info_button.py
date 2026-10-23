from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
# Add Apple-style chrome visibility state.
needle='''    @State private var isDismissing = false\n    private let indexByID: [UUID: Int]'''
replacement='''    @State private var isDismissing = false\n    @State private var chromeVisible = true\n    private let indexByID: [UUID: Int]'''
if needle not in s: raise SystemExit('viewer state anchor not found')
s=s.replace(needle,replacement,1)
old='''.opacity(verticalDismissLocked ? Double(max(0, 1 - dismissProgress * 4)) : 1)\n  .allowsHitTesting(!verticalDismissLocked)'''
new='''.opacity(verticalDismissLocked ? Double(max(0, 1 - dismissProgress * 4)) : (chromeVisible ? 1 : 0))\n  .allowsHitTesting(!verticalDismissLocked && chromeVisible)\n  .animation(.easeOut(duration: 0.18), value: chromeVisible)'''
if old not in s: raise SystemExit('chrome opacity anchor not found')
s=s.replace(old,new,1)
old='''.contentShape(Rectangle())\n        .simultaneousGesture(\n  DragGesture(minimumDistance: 10, coordinateSpace: .global)'''
new='''.contentShape(Rectangle())\n        .onTapGesture {\n            guard !verticalDismissLocked, !showInfo else { return }\n            withAnimation(.easeOut(duration: 0.18)) { chromeVisible.toggle() }\n        }\n        .simultaneousGesture(\n  DragGesture(minimumDistance: 10, coordinateSpace: .global)'''
if old not in s: raise SystemExit('gesture anchor not found')
s=s.replace(old,new,1)
old='''      .onChange(of: selection) { _, newID in\n          prefetchNeighbors(around: newID)\n      }'''
new='''      .onChange(of: selection) { _, newID in\n          chromeVisible = true\n          prefetchNeighbors(around: newID)\n      }'''
if old not in s: raise SystemExit('selection anchor not found')
s=s.replace(old,new,1)
s=s.replace('    @State private var isVideoMuted = false\n','')
s=s.replace('                        player.isMuted = isVideoMuted\n','')
if 'speaker.slash.fill' in s or 'isVideoMuted' in s: raise SystemExit('duplicate custom audio control present')
if '.buttonStyle(.plain).offset(y: 64)' not in s: raise SystemExit('info control is not below native audio zone')
p.write_text(s)
# premium-viewer-trigger-2
