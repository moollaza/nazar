// Accessibility driver for the Nazar verify skill. Compiled once by
// `nazar-app.sh build` into .verify/bin/ax; call it through `nazar-app.sh ax`.
//
// Every command targets one process by PID, so it never touches the user's
// own copy of Nazar. Labels match an element's title, description, value,
// identifier, help (tooltip), or placeholder. Exact match by default; pass --contains for a substring match.
//
//   ax check                         exit 1 unless Accessibility and Screen Recording are granted
//   ax windows <pid>                 list on-screen windows: id, layer, bounds, title
//   ax dump <pid>                    print the app's AX tree (windows, menus, status item)
//   ax find <pid> <label> [--contains]
//   ax wait <pid> <label> [--contains] [--timeout S]
//   ax press <pid> <label> [--contains]       AXPress, or a real click if the element has no AXPress
//   ax click <pid> <label> [--contains]       real left click at the element's center
//   ax rightclick <pid> <label> [--contains]  real right click at the element's center
//   ax statusitem <pid> [--right]    click Nazar's menu bar icon
//   ax type <pid> <text>             type into the focused element
//   ax key <pid> <escape|return|tab|cmd-r|cmd-w>

import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)

func die(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func str(_ el: AXUIElement, _ name: String) -> String? {
    guard let v = attr(el, name) else { return nil }
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

func frame(_ el: AXUIElement) -> CGRect? {
    guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    var out = (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    // The status item lives in the extras menu bar, which is not a child.
    if let extras = attr(el, "AXExtrasMenuBar") { out.append(extras as! AXUIElement) }
    return out
}

func labels(_ el: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute]
        .compactMap { str(el, $0) }
}

func walk(_ root: AXUIElement, depth: Int = 0, _ visit: (AXUIElement, Int) -> Bool) {
    // visit returns false to stop the walk.
    var stop = false
    func go(_ el: AXUIElement, _ d: Int) {
        if stop || d > 60 { return }
        if !visit(el, d) { stop = true; return }
        for c in children(el) { go(c, d + 1) }
    }
    go(root, depth)
}

func app(_ pidArg: String) -> AXUIElement {
    guard let pid = pid_t(pidArg), NSRunningApplication(processIdentifier: pid) != nil else {
        die("no running process with pid \(pidArg)")
    }
    return AXUIElementCreateApplication(pid)
}

func find(_ pidArg: String, _ label: String, contains: Bool) -> AXUIElement? {
    var hit: AXUIElement?
    walk(app(pidArg)) { el, _ in
        let ls = labels(el)
        if ls.contains(where: { contains ? $0.localizedCaseInsensitiveContains(label) : $0 == label }) {
            hit = el
            return false
        }
        return true
    }
    return hit
}

func describe(_ el: AXUIElement) -> String {
    let role = str(el, kAXRoleAttribute) ?? "?"
    let ls = labels(el).map { "\"\($0.replacingOccurrences(of: "\n", with: " "))\"" }.joined(separator: " ")
    let f = frame(el).map { " @\(Int($0.midX)),\(Int($0.midY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
    let en = (attr(el, kAXEnabledAttribute) as? Bool) == false ? " [disabled]" : ""
    return "\(role) \(ls)\(f)\(en)"
}

func mouse(_ point: CGPoint, right: Bool) {
    let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
    let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
    let button: CGMouseButton = right ? .right : .left
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
}

func clickCenter(_ el: AXUIElement, right: Bool) {
    guard let f = frame(el) else { die("element has no frame: \(describe(el))") }
    mouse(CGPoint(x: f.midX, y: f.midY), right: right)
}

func requireElement(_ args: [String]) -> AXUIElement {
    guard args.count >= 4 else { die("usage: ax \(args[1]) <pid> <label> [--contains]") }
    let contains = args.contains("--contains")
    guard let el = find(args[2], args[3], contains: contains) else { die("not found: \(args[3])") }
    return el
}

func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { die("usage: see the header of ax.swift") }

switch args[1] {
case "check":
    let ax = AXIsProcessTrusted()
    let screen = CGPreflightScreenCaptureAccess()
    print("accessibility=\(ax ? "granted" : "MISSING") screen_recording=\(screen ? "granted" : "MISSING")")
    exit(ax && screen ? 0 : 1)

case "windows":
    guard args.count >= 3, let pid = Int(args[2]) else { die("usage: ax windows <pid>") }
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
        let id = w[kCGWindowNumber as String] as? Int ?? 0
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let title = w[kCGWindowName as String] as? String ?? ""
        print("\(id)\tlayer=\(layer)\t\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))\t\(title)")
    }

case "dump":
    guard args.count >= 3 else { die("usage: ax dump <pid>") }
    walk(app(args[2])) { el, d in
        print(String(repeating: "  ", count: d) + describe(el))
        return true
    }

case "find":
    print(describe(requireElement(args)))

case "wait":
    guard args.count >= 4 else { die("usage: ax wait <pid> <label> [--contains] [--timeout S]") }
    let timeout = args.firstIndex(of: "--timeout").flatMap { Double(args[$0 + 1]) } ?? 10
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let el = find(args[2], args[3], contains: args.contains("--contains")) {
            print(describe(el))
            exit(0)
        }
        usleep(250_000)
    }
    die("timed out after \(Int(timeout))s waiting for: \(args[3])")

case "press":
    let el = requireElement(args)
    var actions: CFArray?
    AXUIElementCopyActionNames(el, &actions)
    if ((actions as? [String]) ?? []).contains(kAXPressAction) {
        let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
        if r != .success { die("AXPress failed (\(r.rawValue)) on \(describe(el))") }
    } else {
        clickCenter(el, right: false)
    }
    print("pressed \(describe(el))")

case "click", "rightclick":
    let el = requireElement(args)
    clickCenter(el, right: args[1] == "rightclick")
    print("\(args[1]) \(describe(el))")

case "statusitem":
    guard args.count >= 3 else { die("usage: ax statusitem <pid> [--right]") }
    guard let extras = attr(app(args[2]), "AXExtrasMenuBar"),
          let item = children(extras as! AXUIElement).first else {
        die("no menu bar item for pid \(args[2]); is the app running and the icon visible?")
    }
    if args.contains("--right") {
        clickCenter(item, right: true)
    } else {
        // A real click, not AXPress: the app routes left/right through NSApp.currentEvent.
        clickCenter(item, right: false)
    }
    print("statusitem \(describe(item))")

case "type":
    guard args.count >= 4 else { die("usage: ax type <pid> <text>") }
    for ch in args[3].utf16 {
        var c = ch
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e?.post(tap: .cghidEventTap)
        }
        usleep(15_000)
    }
    print("typed \(args[3].count) chars")

case "key":
    guard args.count >= 4 else { die("usage: ax key <pid> <name>") }
    switch args[3] {
    case "escape": key(53)
    case "return": key(36)
    case "tab": key(48)
    case "cmd-r": key(15, flags: .maskCommand)
    case "cmd-w": key(13, flags: .maskCommand)
    default: die("unknown key \(args[3])")
    }
    print("key \(args[3])")

default:
    die("unknown command \(args[1])")
}
