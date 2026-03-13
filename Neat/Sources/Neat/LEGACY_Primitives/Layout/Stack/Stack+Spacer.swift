func _stackNodeContainsSpacer(_ node: ElementNode) -> Bool {
    switch node {
    case .element(let tag, _, _, let styles, let children):
        if tag == "div", let flexGrow = styles["flex-grow"], flexGrow.value == "1" {
            return true
        }
        return children.contains(where: _stackNodeContainsSpacer)
    case .fragment(let nodes):
        return nodes.contains(where: _stackNodeContainsSpacer)
    case .text:
        return false
    }
}

func _stackNodeContainsHorizontalScrollArea(_ node: ElementNode) -> Bool {
    switch node {
    case .element(_, let attributes, let classes, _, let children):
        if classes.contains("scroll-area") {
            let axis = attributes["data-axis"]
            if axis == "horizontal" || axis == "both" {
                return true
            }
        }
        return children.contains(where: _stackNodeContainsHorizontalScrollArea)
    case .fragment(let nodes):
        return nodes.contains(where: _stackNodeContainsHorizontalScrollArea)
    case .text:
        return false
    }
}

func _stackNodeContainsScrollArea(_ node: ElementNode) -> Bool {
    switch node {
    case .element(_, _, let classes, _, let children):
        if classes.contains("scroll-area") {
            return true
        }
        return children.contains(where: _stackNodeContainsScrollArea)
    case .fragment(let nodes):
        return nodes.contains(where: _stackNodeContainsScrollArea)
    case .text:
        return false
    }
}
