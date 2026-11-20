import Foundation

@main
struct AddressTests {
    static func main() {
        assert(Address.resolve(" example.org/a?x=1 ")?.absoluteString == "https://example.org/a?x=1")
        assert(Address.resolve("http://localhost:8080/")?.host == "localhost")
        assert(Address.resolve("поиск слов")?.host == "www.google.com")
        assert(Address.resolve("поиск слов", engine: .duckDuckGo)?.host == "duckduckgo.com")
        assert(Address.resolve("поиск слов", engine: .bing)?.host == "www.bing.com")
        assert(Address.resolve("поиск слов", search: false) == nil)
        assert(Address.resolve("javascript:alert(1)") == nil)
        assert(Address.resolve("file:///etc/passwd") == nil)
        assert(Address.resolve("https://trusted.example@untrusted.example") == nil)
        assert(Address.resolve("") == nil)
        let docs = Page(title: "Guide", url: URL(string: "https://docs.example.org/guide")!)
        let blog = Page(title: "Documentation", url: URL(string: "https://blog.example.org/")!)
        assert(Address.suggestions(for: "doc", pages: [blog, docs, docs]) == [docs, blog])
        assert(Address.completesHost("doc", with: docs))
        assert(!Address.completesHost("docs.invalid", with: docs))
        assert(!Address.completesHost("Documentation", with: blog))
        assert(Address.suggestions(for: " ", pages: [docs]).isEmpty)
        assert(Address.searchQuery("поиск слов") == "поиск слов")
        assert(Address.searchQuery("example.org/a") == nil)
        assert(Address.searchQuery("mybro://history") == nil)
        assert(Address.searchQuery("  ") == nil)
        assert(Address.suggestions(for: "нщ", pages: Address.suggestedSites).first?.url.host == "youtube.com")
        assert(Address.networkQuery("я") == nil)
        assert(Address.networkQuery("weather tomorrow") == "weather tomorrow")
        assert(Address.networkQuery("https://internal.example/settings") == nil)
        assert(Address.networkQuery("name@example.org") == nil)
        assert(Address.networkQuery("look at https://internal.example/settings") == nil)
        let lookup = SearchSuggestionRequest(engine: .duckDuckGo, query: "новая вкладка")
        assert(lookup.url.host == "duckduckgo.com")
        assert(URLComponents(url: lookup.url, resolvingAgainstBaseURL: false)?.queryItems?.contains(
            URLQueryItem(name: "q", value: "новая вкладка")) == true)
        let response = Data(#"["weather",["Weather","weather radar"," weather radar ","","weather tomorrow"],["metadata"]]"#.utf8)
        assert(SearchSuggestionRequest(engine: .google, query: "weather").parse(response) == ["weather radar", "weather tomorrow"])
        assert(lookup.parse(Data(#"{"bad":true}"#.utf8)).isEmpty)
        print("Address and local completion checks passed")
    }
}
