import Foundation
import NeatSyntax

struct LoweredSourceUnit {
    let outputFileName: String
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let callables: [CallableDeclaration]
    let mainBlock: MainBlockNode?
}

struct LoweredProgram {
    let callables: [CallableDeclaration]
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let mainBlock: MainBlockNode
    let units: [LoweredSourceUnit]
}
