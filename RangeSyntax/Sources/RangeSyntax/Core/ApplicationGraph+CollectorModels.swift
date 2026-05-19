import Foundation

struct DependencyResolutionIndex {
    var declarationProjectionNodeIDsByName: [String: Set<String>] = [:]
    var constructCallableProjectionNodeIDs: [String: [String: String]] = [:]
}

struct DependencyFlowState {
    var aliasTargetByNodeID: [String: String] = [:]
    var inferredConstructTypeByNodeID: [String: String] = [:]
}

struct MemoryScope {
    var symbols: [String: String] = [:]
}
