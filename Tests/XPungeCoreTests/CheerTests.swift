import Testing
@testable import XPungeCore

/// Deterministic generator so the random picks are repeatable.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite struct CheerTests {
    @Test(arguments: Cheer.Moment.allCases)
    func prefixIsAnInterjectionThenAnEmoji(moment: Cheer.Moment) {
        var generator = SeededGenerator(state: 42)
        for _ in 0..<50 {
            let prefix = Cheer.prefix(moment, using: &generator)
            #expect(prefix.hasSuffix(" "))
            let word = Cheer.interjections(for: moment).first { prefix.hasPrefix($0 + " ") }
            #expect(word != nil, "\(prefix)")
            if let word {
                let face = String(prefix.dropFirst(word.count + 1).dropLast())
                #expect(Cheer.emoji(for: moment).contains(face), "\(prefix)")
            }
        }
    }

    @Test func cheersVary() {
        var generator = SeededGenerator(state: 7)
        let picks = Set((0..<30).map { _ in Cheer.prefix(.cleaned, using: &generator) })
        #expect(picks.count > 5)
    }
}
