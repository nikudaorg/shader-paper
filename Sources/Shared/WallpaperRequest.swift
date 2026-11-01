import Foundation

// Reflection follows Phosphene’s named-property approach (MIT; LICENSE.phosphene).
func findProperty(_ label: String, in value: Any, depth: Int = 0) -> Any? {
    guard depth < 9 else { return nil }
    for child in Mirror(reflecting: value).children {
        if child.label == label { return child.value }
        if let found = findProperty(label, in: child.value, depth: depth + 1) { return found }
    }
    return nil
}
func wallpaperUUID(_ value: Any?, depth: Int = 0) -> UUID? {
    guard let value, depth < 8 else { return nil }
    if let uuid = value as? UUID { return uuid }
    for child in Mirror(reflecting: value).children {
        if let id = wallpaperUUID(child.value, depth: depth + 1) { return id }
    }
    return nil
}
func caseName(_ value: Any?) -> String? {
    guard let value else { return nil }
    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional { return caseName(mirror.children.first?.value) }
    if mirror.displayStyle == .enum, let label = mirror.children.first?.label { return label }
    return String(describing: value)
}

