import Foundation

/// Tunable thresholds for gesture recognition. All distances are in
/// normalized trackpad units (0..1). Times are in seconds.
///
/// Override any value by creating ~/.config/trackpad-tabs/config.json, e.g.:
/// { "swipeDownDist": 0.08, "tapMaxDuration": 0.40 }
struct Config: Codable {
    // A finger qualifies as the "anchor" once it has been held this long
    // while moving less than `anchorMaxMove`.
    var anchorMinHold: Double = 0.05
    var anchorMaxMove: Double = 0.09

    // A lift counts as a "tap" if it was this brief and moved this little.
    var tapMaxDuration: Double = 0.35
    var tapMaxMove: Double = 0.08

    // Two-finger downward swipe must travel at least this far in -y.
    var swipeDownDist: Double = 0.10

    // Minimum contact size to treat a finger as actually touching
    // (filters out hovers / proximity noise).
    var minTouchSize: Double = 0.01

    // After firing a gesture, ignore further input for this long. Kept short
    // so repeated taps (tab, tab, tab…) feel responsive; mainly debounces a
    // single contact from registering twice.
    var cooldown: Double = 0.2

    // Bundle identifiers the gestures act on. Gestures are ignored unless
    // one of these apps is frontmost.
    var targetBundleIDs: [String] = ["com.apple.Safari"]

    init() {}

    // Custom decoder so a partial JSON only overrides the keys it specifies;
    // any omitted key keeps its default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Config()
        d.anchorMinHold  = try c.decodeIfPresent(Double.self, forKey: .anchorMinHold)  ?? d.anchorMinHold
        d.anchorMaxMove  = try c.decodeIfPresent(Double.self, forKey: .anchorMaxMove)  ?? d.anchorMaxMove
        d.tapMaxDuration = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration) ?? d.tapMaxDuration
        d.tapMaxMove     = try c.decodeIfPresent(Double.self, forKey: .tapMaxMove)     ?? d.tapMaxMove
        d.swipeDownDist  = try c.decodeIfPresent(Double.self, forKey: .swipeDownDist)  ?? d.swipeDownDist
        d.minTouchSize   = try c.decodeIfPresent(Double.self, forKey: .minTouchSize)   ?? d.minTouchSize
        d.cooldown       = try c.decodeIfPresent(Double.self, forKey: .cooldown)       ?? d.cooldown
        d.targetBundleIDs = try c.decodeIfPresent([String].self, forKey: .targetBundleIDs) ?? d.targetBundleIDs
        self = d
    }

    static let shared: Config = load()

    private static func load() -> Config {
        let path = ("~/.config/trackpad-tabs/config.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        NSLog("OnTouch: loaded config from \(path)")
        return cfg
    }
}
