import Foundation
import RangeCompiler
import Testing
@testable import RangeEmission

@Suite("LLVM lowering emission")
struct LLVMLoweringEmitterTests {
    private typealias RangeExpression = RangeCompiler.Expression

    @Test("Scalar Int function lowers to textual LLVM IR")
    func scalarIntFunctionLowersToTextualLLVMIR() throws {
        let callable = callable(
            "add",
            parameters: [
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ret(binary(id("lhs"), .addition, id("rhs")))
            ]
        )

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.moduleName == "RangeScalar")
        #expect(module.loweredSymbols == [
            LLVMLoweredSymbol(rangeName: "add", llvmName: "RangeLLVM_add")
        ])
        #expect(
            module.ir.contains(
                """
                define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs) {
                entry:
                  %1 = add i64 %lhs, %rhs
                  ret i64 %1
                }
                """
            )
        )
    }

    @Test("Top-level main function lowers to native LLVM entrypoint")
    func topLevelMainFunctionLowersToNativeLLVMEntrypoint() throws {
        let callable = callable(
            "main",
            returnType: .named("Int"),
            body: [
                ret(.integer(0))
            ]
        )

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.loweredSymbols == [
            LLVMLoweredSymbol(rangeName: "main", llvmName: "main")
        ])
        #expect(module.ir.contains("define i64 @main()"))
    }

    @Test("String literal return lowers to LLVM UTF8 storage")
    func stringLiteralReturnLowersToLLVMUTF8Storage() throws {
        let callable = callable(
            "greeting",
            returnType: .named("String"),
            body: [
                ret(.string("hello"))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.String = type { ptr, i64 }"))
        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [6 x i8] c\"hello\\00\", align 1"))
        #expect(module.ir.contains("define %Range.String @RangeLLVM_greeting()"))
        #expect(module.ir.contains("getelementptr inbounds [6 x i8], ptr @.range.string.0, i64 0, i64 0"))
        #expect(module.ir.contains("insertvalue %Range.String undef, ptr"))
        #expect(module.ir.contains("insertvalue %Range.String"))
        #expect(module.ir.contains("i64 5, 1"))
        #expect(module.ir.contains("ret %Range.String"))
    }

    @Test("String parameters can pass through LLVM functions")
    func stringParametersCanPassThroughLLVMFunctions() throws {
        let callable = callable(
            "greet",
            parameters: [
                parameter("name", "String")
            ],
            returnType: .named("String"),
            body: [
                ret(id("name"))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.String = type { ptr, i64 }"))
        #expect(module.ir.contains("define %Range.String @RangeLLVM_greet(%Range.String %name)"))
        #expect(module.ir.contains("ret %Range.String %name"))
    }

    @Test("String literals use UTF8 byte counts")
    func stringLiteralsUseUTF8ByteCounts() throws {
        let callable = callable(
            "greeting",
            returnType: .named("String"),
            body: [
                ret(.string("hé"))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [4 x i8] c\"h\\C3\\A9\\00\", align 1"))
        #expect(module.ir.contains("i64 3, 1"))
    }

    @Test("Calls between LLVM String functions stay in LLVM")
    func callsBetweenLLVMStringFunctionsStayInLLVM() throws {
        let callables = [
            callable(
                "echo",
                parameters: [
                    parameter("value", "String")
                ],
                returnType: .named("String"),
                body: [
                    ret(id("value"))
                ]
            ),
            callable(
                "greeting",
                returnType: .named("String"),
                body: [
                    ret(call("echo", argument("value", .string("hello"))))
                ]
            ),
        ]

        let signatures = Dictionary(
            uniqueKeysWithValues: callables.compactMap { callable in
                LLVMLowerability.scalarSignature(for: callable).map { (callable.name, $0) }
            }
        )

        #expect(
            callables.allSatisfy {
                LLVMLowerability.canLower($0, lowerableFunctionSignatures: signatures)
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(callables: callables)
        )

        #expect(emission.ir.contains("define %Range.String @RangeLLVM_echo(%Range.String %value)"))
        #expect(emission.ir.contains("define %Range.String @RangeLLVM_greeting()"))
        #expect(emission.ir.contains("call %Range.String @RangeLLVM_echo(%Range.String"))
    }

    @Test("Construct values lower to LLVM aggregate insert and extract")
    func constructValuesLowerToLLVMAggregateInsertAndExtract() throws {
        let constructs = [
            construct(
                "Point",
                values: [
                    value("x", typeName: "Int"),
                    value("y", typeName: "Int"),
                ]
            ),
            construct(
                "Label",
                values: [
                    value("text", typeName: "String")
                ]
            ),
        ]
        let callables = [
            callable(
                "sum",
                parameters: [
                    parameter("point", "Point")
                ],
                returnType: .named("Int"),
                body: [
                    ret(binary(id("point.x"), .addition, id("point.y")))
                ]
            ),
            callable(
                "text",
                parameters: [
                    parameter("label", "Label")
                ],
                returnType: .named("String"),
                body: [
                    ret(id("label.text"))
                ]
            ),
		            callable(
		                "make",
		                returnType: .named("Point"),
		                body: [
		                    ret(call("Point", argument("x", .integer(2)), argument("y", .integer(3))))
		                ]
		            ),
            callable(
                "makeSum",
                returnType: .named("Int"),
                body: [
                    ret(
                        call(
                            "sum",
                            argument(
                                "point",
                                call("Point", argument("x", .integer(2)), argument("y", .integer(3)))
                            )
                        )
                    )
                ]
            ),
        ]
        let layouts = LLVMLowerability.constructLayouts(from: constructs)
        let signatures = Dictionary(
            uniqueKeysWithValues: callables.compactMap { callable in
                LLVMLowerability.scalarSignature(
                    for: callable,
                    constructLayouts: layouts
                ).map { (callable.name, $0) }
            }
        )

        #expect(layouts["construct:Point"]?.fields.map(\.name) == ["x", "y"])
        #expect(
            callables.allSatisfy {
                LLVMLowerability.canLower(
                    $0,
                    lowerableFunctionSignatures: signatures,
                    constructLayouts: layouts
                )
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: callables,
                constructLayouts: layouts
            )
        )

        #expect(emission.ir.contains("%Range.Point = type { i64, i64 }"))
        #expect(emission.ir.contains("%Range.Label = type { %Range.String }"))
        #expect(emission.ir.contains("define i64 @RangeLLVM_sum(%Range.Point %point)"))
        #expect(emission.ir.contains("extractvalue %Range.Point %point, 0"))
        #expect(emission.ir.contains("extractvalue %Range.Point %point, 1"))
        #expect(emission.ir.contains("define %Range.String @RangeLLVM_text(%Range.Label %label)"))
        #expect(emission.ir.contains("extractvalue %Range.Label %label, 0"))
        #expect(emission.ir.contains("define %Range.Point @RangeLLVM_make()"))
        #expect(emission.ir.contains("insertvalue %Range.Point undef, i64 2, 0"))
        #expect(emission.ir.contains("insertvalue %Range.Point"))
        #expect(emission.ir.contains("ret %Range.Point"))
        #expect(emission.ir.contains("call i64 @RangeLLVM_sum(%Range.Point"))
    }

    @Test("Duplicate construct display names get distinct LLVM layout identities")
    func duplicateConstructDisplayNamesGetDistinctLLVMLayoutIdentities() throws {
        let left = construct("Thing", values: [value("id", typeName: "Int")])
        let right = construct("Thing", values: [value("active", typeName: "Bool")])

        let layouts = LLVMLowerability.constructLayouts(from: [left, right])

        #expect(Set(layouts.keys) == ["construct:Thing#1", "construct:Thing#2"])
        #expect(
            LLVMLoweringEmitter.constructTypeName(
                identity: "construct:Thing#1",
                name: "Thing"
            )
                != LLVMLoweringEmitter.constructTypeName(
                    identity: "construct:Thing#2",
                    name: "Thing"
                )
        )
    }

    @Test("Nested construct fields lower through LLVM aggregate identities")
    func nestedConstructFieldsLowerThroughLLVMAggregateIdentities() throws {
        let constructs = [
            construct(
                "Name",
                values: [
                    value("value", typeName: "String")
                ]
            ),
            construct(
                "User",
                values: [
                    value("name", typeName: "Name")
                ]
            ),
        ]
        let callables = [
            callable(
                "name",
                parameters: [
                    parameter("user", "User")
                ],
                returnType: .named("Name"),
                body: [
                    ret(id("user.name"))
                ]
            ),
            callable(
                "value",
                parameters: [
                    parameter("user", "User")
                ],
                returnType: .named("String"),
                body: [
                    ret(id("user.name.value"))
                ]
            ),
            callable(
                "make",
                returnType: .named("User"),
                body: [
                    ret(
                        call(
                            "User",
                            argument("name", call("Name", argument("value", .string("George"))))
                        )
                    )
                ]
            ),
        ]
        let layouts = LLVMLowerability.constructLayouts(from: constructs)
        let signatures = Dictionary(
            uniqueKeysWithValues: callables.compactMap { callable in
                LLVMLowerability.scalarSignature(
                    for: callable,
                    constructLayouts: layouts
                ).map { (callable.name, $0) }
            }
        )

        #expect(layouts["construct:Name"]?.fields.map(\.name) == ["value"])
        #expect(layouts["construct:User"]?.fields.map(\.name) == ["name"])
        #expect(
            callables.allSatisfy {
                LLVMLowerability.canLower(
                    $0,
                    lowerableFunctionSignatures: signatures,
                    constructLayouts: layouts
                )
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: callables,
                constructLayouts: layouts
            )
        )

        #expect(emission.ir.contains("%Range.Name = type { %Range.String }"))
        #expect(emission.ir.contains("%Range.User = type { %Range.Name }"))
        #expect(emission.ir.contains("define %Range.Name @RangeLLVM_name(%Range.User %user)"))
        #expect(emission.ir.contains("extractvalue %Range.User %user, 0"))
        #expect(emission.ir.contains("define %Range.String @RangeLLVM_value(%Range.User %user)"))
        #expect(emission.ir.contains("extractvalue %Range.Name"))
        #expect(emission.ir.contains("define %Range.User @RangeLLVM_make()"))
        #expect(emission.ir.contains("insertvalue %Range.Name undef, %Range.String"))
        #expect(emission.ir.contains("insertvalue %Range.User undef, %Range.Name"))
    }

    @Test("Recursive value construct layouts are not LLVM lowerable")
    func recursiveValueConstructLayoutsAreNotLLVMLowerable() throws {
        let constructs = [
            construct(
                "Node",
                values: [
                    value("next", typeName: "Node")
                ]
            )
        ]
        let callables = [
            callable(
                "next",
                parameters: [
                    parameter("node", "Node")
                ],
                returnType: .named("Node"),
                body: [
                    ret(id("node.next"))
                ]
            )
        ]
        let layouts = LLVMLowerability.constructLayouts(from: constructs)

        #expect(layouts["construct:Node"] == nil)
        #expect(
            callables.allSatisfy {
                LLVMLowerability.scalarSignature(for: $0, constructLayouts: layouts) == nil
            }
        )
    }

    @Test("String isEmpty member lowers through LLVM count projection")
    func stringIsEmptyMemberLowersThroughLLVMCountProjection() throws {
        let callable = callable(
            "empty",
            parameters: [
                parameter("value", "String")
            ],
            returnType: .named("Bool"),
            body: [
                ret(id("value.isEmpty"))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_empty(%Range.String %value)"))
        #expect(module.ir.contains("extractvalue %Range.String %value, 1"))
        #expect(module.ir.contains("icmp eq i64"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("String byteCount member lowers through LLVM count projection")
    func stringByteCountMemberLowersThroughLLVMCountProjection() throws {
        let callable = callable(
            "size",
            parameters: [
                parameter("value", "String")
            ],
            returnType: .named("Int"),
            body: [
                ret(id("value.byteCount"))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_size(%Range.String %value)"))
        #expect(module.ir.contains("extractvalue %Range.String %value, 1"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("String literal local isEmpty lowers through LLVM")
    func stringLiteralLocalIsEmptyLowersThroughLLVM() throws {
        let callable = callable(
            "literalEmpty",
            returnType: .named("Bool"),
            body: [
                local("value", typeName: "String", expression: call("String", .string(""))),
                ret(id("value.isEmpty")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [1 x i8] c\"\\00\", align 1"))
        #expect(module.ir.contains("insertvalue %Range.String"))
        #expect(module.ir.contains("store %Range.String"))
        #expect(module.ir.contains("extractvalue %Range.String"))
        #expect(module.ir.contains("icmp eq i64"))
    }

    @Test("String literal local byteCount uses UTF8 byte count through LLVM")
    func stringLiteralLocalByteCountUsesUTF8ByteCountThroughLLVM() throws {
        let callable = callable(
            "literalSize",
            returnType: .named("Int"),
            body: [
                local("value", typeName: "String", expression: call("String", .string("hé"))),
                ret(id("value.byteCount")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("@.range.string.0 = private unnamed_addr constant [4 x i8] c\"h\\C3\\A9\\00\", align 1"))
        #expect(module.ir.contains("i64 3, 1"))
        #expect(module.ir.contains("extractvalue %Range.String"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Int array count and isEmpty lower through LLVM")
    func intArrayCountAndIsEmptyLowerThroughLLVM() throws {
        let callables = [
            callable(
                "size",
                parameters: [
                    parameter("values", .array(.named("Int")))
                ],
                returnType: .named("Int"),
                body: [
                    ret(id("values.count"))
                ]
            ),
            callable(
                "empty",
                parameters: [
                    parameter("values", .array(.named("Int")))
                ],
                returnType: .named("Bool"),
                body: [
                    ret(id("values.isEmpty"))
                ]
            ),
        ]
        let signatures = Dictionary(
            uniqueKeysWithValues: callables.compactMap { callable in
                LLVMLowerability.scalarSignature(for: callable).map { (callable.name, $0) }
            }
        )

        #expect(
            callables.allSatisfy {
                LLVMLowerability.canLower($0, lowerableFunctionSignatures: signatures)
            }
        )
        let emission = try #require(
            try LLVMLoweringEmitter().emitModule(callables: callables)
        )

        #expect(emission.ir.contains("%Range.IntArray = type { ptr, i64, i64 }"))
        #expect(emission.ir.contains("define i64 @RangeLLVM_size(%Range.IntArray %values)"))
        #expect(emission.ir.contains("define i1 @RangeLLVM_empty(%Range.IntArray %values)"))
        #expect(emission.ir.contains("extractvalue %Range.IntArray %values, 1"))
        #expect(emission.ir.contains("icmp eq i64"))
    }

    @Test("Int array element lowers through LLVM pointer load")
    func intArrayElementLowersThroughLLVMPointerLoad() throws {
        let callable = callable(
            "first",
            parameters: [
                parameter("values", .array(.named("Int")))
            ],
            returnType: .named("Int"),
            body: [
                ret(call("values.element", argument("index", .integer(0))))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.IntArray = type { ptr, i64, i64 }"))
        #expect(module.ir.contains("declare void @llvm.trap() noreturn nounwind"))
        #expect(module.ir.contains("define i64 @RangeLLVM_first(%Range.IntArray %values)"))
        #expect(module.ir.contains("array.element.bounds.ok."))
        #expect(module.ir.contains("array.element.bounds.trap."))
        #expect(module.ir.contains("icmp sge i64 0, 0"))
        #expect(module.ir.contains("icmp slt i64 0,"))
        #expect(module.ir.contains("and i1"))
        #expect(module.ir.contains("call void @llvm.trap()"))
        #expect(module.ir.contains("extractvalue %Range.IntArray %values, 0"))
        #expect(module.ir.contains("getelementptr inbounds i64, ptr"))
        #expect(module.ir.contains("load i64, ptr"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Owned Int array allocation and append lower through LLVM memory")
    func ownedIntArrayAllocationAndAppendLowerThroughLLVMMemory() throws {
        let callable = callable(
            "sumAllocated",
            parameters: [
                parameter("limit", "Int")
            ],
            returnType: .named("Int"),
            body: [
                state(
                    "values",
                    type: .array(.named("Int")),
                    expression: call("Array<Int>", argument("capacity", id("limit")))
                ),
                state("index", type: .named("Int"), expression: .integer(0)),
                whileLoop(
                    binary(id("index"), .less, id("limit")),
                    [
                        .expression(call("values.append", argument("element", id("index")))),
                        assign("index", binary(id("index"), .addition, .integer(1))),
                    ]
                ),
                state("total", type: .named("Int"), expression: .integer(0)),
                state("readIndex", type: .named("Int"), expression: .integer(0)),
                whileLoop(
                    binary(id("readIndex"), .less, id("limit")),
                    [
                        assign(
                            "total",
                            binary(
                                id("total"),
                                .addition,
                                call("values.element", argument("index", id("readIndex")))
                            )
                        ),
                        assign("readIndex", binary(id("readIndex"), .addition, .integer(1))),
                    ]
                ),
                ret(id("total")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("declare ptr @malloc(i64)"))
        #expect(module.ir.contains("declare void @free(ptr)"))
        #expect(module.ir.contains("declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))
        #expect(module.ir.contains("declare void @llvm.trap() noreturn nounwind"))
        #expect(module.ir.contains("%Range.IntArray = type { ptr, i64, i64 }"))
        #expect(module.ir.contains("mul i64 %limit, 8"))
        #expect(module.ir.contains("call ptr @malloc(i64"))
        #expect(module.ir.contains("insertvalue %Range.IntArray undef, ptr"))
        #expect(module.ir.contains("insertvalue %Range.IntArray"))
        #expect(module.ir.contains("i64 0, 1"))
        #expect(module.ir.contains("icmp slt i64"))
        #expect(module.ir.contains("array.grow."))
        #expect(module.ir.contains("select i1"))
        #expect(module.ir.contains("call void @llvm.memcpy.p0.p0.i64"))
        #expect(module.ir.contains("array.element.bounds.ok."))
        #expect(module.ir.contains("array.element.bounds.trap."))
        #expect(module.ir.contains("call void @llvm.trap()"))
        #expect(module.ir.contains("call void @free(ptr"))
        #expect(module.ir.contains("store i64"))
        #expect(module.ir.contains("load i64, ptr"))
        #expect(module.ir.contains("define i64 @RangeLLVM_sumAllocated(i64 %limit)"))
    }

    @Test("Default Int array append grows from empty storage")
    func defaultIntArrayAppendGrowsFromEmptyStorage() throws {
        let callable = callable(
            "grown",
            returnType: .named("Int"),
            body: [
                state("values", type: .array(.named("Int")), expression: call("Array<Int>")),
                .expression(call("values.append", argument("element", .integer(4)))),
                .expression(call("values.append", argument("element", .integer(8)))),
                ret(call("values.element", argument("index", .integer(1)))),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("array.grow."))
        #expect(module.ir.contains("ptr null, 0"))
        #expect(module.ir.contains("i64 0, 2"))
        #expect(module.ir.contains("icmp eq i64"))
        #expect(module.ir.contains("icmp ne i64"))
        #expect(module.ir.contains("array.grow.copy."))
        #expect(module.ir.contains("array.grow.finish."))
        #expect(module.ir.contains("select i1"))
        #expect(module.ir.contains("i64 1"))
        #expect(module.ir.contains("call void @llvm.memcpy.p0.p0.i64"))
        #expect(module.ir.contains("call void @free(ptr"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Int array update lowers with LLVM bounds check")
    func intArrayUpdateLowersWithLLVMBoundsCheck() throws {
        let callable = callable(
            "replaceFirst",
            parameters: [
                parameter("value", "Int")
            ],
            returnType: .named("Int"),
            body: [
                state(
                    "values",
                    type: .array(.named("Int")),
                    expression: call("Array<Int>", argument("capacity", .integer(1)))
                ),
                .expression(call("values.append", argument("element", .integer(0)))),
                .expression(
                    call(
                        "values.update",
                        argument("element", id("value")),
                        argument("index", .integer(0))
                    )
                ),
                ret(call("values.element", argument("index", .integer(0)))),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("array.update.bounds.ok."))
        #expect(module.ir.contains("array.update.bounds.trap."))
        #expect(module.ir.contains("icmp sge i64 0, 0"))
        #expect(module.ir.contains("icmp slt i64 0,"))
        #expect(module.ir.contains("call void @llvm.trap()"))
        #expect(module.ir.contains("store i64 %value, ptr"))
        #expect(module.ir.contains("call void @free(ptr"))
    }

    @Test("Bool array lowers with detected element type")
    func boolArrayLowersWithDetectedElementType() throws {
        let callable = callable(
            "firstFlag",
            parameters: [
                parameter("value", "Bool")
            ],
            returnType: .named("Bool"),
            body: [
                state(
                    "values",
                    type: .array(.named("Bool")),
                    expression: call("Array<Bool>", argument("capacity", .integer(1)))
                ),
                .expression(call("values.append", argument("element", id("value")))),
                ret(call("values.element", argument("index", .integer(0)))),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("%Range.BoolArray = type { ptr, i64, i64 }"))
        #expect(module.ir.contains("define i1 @RangeLLVM_firstFlag(i1 %value)"))
        #expect(module.ir.contains("mul i64 1, 1"))
        #expect(module.ir.contains("getelementptr inbounds i1, ptr"))
        #expect(module.ir.contains("store i1 %value, ptr"))
        #expect(module.ir.contains("load i1, ptr"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Nested Int while loops lower to LLVM basic blocks")
    func nestedIntWhileLoopsLowerToLLVMBasicBlocks() throws {
        let callable = nestedSumCallable()

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_nestedSum(i64 %limit)"))
        #expect(module.ir.contains("%outer.addr = alloca i64"))
        #expect(module.ir.contains("%inner.addr = alloca i64"))
        #expect(module.ir.contains("while.cond.1:"))
        #expect(module.ir.contains("while.body.1:"))
        #expect(module.ir.contains("while.end.1:"))
        #expect(module.ir.contains("while.cond.2:"))
        #expect(module.ir.contains("while.body.2:"))
        #expect(module.ir.contains("while.end.2:"))
        #expect(module.ir.contains("icmp slt i64"))
        #expect(module.ir.contains("br i1"))
        #expect(module.ir.contains("store i64"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Let comparison and if lower to LLVM control flow")
    func letComparisonAndIfLowerToLLVMControlFlow() throws {
        let callable = callable(
            "choose",
            parameters: [
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                local("adjusted", typeName: "Int", expression: id("lhs")),
                ifElseStatement(
                    binary(id("lhs"), .less, id("rhs")),
                    [ret(id("rhs"))],
                    [ret(id("adjusted"))]
                ),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_choose(i64 %lhs, i64 %rhs)"))
        #expect(module.ir.contains("%adjusted.addr = alloca i64"))
        #expect(module.ir.contains("icmp slt i64 %lhs, %rhs"))
        #expect(module.ir.contains("br i1"))
        #expect(module.ir.contains("if.body."))
        #expect(module.ir.contains("ret i64 %rhs"))
    }

    @Test("Scalar literal operands lower through LLVM")
    func scalarLiteralOperandsLowerThroughLLVM() throws {
        let callable = CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            name: "adjust",
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: [
                RangeFunctionParameter(
                    macros: [],
                    name: "value",
                    typeReference: .named("Int"),
                    slotName: nil
                )
            ],
            returnType: .named("Int"),
            body: [
                local(
                    "incremented",
                    typeName: "Int",
                    expression: binary(id("value"), .addition, .integer(1))
                ),
                ifElseStatement(
                    binary(id("incremented"), .less, .integer(10)),
                    [ret(binary(id("incremented"), .multiplication, .integer(2)))],
                    [ret(binary(.integer(10), .subtraction, id("value")))]
                ),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_adjust(i64 %value)"))
        #expect(module.ir.contains("add i64 %value, 1"))
        #expect(module.ir.contains("icmp slt i64"))
        #expect(module.ir.contains("mul i64"))
        #expect(module.ir.contains("sub i64 10, %value"))
    }

    @Test("Float arithmetic lowers to LLVM double operations")
    func floatArithmeticLowersToLLVMDoubleOperations() throws {
        let callable = callable(
            "blend",
            parameters: [
                parameter("lhs", "Float"),
                parameter("rhs", "Float"),
            ],
            returnType: .named("Float"),
            body: [
                local(
                    "adjusted",
                    typeName: "Float",
                    expression: binary(
                        id("lhs"),
                        .addition,
                        binary(id("rhs"), .multiplication, .double(2.0))
                    )
                ),
                ret(binary(id("adjusted"), .division, .double(3.0))),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define double @RangeLLVM_blend(double %lhs, double %rhs)"))
        #expect(module.ir.contains("fmul double %rhs, 2.0"))
        #expect(module.ir.contains("fadd double %lhs"))
        #expect(module.ir.contains("%adjusted.addr = alloca double"))
        #expect(module.ir.contains("fdiv double"))
        #expect(module.ir.contains("ret double"))
    }

    @Test("Mixed Int and Float operands lower through LLVM promotion")
    func mixedIntAndFloatOperandsLowerThroughLLVMPromotion() throws {
        let callable = callable(
            "mixed",
            parameters: [
                parameter("lhs", "Float"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Float"),
            body: [
                ret(binary(id("lhs"), .addition, id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define double @RangeLLVM_mixed(double %lhs, i64 %rhs)"))
        #expect(module.ir.contains("sitofp i64 %rhs to double"))
        #expect(module.ir.contains("fadd double %lhs"))
        #expect(module.ir.contains("ret double"))
    }

    @Test("Float comparison lowers to LLVM ordered comparison")
    func floatComparisonLowersToLLVMOrderedComparison() throws {
        let callable = callable(
            "floatLess",
            parameters: [
                parameter("lhs", "Float"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Bool"),
            body: [
                ret(binary(id("lhs"), .less, id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_floatLess(double %lhs, i64 %rhs)"))
        #expect(module.ir.contains("sitofp i64 %rhs to double"))
        #expect(module.ir.contains("fcmp olt double %lhs"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Explicit Int width lowers to matching LLVM integer type")
    func explicitIntWidthLowersToMatchingLLVMIntegerType() throws {
        let unsigned8 = TypeReference.named("Int<8, .unsigned>")
        let callable = callable(
            "wrapping",
            parameters: [
                parameter("value", unsigned8)
            ],
            returnType: unsigned8,
            body: [
                ret(binary(id("value"), .addition, .integer(1)))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i8 @RangeLLVM_wrapping(i8 %value)"))
        #expect(module.ir.contains("trunc i64 1 to i8"))
        #expect(module.ir.contains("add i8 %value"))
        #expect(module.ir.contains("ret i8"))
    }

    @Test("Unsigned Int comparison and division use unsigned LLVM operations")
    func unsignedIntComparisonAndDivisionUseUnsignedLLVMOperations() throws {
        let unsigned13 = TypeReference.named("Int<13, .unsigned>")
        let callable = callable(
            "unsignedOps",
            parameters: [
                parameter("lhs", unsigned13),
                parameter("rhs", unsigned13),
            ],
            returnType: .named("Bool"),
            body: [
                ret(binary(binary(id("lhs"), .division, id("rhs")), .less, id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_unsignedOps(i13 %lhs, i13 %rhs)"))
        #expect(module.ir.contains("udiv i13 %lhs, %rhs"))
        #expect(module.ir.contains("icmp ult i13"))
    }

    @Test("Signed custom-width Int comparison uses signed LLVM predicate")
    func signedCustomWidthIntComparisonUsesSignedLLVMPredicate() throws {
        let signed13 = TypeReference.named("Int<13>")
        let callable = callable(
            "signedLess",
            parameters: [
                parameter("lhs", signed13),
                parameter("rhs", signed13),
            ],
            returnType: .named("Bool"),
            body: [
                ret(binary(id("lhs"), .less, id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_signedLess(i13 %lhs, i13 %rhs)"))
        #expect(module.ir.contains("icmp slt i13 %lhs, %rhs"))
    }

    @Test("Scalar ternary lowers to LLVM select")
    func scalarTernaryLowersToLLVMSelect() throws {
        let callable = callable(
            "choose",
            parameters: [
                parameter("flag", "Bool"),
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ret(.ternary(condition: id("flag"), trueExpression: id("lhs"), falseExpression: id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %lhs, i64 %rhs)"))
        #expect(module.ir.contains("select i1 %flag, i64 %lhs, i64 %rhs"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Mixed scalar ternary promotes Int branch to Float")
    func mixedScalarTernaryPromotesIntBranchToFloat() throws {
        let callable = callable(
            "chooseFloat",
            parameters: [
                parameter("flag", "Bool"),
                parameter("lhs", "Float"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Float"),
            body: [
                ret(.ternary(condition: id("flag"), trueExpression: id("lhs"), falseExpression: id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define double @RangeLLVM_chooseFloat(i1 %flag, double %lhs, i64 %rhs)"))
        #expect(module.ir.contains("sitofp i64 %rhs to double"))
        #expect(module.ir.contains("select i1 %flag, double %lhs, double"))
        #expect(module.ir.contains("ret double"))
    }

    @Test("Local scalar plus-equals lowers to LLVM load add store")
    func localScalarPlusEqualsLowersToLLVMLoadAddStore() throws {
        let callable = CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            name: "addLoop",
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: [
                RangeFunctionParameter(
                    macros: [],
                    name: "limit",
                    typeReference: .named("Int"),
                    slotName: nil
                )
            ],
            returnType: .named("Int"),
            body: [
                state("index", type: .named("Int"), expression: .integer(0)),
                state("total", type: .named("Int"), expression: .integer(0)),
                whileLoop(
                    binary(id("index"), .less, id("limit")),
                    [
                        assign("total", binary(id("total"), .addition, id("index"))),
                        assign("index", binary(id("index"), .addition, .integer(1))),
                    ]
                ),
                ret(id("total")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_addLoop(i64 %limit)"))
        #expect(module.ir.contains("load i64, ptr %total.addr"))
        #expect(module.ir.contains("add i64"))
        #expect(module.ir.contains("store i64"))
        #expect(module.ir.contains("ret i64"))
    }

    @Test("Int comparison can return Bool through LLVM")
    func intComparisonCanReturnBoolThroughLLVM() throws {
        let callable = callable(
            "isLess",
            parameters: [
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Bool"),
            body: [
                ret(binary(id("lhs"), .less, id("rhs")))
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(module.ir.contains("%1 = icmp slt i64 %lhs, %rhs"))
        #expect(module.ir.contains("ret i1 %1"))
    }

    @Test("Bool operators can return Bool through LLVM")
    func boolOperatorsCanReturnBoolThroughLLVM() throws {
        let callable = callable(
            "both",
            parameters: [
                parameter("lhs", "Bool"),
                parameter("rhs", "Bool"),
            ],
            returnType: .named("Bool"),
            body: [
                local(
                    "combined",
                    typeName: "Bool",
                    expression: binary(id("lhs"), .and, id("rhs"))
                ),
                ret(.unary(operatorSymbol: .not, expression: id("combined"))),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_both(i1 %lhs, i1 %rhs)"))
        #expect(module.ir.contains("%1 = and i1 %lhs, %rhs"))
        #expect(module.ir.contains("%2 = load i1, ptr %combined.addr"))
        #expect(module.ir.contains("xor i1 %2, true"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Bool parameter can control Int return through LLVM")
    func boolParameterCanControlIntReturnThroughLLVM() throws {
        let callable = callable(
            "choose",
            parameters: [
                parameter("flag", "Bool"),
                parameter("value", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ifElseStatement(id("flag"), [ret(id("value"))], [ret(.integer(0))])
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %value)"))
        #expect(module.ir.contains("br i1 %flag"))
        #expect(module.ir.contains("ret i64 %value"))
        #expect(module.ir.contains("ret i64 0"))
    }

    @Test("Bool state mutation in loop lowers to LLVM")
    func boolStateMutationInLoopLowersToLLVM() throws {
        let callable = callable(
            "reachesThreshold",
            parameters: [
                parameter("limit", "Int")
            ],
            returnType: .named("Bool"),
            body: [
                state("index", type: .named("Int"), expression: .integer(0)),
                state("found", type: .named("Bool"), expression: .boolean(false)),
                whileLoop(
                    binary(id("index"), .less, id("limit")),
                    [
                        ifStatement(
                            binary(id("index"), .greater, .integer(10)),
                            [
                                assign("found", .boolean(true))
                            ]
                        ),
                        assign("index", binary(id("index"), .addition, .integer(1))),
                    ]
                ),
                ret(id("found")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_reachesThreshold(i64 %limit)"))
        #expect(module.ir.contains("%found.addr = alloca i1"))
        #expect(module.ir.contains("store i1 0, ptr %found.addr"))
        #expect(module.ir.contains("icmp sgt i64"))
        #expect(module.ir.contains("store i1 1, ptr %found.addr"))
        #expect(module.ir.contains("load i1, ptr %found.addr"))
        #expect(module.ir.contains("ret i1"))
    }

    @Test("Break in loop branches to LLVM loop end")
    func breakInLoopBranchesToLLVMLoopEnd() throws {
        let callable = callable(
            "firstOverTen",
            parameters: [
                parameter("limit", "Int")
            ],
            returnType: .named("Bool"),
            body: [
                state("index", type: .named("Int"), expression: .integer(0)),
                state("found", type: .named("Bool"), expression: .boolean(false)),
                whileLoop(
                    binary(id("index"), .less, id("limit")),
                    [
                        ifStatement(
                            binary(id("index"), .greater, .integer(10)),
                            [
                                assign("found", .boolean(true)),
                                breakStatement(),
                            ]
                        ),
                        assign("index", binary(id("index"), .addition, .integer(1))),
                    ]
                ),
                ret(id("found")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i1 @RangeLLVM_firstOverTen(i64 %limit)"))
        #expect(module.ir.contains("while.cond.1:"))
        #expect(module.ir.contains("while.end.1:"))
        #expect(module.ir.contains("store i1 1, ptr %found.addr"))
        #expect(module.ir.contains("br label %while.end.1"))
    }

    @Test("Continue in loop branches to LLVM loop condition")
    func continueInLoopBranchesToLLVMLoopCondition() throws {
        let callable = callable(
            "sumOdd",
            parameters: [
                parameter("limit", "Int")
            ],
            returnType: .named("Int"),
            body: [
                state("index", type: .named("Int"), expression: .integer(0)),
                state("total", type: .named("Int"), expression: .integer(0)),
                whileLoop(
                    binary(id("index"), .less, id("limit")),
                    [
                        assign("index", binary(id("index"), .addition, .integer(1))),
                        ifStatement(
                            binary(
                                binary(id("index"), .remainder, .integer(2)),
                                .equal,
                                .integer(0)
                            ),
                            [
                                continueStatement()
                            ]
                        ),
                        assign("total", binary(id("total"), .addition, id("index"))),
                    ]
                ),
                ret(id("total")),
            ]
        )

        #expect(LLVMLowerability.canLower(callable))
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        #expect(module.ir.contains("define i64 @RangeLLVM_sumOdd(i64 %limit)"))
        #expect(module.ir.contains("while.cond.1:"))
        #expect(module.ir.contains("while.end.1:"))
        #expect(module.ir.contains("srem i64"))
        #expect(module.ir.contains("icmp eq i64"))
        #expect(module.ir.contains("br label %while.cond.1"))
    }

    @Test("Calls between lowerable Int functions stay in LLVM")
    func callsBetweenLowerableIntFunctionsStayInLLVM() throws {
        let callables = [
            callable(
                "add",
                parameters: [
                    parameter("lhs", "Int"),
                    parameter("rhs", "Int"),
                ],
                returnType: .named("Int"),
                body: [
                    ret(binary(id("lhs"), .addition, id("rhs")))
                ]
            ),
            callable(
                "sum3",
                parameters: [
                    parameter("x", "Int"),
                    parameter("y", "Int"),
                    parameter("z", "Int"),
                ],
                returnType: .named("Int"),
                body: [
                    local(
                        "partial",
                        typeName: "Int",
                        expression: call("add", argument("lhs", id("x")), argument("rhs", id("y")))
                    ),
                    ret(call("add", argument("lhs", id("partial")), argument("rhs", id("z")))),
                ]
            ),
        ]
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMCallPlanTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let program = SwiftLoweredProgramAdapter().adapt(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: BlockMacroNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Math.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: callables,
                        mainBlock: nil
                    )
                ]
            )
        )

        try SwiftBackendEmitter().emitWorkspace(
            program: program,
            at: root
        )

        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/Math.swift"),
            encoding: .utf8
        )

        #expect(ir.contains("define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("define i64 @RangeLLVM_sum3(i64 %x, i64 %y, i64 %z)"))
        #expect(ir.contains("call i64 @RangeLLVM_add(i64 %x, i64 %y)"))
        #expect(ir.contains("call i64 @RangeLLVM_add"))
        #expect(!swift.contains("func add"))
        #expect(!swift.contains("func sum3"))
    }

    @Test("LLVM IR links and runs through clang harness")
    func llvmIRLinksAndRunsThroughClangHarness() throws {
        let callable = nestedSumCallable()
        let module = try #require(
            try LLVMLoweringEmitter().emitModule(callables: [callable])
        )

        let clang = URL(fileURLWithPath: "/usr/bin/clang")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMRunTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let irURL = root.appendingPathComponent("RangeScalar.ll")
        let harnessURL = root.appendingPathComponent("harness.c")
        let executableURL = root.appendingPathComponent("nested-sum")

        try module.ir.write(to: irURL, atomically: true, encoding: .utf8)
        try """
            #include <stdint.h>
            #include <stdio.h>

            extern int64_t RangeLLVM_nestedSum(int64_t limit);

            int main(void) {
                printf("%lld\\n", (long long)RangeLLVM_nestedSum(10));
                return 0;
            }
            """
            .write(to: harnessURL, atomically: true, encoding: .utf8)

        let compile = try run(
            clang,
            arguments: [
                irURL.path,
                harnessURL.path,
                "-O3",
                "-o",
                executableURL.path,
            ]
        )
        #expect(compile.status == 0)

        let runResult = try run(executableURL, arguments: [])
        #expect(runResult.status == 0)
        #expect(runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "900")
    }

    @Test("Swift workspace emission writes LLVM IR artifact")
    func swiftWorkspaceEmissionWritesLLVMIRArtifact() throws {
        let callable = callable(
            "multiply",
            parameters: [
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ret(binary(id("lhs"), .multiplication, id("rhs")))
            ]
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMLoweringEmitterTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let program = SwiftLoweredProgramAdapter().adapt(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: BlockMacroNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Main.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: [callable],
                        mainBlock: nil
                    )
                ]
            )
        )

        try SwiftBackendEmitter().emitWorkspace(
            program: program,
            at: root
        )

        let irURL = root.appendingPathComponent("LLVM/RangeScalar.ll")
        let ir = try String(contentsOf: irURL, encoding: .utf8)
        #expect(ir.contains("define i64 @RangeLLVM_multiply(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("%1 = mul i64 %lhs, %rhs"))
    }

    @Test("Swift workspace emission writes hybrid emission report")
    func swiftWorkspaceEmissionWritesHybridEmissionReport() throws {
        let callables = [
            callable(
                "add",
                parameters: [
                    parameter("lhs", "Int"),
                    parameter("rhs", "Int"),
                ],
                returnType: .named("Int"),
                body: [
                    ret(binary(id("lhs"), .addition, id("rhs")))
                ]
            ),
            callable(
                "greet",
                parameters: [
                    parameter("name", "String")
                ],
                returnType: .named("String"),
                body: [
                    ret(id("name"))
                ]
            ),
        ]

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMEmissionReportTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables),
            at: root
        )

        let report = try String(
            contentsOf: root.appendingPathComponent("EmissionReport.txt"),
            encoding: .utf8
        )

        #expect(report.contains("LLVM lowered (2):"))
        #expect(report.contains("- add"))
        #expect(report.contains("- greet"))
        #expect(report.contains("Swift emitted (0):"))
        #expect(report.contains("- none"))
    }

    @Test("Swift workspace emission bridges calls to LLVM object")
    func swiftWorkspaceEmissionBridgesCallsToLLVMObject() throws {
        let callables = [sum3Callable()]
        let mainBlockNode = mainBlock([
            .expression(
                call(
                    "sum3",
                    argument("x", .integer(1)),
                    argument("y", .integer(2)),
                    argument("z", .integer(3))
                )
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )

        #expect(package.contains(".unsafeFlags([\"LLVM/RangeScalar.o\"])"))
        #expect(runtime.contains("@_silgen_name(\"RangeLLVM_sum3\")"))
        #expect(runtime.contains("func RangeLLVM_sum3(_ argument0: Int64, _ argument1: Int64, _ argument2: Int64) -> Int64"))
        #expect(main.contains("Int(RangeLLVM_sum3(Int64(1), Int64(2), Int64(3)))"))
        #expect(!main.contains("func sum3"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("LLVM/RangeScalar.ll").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("LLVM/RangeScalar.o").path))
    }

    @Test("Swift workspace emission bridges mixed Bool and Int LLVM calls")
    func swiftWorkspaceEmissionBridgesMixedBoolAndIntLLVMCalls() throws {
        let callables = [isLessCallable(), chooseCallable()]
        let mainBlockNode = mainBlock([
            .expression(
                call(
                    "choose",
                    argument(
                        "flag",
                        call("isLess", argument("lhs", .integer(1)), argument("rhs", .integer(2)))
                    ),
                    argument("value", .integer(42))
                )
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMMixedBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(
            runtime.contains(
                "func RangeLLVM_isLess(_ argument0: Int64, _ argument1: Int64) -> Bool"
            )
        )
        #expect(
            runtime.contains(
                "func RangeLLVM_choose(_ argument0: Bool, _ argument1: Int64) -> Int64"
            )
        )
        #expect(
            main.contains(
                "Int(RangeLLVM_choose(RangeLLVM_isLess(Int64(1), Int64(2)), Int64(42)))"
            )
        )
        #expect(ir.contains("define i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %value)"))
    }

    @Test("Swift workspace emission bridges Float LLVM calls")
    func swiftWorkspaceEmissionBridgesFloatLLVMCalls() throws {
        let callables = [mixedCallable()]
        let mainBlockNode = mainBlock([
            .expression(
                call("mixed", argument("lhs", .double(1.5)), argument("rhs", .integer(2)))
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMFloatBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("func RangeLLVM_mixed(_ argument0: Double, _ argument1: Int64) -> Double"))
        #expect(main.contains("Float(RangeLLVM_mixed(Double(1.5), Int64(2)))"))
        #expect(ir.contains("define double @RangeLLVM_mixed(double %lhs, i64 %rhs)"))
        #expect(ir.contains("sitofp i64 %rhs to double"))
        #expect(!main.contains("func mixed"))
    }

    @Test("Swift workspace emission bridges LLVM String returns")
    func swiftWorkspaceEmissionBridgesLLVMStringReturns() throws {
        let callables = [greetingCallable()]
        let mainBlockNode = mainBlock([
            .expression(call("greeting"))
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("struct __RangeLLVMString"))
        #expect(runtime.contains("func RangeLLVM_greeting() -> __RangeLLVMString"))
        #expect(main.contains("__RangeLLVMString.decode(RangeLLVM_greeting())"))
        #expect(ir.contains("define %Range.String @RangeLLVM_greeting()"))
        #expect(!main.contains("func greeting"))
    }

    @Test("Swift workspace emission keeps construct helpers inside LLVM island")
    func swiftWorkspaceEmissionKeepsConstructHelpersInsideLLVMIsland() throws {
        let declarations = [
            construct(
                "Point",
                values: [
                    value("x", typeName: "Int"),
                    value("y", typeName: "Int"),
                ]
            )
        ]
        let callables = [
            callable(
                "make",
                returnType: .named("Point"),
                body: [
                    ret(call("Point", argument("x", .integer(2)), argument("y", .integer(3))))
                ]
            ),
		            callable(
		                "score",
		                returnType: .named("Int"),
		                body: [
		                    local("point", typeName: "Point", expression: call("make")),
		                    ret(binary(id("point.x"), .addition, id("point.y"))),
		                ]
		            ),
        ]
        let mainBlockNode = mainBlock([
            .expression(call("score"))
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMConstructIslandTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(
                declarations: declarations,
                callables: callables,
                mainBlock: mainBlockNode
            ),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("func RangeLLVM_score() -> Int64"))
        #expect(!runtime.contains("func RangeLLVM_make"))
        #expect(main.contains("Int(RangeLLVM_score())"))
        #expect(!main.contains("func make"))
        #expect(!main.contains("func score"))
        #expect(ir.contains("%Range.Point = type { i64, i64 }"))
        #expect(ir.contains("define %Range.Point @RangeLLVM_make()"))
        #expect(ir.contains("define i64 @RangeLLVM_score()"))
        #expect(ir.contains("call %Range.Point @RangeLLVM_make()"))
    }

    @Test("Swift workspace emission bridges LLVM String arguments")
    func swiftWorkspaceEmissionBridgesLLVMStringArguments() throws {
        let callables = [echoCallable()]
        let mainBlockNode = mainBlock([
            .expression(call("echo", argument("value", .string("hello"))))
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringArgumentBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("static func withString<Result>"))
        #expect(runtime.contains("func RangeLLVM_echo(_ argument0: __RangeLLVMString) -> __RangeLLVMString"))
        #expect(
            main.contains(
                "__RangeLLVMString.decode(__RangeLLVMString.withString(\"hello\") { __rangeLLVMStringArgument0 in RangeLLVM_echo(__rangeLLVMStringArgument0) })"
            )
        )
        #expect(ir.contains("define %Range.String @RangeLLVM_echo(%Range.String %value)"))
        #expect(!main.contains("func echo"))
    }

    @Test("Swift workspace emission bridges LLVM String isEmpty Bool returns")
    func swiftWorkspaceEmissionBridgesLLVMStringIsEmptyBoolReturns() throws {
        let callables = [stringEmptyCallable()]
        let mainBlockNode = mainBlock([
            .expression(call("empty", argument("value", .string(""))))
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringIsEmptyBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("func RangeLLVM_empty(_ argument0: __RangeLLVMString) -> Bool"))
        #expect(main.contains("__RangeLLVMString.withString(\"\") { __rangeLLVMStringArgument0 in RangeLLVM_empty(__rangeLLVMStringArgument0) }"))
        #expect(ir.contains("define i1 @RangeLLVM_empty(%Range.String %value)"))
        #expect(ir.contains("extractvalue %Range.String %value, 1"))
        #expect(!main.contains("func empty"))
    }

    @Test("Swift workspace emission bridges LLVM String byteCount Int returns")
    func swiftWorkspaceEmissionBridgesLLVMStringByteCountIntReturns() throws {
        let callables = [stringSizeCallable()]
        let mainBlockNode = mainBlock([
            .expression(call("size", argument("value", .string("hé"))))
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMStringByteCountBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("func RangeLLVM_size(_ argument0: __RangeLLVMString) -> Int64"))
        #expect(main.contains("Int(__RangeLLVMString.withString(\"hé\") { __rangeLLVMStringArgument0 in RangeLLVM_size(__rangeLLVMStringArgument0) })"))
        #expect(ir.contains("define i64 @RangeLLVM_size(%Range.String %value)"))
        #expect(ir.contains("extractvalue %Range.String %value, 1"))
        #expect(!main.contains("func size"))
    }

    @Test("Swift workspace emission bridges LLVM Int array arguments")
    func swiftWorkspaceEmissionBridgesLLVMIntArrayArguments() throws {
        let callables = [firstArrayCallable()]
        let mainBlockNode = mainBlock([
            .expression(
                call(
                    "first",
                    argument("values", .array([.integer(1), .integer(2), .integer(3)]))
                )
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMIntArrayBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/Runtime.swift"),
            encoding: .utf8
        )
        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )
        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )

        #expect(runtime.contains("struct __RangeLLVMIntArray"))
        #expect(runtime.contains("func RangeLLVM_first(_ argument0: __RangeLLVMIntArray) -> Int64"))
        #expect(main.contains("Int(__RangeLLVMIntArray.withIntArray([1, 2, 3]) { __rangeLLVMIntArrayArgument0 in RangeLLVM_first(__rangeLLVMIntArrayArgument0) })"))
        #expect(ir.contains("define i64 @RangeLLVM_first(%Range.IntArray %values)"))
        #expect(ir.contains("load i64, ptr"))
        #expect(!main.contains("func first"))
    }

    @Test("Swift workspace emission converts LLVM Float return for Swift wrappers")
    func swiftWorkspaceEmissionConvertsLLVMFloatReturnForSwiftWrappers() throws {
        let callables = [
            mixedCallable(),
            callable(
                "describe",
                parameters: [
                    parameter("value", "Float")
                ],
                returnType: .named("String"),
                body: [
                    ret(call("String", id("value")))
                ]
            ),
        ]
        let mainBlockNode = mainBlock([
            .expression(
                call(
                    "describe",
                    argument(
                        "value",
                        call("mixed", argument("lhs", .double(1.5)), argument("rhs", .integer(2)))
                    )
                )
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMFloatWrapperBridgeTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: loweredProgram(callables: callables, mainBlock: mainBlockNode),
            at: root
        )

        let main = try String(
            contentsOf: root.appendingPathComponent("Sources/Main.swift"),
            encoding: .utf8
        )

        #expect(main.contains("func describe(value: Float) -> String"))
        #expect(main.contains("describe(value: Float(RangeLLVM_mixed(Double(1.5), Int64(2))))"))
        #expect(!main.contains("func mixed"))
    }

    @Test("Mixed scalar calls between LLVM functions stay in LLVM")
    func mixedScalarCallsBetweenLLVMFunctionsStayInLLVM() throws {
        let callables = mixedScalarCallChain()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMMixedCallChainTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try SwiftBackendEmitter().emitWorkspace(
            program: LoweredProgram(
                macrosByName: [:],
                callables: [],
                enumerations: [],
                declarations: [],
                extensions: [],
                mainBlock: BlockMacroNode(macros: [], body: []),
                units: [
                    LoweredSourceUnit(
                        outputFileName: "Math.swift",
                        enumerations: [],
                        declarations: [],
                        extensions: [],
                        callables: callables,
                        mainBlock: nil
                    )
                ]
            ),
            at: root
        )

        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/Math.swift"),
            encoding: .utf8
        )

        #expect(ir.contains("define i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("define i1 @RangeLLVM_invert(i1 %value)"))
        #expect(ir.contains("define i64 @RangeLLVM_choose(i1 %flag, i64 %value)"))
        #expect(ir.contains("define i64 @RangeLLVM_chooseLower(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("call i1 @RangeLLVM_isLess(i64 %lhs, i64 %rhs)"))
        #expect(ir.contains("br i1 %"))
        #expect(ir.contains("call i1 @RangeLLVM_invert(i1 0)"))
        #expect(ir.contains("call i64 @RangeLLVM_choose(i1"))
        #expect(!swift.contains("func isLess"))
        #expect(!swift.contains("func invert"))
        #expect(!swift.contains("func choose("))
        #expect(!swift.contains("func chooseLower"))
    }

    @Test("Explicit while loop lowers through adapter into LLVM while")
    func explicitWhileLoopLowersThroughAdapterIntoLLVMWhile() throws {
        let callables = [
            callable(
                "rangeSum",
                parameters: [
                    parameter("limit", "Int")
                ],
                returnType: .named("Int"),
                body: [
                    state("total", type: .named("Int"), expression: .integer(0)),
                    state("index", type: .named("Int"), expression: .integer(0)),
                    whileLoop(
                        binary(id("index"), .less, id("limit")),
                        [
                            assign("total", binary(id("total"), .addition, id("index"))),
                            assign("index", binary(id("index"), .addition, .integer(1))),
                        ]
                    ),
                    ret(id("total")),
                ]
            )
        ]
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeLLVMRangeForTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let program = SwiftLoweredProgramAdapter().adapt(
            program: loweredProgram(outputFileName: "Loops.swift", callables: callables)
        )

        try SwiftBackendEmitter().emitWorkspace(
            program: program,
            at: root
        )

        let ir = try String(
            contentsOf: root.appendingPathComponent("LLVM/RangeScalar.ll"),
            encoding: .utf8
        )
        let swift = try String(
            contentsOf: root.appendingPathComponent("Sources/Loops.swift"),
            encoding: .utf8
        )

        #expect(ir.contains("define i64 @RangeLLVM_rangeSum(i64 %limit)"))
        #expect(ir.contains("%index.addr = alloca i64"))
        #expect(ir.contains("while.cond."))
        #expect(ir.contains("icmp slt i64"))
        #expect(ir.contains("add i64"))
        #expect(ir.contains("ret i64"))
        #expect(!swift.contains("func rangeSum"))
    }

    @Test("Core Int carries evaluated @integer scalar metadata")
    func coreIntCarriesEvaluatedIntegerScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let intConstruct = try #require(program.declarationGraph.constructsByName["Int"])
        let integerMacro = try #require(
            intConstruct.macros.first(where: { $0.name == "integer" }))
        #expect(integerMacro.evaluatedStringValue == "integer|bits=64|signedness=signed")
    }

    @Test("Int @integer macro evaluated value carries scalar metadata")
    func integerMacroEvaluatedValueCarriesScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let intConstruct = try #require(program.declarationGraph.constructsByName["Int"])
        let integerMacro = try #require(
            intConstruct.macros.first(where: { $0.name == "integer" }))
        #expect(integerMacro.evaluatedStringValue == "integer|bits=64|signedness=signed")
    }

    @Test("Core Bool carries evaluated @bool scalar metadata")
    func coreBoolCarriesEvaluatedBoolScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let boolConstruct = try #require(program.declarationGraph.constructsByName["Bool"])
        let boolMacro = try #require(
            boolConstruct.macros.first(where: { $0.name == "bool" }))
        #expect(boolMacro.evaluatedStringValue == "bool")

        let declarations = Array(program.declarationGraph.constructsByName.values)
        let scalarTypes = LLVMLowerability.scalarTypes(from: declarations)
        #expect(scalarTypes["Bool"] == .bool)
    }

    @Test("Capability LLVM emitter gathers scalar applications before declarations")
    func capabilityLLVMEmitterGathersScalarApplicationsBeforeDeclarations() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)

        let emitter = CapabilityLLVMEmitter()
        let applications = emitter.collectScalarApplications(files: program.expandedFiles)
        let declarations = emitter.resolveScalarDeclarations(applications: applications)

        #expect(
            applications.contains {
                $0.macroName == "integer" && $0.targetName == "Int" && $0.resolvedValue == "i64"
            }
        )
        #expect(
            applications.contains {
                $0.macroName == "bool" && $0.targetName == "Bool" && $0.resolvedValue == "i1"
            }
        )
        #expect(
            declarations.contains {
                $0.macroName == "integer" && $0.targetName == "Int" && $0.llvmType == "i64"
            }
        )
        #expect(
            declarations.contains {
                $0.macroName == "bool" && $0.targetName == "Bool" && $0.llvmType == "i1"
            }
        )
    }

    @Test("Capability LLVM emitter keeps scalar declarations out of main IR")
    func capabilityLLVMEmitterKeepsScalarDeclarationsOutOfMainIR() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let module = CapabilityLLVMEmitter().emitModule(compiledProgram: program)

        #expect(
            module.scalarDeclarations.contains {
                $0.targetName == "Int" && $0.llvmType == "i64"
            }
        )
        #expect(
            module.scalarDeclarations.contains {
                $0.targetName == "Bool" && $0.llvmType == "i1"
            }
        )
        #expect(!module.ir.contains("range.scalar"))
        #expect(!module.ir.contains("%Range.Int"))
        #expect(!module.ir.contains("%Range.Bool"))
        #expect(module.mainIR == nil)
        #expect(module.ir.isEmpty)
    }

    @Test("Core String carries evaluated @string marker metadata")
    func coreStringCarriesEvaluatedStringMarkerMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let stringConstruct = try #require(program.declarationGraph.constructsByName["String"])
        let stringMacro = try #require(
            stringConstruct.macros.first(where: { $0.name == "string" }))
        #expect(stringMacro.evaluatedStringValue == "string")
    }

    @Test("LLVM lowerability uses evaluated @integer scalar metadata")
    func llvmLowerabilityUsesEvaluatedIntegerScalarMetadata() throws {
        let inputs = try rangeCoreInputs()
        let program = try CompilerPipeline().build(inputs: inputs)
        let declarations = Array(program.declarationGraph.constructsByName.values)
        let scalarTypes = LLVMLowerability.scalarTypes(from: declarations)
        #expect(scalarTypes["Int"] == .int(bits: 64, signed: true))

        let callable = callable(
            "add",
            parameters: [
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ret(binary(id("lhs"), .addition, id("rhs")))
            ]
        )
        let signature = try #require(
            LLVMLowerability.scalarSignature(for: callable, scalarTypes: scalarTypes)
        )
        #expect(signature.returnType == .int(bits: 64, signed: true))

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: [callable],
                scalarTypes: scalarTypes
            )
        )
        #expect(module.ir.contains("define i64 @RangeLLVM_add(i64 %lhs, i64 %rhs)"))
    }

    @Test("Extension member lowers directly through receiver scalar metadata")
    func extensionMemberLowersDirectlyThroughReceiverScalarMetadata() throws {
        let callable = CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            receiverType: .named("Int"),
            name: "+",
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: [
                RangeFunctionParameter(
                    macros: [],
                    name: "lhs",
                    typeReference: .named("Self"),
                    slotName: nil
                ),
                RangeFunctionParameter(
                    macros: [],
                    name: "rhs",
                    typeReference: .named("Self"),
                    slotName: nil
                ),
            ],
            returnType: .named("Self"),
            body: [
                ret(binary(id("lhs"), .addition, id("rhs")))
            ]
        )
        let scalarTypes: [String: LLVMLowerability.ScalarType] = [
            "Int": .int(bits: 64, signed: true)
        ]

        #expect(LLVMLowerability.canLower(callable, scalarTypes: scalarTypes))

        let module = try #require(
            try LLVMLoweringEmitter().emitModule(
                callables: [callable],
                scalarTypes: scalarTypes
            )
        )
        #expect(module.loweredSymbols == [
            LLVMLoweredSymbol(rangeName: "Int.+", llvmName: "RangeLLVM_Int__")
        ])
        #expect(module.ir.contains("define i64 @RangeLLVM_Int__(i64 %lhs, i64 %rhs)"))
    }

    @Test("Swift backend public LLVM emission has no Swift-owned @main fallback")
    func swiftBackendPublicLLVMEmissionHasNoSwiftOwnedMainFallback() throws {
        var inputs = try rangeCoreInputs()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainBlock-\(UUID().uuidString).range")
        inputs.append(
            SourceInput(
                path: fileURL.path,
                source: """
                    @main {
                    }
                    """,
                role: .project
            )
        )
        let program = try CompilerPipeline().build(inputs: inputs)
        do {
            _ = try SwiftBackend().emitLLVMIR(
                project: SwiftBackendProject(
                    projectFiles: [fileURL],
                    isSingleFile: true,
                    buildRoot: FileManager.default.temporaryDirectory
                        .appendingPathComponent("RangeLLVM-\(UUID().uuidString)")
                ),
                compiledProgram: program
            )
            Issue.record("Expected Swift backend LLVM emission to reject @main-only source.")
        } catch let error as SwiftBackendError {
            #expect(
                error.message.contains(
                    "Range program has no LLVM-lowerable declarations."
                )
            )
        }
    }

    @Test("Concrete @llvm body is collected, written, and run through clang")
    func concreteLLVMBodyEmitsWritesAndRuns() throws {
        // A Range-authored @llvm string can be returned through an ordinary
        // String-producing macro, then written to .ll and run through clang.
        var inputs = try rangeCoreInputs()
        inputs.append(
            SourceInput(
                path: "/tmp/ConcreteLLVM.range",
                source: """
                    @macro(name: "concreteLLVM", result: "String", target: "@syntax") {
                        @return(value: "@llvm(body: \\"define i64 @range_concrete_answer() {\\nentry:\\n  ret i64 42\\n}\\")")
                    }

                    @concreteLLVM
                    @construct(name: "ConcreteAnswer") {
                        @let(name: "value") {
                            @value(type: "Int")
                        }
                    }
                    """,
                role: .project
            )
        )
        let program = try CompilerPipeline().build(inputs: inputs)
        let construct = try #require(program.declarationGraph.constructsByName["ConcreteAnswer"])
        let concreteLLVM = try #require(
            construct.macros.first(where: { $0.name == "concreteLLVM" })?
                .evaluatedStringValue
        )
        let ir = concreteLLVM + "\n"

        let clang = URL(fileURLWithPath: "/usr/bin/clang")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RangeConcreteLLVMTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let irURL = root.appendingPathComponent("concrete.ll")
        let harnessURL = root.appendingPathComponent("harness.c")
        let executableURL = root.appendingPathComponent("concrete")

        try ir.write(to: irURL, atomically: true, encoding: .utf8)
        try """
            #include <stdint.h>
            #include <stdio.h>

            extern int64_t range_concrete_answer(void);

            int main(void) {
                printf("%lld\\n", (long long)range_concrete_answer());
                return 0;
            }
            """
            .write(to: harnessURL, atomically: true, encoding: .utf8)

        let compile = try run(
            clang,
            arguments: [irURL.path, harnessURL.path, "-O3", "-o", executableURL.path]
        )
        if compile.status != 0 {
            Issue.record("clang failed:\n\(compile.stderr)\nIR:\n\(ir)")
        }
        #expect(compile.status == 0)

        let runResult = try run(executableURL, arguments: [])
        #expect(runResult.status == 0)
        #expect(runResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }

    @Test("Multi-line @llvm template splits into instruction lines on newline")
    func multiLineLLVMTemplateSplitsOnNewline() throws {
        let template = SwiftBackendEmitter.CollectedLLVMConstruct(
            constructName: "Int",
            rawBody: "%r = add i$bits $lhs, $rhs\nret i$bits %r"
        )
        let lines = template.lines(bindings: ["bits": "32", "lhs": "%lhs", "rhs": "%rhs"])
        #expect(lines == ["%r = add i32 %lhs, %rhs", "ret i32 %r"])
    }

    private func loweredProgram(
        outputFileName: String = "Main.swift",
        declarations: [ConstructDeclaration] = [],
        callables: [CallableDeclaration],
        mainBlock: BlockMacroNode? = nil
    ) -> LoweredProgram {
        LoweredProgram(
            macrosByName: [:],
            callables: [],
            enumerations: [],
            declarations: [],
            extensions: [],
            mainBlock: BlockMacroNode(macros: [], body: []),
            units: [
                LoweredSourceUnit(
                    outputFileName: outputFileName,
                    enumerations: [],
                    declarations: declarations,
                    extensions: [],
                    callables: callables,
                    mainBlock: mainBlock
                )
            ]
        )
    }

    private func mainBlock(_ body: [Statement]) -> BlockMacroNode {
        BlockMacroNode(
            macros: [
                MacroApplication(name: "main", genericArguments: [], argumentClause: nil)
            ],
            body: body
        )
    }

    private func callable(
        _ name: String,
        parameters: [RangeFunctionParameter] = [],
        returnType: TypeReference?,
        body: [Statement]
    ) -> CallableDeclaration {
        CallableDeclaration(
            macros: [],
            attribute: nil,
            targetType: nil,
            name: name,
            genericParameters: [],
            hasExplicitParameterClause: true,
            parameters: parameters,
            returnType: returnType,
            body: body
        )
    }

    private func parameter(_ name: String, _ typeName: String) -> RangeFunctionParameter {
        parameter(name, .named(typeName))
    }

    private func parameter(
        _ name: String,
        _ typeReference: TypeReference
    ) -> RangeFunctionParameter {
        RangeFunctionParameter(
            macros: [],
            name: name,
            typeReference: typeReference,
            slotName: nil
        )
    }

    private func ret(_ expression: RangeExpression) -> Statement {
        .emitted("statement|kind=return|value=\(expressionSource(expression))|llvm=ret value")
    }

    private func local(
        _ name: String,
        typeName: String,
        expression: RangeExpression
    ) -> Statement {
        .emitted(
            "member|kind=let|name=\(name)|type=\(typeName)|value=\(expressionSource(expression))"
        )
    }

    private func state(
        _ name: String,
        type: TypeReference,
        expression: RangeExpression
    ) -> Statement {
        .emitted(
            "member|kind=state|name=\(name)|type=\(type.displayName)|value=\(expressionSource(expression))"
        )
    }

    private func assign(_ name: String, _ expression: RangeExpression) -> Statement {
        .emitted("statement|kind=assign|target=\(name)|value=\(expressionSource(expression))")
    }

    private func whileLoop(
        _ condition: RangeExpression,
        _ body: [Statement]
    ) -> Statement {
        .emitted(
            (["statement|kind=while|condition=\(expressionSource(condition))"]
                + body.map(statementRecordSource)
                + ["statement|kind=end"])
                .joined(separator: "\n")
        )
    }

    private func ifStatement(
        _ condition: RangeExpression,
        _ body: [Statement]
    ) -> Statement {
        .emitted(
            (["statement|kind=if|condition=\(expressionSource(condition))"]
                + body.map(statementRecordSource)
                + ["statement|kind=end"])
                .joined(separator: "\n")
        )
    }

    private func ifElseStatement(
        _ condition: RangeExpression,
        _ trueBody: [Statement],
        _ falseBody: [Statement]
    ) -> Statement {
        .emitted(
            (["statement|kind=if|condition=\(expressionSource(condition))"]
                + trueBody.map(statementRecordSource)
                + ["statement|kind=else"]
                + falseBody.map(statementRecordSource)
                + ["statement|kind=end"])
                .joined(separator: "\n")
        )
    }

    private func breakStatement() -> Statement {
        .emitted("statement|kind=break")
    }

    private func continueStatement() -> Statement {
        .emitted("statement|kind=continue")
    }

    private func statementRecordSource(_ statement: Statement) -> String {
        if case .emitted(let text) = statement {
            return text
        }
        if case .expression(let expression) = statement {
            return "statement|kind=expression|value=\(expressionSource(expression))"
        }
        else {
            Issue.record("Expected stringy statement record, got \(statement).")
            return ""
        }
    }

    private func expressionSource(_ expression: RangeExpression) -> String {
        switch expression {
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return "\(value)"
        case .string(let value):
            return "\"\(escapedString(value))\""
        case .boolean(let value):
            return value ? "true" : "false"
        case .nilLiteral:
            return "nil"
        case .identifier(let name):
            return name
        case .bindingReference(let name):
            return "$\(name)"
        case .call(let name, let arguments):
            let renderedArguments = arguments.map { argument in
                if let label = argument.label {
                    return "\(label): \(expressionSource(argument.value))"
                }
                return expressionSource(argument.value)
            }.joined(separator: ", ")
            return "\(name)(\(renderedArguments))"
        case .array(let elements):
            return "[\(elements.map(expressionSource).joined(separator: ", "))]"
        case .dictionary(let elements):
            return "[\(elements.map { "\(expressionSource($0.key)): \(expressionSource($0.value))" }.joined(separator: ", "))]"
        case .ternary(let condition, let trueExpression, let falseExpression):
            return
                "(\(expressionSource(condition)) ? \(expressionSource(trueExpression)) : \(expressionSource(falseExpression)))"
        case .unary(let operatorSymbol, let nested):
            return "\(operatorSymbol.rawValue)\(expressionSource(nested))"
        case .binary(let lhs, let operatorSymbol, let rhs):
            return "(\(expressionSource(lhs)) \(operatorSymbol.rawValue) \(expressionSource(rhs)))"
        case .block, .macroInvocation:
            Issue.record("Unsupported expression in stringy LLVM fixture: \(expression).")
            return ""
        }
    }

    private func escapedString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func id(_ name: String) -> RangeExpression {
        .identifier(name)
    }

    private func call(_ name: String) -> RangeExpression {
        .call(name: name, arguments: [])
    }

    private func call(_ name: String, _ arguments: RangeExpression...) -> RangeExpression {
        .call(
            name: name,
            arguments: arguments.map { CallArgument(label: nil, value: $0) }
        )
    }

    private func call(_ name: String, _ arguments: CallArgument...) -> RangeExpression {
        .call(name: name, arguments: arguments)
    }

    private func argument(_ label: String, _ value: RangeExpression) -> CallArgument {
        CallArgument(label: label, value: value)
    }

    private func binary(
        _ lhs: RangeExpression,
        _ operatorSymbol: BinaryOperator,
        _ rhs: RangeExpression
    ) -> RangeExpression {
        .binary(lhs: lhs, operatorSymbol: operatorSymbol, rhs: rhs)
    }

    private func nestedSumCallable() -> CallableDeclaration {
        callable(
            "nestedSum",
            parameters: [
                parameter("limit", "Int")
            ],
            returnType: .named("Int"),
            body: [
                state("outer", type: .named("Int"), expression: .integer(0)),
                state("total", type: .named("Int"), expression: .integer(0)),
                whileLoop(
                    binary(id("outer"), .less, id("limit")),
                    [
                        state("inner", type: .named("Int"), expression: .integer(0)),
                        whileLoop(
                            binary(id("inner"), .less, id("limit")),
                            [
                                assign(
                                    "total",
                                    binary(
                                        binary(id("total"), .addition, id("outer")),
                                        .addition,
                                        id("inner")
                                    )
                                ),
                                assign("inner", binary(id("inner"), .addition, .integer(1))),
                            ]
                        ),
                        assign("outer", binary(id("outer"), .addition, .integer(1))),
                    ]
                ),
                ret(id("total")),
            ]
        )
    }

    private func sum3Callable() -> CallableDeclaration {
        callable(
            "sum3",
            parameters: [
                parameter("x", "Int"),
                parameter("y", "Int"),
                parameter("z", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ret(binary(binary(id("x"), .addition, id("y")), .addition, id("z")))
            ]
        )
    }

    private func isLessCallable() -> CallableDeclaration {
        callable(
            "isLess",
            parameters: [
                parameter("lhs", "Int"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Bool"),
            body: [
                ret(binary(id("lhs"), .less, id("rhs")))
            ]
        )
    }

    private func chooseCallable() -> CallableDeclaration {
        callable(
            "choose",
            parameters: [
                parameter("flag", "Bool"),
                parameter("value", "Int"),
            ],
            returnType: .named("Int"),
            body: [
                ifElseStatement(id("flag"), [ret(id("value"))], [ret(.integer(0))])
            ]
        )
    }

    private func mixedCallable() -> CallableDeclaration {
        callable(
            "mixed",
            parameters: [
                parameter("lhs", "Float"),
                parameter("rhs", "Int"),
            ],
            returnType: .named("Float"),
            body: [
                ret(binary(id("lhs"), .addition, id("rhs")))
            ]
        )
    }

    private func greetingCallable() -> CallableDeclaration {
        callable(
            "greeting",
            returnType: .named("String"),
            body: [
                ret(.string("hello"))
            ]
        )
    }

    private func echoCallable() -> CallableDeclaration {
        callable(
            "echo",
            parameters: [
                parameter("value", "String")
            ],
            returnType: .named("String"),
            body: [
                ret(id("value"))
            ]
        )
    }

    private func stringEmptyCallable() -> CallableDeclaration {
        callable(
            "empty",
            parameters: [
                parameter("value", "String")
            ],
            returnType: .named("Bool"),
            body: [
                ret(id("value.isEmpty"))
            ]
        )
    }

    private func stringSizeCallable() -> CallableDeclaration {
        callable(
            "size",
            parameters: [
                parameter("value", "String")
            ],
            returnType: .named("Int"),
            body: [
                ret(id("value.byteCount"))
            ]
        )
    }

    private func firstArrayCallable() -> CallableDeclaration {
        callable(
            "first",
            parameters: [
                parameter("values", .array(.named("Int")))
            ],
            returnType: .named("Int"),
            body: [
                ret(call("values.element", argument("index", .integer(0))))
            ]
        )
    }

    private func mixedScalarCallChain() -> [CallableDeclaration] {
        [
            callable(
                "isLess",
                parameters: [
                    parameter("lhs", "Int"),
                    parameter("rhs", "Int"),
                ],
                returnType: .named("Bool"),
                body: [
                    ret(binary(id("lhs"), .less, id("rhs")))
                ]
            ),
            callable(
                "invert",
                parameters: [
                    parameter("value", "Bool")
                ],
                returnType: .named("Bool"),
                body: [
                    ret(.unary(operatorSymbol: .not, expression: id("value")))
                ]
            ),
            callable(
                "choose",
                parameters: [
                    parameter("flag", "Bool"),
                    parameter("value", "Int"),
                ],
                returnType: .named("Int"),
                body: [
                    ifElseStatement(id("flag"), [ret(id("value"))], [ret(.integer(0))])
                ]
            ),
            callable(
                "chooseLower",
                parameters: [
                    parameter("lhs", "Int"),
                    parameter("rhs", "Int"),
                ],
                returnType: .named("Int"),
                body: [
                    ifElseStatement(
                        call(
                            "isLess",
                            argument("lhs", id("lhs")),
                            argument("rhs", id("rhs"))
                        ),
                        [
                            ret(
                                call(
                                    "choose",
                                    argument(
                                        "flag",
                                        call("invert", argument("value", .boolean(false)))
                                    ),
                                    argument("value", id("lhs"))
                                )
                            )
                        ],
                        [
                            ret(
                                call(
                                    "choose",
                                    argument("flag", .boolean(false)),
                                    argument("value", id("rhs"))
                                )
                            )
                        ]
                    )
                ]
            ),
        ]
    }

    private func construct(
        _ name: String,
        values: [ValueDeclaration] = []
    ) -> ConstructDeclaration {
        ConstructDeclaration(
            macros: [],
            kind: .declaration,
            attribute: nil,
            name: name,
            genericParameters: [],
            conformances: [],
            states: [],
            bindings: [],
            deriveds: [],
            values: values,
            initializers: [],
            callables: [],
            constructs: []
        )
    }

    private func value(
        _ name: String,
        typeName: String,
        value: RangeCompiler.Expression? = nil
    ) -> ValueDeclaration {
        ValueDeclaration(
            macros: [],
            name: name,
            typeName: typeName,
            value: value
        )
    }

    private func mainBlock(in module: ModuleFileNode) -> BlockMacroNode? {
        module.blockMacros.first(where: { $0.macros.first?.name == "main" })
    }

    private func callableDeclarations(in module: ModuleFileNode) -> [CallableDeclaration] {
        module.constructs.flatMap(callableDeclarations(in:))
            + module.extensions.flatMap { extensionDeclaration in
                extensionDeclaration.callables
                    + extensionDeclaration.constructs.flatMap(callableDeclarations(in:))
            }
    }

    private func callableDeclarations(in construct: ConstructDeclaration) -> [CallableDeclaration] {
        construct.callables + construct.constructs.flatMap(callableDeclarations(in:))
    }

    private func rangeCoreInputs() throws -> [SourceInput] {
        let root = try repositoryRoot()
            .appendingPathComponent("RangeCompiler", isDirectory: true)
            .appendingPathComponent("Range", isDirectory: true)
        let files =
            try rangeFiles(
                in: root.appendingPathComponent("Core", isDirectory: true),
                excludingExploration: true
            )
        + rangeFiles(
            in: root.appendingPathComponent("Foundation/Macros", isDirectory: true),
            excludingExploration: true
        )

        return try files.map { file in
            SourceInput(
                path: file.path,
                source: try String(contentsOf: file, encoding: .utf8),
                role: .core
            )
        }
    }

    private func rangeFiles(in root: URL, excludingExploration: Bool) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw LLVMLoweringEmitterTestError.missingDirectory(root.path)
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isDirectory =
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if excludingExploration,
                isDirectory,
                url.lastPathComponent == "Exploration",
                url.path.contains("/RangeCompiler/Range/Core/")
            {
                enumerator.skipDescendants()
                continue
            }

            guard !isDirectory, url.pathExtension.lowercased() == "range" else {
                continue
            }
            files.append(url)
        }

        return files.sorted(by: rangeCoreFilePrecedence)
    }

    private func rangeCoreFilePrecedence(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsPriority = lhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
        let rhsPriority = rhs.path.hasSuffix("/Range/Foundation/Macros/Macro.range") ? 0 : 1
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.path < rhs.path
    }

    private func repositoryRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidateCore =
                current
                .appendingPathComponent("RangeCompiler", isDirectory: true)
                .appendingPathComponent("Range", isDirectory: true)
                .appendingPathComponent("Core", isDirectory: true)
            var isCoreDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: candidateCore.path,
                isDirectory: &isCoreDirectory
            ),
                isCoreDirectory.boolValue
            {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw LLVMLoweringEmitterTestError.missingDirectory("repository root")
    }

    private func run(_ executableURL: URL, arguments: [String]) throws -> (
        status: Int32, stdout: String, stderr: String
    ) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private enum LLVMLoweringEmitterTestError: Error {
    case expectedCallable
    case missingDirectory(String)
}
