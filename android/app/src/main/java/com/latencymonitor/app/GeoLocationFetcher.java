package com.latencymonitor.app;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

public class GeoLocationFetcher {

    public static class GeoInfo {
        public final boolean success;
        public final String displayText;
        public final String source;

        public GeoInfo(boolean success, String displayText, String source) {
            this.success = success;
            this.displayText = displayText;
            this.source = source;
        }
    }

    private static final Map<String, String> COUNTRY_NAMES = new HashMap<>();
    private static final Map<String, String> CITY_NAMES = new HashMap<>();

    static {
        COUNTRY_NAMES.put("CN", "中国");
        COUNTRY_NAMES.put("HK", "中国香港");
        COUNTRY_NAMES.put("TW", "中国台湾");
        COUNTRY_NAMES.put("MO", "中国澳门");
        COUNTRY_NAMES.put("JP", "日本");
        COUNTRY_NAMES.put("SG", "新加坡");
        COUNTRY_NAMES.put("US", "美国");
        COUNTRY_NAMES.put("KR", "韩国");
        COUNTRY_NAMES.put("GB", "英国");
        COUNTRY_NAMES.put("UK", "英国");
        COUNTRY_NAMES.put("DE", "德国");
        COUNTRY_NAMES.put("FR", "法国");
        COUNTRY_NAMES.put("NL", "荷兰");
        COUNTRY_NAMES.put("CA", "加拿大");
        COUNTRY_NAMES.put("AU", "澳大利亚");
        COUNTRY_NAMES.put("RU", "俄罗斯");
        COUNTRY_NAMES.put("IN", "印度");
        COUNTRY_NAMES.put("MY", "马来西亚");
        COUNTRY_NAMES.put("TH", "泰国");
        COUNTRY_NAMES.put("VN", "越南");
        COUNTRY_NAMES.put("PH", "菲律宾");
        COUNTRY_NAMES.put("ID", "印度尼西亚");
        COUNTRY_NAMES.put("TR", "土耳其");
        COUNTRY_NAMES.put("BR", "巴西");
        COUNTRY_NAMES.put("AR", "阿根廷");
        COUNTRY_NAMES.put("SE", "瑞典");
        COUNTRY_NAMES.put("CH", "瑞士");
        COUNTRY_NAMES.put("IT", "意大利");
        COUNTRY_NAMES.put("ES", "西班牙");
        COUNTRY_NAMES.put("PL", "波兰");
        COUNTRY_NAMES.put("FI", "芬兰");
        COUNTRY_NAMES.put("NO", "挪威");
        COUNTRY_NAMES.put("IE", "爱尔兰");
        COUNTRY_NAMES.put("AE", "阿联酋");
        COUNTRY_NAMES.put("IL", "以色列");
        COUNTRY_NAMES.put("ZA", "南非");
        COUNTRY_NAMES.put("NZ", "新西兰");
        COUNTRY_NAMES.put("MX", "墨西哥");
        COUNTRY_NAMES.put("CL", "智利");
        COUNTRY_NAMES.put("CO", "哥伦比亚");
        COUNTRY_NAMES.put("UA", "乌克兰");
        COUNTRY_NAMES.put("AT", "奥地利");
        COUNTRY_NAMES.put("BE", "比利时");
        COUNTRY_NAMES.put("CZ", "捷克");
        COUNTRY_NAMES.put("DK", "丹麦");
        COUNTRY_NAMES.put("PT", "葡萄牙");
        COUNTRY_NAMES.put("RO", "罗马尼亚");
        COUNTRY_NAMES.put("HU", "匈牙利");
        COUNTRY_NAMES.put("GR", "希腊");
        COUNTRY_NAMES.put("LU", "卢森堡");
        COUNTRY_NAMES.put("IS", "冰岛");
        COUNTRY_NAMES.put("SA", "沙特阿拉伯");
        COUNTRY_NAMES.put("QA", "卡塔尔");
        COUNTRY_NAMES.put("KH", "柬埔寨");

        CITY_NAMES.put("tokyo", "东京");
        CITY_NAMES.put("osaka", "大阪");
        CITY_NAMES.put("nagoya", "名古屋");
        CITY_NAMES.put("fukuoka", "福冈");
        CITY_NAMES.put("singapore", "新加坡");
        CITY_NAMES.put("hong kong", "香港");
        CITY_NAMES.put("taipei", "台北");
        CITY_NAMES.put("kaohsiung", "高雄");
        CITY_NAMES.put("taichung", "台中");
        CITY_NAMES.put("seoul", "首尔");
        CITY_NAMES.put("busan", "釜山");
        CITY_NAMES.put("chuncheon", "春川");
        CITY_NAMES.put("los angeles", "洛杉矶");
        CITY_NAMES.put("san jose", "圣何塞");
        CITY_NAMES.put("seattle", "西雅图");
        CITY_NAMES.put("new york", "纽约");
        CITY_NAMES.put("ashburn", "阿什本");
        CITY_NAMES.put("dallas", "达拉斯");
        CITY_NAMES.put("chicago", "芝加哥");
        CITY_NAMES.put("miami", "迈阿密");
        CITY_NAMES.put("san francisco", "旧金山");
        CITY_NAMES.put("santa clara", "圣克拉拉");
        CITY_NAMES.put("phoenix", "菲尼克斯");
        CITY_NAMES.put("atlanta", "亚特兰大");
        CITY_NAMES.put("las vegas", "拉斯维加斯");
        CITY_NAMES.put("denver", "丹佛");
        CITY_NAMES.put("boston", "波士顿");
        CITY_NAMES.put("houston", "休斯顿");
        CITY_NAMES.put("fremont", "弗里蒙特");
        CITY_NAMES.put("frankfurt", "法兰克福");
        CITY_NAMES.put("frankfurt am main", "法兰克福");
        CITY_NAMES.put("munich", "慕尼黑");
        CITY_NAMES.put("berlin", "柏林");
        CITY_NAMES.put("london", "伦敦");
        CITY_NAMES.put("amsterdam", "阿姆斯特丹");
        CITY_NAMES.put("paris", "巴黎");
        CITY_NAMES.put("zurich", "苏黎世");
        CITY_NAMES.put("stockholm", "斯德哥尔摩");
        CITY_NAMES.put("dublin", "都柏林");
        CITY_NAMES.put("madrid", "马德里");
        CITY_NAMES.put("milan", "米兰");
        CITY_NAMES.put("moscow", "莫斯科");
        CITY_NAMES.put("sydney", "悉尼");
        CITY_NAMES.put("melbourne", "墨尔本");
        CITY_NAMES.put("toronto", "多伦多");
        CITY_NAMES.put("vancouver", "温哥华");
        CITY_NAMES.put("montreal", "蒙特利尔");
        CITY_NAMES.put("mumbai", "孟买");
        CITY_NAMES.put("bangkok", "曼谷");
        CITY_NAMES.put("kuala lumpur", "吉隆坡");
        CITY_NAMES.put("jakarta", "雅加达");
        CITY_NAMES.put("manila", "马尼拉");
        CITY_NAMES.put("ho chi minh city", "胡志明市");
        CITY_NAMES.put("hanoi", "河内");
        CITY_NAMES.put("dubai", "迪拜");
        CITY_NAMES.put("beijing", "北京");
        CITY_NAMES.put("shanghai", "上海");
        CITY_NAMES.put("shenzhen", "深圳");
        CITY_NAMES.put("guangzhou", "广州");
        CITY_NAMES.put("hangzhou", "杭州");
        CITY_NAMES.put("chengdu", "成都");
    }

    public static GeoInfo fetch(int timeoutMs) {
        int t = Math.max(2500, Math.min(timeoutMs, 4500));

        GeoInfo info = tryIpApi(t);
        if (info != null && info.success) return info;

        info = tryIpSb(t);
        if (info != null && info.success) return info;

        info = tryIpWhoIs(t);
        if (info != null && info.success) return info;

        info = tryIpInfo(t);
        if (info != null && info.success) return info;

        info = tryCloudflareTrace(t);
        if (info != null && info.success) return info;

        return new GeoInfo(false, "地域获取失败", "");
    }

    private static String httpGet(String urlStr, int timeoutMs) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlStr);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setInstanceFollowRedirects(true);
            conn.setUseCaches(false);
            conn.setRequestProperty("Connection", "close");
            conn.setRequestProperty("User-Agent",
                    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36");

            int code = conn.getResponseCode();
            if (code < 200 || code >= 300) return null;

            InputStream is = conn.getInputStream();
            if (is == null) return null;
            try (BufferedReader br = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = br.readLine()) != null) {
                    sb.append(line).append('\n');
                }
                return sb.toString();
            }
        } catch (Exception e) {
            return null;
        } finally {
            if (conn != null) {
                try {
                    conn.disconnect();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private static GeoInfo tryIpApi(int timeoutMs) {
        String body = httpGet("http://ip-api.com/json/?lang=zh-CN&fields=status,country,countryCode,regionName,city", timeoutMs);
        if (body == null) return null;
        try {
            JSONObject obj = new JSONObject(body);
            if (!"success".equalsIgnoreCase(obj.optString("status"))) return null;
            return buildGeo(
                    obj.optString("countryCode"),
                    obj.optString("country"),
                    obj.optString("regionName"),
                    obj.optString("city"),
                    "ip-api.com"
            );
        } catch (Exception e) {
            return null;
        }
    }

    private static GeoInfo tryIpSb(int timeoutMs) {
        String body = httpGet("https://api.ip.sb/geoip", timeoutMs);
        if (body == null) return null;
        try {
            JSONObject obj = new JSONObject(body);
            String code = obj.optString("country_code");
            String country = obj.optString("country");
            if (code.isEmpty() && country.isEmpty()) return null;
            return buildGeo(code, country, obj.optString("region"), obj.optString("city"), "api.ip.sb");
        } catch (Exception e) {
            return null;
        }
    }

    private static GeoInfo tryIpWhoIs(int timeoutMs) {
        String body = httpGet("https://ipwho.is/", timeoutMs);
        if (body == null) return null;
        try {
            JSONObject obj = new JSONObject(body);
            if (!obj.optBoolean("success", true)) return null;
            String code = obj.optString("country_code");
            String country = obj.optString("country");
            if (code.isEmpty() && country.isEmpty()) return null;
            return buildGeo(code, country, obj.optString("region"), obj.optString("city"), "ipwho.is");
        } catch (Exception e) {
            return null;
        }
    }

    private static GeoInfo tryIpInfo(int timeoutMs) {
        String body = httpGet("https://ipinfo.io/json", timeoutMs);
        if (body == null) return null;
        try {
            JSONObject obj = new JSONObject(body);
            String code = obj.optString("country");
            if (code.isEmpty()) return null;
            return buildGeo(code, "", obj.optString("region"), obj.optString("city"), "ipinfo.io");
        } catch (Exception e) {
            return null;
        }
    }

    private static GeoInfo tryCloudflareTrace(int timeoutMs) {
        String body = httpGet("https://www.cloudflare.com/cdn-cgi/trace", timeoutMs);
        if (body == null) return null;
        String[] lines = body.split("\\r?\\n");
        for (String line : lines) {
            if (line.startsWith("loc=")) {
                String loc = line.substring(4).trim();
                if (!loc.isEmpty()) {
                    return buildGeo(loc, "", "", "", "Cloudflare");
                }
            }
        }
        return null;
    }

    private static GeoInfo buildGeo(String rawCode, String rawCountry, String rawRegion, String rawCity, String source) {
        String code = rawCode == null ? "" : rawCode.trim().toUpperCase(Locale.US);
        String country = translateCountry(code, rawCountry);
        String region = translatePlace(rawRegion);
        String city = translatePlace(rawCity);

        String display = formatDisplay(code, country, region, city);
        if (display == null || display.trim().isEmpty()) {
            return null;
        }
        return new GeoInfo(true, display, source);
    }

    private static String translateCountry(String code, String rawCountry) {
        String cn = COUNTRY_NAMES.get(code);
        if (cn != null) return cn;
        return rawCountry == null ? "" : rawCountry.trim();
    }

    private static String translatePlace(String raw) {
        if (raw == null) return "";
        String s = raw.trim();
        if (s.isEmpty()) return "";
        String cn = CITY_NAMES.get(s.toLowerCase(Locale.US));
        return cn != null ? cn : s;
    }

    private static String cleanCnSuffix(String s) {
        if (s == null || s.isEmpty()) return "";
        if ((s.endsWith("省") || s.endsWith("市")) && s.length() > 2) {
            return s.substring(0, s.length() - 1);
        }
        return s;
    }

    private static String formatDisplay(String code, String country, String region, String city) {
        if (country.isEmpty()) {
            return !city.isEmpty() ? city : region;
        }
        if ("HK".equals(code) || "MO".equals(code) || "SG".equals(code)) {
            return country;
        }
        if ("TW".equals(code)) {
            if (!city.isEmpty() && !isSame(city, "台湾") && !isSame(city, "中国台湾")) {
                return country + "·" + cleanCnSuffix(city);
            }
            return country;
        }
        if ("CN".equals(code)) {
            String r = cleanCnSuffix(region);
            String c = cleanCnSuffix(city);
            if (!r.isEmpty() && !c.isEmpty()) {
                return isSame(r, c) ? c : (r + "·" + c);
            }
            if (!c.isEmpty()) return c;
            if (!r.isEmpty()) return r;
            return country;
        }
        String sub = !city.isEmpty() ? city : region;
        if (!sub.isEmpty() && !isSame(country, sub)) {
            return country + "·" + sub;
        }
        return country;
    }

    private static boolean isSame(String a, String b) {
        if (a == null || b == null || a.isEmpty() || b.isEmpty()) return false;
        String la = a.toLowerCase(Locale.US);
        String lb = b.toLowerCase(Locale.US);
        return la.equals(lb) || la.contains(lb) || lb.contains(la);
    }
}
