from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
old='''          Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56) }.buttonStyle(.plain)'''
new='''          Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56) }.buttonStyle(.plain).padding(.trailing, 54)'''
if old not in s: raise SystemExit('info button line not found')
s=s.replace(old,new,1)
p.write_text(s)
