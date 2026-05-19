import Foundation

struct Person {
    let name: String
    
    var age: Int
}

struct User {
    var person: Person
    
    mutating func incrementAge() {
            person.age += 1
    }
}

@main
struct RangeMain {
    static func main() throws {
        var person: Person = Person(name: "George", age: 26)
        person.age += 1
        let personString: String = {
                "Person: \(person.name), Age: \(person.age)"
        }()
        var user: User = User(person: person)
        user.incrementAge()
    }
}
