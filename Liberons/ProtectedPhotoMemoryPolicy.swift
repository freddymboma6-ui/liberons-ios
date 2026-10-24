import CoreGraphics

// App-level shadow for PhotoKit's PHImageManagerMaximumSize.
// ProtectedLibraryView previously requested the largest rendered asset available,
// which can decode multi-megapixel photos at their full pixel dimensions while
// the paged viewer is also retaining neighbouring pages. That is unnecessary for
// an iPhone display and can cause iOS to terminate the process under memory pressure.
//
// 3072 px keeps enough detail for the existing 2.5x–5x interactive zoom while
// bounding a single RGBA decode to roughly 36 MB in the worst square case instead
// of potentially hundreds of MB for modern camera originals.
let PHImageManagerMaximumSize = CGSize(width: 3072, height: 3072)
