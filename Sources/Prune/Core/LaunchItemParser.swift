import Foundation

enum LaunchItemParser {
    static func program(of dict: [String: Any]) -> String? {
        if let p = dict["Program"] as? String { return p }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first { return first }
        return nil
    }
}
