/// A random interjection and emoji to start a success message, e.g. "Woohoo! 🎉 ".
/// Kept out of tables: emoji are two columns wide and would break the borders.
public enum Cheer {
    public enum Moment: CaseIterable, Sendable {
        /// `scan` finished.
        case scanned
        /// A dry run showed its plan.
        case previewed
        /// A clean finished with no failures.
        case cleaned
        /// There was nothing to clean.
        case spotless
    }

    static func interjections(for moment: Moment) -> [String] {
        switch moment {
        case .scanned: ["Ta-da!", "Voilà!", "Behold!", "Here we go!", "Lo and behold!"]
        case .previewed: ["Psst!", "Heads up!", "Just looking!", "No worries!", "Sneak peek!"]
        case .cleaned: ["Woohoo!", "Boom!", "Sweet!", "Whoosh!", "Yay!", "Ta-da!", "Hooray!", "Kaboom!"]
        case .spotless: ["All clear!", "Spotless!", "Squeaky clean!", "Nothing to see here!"]
        }
    }

    static func emoji(for moment: Moment) -> [String] {
        switch moment {
        case .scanned: ["📊", "🔍", "🧐", "📦"]
        case .previewed: ["👀", "🔭", "🫣", "🗺️"]
        case .cleaned: ["🎉", "🧹", "✨", "🚀", "🥳", "💨"]
        case .spotless: ["✨", "😌", "🫧", "🧼"]
        }
    }

    /// "Interjection emoji " with a trailing space, ready to put in front of a message.
    public static func prefix<G: RandomNumberGenerator>(_ moment: Moment, using generator: inout G) -> String {
        let word = interjections(for: moment).randomElement(using: &generator)!
        let face = emoji(for: moment).randomElement(using: &generator)!
        return "\(word) \(face) "
    }

    public static func prefix(_ moment: Moment) -> String {
        var generator = SystemRandomNumberGenerator()
        return prefix(moment, using: &generator)
    }
}
