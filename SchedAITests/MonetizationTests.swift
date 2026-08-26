import Foundation
import Testing
@testable import SchedAI

@Suite("SchedAI monetization")
struct MonetizationTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Free hosted AI allowance counts down and stops at zero")
    func hostedAIAllowanceCountsDown() {
        let date = Date(timeIntervalSince1970: 1_777_075_200)
        var usage = HostedAIUsage()

        #expect(usage.remaining(limit: 3, on: date, calendar: utcCalendar) == 3)
        usage.recordUse(on: date, calendar: utcCalendar)
        usage.recordUse(on: date, calendar: utcCalendar)
        #expect(usage.remaining(limit: 3, on: date, calendar: utcCalendar) == 1)
        usage.recordUse(on: date, calendar: utcCalendar)
        usage.recordUse(on: date, calendar: utcCalendar)
        #expect(usage.remaining(limit: 3, on: date, calendar: utcCalendar) == 0)
    }

    @Test("Free hosted AI allowance resets on a new day")
    func hostedAIAllowanceResets() {
        let dayOne = Date(timeIntervalSince1970: 1_777_075_200)
        let dayTwo = dayOne.addingTimeInterval(86_400)
        var usage = HostedAIUsage()

        usage.recordUse(on: dayOne, calendar: utcCalendar)
        usage.recordUse(on: dayOne, calendar: utcCalendar)

        #expect(usage.remaining(limit: 3, on: dayOne, calendar: utcCalendar) == 1)
        #expect(usage.remaining(limit: 3, on: dayTwo, calendar: utcCalendar) == 3)

        usage.recordUse(on: dayTwo, calendar: utcCalendar)
        #expect(usage.remaining(limit: 3, on: dayTwo, calendar: utcCalendar) == 2)
    }

    @Test("Only SchedAI Pro product identifiers grant Pro")
    func proProductIdentifiers() {
        #expect(SchedAIProduct.isPro("me.SchedAI.pro.monthly"))
        #expect(SchedAIProduct.isPro("me.SchedAI.pro.annual"))
        #expect(!SchedAIProduct.isPro("me.SchedAI.pro.fake"))
    }
}
