import Foundation

enum MacroTargetKind: Hashable {
    case expression
    case parameter
    case initializer
    case state
    case immutable
    case binding
    case derived
    case property
    case block
    case function
    case construct
    case enumeration
    case typeExtension
    case macro
    case other(String)
}

func macroTargetKind(
    for macro: MacroDeclaration,
    syntaxResolver: DeclarationSyntaxResolver
) -> MacroTargetKind {
    guard let target = macro.target else {
        return .other("__freestanding")
    }
    let kinds = macroTargetKinds(for: target, syntaxResolver: syntaxResolver)
    for kind in macroTargetKindPriority() where kinds.contains(kind) {
        return kind
    }
    return kinds.first ?? .other("__unknown")
}

func macroTargetKindPriority() -> [MacroTargetKind] {
    [
        .block,
        .expression,
        .parameter,
        .initializer,
        .state,
        .immutable,
        .binding,
        .derived,
        .property,
        .function,
        .construct,
        .enumeration,
        .typeExtension,
        .macro,
    ]
}

func syntaxSurfaceTargetKinds(syntaxResolver: DeclarationSyntaxResolver) -> Set<MacroTargetKind> {
    Set(
        syntaxResolver.syntaxSurfaceTypeNames.map {
            macroTargetKind(for: .named($0), syntaxResolver: syntaxResolver)
        }
    )
}

func macroTargetKind(
    for typeReference: TypeReference,
    syntaxResolver: DeclarationSyntaxResolver
) -> MacroTargetKind {
    var name: String
    switch typeReference {
    case .named(let named):
        name = named
    case .member(_, let member):
        name = member
    case .generic(let base, _):
        return macroTargetKind(for: base, syntaxResolver: syntaxResolver)
    case .array, .function, .optional, .variadic:
        name = typeReference.displayName
    }

    if name.hasPrefix("@") {
        let surfaceName = String(name.dropFirst())
        guard let syntaxTypeName = syntaxResolver.syntaxTypeName(forSurface: surfaceName) else {
            return .other(name)
        }
        name = syntaxTypeName
    }

    switch name {
    case "Expression":
        return .expression
    case "Parameter":
        return .parameter
    case "Init":
        return .initializer
    case "State":
        return .state
    case "Let":
        return .immutable
    case "Binding":
        return .binding
    case "Derived":
        return .derived
    case "Function":
        return .function
    case "Block":
        return .block
    case "Construct":
        return .construct
    case "Enum":
        return .enumeration
    case "Extension":
        return .typeExtension
    case "Macro":
        return .macro
    default:
        return .other(name)
    }
}


func macroTargetKinds(
    for target: MacroTarget,
    syntaxResolver: DeclarationSyntaxResolver
) -> Set<MacroTargetKind> {
    switch target {
    case .syntax(let typeReference):
        return [macroTargetKind(for: typeReference, syntaxResolver: syntaxResolver)]
    case .macroSurface(let name):
        if name == "syntax" {
            return syntaxSurfaceTargetKinds(syntaxResolver: syntaxResolver)
        }
        if name == "property" {
            return [.property]
        }
        if name == "macro" {
            return [.macro]
        }
        return [macroTargetKind(for: .named("@\(name)"), syntaxResolver: syntaxResolver)]
    case .anyOf(let targets), .allOf(let targets):
        return Set(targets.flatMap { macroTargetKinds(for: $0, syntaxResolver: syntaxResolver) })
    }
}

func macroTargetAllows(
    _ target: MacroTarget,
    kind: MacroTargetKind,
    syntaxResolver: DeclarationSyntaxResolver
) -> Bool {
    switch target {
    case .syntax(let typeReference):
        return macroTargetKind(for: typeReference, syntaxResolver: syntaxResolver) == kind
    case .macroSurface(let name):
        if name == "syntax" {
            return syntaxSurfaceTargetKinds(syntaxResolver: syntaxResolver).contains(kind)
        }
        if name == "property" {
            return kind == .property
        }
        if name == "macro" {
            return kind == .macro
        }
        return macroTargetKind(for: .named("@\(name)"), syntaxResolver: syntaxResolver) == kind
    case .anyOf(let targets):
        return targets.contains { macroTargetAllows($0, kind: kind, syntaxResolver: syntaxResolver) }
    case .allOf(let targets):
        return targets.allSatisfy { macroTargetAllows($0, kind: kind, syntaxResolver: syntaxResolver) }
    }
}

func macroTargetAllowsAny(
    _ target: MacroTarget,
    kinds: Set<MacroTargetKind>,
    syntaxResolver: DeclarationSyntaxResolver
) -> Bool {
    kinds.contains { macroTargetAllows(target, kind: $0, syntaxResolver: syntaxResolver) }
}

func indexedReference(
    _ identifier: String,
    prefix: String,
    suffix: String
) -> Int? {
    guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else {
        return nil
    }
    let start = identifier.index(identifier.startIndex, offsetBy: prefix.count)
    let end = identifier.index(identifier.endIndex, offsetBy: -suffix.count)
    guard start <= end else {
        return nil
    }
    return Int(identifier[start..<end])
}

struct MacroExpansionContext {
    let syntaxResolver: DeclarationSyntaxResolver
    let graphContext: MacroGraphContext
    let macroDeclarationsByName: [String: MacroDeclaration]
    let macroMetadataByName: [String: MacroMetadataDeclaration]
    let callableDeclarationsByName: [String: [CallableDeclaration]]
    let diagnosticEngine: RangeDiagnosticEngine?
    let currentPath: String?

    func withCurrentPath(_ path: String) -> MacroExpansionContext {
        MacroExpansionContext(
            syntaxResolver: syntaxResolver,
            graphContext: graphContext,
            macroDeclarationsByName: macroDeclarationsByName,
            macroMetadataByName: macroMetadataByName,
            callableDeclarationsByName: callableDeclarationsByName,
            diagnosticEngine: diagnosticEngine,
            currentPath: path
        )
    }

}

struct MacroGraphContext {
    let declarationsByID: [String: CompileTimeValue]
    let membersByID: [String: [CompileTimeValue]]
    let parentByID: [String: CompileTimeValue]
    let macrosByID: [String: [CompileTimeValue]]
    let macrosByName: [String: [CompileTimeValue]]
    let main: CompileTimeValue
    let writtenSyntaxByID: [String: CompileTimeValue]
    let sourcePathByID: [String: String]
    let sourceDirectoryByID: [String: String]
    let constructsByName: [String: ConstructDeclaration]
    let knownObjectTypeNames: Set<String>
    let extensionsByTargetName: [String: [ExtensionDeclaration]]

    init(
        declarationGraph: DeclarationGraph,
        macroDeclarationsByName: [String: MacroDeclaration],
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration]
    ) {
        let writtenSyntaxByID = Self.writtenSyntaxByID(for: declarationGraph)
        let sourcePathByID = Self.sourcePathByID(for: declarationGraph)
        let sourceDirectoryByID = sourcePathByID.mapValues(Self.directoryPath(for:))
        let knownObjectTypeNames = Self.knownObjectTypeNames(
            declarationGraph: declarationGraph,
            macroMetadataDeclarationsByName: macroMetadataDeclarationsByName
        )
        let extensionsByTargetName = declarationGraph.extensionsByTargetName
        let builder = MacroTargetValueBuilder(
            macroDeclarationsByName: macroDeclarationsByName,
            macroMetadataByName: macroMetadataDeclarationsByName,
            constructsByName: declarationGraph.constructsByName,
            writtenSyntaxByID: writtenSyntaxByID,
            knownObjectTypeNames: knownObjectTypeNames,
            extensionsByTargetName: extensionsByTargetName
        )
        var declarationsByID: [String: CompileTimeValue] = [:]
        var membersByID: [String: [CompileTimeValue]] = [:]
        var parentByID: [String: CompileTimeValue] = [:]
        var macrosByID: [String: [CompileTimeValue]] = [:]
        var macrosByName: [String: [CompileTimeValue]] = [:]
        var main: CompileTimeValue = .nilValue

        func recordMacros(_ macros: [CompileTimeValue], id: String) {
            macrosByID[id] = macros
            for macro in macros {
                guard let name = Self.applicationIdentifierName(macro) else {
                    continue
                }
                macrosByName[name, default: []].append(macro)
            }
        }

        for construct in declarationGraph.constructsByName.values {
            let constructID = "construct:\(construct.name)"
            let constructValue = builder.declarationValue(for: construct, qualifiedName: construct.name)
            declarationsByID[constructID] = constructValue
            recordMacros(Self.macroValues(from: constructValue), id: constructID)

            var members: [CompileTimeValue] = []
            let constructIdentity = builder.graphIdentity(kind: "construct", name: construct.name)
            for value in construct.values {
                let id = "let:\(construct.name).\(value.name)"
                let valueValue = builder.value(for: value, ownerConstructName: construct.name)
                declarationsByID[id] = valueValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: valueValue), id: id)
                members.append(builder.graphIdentity(kind: "let", name: "\(construct.name).\(value.name)"))
            }
            for state in construct.states {
                let id = "state:\(construct.name).\(state.name)"
                let stateValue = builder.value(for: state, ownerConstructName: construct.name)
                declarationsByID[id] = stateValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: stateValue), id: id)
                members.append(builder.graphIdentity(kind: "state", name: "\(construct.name).\(state.name)"))
            }
            for binding in construct.bindings {
                let id = "binding:\(construct.name).\(binding.name)"
                let bindingValue = builder.value(for: binding, ownerConstructName: construct.name)
                declarationsByID[id] = bindingValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: bindingValue), id: id)
                members.append(builder.graphIdentity(kind: "binding", name: "\(construct.name).\(binding.name)"))
            }
            for derived in construct.deriveds {
                let id = "derived:\(construct.name).\(derived.name)"
                let derivedValue = builder.value(for: derived, ownerConstructName: construct.name)
                declarationsByID[id] = derivedValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: derivedValue), id: id)
                members.append(builder.graphIdentity(kind: "derived", name: "\(construct.name).\(derived.name)"))
            }
            for initializer in construct.initializers {
                let name = "init"
                let id = "init:\(construct.name).\(name)"
                let initializerValue = builder.value(for: initializer)
                declarationsByID[id] = initializerValue
                recordMacros(Self.macroValues(from: initializerValue), id: id)
                members.append(builder.graphIdentity(kind: "init", name: "\(construct.name).\(name)"))
            }
            for callable in construct.callables {
                let id = "function:\(construct.name).\(callable.name)"
                let callableValue = builder.value(for: callable, ownerConstructName: construct.name)
                declarationsByID[id] = callableValue
                parentByID[id] = constructIdentity
                recordMacros(Self.macroValues(from: callableValue), id: id)
                members.append(builder.graphIdentity(kind: "function", name: "\(construct.name).\(callable.name)"))
            }
            for nested in construct.constructs {
                let nestedName = builder.qualifiedNestedName(owner: construct.name, member: nested.name)
                parentByID["construct:\(nestedName)"] = constructIdentity
                members.append(builder.graphIdentity(kind: "construct", name: nestedName))
            }
            membersByID[constructID] = members
        }

        for extensionDeclaration in declarationGraph.extensionsByTargetName.values.flatMap({ $0 }) {
            let extensionID = "extension:\(extensionDeclaration.targetType.displayName)"
            let extensionValue = builder.value(for: extensionDeclaration)
            declarationsByID[extensionID] = extensionValue
            recordMacros(Self.macroValues(from: extensionValue), id: extensionID)
        }

        for (index, application) in declarationGraph.mainBlockMacros.enumerated() {
            let applicationValue = builder.value(for: application)
            if index == 0 {
                main = applicationValue
            }
            recordMacros([applicationValue], id: "mainBlock:\(index)")
        }

        self.declarationsByID = declarationsByID
        self.membersByID = membersByID
        self.parentByID = parentByID
        self.macrosByID = macrosByID
        self.macrosByName = macrosByName
        self.main = main
        self.writtenSyntaxByID = writtenSyntaxByID
        self.sourcePathByID = sourcePathByID
        self.sourceDirectoryByID = sourceDirectoryByID
        self.constructsByName = declarationGraph.constructsByName
        self.extensionsByTargetName = extensionsByTargetName
        self.knownObjectTypeNames = Self.knownObjectTypeNames(
            seededBy: knownObjectTypeNames,
            declarationsByID: declarationsByID,
            membersByID: membersByID,
            parentByID: parentByID,
            macrosByID: macrosByID,
            macrosByName: macrosByName,
            main: main,
            writtenSyntaxByID: writtenSyntaxByID
        )
    }

    private static func knownObjectTypeNames(
        declarationGraph: DeclarationGraph,
        macroMetadataDeclarationsByName: [String: MacroMetadataDeclaration]
    ) -> Set<String> {
        var names = Set(declarationGraph.constructsByName.keys)
        for metadata in macroMetadataDeclarationsByName.values {
            names.formUnion(objectTypeNames(for: metadata.valueType))
        }
        return names
    }

    private static func objectTypeNames(for type: TypeReference) -> Set<String> {
        switch type {
        case .named(let name):
            return [name]
        case .member(let base, let member):
            var names = Set(objectTypeNames(for: base).map { "\($0).\(member)" })
            names.insert(type.displayName)
            return names
        case .generic(let base, _):
            return objectTypeNames(for: base)
        case .optional(let wrapped), .variadic(let wrapped):
            return objectTypeNames(for: wrapped)
        case .array(let element):
            return objectTypeNames(for: element)
        case .function:
            return []
        }
    }

    private static func knownObjectTypeNames(
        seededBy seeds: Set<String>,
        declarationsByID: [String: CompileTimeValue],
        membersByID: [String: [CompileTimeValue]],
        parentByID: [String: CompileTimeValue],
        macrosByID: [String: [CompileTimeValue]],
        macrosByName: [String: [CompileTimeValue]],
        main: CompileTimeValue,
        writtenSyntaxByID: [String: CompileTimeValue]
    ) -> Set<String> {
        var names = seeds
        for value in declarationsByID.values {
            names.formUnion(objectTypeNames(in: value))
        }
        for values in membersByID.values {
            for value in values {
                names.formUnion(objectTypeNames(in: value))
            }
        }
        for value in parentByID.values {
            names.formUnion(objectTypeNames(in: value))
        }
        for values in macrosByID.values {
            for value in values {
                names.formUnion(objectTypeNames(in: value))
            }
        }
        for values in macrosByName.values {
            for value in values {
                names.formUnion(objectTypeNames(in: value))
            }
        }
        names.formUnion(objectTypeNames(in: main))
        for value in writtenSyntaxByID.values {
            names.formUnion(objectTypeNames(in: value))
        }
        return names
    }

    private static func objectTypeNames(in value: CompileTimeValue) -> Set<String> {
        switch value {
        case .string, .integer, .double, .boolean, .nilValue:
            return []
        case .array(let values):
            return values.reduce(into: Set<String>()) { names, value in
                names.formUnion(objectTypeNames(in: value))
            }
        case .object(let typeName, let fields):
            return fields.values.reduce(into: Set([typeName])) { names, value in
                names.formUnion(objectTypeNames(in: value))
            }
        }
    }

    func declaration(for identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return declarationsByID[id] ?? .nilValue
    }

    func members(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return .array(membersByID[id, default: []])
    }

    func parent(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return parentByID[id] ?? .nilValue
    }

    func macros(on identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity) else { return nil }
        return .array(macrosByID[id, default: []])
    }

    func macros() -> CompileTimeValue {
        .array(macrosByName.values.flatMap { $0 })
    }

    func macros(named name: String) -> CompileTimeValue {
        .array(macrosByName[name, default: []])
    }

    func mainMacro() -> CompileTimeValue {
        main
    }

    func sourcePath(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity), let path = sourcePathByID[id] else { return nil }
        return .string(path)
    }

    func sourceDirectory(of identity: CompileTimeValue) -> CompileTimeValue? {
        guard let id = identityID(identity), let path = sourceDirectoryByID[id] else { return nil }
        return .string(path)
    }

    func unknownCall(name: String, arguments: [CallArgument]) -> CompileTimeValue {
        switch name {
        case "members", "macros":
            return .array([])
        default:
            return .nilValue
        }
    }

    private static func writtenSyntaxByID(for graph: DeclarationGraph) -> [String: CompileTimeValue] {
        let builder = MacroTargetValueBuilder()
        var values: [String: CompileTimeValue] = [:]

        for location in graph.sourceLocations {
            guard let source = graph.sourceTextByPath[location.path] else {
                continue
            }
            let text = declarationText(in: source, startingAt: location.range.start.line)
            let written = builder.writtenSyntax(text)
            switch location.kind {
            case .type:
                if graph.constructsByName[location.name] != nil { values["construct:\(location.name)"] = written }
                if graph.enumsByName[location.name] != nil { values["enum:\(location.name)"] = written }
            case .function:
                values["function:\(location.name)"] = written
            case .macro:
                values["macro:\(location.name)"] = written
            }
        }

        return values
    }

    private static func sourcePathByID(for graph: DeclarationGraph) -> [String: String] {
        var values: [String: String] = [:]

        for location in graph.sourceLocations {
            switch location.kind {
            case .type:
                if graph.constructsByName[location.name] != nil { values["construct:\(location.name)"] = location.path }
                if graph.enumsByName[location.name] != nil { values["enum:\(location.name)"] = location.path }
            case .function:
                values["function:\(location.name)"] = location.path
            case .macro:
                values["macro:\(location.name)"] = location.path
            }
        }

        return values
    }

    private static func directoryPath(for path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func declarationText(in source: String, startingAt line: Int) -> String {
        let lines = source.components(separatedBy: .newlines)
        guard line >= 0, line < lines.count else { return "" }
        var start = line
        while start > 0 {
            let previous = lines[start - 1].trimmingCharacters(in: .whitespaces)
            guard previous.hasPrefix("#") || previous.hasPrefix("@") else { break }
            start -= 1
        }
        var end = line
        var balance = 0
        var sawBrace = false
        for index in line..<lines.count {
            for character in lines[index] {
                if character == "{" { sawBrace = true; balance += 1 }
                else if character == "}" { balance -= 1 }
            }
            end = index
            if sawBrace && balance <= 0 { break }
            if !sawBrace { break }
        }
        return lines[start...end].joined(separator: "\n")
    }

    private func identityID(_ identity: CompileTimeValue) -> String? {
        guard case .object("GraphIdentity", let fields) = identity,
            case .string(let id)? = fields["id"]
        else { return nil }
        return id
    }

    private static func macroValues(from value: CompileTimeValue) -> [CompileTimeValue] {
        guard case .array(let macros)? = value.field("macros") else { return [] }
        return macros
    }

    private static func applicationIdentifierName(_ value: CompileTimeValue) -> String? {
        guard case .object("Macro.Application", let fields) = value,
            case .object(_, let identifierFields)? = fields["identifier"],
            case .string(let name)? = identifierFields["name"]
        else { return nil }
        return name
    }
}

private struct MacroTargetTypeMatcher {
    let syntaxResolver: DeclarationSyntaxResolver
    let genericParameters: [GenericParameter]

    func matches(
        actual: TypeReference,
        expected: MacroTarget
    ) -> Bool {
        switch expected {
        case .syntax(let typeReference):
            return matches(actual: actual, expected: typeReference)
        case .macroSurface(let name):
            return name == "syntax" && syntaxResolver.typeConformsToSyntax(actual)
                || syntaxResolver.type(actual, matchesSyntaxSurface: name)
        case .anyOf(let targets):
            return targets.contains { matches(actual: actual, expected: $0) }
        case .allOf(let targets):
            return targets.allSatisfy { matches(actual: actual, expected: $0) }
        }
    }

    func matches(
        actual: TypeReference,
        expected: TypeReference
    ) -> Bool {

        var bindings: [String: TypeReference] = [:]
        guard typeMatches(actual: actual, expected: expected, bindings: &bindings) else {
            return false
        }

        for parameter in genericParameters {
            guard case .type(let name, let constraint, _) = parameter,
                let constraint,
                let binding = bindings[name]
            else {
                continue
            }

            guard typeMatches(actual: binding, expected: constraint, bindings: &bindings) else {
                return false
            }
        }

        return true
    }

    private func typeMatches(
        actual: TypeReference,
        expected: TypeReference,
        bindings: inout [String: TypeReference]
    ) -> Bool {
        if case .named(let name) = expected,
            typeGenericParameterNames.contains(name)
        {
            if let existing = bindings[name] {
                return existing == actual
            }

            bindings[name] = actual
            return true
        }

        if case .optional(let actualWrapped) = actual,
            case .generic(.named("Optional"), let expectedArguments) = expected,
            expectedArguments.count == 1
        {
            return typeMatches(
                actual: actualWrapped,
                expected: expectedArguments[0],
                bindings: &bindings
            )
        }

        if case .generic(.named("Optional"), let actualArguments) = actual,
            actualArguments.count == 1,
            case .optional(let expectedWrapped) = expected
        {
            return typeMatches(
                actual: actualArguments[0],
                expected: expectedWrapped,
                bindings: &bindings
            )
        }

        switch (actual, expected) {
        case (.named(let actualName), .named(let expectedName)):
            return actualName == expectedName
        case (.generic(let actualBase, _), .named):
            return typeMatches(
                actual: actualBase,
                expected: expected,
                bindings: &bindings
            )
        case (.member(let actualBase, let actualName), .member(let expectedBase, let expectedName)):
            return actualName == expectedName
                && typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    bindings: &bindings
                )
        case (
            .generic(let actualBase, let actualArguments),
            .generic(let expectedBase, let expectedArguments)
        ):
            guard actualArguments.count == expectedArguments.count,
                typeMatches(
                    actual: actualBase,
                    expected: expectedBase,
                    bindings: &bindings
                )
            else {
                return false
            }

            return zip(actualArguments, expectedArguments).allSatisfy { actualArgument, expectedArgument in
                typeMatches(
                    actual: actualArgument,
                    expected: expectedArgument,
                    bindings: &bindings
                )
            }
        case (.array(let actualElement), .array(let expectedElement)),
            (.optional(let actualElement), .optional(let expectedElement)),
            (.variadic(let actualElement), .variadic(let expectedElement)):
            return typeMatches(
                actual: actualElement,
                expected: expectedElement,
                bindings: &bindings
            )
        case (
            .function(let actualParameters, let actualReturn),
            .function(let expectedParameters, let expectedReturn)
        ):
            guard actualParameters.count == expectedParameters.count else {
                return false
            }

            return zip(actualParameters, expectedParameters).allSatisfy { actualParameter, expectedParameter in
                typeMatches(
                    actual: actualParameter,
                    expected: expectedParameter,
                    bindings: &bindings
                )
            } && typeMatches(
                actual: actualReturn,
                expected: expectedReturn,
                bindings: &bindings
            )
        default:
            return false
        }
    }

    private var typeGenericParameterNames: Set<String> {
        Set(
            genericParameters.compactMap { parameter in
                guard case .type(let name, _, _) = parameter else {
                    return nil
                }
                return name
            }
        )
    }
}
