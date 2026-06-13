import Foundation
import RangeSyntax

struct LoweredSourceUnit {
    let outputFileName: String
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let extensions: [ExtensionDeclaration]
    let callables: [CallableDeclaration]
    let mainBlock: MainBlockNode?
}

struct LoweredProgram {
    let macrosByName: [String: MacroDeclaration]
    let callables: [CallableDeclaration]
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let extensions: [ExtensionDeclaration]
    let mainBlock: MainBlockNode
    let units: [LoweredSourceUnit]
}
