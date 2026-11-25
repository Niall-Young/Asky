import Testing
import Foundation
@preconcurrency import Contacts
@testable import Adapters

@Suite struct ContactsSearchTests {
    private func record(
        id: String,
        name: String,
        nickname: String = "",
        primaryExtras: [String] = [],
        organization: String = "",
        phonetics: [String] = [],
        phones: [String] = [],
        emails: [String] = []
    ) -> ContactsBridge.SearchRecord {
        let person = ContactsBridge.Person(
            id: id,
            name: name,
            nickname: nickname,
            phones: phones,
            emails: emails,
            organization: organization
        )
        let primary = ([name, nickname] + primaryExtras).filter { !$0.isEmpty }
        let secondary = ([organization] + phonetics).filter { !$0.isEmpty }
        return ContactsBridge.SearchRecord(person: person, primaryNames: primary, secondaryNames: secondary)
    }

    @Test func substringMatchesChineseContactsMissedByPrefixSearch() {
        let records = [
            record(id: "mom", name: "老妈 Mum", phones: ["13900001111"]),
            record(id: "dad", name: "老爸 Dad", phones: ["13800002222"]),
            record(id: "zhang", name: "张小明", phones: ["13700003333"]),
        ]

        let dadHits = ContactsBridge.match(query: "爸", in: records, limit: 10)
        #expect(dadHits.map(\.id) == ["dad"])

        let momHits = ContactsBridge.match(query: "妈", in: records, limit: 10)
        #expect(momHits.map(\.id) == ["mom"])

        let givenHits = ContactsBridge.match(query: "小明", in: records, limit: 10)
        #expect(givenHits.map(\.id) == ["zhang"])
    }

    @Test func ranksExactBeforePrefixBeforeSubstringAndNickname() {
        let records = [
            record(id: "sub", name: "张老爸"),
            record(id: "prefix", name: "老爸 Dad"),
            record(id: "exact", name: "老爸"),
            record(id: "nick", name: "张建国", nickname: "老爸"),
        ]

        let hits = ContactsBridge.match(query: "老爸", in: records, limit: 10)
        #expect(hits.map(\.id) == ["exact", "nick", "prefix", "sub"])
    }

    @Test func matchesCompactedSpacesCaseDiacriticsWidthAndMultiTokens() {
        let records = [
            record(id: "spaced", name: "张 三", primaryExtras: ["张三"]),
            record(id: "dad", name: "老爸 Dad", organization: "杭州家居"),
            record(id: "accent", name: "René Martin"),
        ]

        #expect(ContactsBridge.match(query: "张三", in: records, limit: 10).map(\.id) == ["spaced"])
        #expect(ContactsBridge.match(query: "dad", in: records, limit: 10).map(\.id) == ["dad"])
        #expect(ContactsBridge.match(query: "老爸 杭州", in: records, limit: 10).map(\.id) == ["dad"])
        #expect(ContactsBridge.match(query: "ｒｅｎｅ", in: records, limit: 10).map(\.id) == ["accent"])
    }

    @Test func matchesOrganizationPhoneticPhoneEmailAndPredicateUnion() {
        let records = [
            record(id: "org", name: "王五", organization: "天谷信息"),
            record(id: "phonetic", name: "李四", phonetics: ["lisi"]),
            record(id: "handle", name: "Alice", phones: ["+86 138-1234-5678"], emails: ["alice@example.com"]),
            record(id: "predicate", name: "Special Contact"),
        ]

        #expect(ContactsBridge.match(query: "天谷", in: records, limit: 10).map(\.id) == ["org"])
        #expect(ContactsBridge.match(query: "lisi", in: records, limit: 10).map(\.id) == ["phonetic"])
        #expect(ContactsBridge.match(query: "12345678", in: records, limit: 10).map(\.id) == ["handle"])
        #expect(ContactsBridge.match(query: "alice@example", in: records, limit: 10).map(\.id) == ["handle"])
        #expect(ContactsBridge.match(query: "unmatched", in: records, predicateMatchedIDs: ["predicate"], limit: 10).map(\.id) == ["predicate"])
        #expect(ContactsBridge.match(query: "   ", in: records, limit: 10).isEmpty)
        #expect(ContactsBridge.match(query: "王", in: records, limit: 0).isEmpty)
    }

    @Test func searchRecordExtractsNicknameAndFallbacksFromCNContact() {
        let bridge = ContactsBridge()
        let nicknameOnly = CNMutableContact()
        nicknameOnly.nickname = "老爸"
        nicknameOnly.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "13800138000"))]

        let built = bridge.searchRecord(nicknameOnly)
        #expect(built.person.name == "老爸")
        #expect(built.person.nickname == "老爸")
        #expect(ContactsBridge.match(query: "爸", in: [built], limit: 5).map(\.name) == ["老爸"])
    }
}
