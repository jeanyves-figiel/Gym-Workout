import SwiftUI

/// How an iPhone Duo is held (#598): flat (open or folded, held normally), Flex (half open on a table, landscape:
/// top half to watch, bottom half to tap), Book (half open, portrait: left and right pages) or Tent (stood up
/// on its edges, read from a distance). Other iPhones are always `.flat`.
enum DuoPosture: String {
    case flat, flex, book, tent

    /// DEBUG `-duoPosture flex|book|tent`: the simulator has no hinge, so CI screenshots force one.
    static var forced: DuoPosture? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-duoPosture"), args.indices.contains(i + 1) { return DuoPosture(rawValue: args[i + 1]) }
        #endif
        return nil
    }
}
