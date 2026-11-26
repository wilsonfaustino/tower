import SwiftUI

// Places subviews left to right at their ideal size and starts a new line when the next one does not fit.
struct FlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    let frames = frames(of: subviews, maxWidth: proposal.width ?? .infinity)
    return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
    for (subview, frame) in zip(subviews, frames(of: subviews, maxWidth: bounds.width)) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
    }
  }

  private func frames(of subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
    var frames: [CGRect] = []
    var origin = CGPoint.zero
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if origin.x > 0, origin.x + size.width > maxWidth {
        origin = CGPoint(x: 0, y: origin.y + lineHeight + spacing)
        lineHeight = 0
      }
      frames.append(CGRect(origin: origin, size: size))
      origin.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return frames
  }
}
