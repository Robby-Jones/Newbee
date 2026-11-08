import Foundation
import NewbeeKit
import SwiftData
import Testing
@testable import Newbee

@MainActor
@Suite("Onboarding")
struct OnboardingTests {
    @Test func emptyDraftCreatesNoBaby() throws {
        let context = try makeInMemoryContainer().mainContext
        try OnboardingProfile.save(.init(name: "   "), in: context)
        #expect(try context.fetchCount(FetchDescriptor<Baby>()) == 0)
        #expect(!OnboardingProfile.hasExistingData(in: context))
    }

    @Test func savesTrimmedNameAndBirthDate() throws {
        let context = try makeInMemoryContainer().mainContext
        let born = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        try OnboardingProfile.save(.init(name: "  Ava ", hasBirthDate: true, birthDate: born), in: context)
        let babies = try context.fetch(FetchDescriptor<Baby>())
        #expect(babies.count == 1)
        #expect(babies.first?.name == "Ava")
        #expect(babies.first?.birthDate == born)
    }

    @Test func updatesExistingBabyWithoutClearingIt() throws {
        let context = try makeInMemoryContainer().mainContext
        let born = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(Baby(name: "Ava", birthDate: born))
        try context.save()
        // Only a name entered: the birth date already saved stays.
        try OnboardingProfile.save(.init(name: "Avery"), in: context)
        let babies = try context.fetch(FetchDescriptor<Baby>())
        #expect(babies.count == 1)
        #expect(babies.first?.name == "Avery")
        #expect(babies.first?.birthDate == born)
    }

    @Test func existingFeedsSkipOnboarding() throws {
        let context = try makeInMemoryContainer().mainContext
        #expect(!OnboardingProfile.hasExistingData(in: context))
        context.insert(FeedingSession(kind: .bottle, status: .completed, startedAt: .now, source: .manual))
        try context.save()
        #expect(OnboardingProfile.hasExistingData(in: context))
    }

    @Test func completionPersistsAndSurvivesDeleteAllData() {
        let defaults = UserDefaults(suiteName: "NewbeeTests.\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        #expect(!preferences.onboardingComplete)
        preferences.onboardingComplete = true
        #expect(AppPreferences(defaults: defaults).onboardingComplete)
        preferences.resetToDefaults()
        #expect(AppPreferences(defaults: defaults).onboardingComplete)
    }
}
