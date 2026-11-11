import Combine

/// Local view state without `@State`: on the macOS 27 SDK `@State` is a macro whose plugin ships only
/// with Xcode, and this project builds with Command Line Tools. Use as `@StateObject var x = Box(value)`
/// and bind with `$x.value`.
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}
