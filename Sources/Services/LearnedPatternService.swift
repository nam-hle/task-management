import Foundation
import SwiftData

enum LearnedPatternServiceError: Error, LocalizedError {
    case patternNotFound
    var errorDescription: String? { "Learned pattern not found" }
}

@ModelActor
actor LearnedPatternService: LearnedPatternServiceProtocol {
    func findMatch(
        contextType: String,
        identifier: String
    ) throws -> PersistentIdentifier? {
        let predicate = #Predicate<LearnedPattern> {
            $0.contextType == contextType
                && $0.identifierValue == identifier
                && $0.isActive == true
        }
        let descriptor = FetchDescriptor<LearnedPattern>(predicate: predicate)
        guard let pattern = try modelContext.fetch(descriptor).first else {
            return nil
        }
        return pattern.persistentModelID
    }

    func linkedTodoID(for patternID: PersistentIdentifier) -> PersistentIdentifier? {
        guard let pattern = modelContext.model(for: patternID) as? LearnedPattern else {
            return nil
        }
        return pattern.linkedTodo?.persistentModelID
    }

    func learnFromReview(
        contextType: String,
        identifier: String,
        todoID: PersistentIdentifier
    ) throws {
        let predicate = #Predicate<LearnedPattern> {
            $0.contextType == contextType
                && $0.identifierValue == identifier
        }
        let descriptor = FetchDescriptor<LearnedPattern>(predicate: predicate)

        if let existing = try modelContext.fetch(descriptor).first {
            existing.confirmationCount += 1
            existing.lastConfirmedAt = Date()
            existing.isActive = true
            if let todo = modelContext.model(for: todoID) as? Todo {
                existing.linkedTodo = todo
            }
        } else {
            let todo = modelContext.model(for: todoID) as? Todo
            let pattern = LearnedPattern(
                contextType: contextType,
                identifierValue: identifier,
                linkedTodo: todo
            )
            modelContext.insert(pattern)
        }
        try modelContext.save()
    }

    func revoke(patternID: PersistentIdentifier) throws {
        guard let pattern = modelContext.model(for: patternID) as? LearnedPattern else {
            throw LearnedPatternServiceError.patternNotFound
        }
        pattern.isActive = false
        try modelContext.save()
    }

    func flagStalePatterns() throws -> Int {
        let predicate = #Predicate<LearnedPattern> {
            $0.isActive == true
        }
        let descriptor = FetchDescriptor<LearnedPattern>(predicate: predicate)
        let patterns = try modelContext.fetch(descriptor)

        var staleCount = 0
        for pattern in patterns {
            if let todo = pattern.linkedTodo,
               todo.isCompleted || todo.isTrashed {
                pattern.isActive = false
                staleCount += 1
            }
        }
        if staleCount > 0 {
            try modelContext.save()
        }
        return staleCount
    }
}
