import Foundation

@main
struct NeatMain {
    static func main() throws {
        var person = Person(name: "George", age: 26)
        person.age += 1
        let personString: String = {
                "Person: \(person.name), Age: \(person.age)"
        }()
        var user = User(person: person)
        user.incrementAge()
    }
}
