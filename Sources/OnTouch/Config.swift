import Foundation

/// One gesture → action binding. A gesture is described by whether a finger is
/// held as an anchor, how many *other* fingers act, whether they tap or swipe,
/// and the direction.
///
///   anchor:    true if one finger is held still while others act
///   fingers:   number of acting fingers (the anchor is not counted)
///   type:      "tap" | "swipe"
///   direction: tap   → "left" | "right" | "up" | "down" | "any"
///                       (position of the tap relative to the anchor)
///              swipe → "left" | "right" | "up" | "down"
///   action:    a built-in name (see Keys.builtins) or a chord like "cmd+shift+t"
///   apps:      optional bundle IDs to restrict this binding to; nil = use the
///              global targetBundleIDs
struct Mapping: Codable {
    var anchor: Bool = true
    var fingers: Int = 1
    var type: String = "tap"
    var direction: String = "right"
    var action: String = ""
    var apps: [String]? = nil

    init(anchor: Bool = true, fingers: Int = 1, type: String, direction: String, action: String, apps: [String]? = nil) {
        self.anchor = anchor; self.fingers = fingers; self.type = type
        self.direction = direction; self.action = action; self.apps = apps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Mapping(type: "tap", direction: "right", action: "")
        d.anchor    = try c.decodeIfPresent(Bool.self,   forKey: .anchor)    ?? d.anchor
        d.fingers   = try c.decodeIfPresent(Int.self,    forKey: .fingers)   ?? d.fingers
        d.type      = try c.decodeIfPresent(String.self, forKey: .type)      ?? d.type
        d.direction = try c.decodeIfPresent(String.self, forKey: .direction) ?? d.direction
        d.action    = try c.decodeIfPresent(String.self, forKey: .action)    ?? d.action
        d.apps      = try c.decodeIfPresent([String].self, forKey: .apps)    ?? d.apps
        self = d
    }
}

/// Tunable thresholds + gesture bindings. Override any subset by writing
/// ~/.config/trackpad-tabs/config.json.
struct Config: Codable {
    var anchorMinHold: Double = 0.05
    var anchorMaxMove: Double = 0.09
    var tapMaxDuration: Double = 0.35
    var tapMaxMove: Double = 0.08
    var swipeDist: Double = 0.10
    var minTouchSize: Double = 0.01
    var cooldown: Double = 0.2
    var targetBundleIDs: [String] = ["com.apple.Safari"]

    /// Jitouch-style defaults. Hold one finger as the anchor, then:
    var mappings: [Mapping] = [
        Mapping(fingers: 1, type: "tap",   direction: "left",  action: "prevTab"),
        Mapping(fingers: 1, type: "tap",   direction: "right", action: "nextTab"),
        Mapping(fingers: 1, type: "swipe", direction: "left",  action: "back"),
        Mapping(fingers: 1, type: "swipe", direction: "right", action: "forward"),
        Mapping(fingers: 1, type: "swipe", direction: "up",    action: "reload"),
        Mapping(fingers: 2, type: "swipe", direction: "down",  action: "closeTab"),
        Mapping(fingers: 2, type: "swipe", direction: "up",    action: "newTab"),
        Mapping(fingers: 2, type: "tap",   direction: "any",   action: "reopenTab"),
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Config()
        d.anchorMinHold   = try c.decodeIfPresent(Double.self, forKey: .anchorMinHold)   ?? d.anchorMinHold
        d.anchorMaxMove   = try c.decodeIfPresent(Double.self, forKey: .anchorMaxMove)   ?? d.anchorMaxMove
        d.tapMaxDuration  = try c.decodeIfPresent(Double.self, forKey: .tapMaxDuration)  ?? d.tapMaxDuration
        d.tapMaxMove      = try c.decodeIfPresent(Double.self, forKey: .tapMaxMove)      ?? d.tapMaxMove
        d.swipeDist       = try c.decodeIfPresent(Double.self, forKey: .swipeDist)       ?? d.swipeDist
        d.minTouchSize    = try c.decodeIfPresent(Double.self, forKey: .minTouchSize)    ?? d.minTouchSize
        d.cooldown        = try c.decodeIfPresent(Double.self, forKey: .cooldown)        ?? d.cooldown
        d.targetBundleIDs = try c.decodeIfPresent([String].self, forKey: .targetBundleIDs) ?? d.targetBundleIDs
        d.mappings        = try c.decodeIfPresent([Mapping].self, forKey: .mappings)     ?? d.mappings
        self = d
    }

    static let shared: Config = load()

    private static func load() -> Config {
        let path = ("~/.config/trackpad-tabs/config.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        NSLog("OnTouch: loaded config from \(path) (\(cfg.mappings.count) mappings)")
        return cfg
    }
}
