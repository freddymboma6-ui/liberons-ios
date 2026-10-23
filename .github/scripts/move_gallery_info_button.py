from pathlib import Path
p=Path('Liberons/ProtectedLibraryView.swift')
s=p.read_text()
old='''  VStack {
      HStack {
          Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title2.bold()).foregroundStyle(.white).frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }.buttonStyle(.plain)
          if let i = currentIndex { Text("\\(i + 1) / \\(items.count)").font(.subheadline.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.45), in: Capsule()) }
          Spacer()
          Button { showInfo = true } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(.white).frame(width: 56, height: 56) }.buttonStyle(.plain).offset(y: 64)
      }.padding(.horizontal, 8).padding(.top, 4)
      Spacer()
  }'''
new='''  VStack {
      HStack(alignment: .top) {
          HStack(spacing: 10) {
              Button { dismiss() } label: {
                  Image(systemName: "chevron.left")
                      .font(.title2.bold())
                      .foregroundStyle(.white)
                      .frame(width: 48, height: 48)
                      .background(.black.opacity(0.45), in: Circle())
              }
              .buttonStyle(.plain)
              if let i = currentIndex {
                  Text("\\(i + 1) / \\(items.count)")
                      .font(.subheadline.bold())
                      .foregroundStyle(.white)
                      .padding(.horizontal, 10)
                      .frame(height: 48)
                      .background(.black.opacity(0.45), in: Capsule())
              }
          }
          Spacer()
          Button { showInfo = true } label: {
              Image(systemName: "ellipsis")
                  .font(.system(size: 20, weight: .bold))
                  .foregroundStyle(.white)
                  .frame(width: 48, height: 48)
                  .background(.black.opacity(0.45), in: Circle())
          }
          .buttonStyle(.plain)
          .padding(.top, 76)
      }
      .padding(.horizontal, 14)
      .padding(.top, 4)
      Spacer()
  }'''
if old not in s: raise SystemExit('viewer top chrome anchor not found')
s=s.replace(old,new,1)
if 'speaker.slash.fill' in s or 'isVideoMuted' in s: raise SystemExit('duplicate custom audio control present')
p.write_text(s)
# focused-fix-trigger
