from pathlib import Path
p = Path('Liberons/ProtectedLibraryView.swift')
s = p.read_text()
old = '''          .buttonStyle(.plain)
          .padding(.trailing, current?.mediaType.lowercased().contains("video") == true ? 72 : 0)
          .padding(.top, current?.mediaType.lowercased().contains("video") == true ? 0 : 76)'''
new = '''          .buttonStyle(.plain)
          .padding(.trailing, current?.mediaType.lowercased().contains("video") == true ? 72 : 0)'''
if old not in s:
    raise SystemExit('info button placement anchor not found')
s = s.replace(old, new, 1)
p.write_text(s)
