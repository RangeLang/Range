import Foundation
import RangeCompiler

struct LoweredSourceUnit {
    let outputFileName: String
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let extensions: [ExtensionDeclaration]
    let callables: [CallableDeclaration]
    let mainBlock: BlockMacroNode?
}

struct LoweredProgram {
    let macrosByName: [String: MacroDeclaration]
    let callables: [CallableDeclaration]
    let enumerations: [EnumDeclaration]
    let declarations: [ConstructDeclaration]
    let extensions: [ExtensionDeclaration]
    let mainBlock: BlockMacroNode
    let units: [LoweredSourceUnit]
}
