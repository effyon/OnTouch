import CoreGraphics

/// A resolved key event: a virtual key code plus modifier flags.
struct Keystroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

/// Resolves action strings into keystrokes. An action is either a built-in
/// name (e.g. "nextTab") or a literal chord (e.g. "cmd+shift+t").
enum Keys {
    /// Friendly action names → key chords. Browser-focused, but any chord works.
    static let builtins: [String: String] = [
        "nextTab":       "ctrl+tab",
        "prevTab":       "ctrl+shift+tab",
        "closeTab":      "cmd+w",
        "newTab":        "cmd+t",
        "reopenTab":     "cmd+shift+t",
        "closeWindow":   "cmd+shift+w",
        "reload":        "cmd+r",
        "back":          "cmd+[",
        "forward":       "cmd+]",
        "newWindow":     "cmd+n",
        "privateWindow": "cmd+shift+n",
        "showAllTabs":   "cmd+shift+backslash",
        "zoomIn":        "cmd+=",
        "zoomOut":       "cmd+-",
        "firstTab":      "cmd+1",
    ]

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "ctrl": .maskControl, "control": .maskControl,
        "alt": .maskAlternate, "opt": .maskAlternate, "option": .maskAlternate,
    ]

    /// Named keys and symbols → virtual key codes (kVK_*).
    private static let namedKeys: [String: CGKeyCode] = [
        "tab": 48, "space": 49, "return": 36, "enter": 36, "delete": 51,
        "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "[": 33, "]": 30, "backslash": 42, "\\": 42,
        "=": 24, "-": 27, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    private static let letters: [Character: CGKeyCode] = [
        "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,
        "q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,
        "l":37,"j":38,"k":40,"n":45,"m":46,
        "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,
    ]

    /// Parse "cmd+shift+t" (or a built-in name) into a Keystroke.
    static func parse(_ action: String) -> Keystroke? {
        let chord = builtins[action] ?? action
        let parts = chord.lowercased().split(separator: "+").map(String.init)
        guard let keyToken = parts.last else { return nil }

        var flags: CGEventFlags = []
        for mod in parts.dropLast() {
            guard let f = modifiers[mod] else { return nil }
            flags.insert(f)
        }

        let keyCode: CGKeyCode
        if let k = namedKeys[keyToken] {
            keyCode = k
        } else if keyToken.count == 1, let k = letters[keyToken.first!] {
            keyCode = k
        } else {
            return nil
        }
        return Keystroke(keyCode: keyCode, flags: flags)
    }
}
