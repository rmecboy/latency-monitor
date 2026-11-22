import Foundation

struct GeoInfo {
    let success: Bool
    let displayText: String
    let source: String
}

enum GeoLocationFetcher {
    private static let countryNames: [String: String] = [
        "CN": "中国", "HK": "中国香港", "TW": "中国台湾", "MO": "中国澳门",
        "JP": "日本", "SG": "新加坡", "US": "美国", "KR": "韩国",
        "GB": "英国", "UK": "英国", "DE": "德国", "FR": "法国",
        "NL": "荷兰", "CA": "加拿大", "AU": "澳大利亚", "RU": "俄罗斯",
        "IN": "印度", "MY": "马来西亚", "TH": "泰国", "VN": "越南",
        "PH": "菲律宾", "ID": "印度尼西亚", "TR": "土耳其", "BR": "巴西",
        "AR": "阿根廷", "SE": "瑞典", "CH": "瑞士", "IT": "意大利",
        "ES": "西班牙", "PL": "波兰", "FI": "芬兰", "NO": "挪威",
        "IE": "爱尔兰", "AE": "阿联酋", "IL": "以色列", "ZA": "南非",
        "NZ": "新西兰", "MX": "墨西哥", "CL": "智利", "CO": "哥伦比亚",
        "UA": "乌克兰", "AT": "奥地利", "BE": "比利时", "CZ": "捷克",
        "DK": "丹麦", "PT": "葡萄牙", "RO": "罗马尼亚", "HU": "匈牙利",
        "GR": "希腊", "LU": "卢森堡", "IS": "冰岛", "SA": "沙特阿拉伯",
        "QA": "卡塔尔", "KH": "柬埔寨"
    ]

    private static let cityNames: [String: String] = [
        "tokyo": "东京", "osaka": "大阪", "nagoya": "名古屋", "fukuoka": "福冈",
        "singapore": "新加坡", "hong kong": "香港", "taipei": "台北", "kaohsiung": "高雄",
        "taichung": "台中", "seoul": "首尔", "busan": "釜山", "chuncheon": "春川",
        "los angeles": "洛杉矶", "san jose": "圣何塞", "seattle": "西雅图", "new york": "纽约",
        "ashburn": "阿什本", "dallas": "达拉斯", "chicago": "芝加哥", "miami": "迈阿密",
        "san francisco": "旧金山", "santa clara": "圣克拉拉", "phoenix": "菲尼克斯",
        "atlanta": "亚特兰大", "las vegas": "拉斯维加斯", "denver": "丹佛", "boston": "波士顿",
        "houston": "休斯顿", "fremont": "弗里蒙特", "frankfurt": "法兰克福",
        "frankfurt am main": "法兰克福", "munich": "慕尼黑", "berlin": "柏林",
        "london": "伦敦", "amsterdam": "阿姆斯特丹", "paris": "巴黎", "zurich": "苏黎世",
        "stockholm": "斯德哥尔摩", "dublin": "都柏林", "madrid": "马德里", "milan": "米兰",
        "moscow": "莫斯科", "sydney": "悉尼", "melbourne": "墨尔本", "toronto": "多伦多",
        "vancouver": "温哥华", "montreal": "蒙特利尔", "mumbai": "孟买", "bangkok": "曼谷",
        "kuala lumpur": "吉隆坡", "jakarta": "雅加达", "manila": "马尼拉",
        "ho chi minh city": "胡志明市", "hanoi": "河内", "dubai": "迪拜",
        "beijing": "北京", "shanghai": "上海", "shenzhen": "深圳", "guangzhou": "广州",
        "hangzhou": "杭州", "chengdu": "成都"
    ]

    static func fetch(timeoutSec: TimeInterval = 3.5) async -> GeoInfo {
        if let res = await tryIpApi(timeoutSec: timeoutSec), res.success { return res }
        if let res = await tryIpSb(timeoutSec: timeoutSec), res.success { return res }
        if let res = await tryIpWhoIs(timeoutSec: timeoutSec), res.success { return res }
        if let res = await tryIpInfo(timeoutSec: timeoutSec), res.success { return res }
        if let res = await tryCloudflareTrace(timeoutSec: timeoutSec), res.success { return res }
        return GeoInfo(success: false, displayText: "地域未知", source: "")
    }

    private static func httpGet(_ urlStr: String, timeoutSec: TimeInterval) async -> Data? {
        guard let url = URL(string: urlStr) else { return nil }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSec
        cfg.timeoutIntervalForResource = timeoutSec
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSec)
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue(
            "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func parseDict(_ data: Data?) -> [String: Any]? {
        guard let data = data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    private static func str(_ dict: [String: Any], _ key: String) -> String {
        (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func tryIpApi(timeoutSec: TimeInterval) async -> GeoInfo? {
        let data = await httpGet("http://ip-api.com/json/?lang=zh-CN&fields=status,country,countryCode,regionName,city", timeoutSec: timeoutSec)
        guard let dict = parseDict(data), str(dict, "status").lowercased() == "success" else { return nil }
        return buildGeo(code: str(dict, "countryCode"), country: str(dict, "country"), region: str(dict, "regionName"), city: str(dict, "city"), source: "ip-api.com")
    }

    private static func tryIpSb(timeoutSec: TimeInterval) async -> GeoInfo? {
        let data = await httpGet("https://api.ip.sb/geoip", timeoutSec: timeoutSec)
        guard let dict = parseDict(data) else { return nil }
        let code = str(dict, "country_code")
        let country = str(dict, "country")
        guard !code.isEmpty || !country.isEmpty else { return nil }
        return buildGeo(code: code, country: country, region: str(dict, "region"), city: str(dict, "city"), source: "api.ip.sb")
    }

    private static func tryIpWhoIs(timeoutSec: TimeInterval) async -> GeoInfo? {
        let data = await httpGet("https://ipwho.is/", timeoutSec: timeoutSec)
        guard let dict = parseDict(data) else { return nil }
        if let ok = dict["success"] as? Bool, !ok { return nil }
        let code = str(dict, "country_code")
        let country = str(dict, "country")
        guard !code.isEmpty || !country.isEmpty else { return nil }
        return buildGeo(code: code, country: country, region: str(dict, "region"), city: str(dict, "city"), source: "ipwho.is")
    }

    private static func tryIpInfo(timeoutSec: TimeInterval) async -> GeoInfo? {
        let data = await httpGet("https://ipinfo.io/json", timeoutSec: timeoutSec)
        guard let dict = parseDict(data) else { return nil }
        let code = str(dict, "country")
        guard !code.isEmpty else { return nil }
        return buildGeo(code: code, country: "", region: str(dict, "region"), city: str(dict, "city"), source: "ipinfo.io")
    }

    private static func tryCloudflareTrace(timeoutSec: TimeInterval) async -> GeoInfo? {
        guard let data = await httpGet("https://www.cloudflare.com/cdn-cgi/trace", timeoutSec: timeoutSec),
              let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("loc=") {
                let loc = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !loc.isEmpty {
                    return buildGeo(code: loc, country: "", region: "", city: "", source: "Cloudflare")
                }
            }
        }
        return nil
    }

    private static func buildGeo(code rawCode: String, country rawCountry: String, region rawRegion: String, city rawCity: String, source: String) -> GeoInfo? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let country = countryNames[code] ?? rawCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = translatePlace(rawRegion)
        let city = translatePlace(rawCity)

        let display = formatDisplay(code: code, country: country, region: region, city: city)
        guard !display.isEmpty else { return nil }
        return GeoInfo(success: true, displayText: display, source: source)
    }

    private static func translatePlace(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        return cityNames[s.lowercased()] ?? s
    }

    private static func cleanCnSuffix(_ s: String) -> String {
        if (s.hasSuffix("省") || s.hasSuffix("市")) && s.count > 2 {
            return String(s.dropLast())
        }
        return s
    }

    private static func formatDisplay(code: String, country: String, region: String, city: String) -> String {
        if country.isEmpty { return !city.isEmpty ? city : region }
        if code == "HK" || code == "MO" || code == "SG" { return country }
        if code == "TW" {
            if !city.isEmpty && !isSame(city, "台湾") && !isSame(city, "中国台湾") {
                return "\(country)·\(cleanCnSuffix(city))"
            }
            return country
        }
        if code == "CN" {
            let r = cleanCnSuffix(region)
            let c = cleanCnSuffix(city)
            if !r.isEmpty && !c.isEmpty {
                return isSame(r, c) ? c : "\(r)·\(c)"
            }
            if !c.isEmpty { return c }
            if !r.isEmpty { return r }
            return country
        }
        let sub = !city.isEmpty ? city : region
        if !sub.isEmpty && !isSame(country, sub) {
            return "\(country)·\(sub)"
        }
        return country
    }

    private static func isSame(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty && !b.isEmpty else { return false }
        let la = a.lowercased()
        let lb = b.lowercased()
        return la == lb || la.contains(lb) || lb.contains(la)
    }
}
