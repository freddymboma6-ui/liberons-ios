from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
old='''.buttonStyle(.plain)
          .padding(.top, 76)
      }
      .padding(.horizontal, 14)'''
new='''.buttonStyle(.plain)
          .padding(.trailing, current?.mediaType.lowercased().contains("video") == true ? 72 : 0)
          .padding(.top, current?.mediaType.lowercased().contains("video") == true ? 0 : 76)
      }
      .padding(.horizontal, 14)'''
if old not in s: raise SystemExit('gallery info placement anchor not found')
s=s.replace(old,new,1)
if 'speaker.slash.fill' in s or 'isVideoMuted' in s: raise SystemExit('custom audio control must not exist')
p.write_text(s)
