import Foundation

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let requiresAdmin: Bool
    let command: String
    /// How often (in days) it is recommended to run it.
    let recommendedDays: Int
    /// App that must be closed (bundle ID).
    var requiresClosed: String?
}

enum MaintenanceCatalog {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let tasks: [MaintenanceTask] = [
        .init(id: "purgeable", title: String(localized: "Free up purgeable space"), icon: "externaldrive.badge.minus",
              description: String(localized: "Removes local Time Machine snapshots and other purgeable data."),
              requiresAdmin: true, command: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4", recommendedDays: 14),
        .init(id: "dns", title: String(localized: "Flush the DNS cache"), icon: "network",
              description: String(localized: "Fixes websites that do not open or open an old version."),
              requiresAdmin: true, command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", recommendedDays: 30),
        .init(id: "spotlight", title: String(localized: "Reindex Spotlight"), icon: "magnifyingglass",
              description: String(localized: "Rebuilds the index when searches fail. It keeps running in the background for a few hours."),
              requiresAdmin: true, command: "/usr/bin/mdutil -E /", recommendedDays: 90),
        .init(id: "launchservices", title: String(localized: "Rebuild Launch Services"), icon: "square.stack.3d.up",
              description: String(localized: "Fixes duplicate entries in \"Open With\" and wrong file associations."),
              requiresAdmin: false, command: "\(lsregister) -r -domain local -domain system -domain user", recommendedDays: 60),
        .init(id: "quicklook", title: String(localized: "Clear the Quick Look cache"), icon: "eye",
              description: String(localized: "Restores wrong or blank previews and thumbnails."),
              requiresAdmin: false, command: "/usr/bin/qlmanage -r cache; /usr/bin/qlmanage -r", recommendedDays: 30),
        .init(id: "fonts", title: String(localized: "Clear the font cache"), icon: "textformat",
              description: String(localized: "Fixes corrupted or mixed-up fonts. Restart your Mac afterwards."),
              requiresAdmin: false, command: "/usr/bin/atsutil databases -removeUser", recommendedDays: 90),
        .init(id: "mail", title: String(localized: "Optimize Mail"), icon: "envelope.open",
              description: String(localized: "Compacts the message database. Mail must be closed."),
              requiresAdmin: false,
              command: "for f in ~/Library/Mail/V*/MailData/Envelope\\ Index; do [ -f \"$f\" ] && /usr/bin/sqlite3 \"$f\" 'VACUUM;'; done; true",
              recommendedDays: 30, requiresClosed: "com.apple.mail"),
        .init(id: "verify", title: String(localized: "Verify the startup disk"), icon: "internaldrive",
              description: String(localized: "Looks for file system errors."),
              requiresAdmin: true, command: "/usr/sbin/diskutil verifyVolume /", recommendedDays: 60),
        .init(id: "permissions", title: String(localized: "Repair home folder permissions"), icon: "lock.shield",
              description: String(localized: "Resets the permissions of your home folder. Fixes access errors in apps."),
              requiresAdmin: false, command: "/usr/sbin/diskutil resetUserPermissions / $(id -u)", recommendedDays: 180),
        .init(id: "dock", title: String(localized: "Restart Dock and Finder"), icon: "dock.rectangle",
              description: String(localized: "Restarts the Dock, the Finder and the menu bar when they become slow or glitchy."),
              requiresAdmin: false, command: "/usr/bin/killall Dock; /usr/bin/killall Finder; /usr/bin/killall SystemUIServer; true", recommendedDays: 0),
    ]
}
