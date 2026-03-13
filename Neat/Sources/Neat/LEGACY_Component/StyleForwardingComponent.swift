protocol _StyleForwardingComponent {
    func _buildForwardingStyles(
        _ styles: [any StyleModifier],
        in context: RenderContext?
    ) -> ElementNode
}
