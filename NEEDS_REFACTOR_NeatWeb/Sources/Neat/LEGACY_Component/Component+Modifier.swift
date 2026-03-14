public extension Component {
    func style(_ style: any StyleModifier) -> some Component {
        let wrapped = wrapStyleWithCurrentPriority(style)
        
        if let container = self as? _ModifierContainer {
            return ModifiedComponent(
                base: AnyComponent(container.anyBase), 
                styles: container.styles + [wrapped],
                events: container.events,
                a11y: container.a11y
            )
        }
        
        return ModifiedComponent(base: AnyComponent(self), styles: [wrapped])
    }

    func event(_ event: any EventModifier) -> some Component {
        if let container = self as? _ModifierContainer {
            return ModifiedComponent(
                base: AnyComponent(container.anyBase),
                styles: container.styles,
                events: container.events + [event],
                a11y: container.a11y
            )
        }
        return ModifiedComponent(base: AnyComponent(self), events: [event])
    }

    func accessibility(_ ax: any AccessibilityModifier) -> some Component {
        if let container = self as? _ModifierContainer {
             return ModifiedComponent(
                base: AnyComponent(container.anyBase),
                styles: container.styles,
                events: container.events,
                a11y: container.a11y + [ax]
            )
        }
        return ModifiedComponent(base: AnyComponent(self), a11y: [ax])
    }
}
