import CoreData
import Foundation
import SwiftData
import Testing
@testable import Newbee

/// `cloudkit/schema.ckdb` must describe every record type and field Core Data's CloudKit
/// mirroring writes for the current models. TestFlight and App Store builds only sync with the
/// production schema, so a field missing there stops sync on every device (docs/ICLOUD_SYNC.md).
@Suite("CloudKit schema")
struct CloudKitSchemaTests {
    struct Field: Hashable, CustomStringConvertible {
        let recordType: String
        let name: String
        let type: String

        var description: String { "\(recordType).\(name) \(type)" }
    }

    /// The fields mirroring writes for `NewbeeSchemaV3`, from the same Core Data model SwiftData
    /// builds for it.
    static func expectedFields() throws -> Set<Field> {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: NewbeeSchemaV3.models))
        var fields = Set<Field>()
        for entity in model.entities {
            let entityName = try #require(entity.name)
            let recordType = "CD_\(entityName)"
            fields.insert(Field(recordType: recordType, name: "CD_entityName", type: "STRING"))
            for (name, attribute) in entity.attributesByName {
                let type: String
                var hasAsset = false
                switch attribute.attributeType {
                case .stringAttributeType:
                    type = "STRING"
                    hasAsset = true
                case .UUIDAttributeType, .URIAttributeType:
                    type = "STRING"
                case .dateAttributeType:
                    type = "TIMESTAMP"
                case .booleanAttributeType, .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
                    type = "INT64"
                case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
                    type = "DOUBLE"
                case .binaryDataAttributeType, .transformableAttributeType:
                    type = "BYTES"
                    hasAsset = true
                default:
                    Issue.record("\(entityName).\(name) has a type CloudKit mirroring doesn't support")
                    continue
                }
                fields.insert(Field(recordType: recordType, name: "CD_\(name)", type: type))
                if hasAsset {
                    fields.insert(Field(recordType: recordType, name: "CD_\(name)_ckAsset", type: "ASSET"))
                }
            }
            for (name, relationship) in entity.relationshipsByName {
                if relationship.isToMany {
                    // Stored on the other side's to-one field. Many-to-many would need CDMR records.
                    #expect(relationship.inverseRelationship?.isToMany == false, "\(entityName).\(name) is many-to-many")
                } else {
                    fields.insert(Field(recordType: recordType, name: "CD_\(name)", type: "STRING"))
                }
            }
        }
        return fields
    }

    /// The `CD_` fields declared in the schema file.
    static func declaredFields() throws -> Set<Field> {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "cloudkit/schema.ckdb")
        let text = try String(contentsOf: url, encoding: .utf8)
        var fields = Set<Field>()
        var recordType: String?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") { continue }
            if line.hasPrefix("RECORD TYPE ") {
                recordType = line.dropFirst("RECORD TYPE ".count).split(separator: " ").first.map(String.init)
                continue
            }
            if line.hasPrefix(");") {
                recordType = nil
                continue
            }
            let words = line.split(separator: " ")
            guard let recordType, recordType.hasPrefix("CD_"), words.count >= 2, words[0].hasPrefix("CD_") else { continue }
            fields.insert(Field(recordType: recordType, name: String(words[0]), type: String(words[1]).trimmingCharacters(in: CharacterSet(charactersIn: ","))))
        }
        return fields
    }

    @Test func schemaFileCoversEveryField() throws {
        let expected = try Self.expectedFields()
        let declared = try Self.declaredFields()
        let missing = expected.subtracting(declared).map(\.description).sorted()
        #expect(missing.isEmpty, "Add these to cloudkit/schema.ckdb: \(missing.joined(separator: ", "))")
    }

    /// Extra fields are harmless, but a field with the wrong type, or a model that's gone, means
    /// the file and the models have drifted apart.
    @Test func schemaFileHasNoStrayFields() throws {
        let expected = try Self.expectedFields()
        let declared = try Self.declaredFields()
        let stray = declared.subtracting(expected).map(\.description).sorted()
        #expect(stray.isEmpty, "Not written by the current models: \(stray.joined(separator: ", "))")
    }
}
