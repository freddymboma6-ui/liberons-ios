from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
# Add Apple-style chrome visibility state.
needle='''    @State private var isDismissing = false\n    private let indexByID: [UUID: Int]'''
replacement='''    @State private var isDismissing = false\n    @State private var chromeVisible = true\n    private let indexByID: [UUID: Int]'''
if needle not in s: raise SystemExit('viewer state anchor not found')
s=s.replace(needle,replacement,1)
# Keep info directly below the native Apple audio zone and make top chrome disappear as one unit.
old='''.opacity(verticalDismissLocked ? Double(max(0, 1 - dismissProgress * 4)) : 1)\n  .allowsHitTesting(!verticalDismissLocked)'''
new='''.opacity(verticalDismissLocked ? Double(max(0, 1 - dismissProgress * 4)) : (chromeVisible ? 1 : 0))\n  .allowsHitTesting(!verticalDismissLocked && chromeVisible)\n  .animation(.easeOut(duration: 0.18), value: chromeVisible)'''
if old not in s: raise SystemExit('chrome opacity anchor not found')
s=s.replace(old,new,1)
# Tap empty media area to show/hide Libérons chrome, matching Photos. Preserve info-sheet tap behavior.
old='''.contentShape(Rectangle())\n        .simultaneousGesture(\n  DragGesture(minimumDistance: 10, coordinateSpace: .global)'''
new='''.contentShape(Rectangle())\n        .onTapGesture {\n            guard !verticalDismissLocked, !showInfo else { return }\n            withAnimation(.easeOut(duration: 0.18)) { chromeVisible.toggle() }\n        }\n        .simultaneousGesture(\n  DragGesture(minimumDistance: 10, coordinateSpace: .global)'''
if old not in s: raise SystemExit('gesture anchor not found')
s=s.replace(old,new,1)
# When swiping to another memory, restore chrome so navigation remains discoverable.
old='''      .onChange(of: selection) { _, newID in\n          prefetchNeighbors(around: newID)\n      }'''
new='''      .onChange(of: selection) { _, newID in\n          chromeVisible = true\n          prefetchNeighbors(around: newID)\n      }'''
if old not in s: raise SystemExit('selection anchor not found')
s=s.replace(old,new,1)
# Ensure the custom duplicate mute never returns.
s=s.replace('    @State private var isVideoMuted = false\n','')
s=s.replace('                        player.isMuted = isVideoMuted\n','')
if 'speaker.slash.fill' in s or 'isVideoMuted' in s: raise SystemExit('duplicate custom audio control present')
# Current info control must remain vertically below Apple's native top-right audio control.
if '.buttonStyle(.plain).offset(y: 64)' not in s: raise SystemExit('info control is not below native audio zone')
p.write_text(s)
