import Foundation

/// One rendered key on the Stream Deck. `DeckLayout` produces exactly `keyCount`
/// of these; `DeckdBridge` serialises them for the Python renderer.
public struct DeckKey: Equatable {
    public enum Kind: Equatable {
        /// A session: its label, status, a relative-time "age" string, how many
        /// background agents it's running (0 = no badge), and whether it's been
        /// waiting long enough to escalate (louder pulse).
        case agent(label: DeckLabel, status: SessionStatus, age: String,
                   subagents: Int, stuck: Bool)
        /// The paging key: `remaining` sessions are on further pages.
        case more(remaining: Int)
        /// Part of the "no sessions" banner spanning the whole deck.
        case banner(text: String)
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
