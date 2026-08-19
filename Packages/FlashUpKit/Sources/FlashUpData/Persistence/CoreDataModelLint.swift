import CoreData

public enum CoreDataModelLint {
    private static let requiredIndexes: [String: Set<String>] = [
        "CDDeck": ["uuidIndex", "deletedAtIndex"],
        "CDNote": ["uuidIndex", "deletedAtIndex"],
        "CDCard": ["uuidIndex", "deletedAtIndex"],
        "CDTag": ["uuidIndex", "normalizedNameIndex", "deletedAtIndex"],
        "CDSchedule": ["uuidIndex", "cardUUIDIndex", "deckUUIDIndex", "dueAtIndex"],
        "CDReviewLog": ["uuidIndex", "cardUUIDIndex", "deckUUIDIndex", "reviewedAtIndex"],
        "CDImportBatch": ["uuidIndex", "destinationDeckUUIDIndex", "importedAtIndex"],
        "CDStudySettings": ["uuidIndex", "singletonKeyIndex"]
    ]

    public static func issues(in model: NSManagedObjectModel) -> [String] {
        let expected: Set<String> = [
            "CDDeck", "CDNote", "CDCard", "CDTag", "CDSchedule", "CDReviewLog", "CDImportBatch", "CDStudySettings"
        ]
        let actualEntities = Set(model.entities.compactMap(\.name))
        let missing = expected.subtracting(actualEntities).sorted().map { "missing entity \($0)" }
        let unexpected = actualEntities.subtracting(expected).sorted().map { "unexpected entity \($0)" }
        return missing + unexpected + model.entities.flatMap(entityIssues)
    }

    private static func entityIssues(_ entity: NSEntityDescription) -> [String] {
        let name = entity.name ?? "?"
        let uniqueness = entity.uniquenessConstraints.isEmpty ? [] : ["\(name) has uniqueness constraints"]
        let attributes = entity.attributesByName.values.compactMap { attribute in
            attribute.isOptional || attribute.defaultValue != nil
                ? nil
                : "\(name).\(attribute.name) is required without a default"
        }
        let required = requiredIndexes[entity.name ?? ""] ?? []
        let actual = Set(entity.indexes.compactMap(\.name))
        let indexes = required.subtracting(actual).sorted().map { index in
            "\(name) is missing index \(index)"
        }
        let relationships = entity.relationshipsByName.values.flatMap(relationshipIssues)
        return uniqueness + attributes + indexes + relationships
    }

    private static func relationshipIssues(_ relationship: NSRelationshipDescription) -> [String] {
        let name = "\(relationship.entity.name ?? "?").\(relationship.name)"
        var issues: [String] = []
        if !relationship.isOptional { issues.append("\(name) is required") }
        if relationship.inverseRelationship == nil { issues.append("\(name) has no inverse") }
        if relationship.isOrdered { issues.append("\(name) is ordered") }
        if relationship.deleteRule == .denyDeleteRule { issues.append("\(name) uses deny delete") }
        return issues
    }
}
