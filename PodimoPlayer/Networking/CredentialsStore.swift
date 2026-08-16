import Foundation
import Observation

@Observable
final class CredentialsStore: @unchecked Sendable {
    static let shared = CredentialsStore()

    private let cookieKey = "podimo_cookie"
    private let authKey = "podimo_auth"

    var cookie: String {
        didSet { UserDefaults.standard.set(cookie, forKey: cookieKey) }
    }

    var authToken: String {
        didSet { UserDefaults.standard.set(authToken, forKey: authKey) }
    }

    var hasCredentials: Bool {
        !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Preset defaults so the app works out of the box. These will expire and can be
    // replaced by the user in Settings at any time.
    private static let defaultCookie = "pmo_fp=2f2372705b2f0f85290f741d55950c8c; pmo_auth=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3ODY4OTM4NzgsImFkbWluIjpmYWxzZSwic3lzdGVtIjpmYWxzZSwiY3JlYXRvciI6ZmFsc2UsImlkIjoiZjVjOWI0NmEtNmU4Ny00MGNmLTkyNDItYjNlZjYxYjdlMjZkIiwiZGF0ZXRpbWUiOiIyMDI1LTA1LTIwVDE2OjA2OjQ4Ljc3NloiLCJlbWFpbCI6ImRpZGllci5yZW56bytwb2RpbmwyQGdtYWlsLmNvbSIsInJlZ2lvbiI6Im5sIiwic2VnbWVudCI6IjEiLCJsb2NhbGUiOiJlbiIsImN1cnJlbnRSZWdpb24iOiJubCIsImN1cnJlbnRSZWdpb25FbnRlcmVkRGF0ZXRpbWUiOiIyMDI2LTA4LTE2VDE1OjI0OjM4Ljg2ODY0NTg5OFoifQ.yaeX3ThiHIE9fpOcQMSUTI9OmIX8rdorjeVK1oZvTQM; pmo_al_t=553dbdaa-a8e6-4b4e-b34e-bb6e9b128972; pmo_uid=f5c9b46a-6e87-40cf-9242-b3ef61b7e26d; mp_08489be00b70440cae91e69adb879e28_mixpanel=%7B%22distinct_id%22%3A%22%24device%3A194a905b9e6395-093d8a2c717702-f515724-1fa400-194a905b9e6395%22%2C%22%24device_id%22%3A%222f2372705b2f0f85290f741d55950c8c%22%2C%22%24search_engine%22%3A%22google%22%2C%22%24initial_referrer%22%3A%22https%3A%2F%2Fwww.google.com%2F%22%2C%22%24initial_referring_domain%22%3A%22www.google.com%22%2C%22__mps%22%3A%7B%7D%2C%22__mpso%22%3A%7B%22%24initial_referrer%22%3A%22https%3A%2F%2Fwww.google.com%2F%22%2C%22%24initial_referring_domain%22%3A%22www.google.com%22%7D%2C%22__mpus%22%3A%7B%7D%2C%22__mpa%22%3A%7B%7D%2C%22__mpu%22%3A%7B%7D%2C%22__mpr%22%3A%5B%5D%2C%22__mpap%22%3A%5B%5D%7D; pmo_lang=nl; __cf_bm=ebAD8F4ZZtXQpdMuhp8lNAQvHOkho7xJzb18AvviS1Q-1786893870.4870362-1.0.1.1-.ldWi0eAfQSk13IyXCmHXiAxZeO_g5AiqEV7XQmdQlNbsMSV4uKXqhe3aA114LJ2TM9XRF1eQmUK7RlLTWDJmbuQL0ROzeTYs5M6qP1bV1kSNBl14VmpcTPZeCUy9pBI; pmo_session_id=1a7f57f6-6890-4bf6-b0cb-05e1ade0be5c"
    private static let defaultAuth = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3ODY4OTM4NzgsImFkbWluIjpmYWxzZSwic3lzdGVtIjpmYWxzZSwiY3JlYXRvciI6ZmFsc2UsImlkIjoiZjVjOWI0NmEtNmU4Ny00MGNmLTkyNDItYjNlZjYxYjdlMjZkIiwiZGF0ZXRpbWUiOiIyMDI1LTA1LTIwVDE2OjA2OjQ4Ljc3NloiLCJlbWFpbCI6ImRpZGllci5yZW56bytwb2RpbmwyQGdtYWlsLmNvbSIsInJlZ2lvbiI6Im5sIiwic2VnbWVudCI6IjEiLCJsb2NhbGUiOiJlbiIsImN1cnJlbnRSZWdpb24iOiJubCIsImN1cnJlbnRSZWdpb25FbnRlcmVkRGF0ZXRpbWUiOiIyMDI2LTA4LTE2VDE1OjI0OjM4Ljg2ODY0NTg5OFoifQ.yaeX3ThiHIE9fpOcQMSUTI9OmIX8rdorjeVK1oZvTQM"

    private init() {
        cookie = UserDefaults.standard.string(forKey: cookieKey) ?? Self.defaultCookie
        authToken = UserDefaults.standard.string(forKey: authKey) ?? Self.defaultAuth
    }

    func clear() {
        cookie = ""
        authToken = ""
    }
}
