import Foundation
import NeatSyntax

struct LoweredSourceUnit {
    let outputFileName: String
    let protocols: [ProtocolDeclaration]
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let extensions: [ExtensionDeclaration]
    let callables: [CallableDeclaration]
    let mainBlock: MainBlockNode?
}

struct LoweredProgram {
    let callables: [CallableDeclaration]
    let protocols: [ProtocolDeclaration]
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let extensions: [ExtensionDeclaration]
    let mainBlock: MainBlockNode
    let units: [LoweredSourceUnit]
}
