@testable import Newbee
import SwiftData

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try PersistenceController.makeContainer(.inMemory)
}
