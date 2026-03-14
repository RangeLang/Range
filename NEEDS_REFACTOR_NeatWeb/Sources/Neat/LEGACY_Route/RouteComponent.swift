/// A building block for defining the application's routes.
public protocol RouteComponent {
    /// Returns the route nodes produced by this component.
    func build() -> [RouteNode]
}
