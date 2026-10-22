import Foundation

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let requiresAdmin: Bool
    let command: String
    /// De quantos em quantos dias é recomendado executar.
    let recommendedDays: Int
    /// App que tem de estar fechada (bundle ID).
    var requiresClosed: String?
}

enum MaintenanceCatalog {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let tasks: [MaintenanceTask] = [
        .init(id: "purgeable", title: "Libertar espaço purgável", icon: "externaldrive.badge.minus",
              description: "Remove instantâneos locais do Time Machine e outros dados purgáveis, devolvendo espaço livre ao disco.",
              requiresAdmin: true, command: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4", recommendedDays: 14),
        .init(id: "dns", title: "Limpar a cache de DNS", icon: "network",
              description: "Resolve problemas de sites que não abrem ou que abrem a versão errada, limpando a cache de nomes de domínio.",
              requiresAdmin: true, command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", recommendedDays: 30),
        .init(id: "spotlight", title: "Reindexar o Spotlight", icon: "magnifyingglass",
              description: "Reconstrói o índice do Spotlight. Útil quando as pesquisas são lentas ou não encontram ficheiros. Pode demorar algumas horas em segundo plano.",
              requiresAdmin: true, command: "/usr/bin/mdutil -E /", recommendedDays: 90),
        .init(id: "launchservices", title: "Reconstruir Launch Services", icon: "square.stack.3d.up",
              description: "Corrige entradas duplicadas no menu \"Abrir com\" e associações de ficheiros erradas.",
              requiresAdmin: false, command: "\(lsregister) -r -domain local -domain system -domain user", recommendedDays: 60),
        .init(id: "quicklook", title: "Limpar a cache do Quick Look", icon: "eye",
              description: "Repõe as pré-visualizações e miniaturas de ficheiros quando aparecem erradas ou em branco.",
              requiresAdmin: false, command: "/usr/bin/qlmanage -r cache; /usr/bin/qlmanage -r", recommendedDays: 30),
        .init(id: "fonts", title: "Limpar a cache de tipos de letra", icon: "textformat",
              description: "Resolve texto com tipos de letra corrompidos ou trocados. Recomenda-se reiniciar a seguir.",
              requiresAdmin: false, command: "/usr/bin/atsutil databases -removeUser", recommendedDays: 90),
        .init(id: "mail", title: "Acelerar o Mail", icon: "envelope.open",
              description: "Compacta a base de dados de mensagens do Mail, tornando as pesquisas e a navegação mais rápidas. O Mail tem de estar fechado.",
              requiresAdmin: false,
              command: "for f in ~/Library/Mail/V*/MailData/Envelope\\ Index; do [ -f \"$f\" ] && /usr/bin/sqlite3 \"$f\" 'VACUUM;'; done; true",
              recommendedDays: 30, requiresClosed: "com.apple.mail"),
        .init(id: "verify", title: "Verificar o disco de arranque", icon: "internaldrive",
              description: "Verifica a estrutura do sistema de ficheiros do disco de arranque e reporta erros.",
              requiresAdmin: true, command: "/usr/sbin/diskutil verifyVolume /", recommendedDays: 60),
        .init(id: "permissions", title: "Reparar permissões da pasta pessoal", icon: "lock.shield",
              description: "Repõe as permissões corretas dos ficheiros da sua pasta pessoal. Resolve erros de acesso em apps.",
              requiresAdmin: false, command: "/usr/sbin/diskutil resetUserPermissions / $(id -u)", recommendedDays: 180),
        .init(id: "dock", title: "Reiniciar Dock e Finder", icon: "dock.rectangle",
              description: "Reinicia o Dock, o Finder e a barra de menus quando ficam lentos ou com falhas visuais.",
              requiresAdmin: false, command: "/usr/bin/killall Dock; /usr/bin/killall Finder; /usr/bin/killall SystemUIServer; true", recommendedDays: 0),
    ]
}
