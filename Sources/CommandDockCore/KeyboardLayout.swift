import Foundation

public struct KeyboardKey: Identifiable, Hashable {
    public let code: UInt16
    public let label: String
    public let width: Double
    public var id: UInt16 { code }
    public init(_ code: UInt16, _ label: String, width: Double = 1) {
        self.code = code; self.label = label; self.width = width
    }
}

/// ANSI MacBook physical key positions; launch bindings use hardware codes so IMEs do not interfere.
public enum KeyboardLayout {
    public static let rows: [[KeyboardKey]] = [
        [.init(50,"`"),.init(18,"1"),.init(19,"2"),.init(20,"3"),.init(21,"4"),.init(23,"5"),.init(22,"6"),.init(26,"7"),.init(28,"8"),.init(25,"9"),.init(29,"0"),.init(27,"−"),.init(24,"="),.init(51,"delete",width:1.5)],
        [.init(48,"tab",width:1.5),.init(12,"Q"),.init(13,"W"),.init(14,"E"),.init(15,"R"),.init(17,"T"),.init(16,"Y"),.init(32,"U"),.init(34,"I"),.init(31,"O"),.init(35,"P"),.init(33,"["),.init(30,"]"),.init(42,"\\")],
        [.init(57,"caps lock",width:1.75),.init(0,"A"),.init(1,"S"),.init(2,"D"),.init(3,"F"),.init(5,"G"),.init(4,"H"),.init(38,"J"),.init(40,"K"),.init(37,"L"),.init(41,";"),.init(39,"'"),.init(36,"return",width:1.75)],
        [.init(56,"shift",width:2.25),.init(6,"Z"),.init(7,"X"),.init(8,"C"),.init(9,"V"),.init(11,"B"),.init(45,"N"),.init(46,"M"),.init(43,","),.init(47,"."),.init(44,"/"),.init(60,"shift",width:2.25)]
    ]
    public static let space = KeyboardKey(49,"space",width:5.5)
    public static let reserved: Set<UInt16> = [48,51,57,56,60,36]
    public static let bindable = rows.flatMap { $0 }.filter { !reserved.contains($0.code) } + [space]
    public static func key(code: UInt16) -> KeyboardKey? { bindable.first { $0.code == code } }
}

public struct AppBinding: Codable, Equatable {
    public var bundleIdentifier: String?
    public var path: String
    public var name: String
    public init(bundleIdentifier: String?, path: String, name: String) {
        self.bundleIdentifier = bundleIdentifier; self.path = path; self.name = name
    }
}

public enum BindingCodec {
    public static func decode(_ data: Data) throws -> [UInt16: AppBinding] {
        let raw = try JSONDecoder().decode([String: AppBinding].self, from: data)
        var result: [UInt16: AppBinding] = [:]
        for (key, binding) in raw {
            if let code = UInt16(key), KeyboardLayout.key(code: code) != nil {
                result[code] = binding
            }
        }
        return result
    }
    public static func encode(_ bindings: [UInt16: AppBinding]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Dictionary(uniqueKeysWithValues: bindings.map { (String($0.key), $0.value) }))
    }
}
