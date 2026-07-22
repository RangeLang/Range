import Foundation

let n = CommandLine.arguments.dropFirst().first.flatMap(Int64.init) ?? 10_000_000

var i: Int64 = 0
var acc: Int64 = 1
while i < n {
    acc = (acc * 1_664_525 + i) % 2_147_483_647
    i += 1
}

print(acc)
