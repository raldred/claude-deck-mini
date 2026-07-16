import Foundation

/// One rendered key on the Stream Deck. `DeckLayout` produces exactly `keyCount`
/// of these; `DeckdBridge` serialises them for the Python renderer.
public struct DeckKey: Equatable {
    public enum Kind: Equatable {
        /// A session: its label, status, and a relative-time "age" string.
        case agent(label: DeckLabel, status: SessionStatus, age: String)
        /// The paging key: `remaining` sessions are on further pages.
        case more(remaining: Int)
        /// An empty slot.
        case blank
    }

    public let index: Int
    public let kind: Kind

    public init(index: Int, kind: Kind) {
        self.index = index
        self.kind = kind
    }
}
