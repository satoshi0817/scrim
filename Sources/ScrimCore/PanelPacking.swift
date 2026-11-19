import Foundation

/// Fits panels around the active tile on Scrim's 12 × 8 editing grid.
public struct PanelPacking {
    private let grid: PanelGrid
    private let columns = Placement.gridColumns
    private let rows = Placement.gridRows

    public init(screen: CGSize) { grid = PanelGrid(screen: screen) }

    private func cells(_ frame: CGRect) -> CGRect {
        let width = min(CGFloat(columns), max(1, ((frame.width + grid.gap) / grid.step.width).rounded()))
        let height = min(CGFloat(rows), max(1, ((frame.height + grid.gap) / grid.step.height).rounded()))
        return CGRect(x: min(CGFloat(columns)-width, max(0, ((frame.minX-grid.bounds.minX)/grid.step.width).rounded())),
                      y: min(CGFloat(rows)-height, max(0, ((frame.minY-grid.bounds.minY)/grid.step.height).rounded())),
                      width: width, height: height)
    }

    private func frame(_ rect: CGRect) -> CGRect {
        grid.frame(column: Int(rect.minX), row: Int(rect.minY), columns: Int(rect.width), rows: Int(rect.height))
    }

    public func snapped(_ target: CGRect) -> CGRect { frame(cells(target)) }

    public func initial(others: [CGRect]) -> CGRect {
        var best = CGRect.zero
        var cost = CGFloat.infinity
        for row in (0..<rows).reversed() {
            for column in 0..<(columns-1) {
                let candidate = grid.frame(column: column, row: row, columns: 2, rows: 1)
                let overlap = others.reduce(CGFloat.zero) { total, other in
                    let common = candidate.intersection(other)
                    return total + (common.isNull ? 0 : common.width * common.height)
                }
                if overlap == 0 { return candidate }
                if overlap < cost { best = candidate; cost = overlap }
            }
        }
        return best
    }

    public func layout(target: CGRect, others: [CGRect]) -> (target: CGRect, others: [CGRect])? {
        let tile = cells(target)
        let originals = others.map(cells)
        var occupied = Array(repeating: false, count: rows * columns)
        var remaining = occupied.count
        func reserve(_ rect: CGRect) {
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) { occupied[y * columns + x] = true }
            }
            remaining -= Int(rect.width * rect.height)
        }
        reserve(tile)
        guard remaining >= others.count else { return nil }
        var result = originals
        // Keep unaffected tiles first. Reserve at least one cell for each remaining tile.
        let order = originals.indices.sorted {
            let a = originals[$0].intersection(tile), b = originals[$1].intersection(tile)
            let aa = a.isNull ? 0 : a.width*a.height, ba = b.isNull ? 0 : b.width*b.height
            return aa == ba ? $0 < $1 : aa < ba
        }
        for (offset, index) in order.enumerated() {
            let original = originals[index]
            let budget = remaining - (others.count - offset - 1)
            var best: CGRect?
            var bestCost = CGFloat.infinity
            for y in 0..<rows {
                for x in 0..<columns where !occupied[y*columns+x] {
                    var width = min(Int(original.width), columns-x)
                    for h in 1...min(Int(original.height), rows-y) {
                        let rowStart = (y+h-1)*columns+x
                        if let block = (0..<width).first(where: { occupied[rowStart+$0] }) { width = block }
                        let w = min(width, budget/h)
                        if w == 0 { break }
                        let rect = CGRect(x: x, y: y, width: w, height: h)
                        let displacement = abs(rect.midX-original.midX) + abs(rect.midY-original.midY)
                        let cost = original.width*original.height - rect.width*rect.height + displacement * 2
                        if cost < bestCost { bestCost = cost; best = rect }
                    }
                }
            }
            guard let best else { return nil }
            result[index] = best
            reserve(best)
        }
        return (frame(tile), result.map(frame))
    }
}
