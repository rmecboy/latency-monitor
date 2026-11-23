using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfColor = System.Windows.Media.Color;
using WpfFontFamily = System.Windows.Media.FontFamily;
using WpfPoint = System.Windows.Point;
using WpfPath = System.Windows.Shapes.Path;
using WpfRectangle = System.Windows.Shapes.Rectangle;

[assembly: System.Reflection.AssemblyTitle("LatencyMonitor")]
[assembly: System.Reflection.AssemblyDescription("网络延迟与地域悬浮窗 (Google / Cloudflare / Oracle)")]
[assembly: System.Reflection.AssemblyProduct("LatencyMonitor")]
[assembly: System.Reflection.AssemblyVersion("1.1.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.1.0.0")]

namespace LatencyMonitor
{
    public class TargetConfig
    {
        public string Name { get; set; }
        public string Url { get; set; }
        public string Host { get; set; }
        public int Port { get; set; }
        public string Method { get; set; }

        public TargetConfig()
        {
            Name = "";
            Url = "";
            Host = "";
            Port = 443;
            Method = "GET";
        }
    }

    public class AppConfig
    {
        public string Mode { get; set; }
        public int IntervalMs { get; set; }
        public int TimeoutMs { get; set; }
        public double Opacity { get; set; }
        public bool Topmost { get; set; }
        public bool CompactHorizontal { get; set; }
        public bool ShowGeoLocation { get; set; }
        public int GeoIntervalMs { get; set; }
        public int GreenMaxMs { get; set; }
        public int YellowMaxMs { get; set; }
        public double WindowLeft { get; set; }
        public double WindowTop { get; set; }
        public List<TargetConfig> Targets { get; set; }

        public AppConfig()
        {
            Mode = "HTTPS";
            IntervalMs = 2000;
            TimeoutMs = 3000;
            Opacity = 0.92;
            Topmost = true;
            CompactHorizontal = false;
            ShowGeoLocation = true;
            GeoIntervalMs = 15000;
            GreenMaxMs = 800;
            YellowMaxMs = 1500;
            WindowLeft = -1;
            WindowTop = -1;
            Targets = new List<TargetConfig>();
        }

        public static AppConfig CreateDefault()
        {
            var cfg = new AppConfig();
            cfg.Targets.Add(new TargetConfig
            {
                Name = "Google",
                Url = "https://www.google.com/generate_204",
                Host = "www.google.com",
                Port = 443,
                Method = "GET"
            });
            cfg.Targets.Add(new TargetConfig
            {
                Name = "Cloudflare",
                Url = "https://cp.cloudflare.com/generate_204",
                Host = "1.1.1.1",
                Port = 443,
                Method = "GET"
            });
            cfg.Targets.Add(new TargetConfig
            {
                Name = "Oracle",
                Url = "https://www.oracle.com/favicon.ico",
                Host = "www.oracle.com",
                Port = 443,
                Method = "HEAD"
            });
            return cfg;
        }
    }

    public class ProbeResult
    {
        public bool Success { get; set; }
        public long LatencyMs { get; set; }
        public string Detail { get; set; }
    }

    public class TargetState
    {
        public TargetConfig Config { get; set; }
        public Ellipse StatusDot { get; set; }
        public TextBlock ValueText { get; set; }
        public FrameworkElement RowElement { get; set; }
        public Queue<long> History { get; set; }
        public DateTime LastChecked { get; set; }
        public ProbeResult LastResult { get; set; }

        public TargetState(TargetConfig cfg)
        {
            Config = cfg;
            History = new Queue<long>();
        }

        public void Record(ProbeResult result)
        {
            LastChecked = DateTime.Now;
            LastResult = result;
            if (result.Success)
            {
                History.Enqueue(result.LatencyMs);
                while (History.Count > 20)
                {
                    History.Dequeue();
                }
            }
        }

        public string BuildTooltip(string mode)
        {
            var sb = new StringBuilder();
            string endpoint = mode == "HTTPS"
                ? Config.Url
                : (mode == "TCP"
                    ? string.Format("{0}:{1}", Config.Host, Config.Port > 0 ? Config.Port : 443)
                    : Config.Host);

            sb.AppendFormat("{0} ({1})", Config.Name, mode);
            sb.AppendLine();
            sb.AppendFormat("目标: {0}", endpoint);
            sb.AppendLine();

            if (LastResult != null)
            {
                if (LastResult.Success)
                {
                    sb.AppendFormat("当前: {0} ms ({1})", LastResult.LatencyMs, LastResult.Detail);
                }
                else
                {
                    sb.AppendFormat("状态: 失败 ({0})", LastResult.Detail);
                }
                sb.AppendLine();
                sb.AppendFormat("时间: {0:HH:mm:ss}", LastChecked);
            }
            else
            {
                sb.Append("状态: 等待测速...");
            }

            if (History.Count > 0)
            {
                long min = long.MaxValue;
                long max = long.MinValue;
                long sum = 0;
                foreach (var v in History)
                {
                    if (v < min) min = v;
                    if (v > max) max = v;
                    sum += v;
                }
                long avg = sum / History.Count;
                sb.AppendLine();
                sb.AppendFormat("近 {0} 次: 平均 {1} ms | 最低 {2} ms | 最高 {3} ms", History.Count, avg, min, max);
            }

            return sb.ToString();
        }
    }

    public static class LatencyProber
    {
        static LatencyProber()
        {
            ServicePointManager.DefaultConnectionLimit = 32;
            ServicePointManager.Expect100Continue = false;
            try
            {
                // TLS 1.2 (3072) | TLS 1.3 (12288)
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)12288;
            }
            catch
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            }
        }

        public static async Task<ProbeResult> ProbeAsync(TargetConfig target, string mode, int timeoutMs)
        {
            string normalizedMode = (mode ?? "HTTPS").Trim().ToUpperInvariant();
            if (normalizedMode == "TCP")
            {
                return await ProbeTcpAsync(target, timeoutMs);
            }
            if (normalizedMode == "ICMP")
            {
                return await ProbeIcmpAsync(target, timeoutMs);
            }
            return await ProbeHttpAsync(target, timeoutMs);
        }

        private static async Task<ProbeResult> ProbeHttpAsync(TargetConfig target, int timeoutMs)
        {
            string url = !string.IsNullOrWhiteSpace(target.Url)
                ? target.Url
                : string.Format("https://{0}/", target.Host);

            var sw = Stopwatch.StartNew();
            HttpWebRequest req = null;
            try
            {
                req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = string.IsNullOrWhiteSpace(target.Method) ? "GET" : target.Method.ToUpperInvariant();
                req.Timeout = timeoutMs;
                req.ReadWriteTimeout = timeoutMs;
                req.AllowAutoRedirect = false;
                req.KeepAlive = false;
                req.Proxy = WebRequest.GetSystemWebProxy();
                req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

                var responseTask = req.GetResponseAsync();
                var delayTask = Task.Delay(timeoutMs);
                var finished = await Task.WhenAny(responseTask, delayTask);

                if (finished != responseTask)
                {
                    try { req.Abort(); } catch { }
                    return new ProbeResult { Success = false, LatencyMs = -1, Detail = "请求超时" };
                }

                using (var resp = (HttpWebResponse)await responseTask)
                {
                    sw.Stop();
                    return new ProbeResult
                    {
                        Success = true,
                        LatencyMs = Math.Max(1, sw.ElapsedMilliseconds),
                        Detail = string.Format("HTTP {0}", (int)resp.StatusCode)
                    };
                }
            }
            catch (WebException wex)
            {
                sw.Stop();
                if (wex.Response != null)
                {
                    try
                    {
                        var httpResp = wex.Response as HttpWebResponse;
                        string statusInfo = httpResp != null
                            ? string.Format("HTTP {0}", (int)httpResp.StatusCode)
                            : "HTTP 响应";
                        wex.Response.Close();
                        return new ProbeResult
                        {
                            Success = true,
                            LatencyMs = Math.Max(1, sw.ElapsedMilliseconds),
                            Detail = statusInfo
                        };
                    }
                    catch { }
                }
                return new ProbeResult
                {
                    Success = false,
                    LatencyMs = -1,
                    Detail = wex.Status == WebExceptionStatus.Timeout ? "请求超时" : wex.Status.ToString()
                };
            }
            catch (Exception ex)
            {
                return new ProbeResult
                {
                    Success = false,
                    LatencyMs = -1,
                    Detail = ex.Message
                };
            }
        }

        private static async Task<ProbeResult> ProbeTcpAsync(TargetConfig target, int timeoutMs)
        {
            string host = target.Host;
            int port = target.Port > 0 ? target.Port : 443;
            if (string.IsNullOrWhiteSpace(host) && !string.IsNullOrWhiteSpace(target.Url))
            {
                try
                {
                    var uri = new Uri(target.Url);
                    host = uri.Host;
                    if (uri.Port > 0) port = uri.Port;
                }
                catch { }
            }

            var sw = Stopwatch.StartNew();
            using (var client = new TcpClient())
            {
                try
                {
                    var connectTask = client.ConnectAsync(host, port);
                    var delayTask = Task.Delay(timeoutMs);
                    var finished = await Task.WhenAny(connectTask, delayTask);

                    if (finished != connectTask)
                    {
                        return new ProbeResult { Success = false, LatencyMs = -1, Detail = "连接超时" };
                    }

                    await connectTask;
                    sw.Stop();
                    return new ProbeResult
                    {
                        Success = true,
                        LatencyMs = Math.Max(1, sw.ElapsedMilliseconds),
                        Detail = string.Format("TCP :{0}", port)
                    };
                }
                catch (Exception ex)
                {
                    return new ProbeResult
                    {
                        Success = false,
                        LatencyMs = -1,
                        Detail = ex.Message
                    };
                }
            }
        }

        private static async Task<ProbeResult> ProbeIcmpAsync(TargetConfig target, int timeoutMs)
        {
            string host = target.Host;
            if (string.IsNullOrWhiteSpace(host) && !string.IsNullOrWhiteSpace(target.Url))
            {
                try { host = new Uri(target.Url).Host; } catch { }
            }

            using (var ping = new Ping())
            {
                try
                {
                    var pingTask = ping.SendPingAsync(host, timeoutMs);
                    var delayTask = Task.Delay(timeoutMs + 200);
                    var finished = await Task.WhenAny(pingTask, delayTask);

                    if (finished != pingTask)
                    {
                        return new ProbeResult { Success = false, LatencyMs = -1, Detail = "Ping 超时" };
                    }

                    var reply = await pingTask;
                    if (reply != null && reply.Status == IPStatus.Success)
                    {
                        return new ProbeResult
                        {
                            Success = true,
                            LatencyMs = Math.Max(1, reply.RoundtripTime),
                            Detail = string.Format("ICMP {0}", reply.Address)
                        };
                    }

                    return new ProbeResult
                    {
                        Success = false,
                        LatencyMs = -1,
                        Detail = reply != null ? reply.Status.ToString() : "无响应"
                    };
                }
                catch (Exception ex)
                {
                    return new ProbeResult
                    {
                        Success = false,
                        LatencyMs = -1,
                        Detail = ex.Message
                    };
                }
            }
        }
    }

    public class GeoLocationInfo
    {
        public bool Success { get; set; }
        public string CountryCode { get; set; }
        public string Country { get; set; }
        public string Region { get; set; }
        public string City { get; set; }
        public string Isp { get; set; }
        public string Asn { get; set; }
        public string Source { get; set; }
        public string DisplayText { get; set; }
        public DateTime UpdatedAt { get; set; }

        public GeoLocationInfo()
        {
            CountryCode = "";
            Country = "";
            Region = "";
            City = "";
            Isp = "";
            Asn = "";
            Source = "";
            DisplayText = "获取地域中...";
            UpdatedAt = DateTime.Now;
        }

        public string BuildTooltip()
        {
            var sb = new StringBuilder();
            sb.AppendLine("当前网络地域");
            if (!Success)
            {
                sb.Append("状态: 暂无法获取地域信息");
                return sb.ToString();
            }

            if (!string.IsNullOrWhiteSpace(Country))
            {
                sb.AppendFormat("国家/地区: {0}", Country);
                sb.AppendLine();
            }
            if (!string.IsNullOrWhiteSpace(Region))
            {
                sb.AppendFormat("省份/州: {0}", Region);
                sb.AppendLine();
            }
            if (!string.IsNullOrWhiteSpace(City))
            {
                sb.AppendFormat("城市: {0}", City);
                sb.AppendLine();
            }
            if (!string.IsNullOrWhiteSpace(Isp))
            {
                sb.AppendFormat("运营商: {0}", Isp);
                sb.AppendLine();
            }
            if (!string.IsNullOrWhiteSpace(Asn))
            {
                sb.AppendFormat("ASN: {0}", Asn);
                sb.AppendLine();
            }
            if (!string.IsNullOrWhiteSpace(Source))
            {
                sb.AppendFormat("来源: {0}", Source);
                sb.AppendLine();
            }
            sb.AppendFormat("更新: {0:HH:mm:ss}", UpdatedAt);
            return sb.ToString();
        }
    }

    public static class GeoLocationFetcher
    {
        private static readonly Dictionary<string, string> CountryNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "CN", "中国" }, { "HK", "中国香港" }, { "TW", "中国台湾" }, { "MO", "中国澳门" },
            { "JP", "日本" }, { "SG", "新加坡" }, { "US", "美国" }, { "KR", "韩国" },
            { "GB", "英国" }, { "UK", "英国" }, { "DE", "德国" }, { "FR", "法国" },
            { "NL", "荷兰" }, { "CA", "加拿大" }, { "AU", "澳大利亚" }, { "RU", "俄罗斯" },
            { "IN", "印度" }, { "MY", "马来西亚" }, { "TH", "泰国" }, { "VN", "越南" },
            { "PH", "菲律宾" }, { "ID", "印度尼西亚" }, { "TR", "土耳其" }, { "BR", "巴西" },
            { "AR", "阿根廷" }, { "SE", "瑞典" }, { "CH", "瑞士" }, { "IT", "意大利" },
            { "ES", "西班牙" }, { "PL", "波兰" }, { "FI", "芬兰" }, { "NO", "挪威" },
            { "IE", "爱尔兰" }, { "AE", "阿联酋" }, { "IL", "以色列" }, { "ZA", "南非" },
            { "NZ", "新西兰" }, { "MX", "墨西哥" }, { "CL", "智利" }, { "CO", "哥伦比亚" },
            { "UA", "乌克兰" }, { "AT", "奥地利" }, { "BE", "比利时" }, { "CZ", "捷克" },
            { "DK", "丹麦" }, { "PT", "葡萄牙" }, { "RO", "罗马尼亚" }, { "HU", "匈牙利" },
            { "GR", "希腊" }, { "LU", "卢森堡" }, { "IS", "冰岛" }, { "BG", "保加利亚" },
            { "SK", "斯洛伐克" }, { "HR", "克罗地亚" }, { "RS", "塞尔维亚" }, { "EE", "爱沙尼亚" },
            { "LV", "拉脱维亚" }, { "LT", "立陶宛" }, { "KZ", "哈萨克斯坦" }, { "PK", "巴基斯坦" },
            { "BD", "孟加拉国" }, { "KH", "柬埔寨" }, { "LA", "老挝" }, { "MM", "缅甸" },
            { "MN", "蒙古" }, { "SA", "沙特阿拉伯" }, { "QA", "卡塔尔" }, { "EG", "埃及" },
            { "NG", "尼日利亚" }, { "KE", "肯尼亚" }, { "KP", "朝鲜" }, { "NP", "尼泊尔" }
        };

        private static readonly Dictionary<string, string> CityNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            { "Tokyo", "东京" }, { "Osaka", "大阪" }, { "Nagoya", "名古屋" }, { "Fukuoka", "福冈" }, { "Sapporo", "札幌" },
            { "Singapore", "新加坡" }, { "Hong Kong", "香港" }, { "Central", "中环" }, { "Kowloon", "九龙" },
            { "Taipei", "台北" }, { "Kaohsiung", "高雄" }, { "Taichung", "台中" }, { "New Taipei", "新北" },
            { "Seoul", "首尔" }, { "Busan", "釜山" }, { "Incheon", "仁川" }, { "Chuncheon", "春川" },
            { "Los Angeles", "洛杉矶" }, { "San Jose", "圣何塞" }, { "Seattle", "西雅图" }, { "New York", "纽约" },
            { "Ashburn", "阿什本" }, { "Dallas", "达拉斯" }, { "Chicago", "芝加哥" }, { "Miami", "迈阿密" },
            { "San Francisco", "旧金山" }, { "Santa Clara", "圣克拉拉" }, { "Phoenix", "菲尼克斯" }, { "Atlanta", "亚特兰大" },
            { "Las Vegas", "拉斯维加斯" }, { "Denver", "丹佛" }, { "Boston", "波士顿" }, { "Houston", "休斯顿" },
            { "Washington", "华盛顿" }, { "Fremont", "弗里蒙特" }, { "Palo Alto", "帕洛阿尔托" }, { "Mountain View", "山景城" },
            { "Frankfurt", "法兰克福" }, { "Frankfurt am Main", "法兰克福" }, { "Munich", "慕尼黑" }, { "Berlin", "柏林" },
            { "London", "伦敦" }, { "Manchester", "曼彻斯特" }, { "Amsterdam", "阿姆斯特丹" }, { "Paris", "巴黎" },
            { "Marseille", "马赛" }, { "Zurich", "苏黎世" }, { "Stockholm", "斯德哥尔摩" }, { "Dublin", "都柏林" },
            { "Madrid", "马德里" }, { "Milan", "米兰" }, { "Rome", "罗马" }, { "Warsaw", "华沙" }, { "Helsinki", "赫尔辛基" },
            { "Moscow", "莫斯科" }, { "Saint Petersburg", "圣彼得堡" }, { "Istanbul", "伊斯坦布尔" },
            { "Sydney", "悉尼" }, { "Melbourne", "墨尔本" }, { "Brisbane", "布里斯班" }, { "Perth", "珀斯" }, { "Auckland", "奥克兰" },
            { "Toronto", "多伦多" }, { "Vancouver", "温哥华" }, { "Montreal", "蒙特利尔" },
            { "Mumbai", "孟买" }, { "New Delhi", "新德里" }, { "Bengaluru", "班加罗尔" }, { "Hyderabad", "海得拉巴" },
            { "Bangkok", "曼谷" }, { "Kuala Lumpur", "吉隆坡" }, { "Jakarta", "雅加达" }, { "Manila", "马尼拉" },
            { "Ho Chi Minh City", "胡志明市" }, { "Hanoi", "河内" }, { "Dubai", "迪拜" }, { "Sao Paulo", "圣保罗" },
            { "Beijing", "北京" }, { "Shanghai", "上海" }, { "Shenzhen", "深圳" }, { "Guangzhou", "广州" },
            { "Hangzhou", "杭州" }, { "Chengdu", "成都" }, { "Chongqing", "重庆" }, { "Wuhan", "武汉" },
            { "Nanjing", "南京" }, { "Suzhou", "苏州" }, { "Xi'an", "西安" }, { "Tianjin", "天津" }
        };

        public static async Task<GeoLocationInfo> FetchAsync(int timeoutMs)
        {
            int perCallTimeout = Math.Max(2500, Math.Min(timeoutMs, 4500));

            // 1. ip-api.com (native zh-CN)
            var info = await TryIpApiAsync(perCallTimeout);
            if (info != null && info.Success) return info;

            // 2. api.ip.sb (reliable on proxy exit nodes)
            info = await TryIpSbAsync(perCallTimeout);
            if (info != null && info.Success) return info;

            // 3. ipwho.is (HTTPS, generous limit)
            info = await TryIpWhoIsAsync(perCallTimeout);
            if (info != null && info.Success) return info;

            // 4. ipinfo.io (HTTPS)
            info = await TryIpInfoAsync(perCallTimeout);
            if (info != null && info.Success) return info;

            // 5. Cloudflare trace (never rate-limited fallback)
            info = await TryCloudflareTraceAsync(perCallTimeout);
            if (info != null && info.Success) return info;

            return new GeoLocationInfo
            {
                Success = false,
                DisplayText = "地域获取失败",
                UpdatedAt = DateTime.Now
            };
        }

        private static async Task<string> HttpGetStringAsync(string url, int timeoutMs)
        {
            HttpWebRequest req = null;
            try
            {
                req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "GET";
                req.Timeout = timeoutMs;
                req.ReadWriteTimeout = timeoutMs;
                req.AllowAutoRedirect = true;
                req.KeepAlive = false;
                req.Proxy = WebRequest.GetSystemWebProxy();
                req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

                var respTask = req.GetResponseAsync();
                var finished = await Task.WhenAny(respTask, Task.Delay(timeoutMs));
                if (finished != respTask)
                {
                    try { req.Abort(); } catch { }
                    return null;
                }

                using (var resp = (HttpWebResponse)await respTask)
                {
                    if ((int)resp.StatusCode < 200 || (int)resp.StatusCode >= 300)
                    {
                        return null;
                    }
                    using (var stream = resp.GetResponseStream())
                    {
                        if (stream == null) return null;
                        using (var reader = new StreamReader(stream, Encoding.UTF8))
                        {
                            var readTask = reader.ReadToEndAsync();
                            var readFinished = await Task.WhenAny(readTask, Task.Delay(timeoutMs));
                            if (readFinished != readTask)
                            {
                                try { req.Abort(); } catch { }
                                return null;
                            }
                            return await readTask;
                        }
                    }
                }
            }
            catch
            {
                return null;
            }
        }

        private static Dictionary<string, object> ParseJsonDict(string json)
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            try
            {
                var serializer = new JavaScriptSerializer();
                return serializer.Deserialize<Dictionary<string, object>>(json);
            }
            catch
            {
                return null;
            }
        }

        private static string GetStr(Dictionary<string, object> dict, string key)
        {
            if (dict == null) return "";
            object val;
            if (dict.TryGetValue(key, out val) && val != null)
            {
                return val.ToString().Trim();
            }
            return "";
        }

        private static async Task<GeoLocationInfo> TryIpApiAsync(int timeoutMs)
        {
            string body = await HttpGetStringAsync("http://ip-api.com/json/?lang=zh-CN&fields=status,country,countryCode,regionName,city,isp,as", timeoutMs);
            var dict = ParseJsonDict(body);
            if (dict == null) return null;
            if (!string.Equals(GetStr(dict, "status"), "success", StringComparison.OrdinalIgnoreCase)) return null;

            return BuildGeoInfo(
                GetStr(dict, "countryCode"),
                GetStr(dict, "country"),
                GetStr(dict, "regionName"),
                GetStr(dict, "city"),
                GetStr(dict, "isp"),
                NormalizeAsn(GetStr(dict, "as")),
                "ip-api.com"
            );
        }

        private static async Task<GeoLocationInfo> TryIpSbAsync(int timeoutMs)
        {
            string body = await HttpGetStringAsync("https://api.ip.sb/geoip", timeoutMs);
            var dict = ParseJsonDict(body);
            if (dict == null) return null;

            string code = GetStr(dict, "country_code");
            string country = GetStr(dict, "country");
            if (string.IsNullOrEmpty(code) && string.IsNullOrEmpty(country)) return null;

            string isp = GetStr(dict, "isp");
            if (string.IsNullOrEmpty(isp)) isp = GetStr(dict, "organization");

            return BuildGeoInfo(
                code,
                country,
                GetStr(dict, "region"),
                GetStr(dict, "city"),
                isp,
                NormalizeAsn(GetStr(dict, "asn")),
                "api.ip.sb"
            );
        }

        private static async Task<GeoLocationInfo> TryIpWhoIsAsync(int timeoutMs)
        {
            string body = await HttpGetStringAsync("https://ipwho.is/", timeoutMs);
            var dict = ParseJsonDict(body);
            if (dict == null) return null;

            object okObj;
            if (dict.TryGetValue("success", out okObj) && okObj is bool && !((bool)okObj)) return null;

            string code = GetStr(dict, "country_code");
            string country = GetStr(dict, "country");
            if (string.IsNullOrEmpty(code) && string.IsNullOrEmpty(country)) return null;

            string isp = "";
            string asn = "";
            object connObj;
            if (dict.TryGetValue("connection", out connObj) && connObj is Dictionary<string, object>)
            {
                var connDict = (Dictionary<string, object>)connObj;
                isp = GetStr(connDict, "isp");
                if (string.IsNullOrEmpty(isp)) isp = GetStr(connDict, "org");
                asn = NormalizeAsn(GetStr(connDict, "asn"));
            }

            return BuildGeoInfo(
                code,
                country,
                GetStr(dict, "region"),
                GetStr(dict, "city"),
                isp,
                asn,
                "ipwho.is"
            );
        }

        private static async Task<GeoLocationInfo> TryIpInfoAsync(int timeoutMs)
        {
            string body = await HttpGetStringAsync("https://ipinfo.io/json", timeoutMs);
            var dict = ParseJsonDict(body);
            if (dict == null) return null;

            string code = GetStr(dict, "country");
            if (string.IsNullOrEmpty(code)) return null;

            string org = GetStr(dict, "org");
            return BuildGeoInfo(
                code,
                "",
                GetStr(dict, "region"),
                GetStr(dict, "city"),
                OrgToIsp(org),
                NormalizeAsn(org),
                "ipinfo.io"
            );
        }

        private static async Task<GeoLocationInfo> TryCloudflareTraceAsync(int timeoutMs)
        {
            string body = await HttpGetStringAsync("https://www.cloudflare.com/cdn-cgi/trace", timeoutMs);
            if (string.IsNullOrWhiteSpace(body)) return null;

            string loc = "";
            string[] lines = body.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i];
                if (line.StartsWith("loc=", StringComparison.OrdinalIgnoreCase))
                {
                    loc = line.Substring(4).Trim();
                    break;
                }
            }

            if (string.IsNullOrEmpty(loc)) return null;

            return BuildGeoInfo(loc, "", "", "", "", "", "Cloudflare");
        }

        /// <summary>把 "45102" / "AS45102" / "AS45102 Alibaba" 统一成 "AS45102"。</summary>
        private static string NormalizeAsn(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return "";
            string s = raw.Trim();
            int start = s.StartsWith("AS", StringComparison.OrdinalIgnoreCase) ? 2 : 0;
            int i = start;
            while (i < s.Length && char.IsDigit(s[i])) i++;
            if (i == start) return "";
            return "AS" + s.Substring(start, i - start);
        }

        /// <summary>从 ipinfo 的 org（"AS45102 Alibaba (US) Technology Co., Ltd."）拆出运营商名。</summary>
        private static string OrgToIsp(string org)
        {
            if (string.IsNullOrWhiteSpace(org)) return "";
            string s = org.Trim();
            if (!s.StartsWith("AS", StringComparison.OrdinalIgnoreCase)) return s;
            int i = 2;
            while (i < s.Length && char.IsDigit(s[i])) i++;
            if (i == 2) return s;
            return s.Substring(i).Trim();
        }

        private static GeoLocationInfo BuildGeoInfo(string countryCode, string rawCountry, string rawRegion, string rawCity, string isp, string asn, string source)
        {
            string code = (countryCode ?? "").Trim().ToUpperInvariant();
            string country = TranslateCountry(code, rawCountry);
            string region = TranslatePlace(rawRegion);
            string city = TranslatePlace(rawCity);

            string display = FormatDisplayText(code, country, region, city);
            if (string.IsNullOrWhiteSpace(display))
            {
                return null;
            }

            return new GeoLocationInfo
            {
                Success = true,
                CountryCode = code,
                Country = country,
                Region = region,
                City = city,
                Isp = (isp ?? "").Trim(),
                Asn = (asn ?? "").Trim(),
                Source = source,
                DisplayText = display,
                UpdatedAt = DateTime.Now
            };
        }

        private static string TranslateCountry(string code, string rawCountry)
        {
            string cn;
            if (!string.IsNullOrEmpty(code) && CountryNames.TryGetValue(code, out cn))
            {
                return cn;
            }
            return (rawCountry ?? "").Trim();
        }

        private static string TranslatePlace(string raw)
        {
            string s = (raw ?? "").Trim();
            if (string.IsNullOrEmpty(s)) return "";
            string cn;
            if (CityNames.TryGetValue(s, out cn))
            {
                return cn;
            }
            return s;
        }

        private static string CleanCnSuffix(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            if (s.EndsWith("省") || s.EndsWith("市"))
            {
                if (s.Length > 2) return s.Substring(0, s.Length - 1);
            }
            return s;
        }

        private static string FormatDisplayText(string code, string country, string region, string city)
        {
            if (string.IsNullOrEmpty(country))
            {
                if (!string.IsNullOrEmpty(city)) return city;
                return region;
            }

            // Special compact formatting for HK / MO / SG
            if (code == "HK" || code == "MO" || code == "SG")
            {
                return country;
            }

            if (code == "TW")
            {
                if (!string.IsNullOrEmpty(city) && !IsSamePlace(city, "台湾") && !IsSamePlace(city, "中国台湾"))
                {
                    return string.Format("{0} · {1}", country, CleanCnSuffix(city));
                }
                return country;
            }

            if (code == "CN")
            {
                string r = CleanCnSuffix(region);
                string c = CleanCnSuffix(city);
                if (!string.IsNullOrEmpty(r) && !string.IsNullOrEmpty(c))
                {
                    if (IsSamePlace(r, c))
                    {
                        return string.Format("{0} · {1}", country, c);
                    }
                    return string.Format("{0} · {1} {2}", country, r, c);
                }
                if (!string.IsNullOrEmpty(c)) return string.Format("{0} · {1}", country, c);
                if (!string.IsNullOrEmpty(r)) return string.Format("{0} · {1}", country, r);
                return country;
            }

            string sub = !string.IsNullOrEmpty(city) ? city : region;
            if (!string.IsNullOrEmpty(sub) && !IsSamePlace(country, sub))
            {
                return string.Format("{0} · {1}", country, sub);
            }

            return country;
        }

        private static bool IsSamePlace(string a, string b)
        {
            if (string.IsNullOrEmpty(a) || string.IsNullOrEmpty(b)) return false;
            return string.Equals(a, b, StringComparison.OrdinalIgnoreCase)
                || a.IndexOf(b, StringComparison.OrdinalIgnoreCase) >= 0
                || b.IndexOf(a, StringComparison.OrdinalIgnoreCase) >= 0;
        }
    }

    public static class ConfigManager
    {
        public static string GetConfigPath()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            return System.IO.Path.Combine(baseDir, "config.json");
        }

        public static AppConfig Load()
        {
            string path = GetConfigPath();
            if (!File.Exists(path))
            {
                var def = AppConfig.CreateDefault();
                Save(def);
                return def;
            }

            try
            {
                string json = File.ReadAllText(path, Encoding.UTF8);
                var serializer = new JavaScriptSerializer();
                var cfg = serializer.Deserialize<AppConfig>(json);
                if (cfg == null)
                {
                    cfg = AppConfig.CreateDefault();
                }
                if (cfg.Targets == null || cfg.Targets.Count == 0)
                {
                    cfg.Targets = AppConfig.CreateDefault().Targets;
                }
                if (cfg.IntervalMs < 500) cfg.IntervalMs = 2000;
                if (cfg.TimeoutMs < 500) cfg.TimeoutMs = 3000;
                if (cfg.GeoIntervalMs < 5000) cfg.GeoIntervalMs = 15000;
                if (cfg.GreenMaxMs <= 0) cfg.GreenMaxMs = 800;
                if (cfg.YellowMaxMs <= 0) cfg.YellowMaxMs = 1500;
                if (cfg.YellowMaxMs < cfg.GreenMaxMs) cfg.YellowMaxMs = cfg.GreenMaxMs;
                if (cfg.Opacity < 0.3 || cfg.Opacity > 1.0) cfg.Opacity = 0.92;
                if (string.IsNullOrWhiteSpace(cfg.Mode)) cfg.Mode = "HTTPS";
                return cfg;
            }
            catch
            {
                return AppConfig.CreateDefault();
            }
        }

        public static void Save(AppConfig cfg)
        {
            try
            {
                string path = GetConfigPath();
                var sb = new StringBuilder();
                sb.AppendLine("{");
                sb.AppendFormat("  \"Mode\": \"{0}\",\r\n", EscapeJson(cfg.Mode));
                sb.AppendFormat("  \"IntervalMs\": {0},\r\n", cfg.IntervalMs);
                sb.AppendFormat("  \"TimeoutMs\": {0},\r\n", cfg.TimeoutMs);
                sb.AppendFormat(System.Globalization.CultureInfo.InvariantCulture, "  \"Opacity\": {0:0.##},\r\n", cfg.Opacity);
                sb.AppendFormat("  \"Topmost\": {0},\r\n", cfg.Topmost ? "true" : "false");
                sb.AppendFormat("  \"CompactHorizontal\": {0},\r\n", cfg.CompactHorizontal ? "true" : "false");
                sb.AppendFormat("  \"ShowGeoLocation\": {0},\r\n", cfg.ShowGeoLocation ? "true" : "false");
                sb.AppendFormat("  \"GeoIntervalMs\": {0},\r\n", cfg.GeoIntervalMs);
                sb.AppendFormat("  \"GreenMaxMs\": {0},\r\n", cfg.GreenMaxMs);
                sb.AppendFormat("  \"YellowMaxMs\": {0},\r\n", cfg.YellowMaxMs);
                sb.AppendFormat(System.Globalization.CultureInfo.InvariantCulture, "  \"WindowLeft\": {0:0},\r\n", cfg.WindowLeft);
                sb.AppendFormat(System.Globalization.CultureInfo.InvariantCulture, "  \"WindowTop\": {0:0},\r\n", cfg.WindowTop);
                sb.AppendLine("  \"Targets\": [");
                for (int i = 0; i < cfg.Targets.Count; i++)
                {
                    var t = cfg.Targets[i];
                    sb.AppendLine("    {");
                    sb.AppendFormat("      \"Name\": \"{0}\",\r\n", EscapeJson(t.Name));
                    sb.AppendFormat("      \"Url\": \"{0}\",\r\n", EscapeJson(t.Url));
                    sb.AppendFormat("      \"Host\": \"{0}\",\r\n", EscapeJson(t.Host));
                    sb.AppendFormat("      \"Port\": {0},\r\n", t.Port > 0 ? t.Port : 443);
                    sb.AppendFormat("      \"Method\": \"{0}\"\r\n", EscapeJson(string.IsNullOrWhiteSpace(t.Method) ? "GET" : t.Method));
                    sb.Append("    }");
                    if (i < cfg.Targets.Count - 1) sb.Append(",");
                    sb.AppendLine();
                }
                sb.AppendLine("  ]");
                sb.AppendLine("}");
                File.WriteAllText(path, sb.ToString(), new UTF8Encoding(false));
            }
            catch
            {
                // Ignore save errors (e.g., read-only folder)
            }
        }

        private static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
        }
    }

    public class FloatingWindow : Window
    {
        private const int GWL_EXSTYLE = -20;
        private const int WS_EX_TRANSPARENT = 0x00000020;
        private const int WS_EX_TOOLWINDOW = 0x00000080;

        [DllImport("user32.dll")]
        private static extern int GetWindowLong(IntPtr hwnd, int index);

        [DllImport("user32.dll")]
        private static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyIcon(IntPtr hIcon);

        private AppConfig _config;
        private readonly List<TargetState> _states = new List<TargetState>();
        private DispatcherTimer _timer;
        private DispatcherTimer _geoTimer;
        private bool _isProbing;
        private bool _isFetchingGeo;
        private bool _clickThrough;
        private bool _isExiting;
        private GeoLocationInfo _lastGeo;

        private Border _cardBorder;
        private StackPanel _headerButtonsPanel;
        private TextBlock _modeBadgeText;
        private Ellipse _pulseDot;
        private TextBlock _geoText;
        private WpfPath _geoPinIcon;
        private FrameworkElement _geoContainer;

        private Forms.NotifyIcon _trayIcon;
        private IntPtr _trayIconHandle = IntPtr.Zero;
        private Forms.ToolStripMenuItem _trayClickThroughItem;
        private Forms.ToolStripMenuItem _trayToggleVisibleItem;

        // Color palette
        private static readonly WpfBrush BrushGreen = new SolidColorBrush(WpfColor.FromRgb(52, 211, 153));
        private static readonly WpfBrush BrushAmber = new SolidColorBrush(WpfColor.FromRgb(251, 191, 36));
        private static readonly WpfBrush BrushRed = new SolidColorBrush(WpfColor.FromRgb(248, 113, 113));
        private static readonly WpfBrush BrushMuted = new SolidColorBrush(WpfColor.FromRgb(148, 163, 184));
        private static readonly WpfBrush BrushName = new SolidColorBrush(WpfColor.FromRgb(241, 245, 249));
        private static readonly WpfBrush BrushGeoPin = new SolidColorBrush(WpfColor.FromRgb(56, 189, 248));
        private static readonly WpfBrush BrushGeoText = new SolidColorBrush(WpfColor.FromRgb(203, 213, 225));
        private static readonly WpfBrush BrushCardBg = new SolidColorBrush(WpfColor.FromArgb(232, 20, 23, 31));
        private static readonly WpfBrush BrushCardBorder = new SolidColorBrush(WpfColor.FromArgb(52, 255, 255, 255));
        private static readonly WpfBrush BrushDivider = new SolidColorBrush(WpfColor.FromArgb(28, 255, 255, 255));
        private static readonly WpfBrush BrushBadgeBg = new SolidColorBrush(WpfColor.FromArgb(180, 30, 41, 59));
        private static readonly WpfBrush BrushBadgeFg = new SolidColorBrush(WpfColor.FromRgb(96, 165, 250));
        private static readonly WpfFontFamily FontUi = new WpfFontFamily("Segoe UI, Microsoft YaHei UI");
        private static readonly WpfFontFamily FontMono = new WpfFontFamily("Cascadia Mono, Consolas, Microsoft YaHei UI");

        public FloatingWindow()
        {
            _config = ConfigManager.Load();

            Title = "网络延迟悬浮窗";
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = WpfBrushes.Transparent;
            ShowInTaskbar = false;
            ResizeMode = ResizeMode.NoResize;
            SizeToContent = SizeToContent.WidthAndHeight;
            Topmost = _config.Topmost;
            Opacity = _config.Opacity;

            SourceInitialized += OnSourceInitialized;
            Loaded += OnLoaded;
            Closing += OnWindowClosing;
            MouseEnter += delegate { SetHeaderButtonsOpacity(0.95); };
            MouseLeave += delegate { SetHeaderButtonsOpacity(0.32); };

            BuildTrayIcon();
            RebuildUi();
            SetupTimer();
        }

        private void OnSourceInitialized(object sender, EventArgs e)
        {
            ApplyWindowExStyles();
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            PositionWindowSafely();
            TriggerProbeAsync();
            if (_config.ShowGeoLocation)
            {
                TriggerGeoFetchAsync();
            }
        }

        private void OnWindowClosing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (!_isExiting)
            {
                e.Cancel = true;
                Hide();
                UpdateTrayLabels();
                return;
            }

            SavePosition();
            if (_timer != null) _timer.Stop();
            if (_geoTimer != null) _geoTimer.Stop();
            DisposeTrayIcon();
        }

        private void ApplyWindowExStyles()
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;

            int style = GetWindowLong(hwnd, GWL_EXSTYLE);
            style |= WS_EX_TOOLWINDOW;
            if (_clickThrough)
            {
                style |= WS_EX_TRANSPARENT;
            }
            else
            {
                style &= ~WS_EX_TRANSPARENT;
            }
            SetWindowLong(hwnd, GWL_EXSTYLE, style);
        }

        private void PositionWindowSafely()
        {
            double vLeft = SystemParameters.VirtualScreenLeft;
            double vTop = SystemParameters.VirtualScreenTop;
            double vRight = vLeft + SystemParameters.VirtualScreenWidth;
            double vBottom = vTop + SystemParameters.VirtualScreenHeight;

            if (_config.WindowLeft < vLeft - 50 || _config.WindowTop < vTop - 50 ||
                _config.WindowLeft > vRight - 60 || _config.WindowTop > vBottom - 40)
            {
                Rect wa = SystemParameters.WorkArea;
                Left = Math.Max(wa.Left + 16, wa.Right - ActualWidth - 20);
                Top = wa.Top + 20;
            }
            else
            {
                Left = _config.WindowLeft;
                Top = _config.WindowTop;
            }
        }

        private void SavePosition()
        {
            if (IsLoaded && ActualWidth > 0)
            {
                _config.WindowLeft = Left;
                _config.WindowTop = Top;
                ConfigManager.Save(_config);
            }
        }

        private void RebuildUi()
        {
            // Keep existing histories when rebuilding layout for same targets
            var oldByName = new Dictionary<string, TargetState>();
            foreach (var s in _states)
            {
                if (!oldByName.ContainsKey(s.Config.Name))
                {
                    oldByName[s.Config.Name] = s;
                }
            }
            _states.Clear();

            var rootGrid = new Grid
            {
                Margin = new Thickness(10)
            };

            _cardBorder = new Border
            {
                Background = BrushCardBg,
                BorderBrush = BrushCardBorder,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(_config.CompactHorizontal ? 16 : 12),
                Padding = _config.CompactHorizontal ? new Thickness(11, 6, 11, 6) : new Thickness(12, 9, 12, 10),
                Effect = new DropShadowEffect
                {
                    BlurRadius = 14,
                    ShadowDepth = 2,
                    Opacity = 0.45,
                    Color = Colors.Black
                },
                ContextMenu = BuildContextMenu()
            };

            _cardBorder.MouseLeftButtonDown += OnCardMouseLeftButtonDown;

            if (_config.CompactHorizontal)
            {
                _cardBorder.Child = BuildHorizontalContent(oldByName);
            }
            else
            {
                _cardBorder.Child = BuildVerticalContent(oldByName);
            }

            rootGrid.Children.Add(_cardBorder);
            Content = rootGrid;
            Opacity = _config.Opacity;
            Topmost = _config.Topmost;
        }

        private UIElement BuildVerticalContent(Dictionary<string, TargetState> oldByName)
        {
            var stack = new StackPanel
            {
                MinWidth = 192
            };

            // Header row
            var headerGrid = new Grid();
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var leftHeader = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center
            };

            _pulseDot = new Ellipse
            {
                Width = 6,
                Height = 6,
                Fill = BrushGreen,
                Margin = new Thickness(0, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            leftHeader.Children.Add(_pulseDot);

            var titleText = new TextBlock
            {
                Text = "LATENCY",
                FontFamily = FontUi,
                FontSize = 10,
                FontWeight = FontWeights.SemiBold,
                Foreground = BrushMuted,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 6, 0)
            };
            leftHeader.Children.Add(titleText);

            var badgeBorder = new Border
            {
                Background = BrushBadgeBg,
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(5, 1, 5, 1),
                VerticalAlignment = VerticalAlignment.Center
            };
            _modeBadgeText = new TextBlock
            {
                Text = (_config.Mode ?? "HTTPS").ToUpperInvariant(),
                FontFamily = FontMono,
                FontSize = 9,
                FontWeight = FontWeights.SemiBold,
                Foreground = BrushBadgeFg
            };
            badgeBorder.Child = _modeBadgeText;
            leftHeader.Children.Add(badgeBorder);

            Grid.SetColumn(leftHeader, 0);
            headerGrid.Children.Add(leftHeader);

            _headerButtonsPanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
                Opacity = 0.32
            };

            _headerButtonsPanel.Children.Add(CreateMiniButton("↻", "立即测速并刷新地域", delegate
            {
                TriggerProbeAsync();
                if (_config.ShowGeoLocation) TriggerGeoFetchAsync();
            }));
            _headerButtonsPanel.Children.Add(CreateMiniButton("⇄", "切换横向迷你条", delegate { ToggleCompactMode(); }));
            _headerButtonsPanel.Children.Add(CreateMiniButton("—", "隐藏到托盘", delegate { Hide(); UpdateTrayLabels(); }));
            _headerButtonsPanel.Children.Add(CreateMiniButton("×", "退出程序", delegate { ExitApp(); }));

            Grid.SetColumn(_headerButtonsPanel, 1);
            headerGrid.Children.Add(_headerButtonsPanel);
            stack.Children.Add(headerGrid);

            // Divider
            stack.Children.Add(new WpfRectangle
            {
                Height = 1,
                Fill = BrushDivider,
                Margin = new Thickness(0, 7, 0, 7)
            });

            // Target rows
            for (int i = 0; i < _config.Targets.Count; i++)
            {
                var target = _config.Targets[i];
                var state = new TargetState(target);
                TargetState prev;
                if (oldByName.TryGetValue(target.Name, out prev))
                {
                    state.History = prev.History;
                    state.LastChecked = prev.LastChecked;
                    state.LastResult = prev.LastResult;
                }

                var row = new Grid
                {
                    Margin = new Thickness(0, i == 0 ? 0 : 5, 0, 0),
                    Background = WpfBrushes.Transparent
                };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var dot = new Ellipse
                {
                    Width = 7,
                    Height = 7,
                    Fill = BrushMuted,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 8, 0)
                };
                Grid.SetColumn(dot, 0);
                row.Children.Add(dot);

                var nameTxt = new TextBlock
                {
                    Text = target.Name,
                    FontFamily = FontUi,
                    FontSize = 12.5,
                    FontWeight = FontWeights.Medium,
                    Foreground = BrushName,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 14, 0)
                };
                Grid.SetColumn(nameTxt, 1);
                row.Children.Add(nameTxt);

                var valTxt = new TextBlock
                {
                    Text = "-- ms",
                    FontFamily = FontMono,
                    FontSize = 12.5,
                    FontWeight = FontWeights.Bold,
                    Foreground = BrushMuted,
                    VerticalAlignment = VerticalAlignment.Center,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    TextAlignment = TextAlignment.Right,
                    MinWidth = 54
                };
                Grid.SetColumn(valTxt, 2);
                row.Children.Add(valTxt);

                state.StatusDot = dot;
                state.ValueText = valTxt;
                state.RowElement = row;
                ApplyStateVisuals(state);

                _states.Add(state);
                stack.Children.Add(row);
            }

            _geoText = null;
            _geoPinIcon = null;
            _geoContainer = null;

            if (_config.ShowGeoLocation)
            {
                stack.Children.Add(new WpfRectangle
                {
                    Height = 1,
                    Fill = BrushDivider,
                    Margin = new Thickness(0, 8, 0, 6)
                });

                var geoRow = new Grid
                {
                    Background = WpfBrushes.Transparent
                };
                geoRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                geoRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                _geoPinIcon = CreateGeoPinIcon(11);
                _geoPinIcon.Margin = new Thickness(0, 0, 6, 0);
                Grid.SetColumn(_geoPinIcon, 0);
                geoRow.Children.Add(_geoPinIcon);

                _geoText = new TextBlock
                {
                    Text = "获取地域中...",
                    FontFamily = FontUi,
                    FontSize = 11.5,
                    FontWeight = FontWeights.Medium,
                    Foreground = BrushGeoText,
                    VerticalAlignment = VerticalAlignment.Center,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    MaxWidth = 175
                };
                Grid.SetColumn(_geoText, 1);
                geoRow.Children.Add(_geoText);

                _geoContainer = geoRow;
                ApplyGeoVisuals();
                stack.Children.Add(geoRow);
            }

            return stack;
        }

        private UIElement BuildHorizontalContent(Dictionary<string, TargetState> oldByName)
        {
            _headerButtonsPanel = null;
            _geoText = null;
            _geoPinIcon = null;
            _geoContainer = null;

            var bar = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center
            };

            _pulseDot = new Ellipse
            {
                Width = 6,
                Height = 6,
                Fill = BrushGreen,
                Margin = new Thickness(0, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            bar.Children.Add(_pulseDot);

            var badgeBorder = new Border
            {
                Background = BrushBadgeBg,
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(5, 1, 5, 1),
                Margin = new Thickness(0, 0, 9, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            _modeBadgeText = new TextBlock
            {
                Text = (_config.Mode ?? "HTTPS").ToUpperInvariant(),
                FontFamily = FontMono,
                FontSize = 9,
                FontWeight = FontWeights.SemiBold,
                Foreground = BrushBadgeFg
            };
            badgeBorder.Child = _modeBadgeText;
            bar.Children.Add(badgeBorder);

            if (_config.ShowGeoLocation)
            {
                var geoPanel = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    VerticalAlignment = VerticalAlignment.Center,
                    Background = WpfBrushes.Transparent
                };

                _geoPinIcon = CreateGeoPinIcon(10);
                _geoPinIcon.Margin = new Thickness(0, 0, 4, 0);
                geoPanel.Children.Add(_geoPinIcon);

                _geoText = new TextBlock
                {
                    Text = "获取地域中...",
                    FontFamily = FontUi,
                    FontSize = 11,
                    FontWeight = FontWeights.Medium,
                    Foreground = BrushGeoText,
                    VerticalAlignment = VerticalAlignment.Center,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    MaxWidth = 140
                };
                geoPanel.Children.Add(_geoText);

                _geoContainer = geoPanel;
                ApplyGeoVisuals();
                bar.Children.Add(geoPanel);

                bar.Children.Add(new WpfRectangle
                {
                    Width = 1,
                    Height = 12,
                    Fill = BrushDivider,
                    Margin = new Thickness(9, 0, 9, 0),
                    VerticalAlignment = VerticalAlignment.Center
                });
            }

            for (int i = 0; i < _config.Targets.Count; i++)
            {
                if (i > 0)
                {
                    bar.Children.Add(new WpfRectangle
                    {
                        Width = 1,
                        Height = 12,
                        Fill = BrushDivider,
                        Margin = new Thickness(9, 0, 9, 0),
                        VerticalAlignment = VerticalAlignment.Center
                    });
                }

                var target = _config.Targets[i];
                var state = new TargetState(target);
                TargetState prev;
                if (oldByName.TryGetValue(target.Name, out prev))
                {
                    state.History = prev.History;
                    state.LastChecked = prev.LastChecked;
                    state.LastResult = prev.LastResult;
                }

                var itemPanel = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    VerticalAlignment = VerticalAlignment.Center,
                    Background = WpfBrushes.Transparent
                };

                var dot = new Ellipse
                {
                    Width = 6,
                    Height = 6,
                    Fill = BrushMuted,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 5, 0)
                };
                itemPanel.Children.Add(dot);

                var nameTxt = new TextBlock
                {
                    Text = target.Name,
                    FontFamily = FontUi,
                    FontSize = 11.5,
                    FontWeight = FontWeights.Medium,
                    Foreground = BrushName,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 5, 0)
                };
                itemPanel.Children.Add(nameTxt);

                var valTxt = new TextBlock
                {
                    Text = "-- ms",
                    FontFamily = FontMono,
                    FontSize = 11.5,
                    FontWeight = FontWeights.Bold,
                    Foreground = BrushMuted,
                    VerticalAlignment = VerticalAlignment.Center,
                    MinWidth = 42
                };
                itemPanel.Children.Add(valTxt);

                state.StatusDot = dot;
                state.ValueText = valTxt;
                state.RowElement = itemPanel;
                ApplyStateVisuals(state);

                _states.Add(state);
                bar.Children.Add(itemPanel);
            }

            return bar;
        }

        private WpfPath CreateGeoPinIcon(double size)
        {
            return new WpfPath
            {
                Data = Geometry.Parse("M12,2 C8.13,2 5,5.13 5,9 C5,14.25 12,22 12,22 C12,22 19,14.25 19,9 C19,5.13 15.87,2 12,2 Z M12,11.5 C10.62,11.5 9.5,10.38 9.5,9 C9.5,7.62 10.62,6.5 12,6.5 C13.38,6.5 14.5,7.62 14.5,9 C14.5,10.38 13.38,11.5 12,11.5 Z"),
                Fill = BrushGeoPin,
                Width = size,
                Height = size,
                Stretch = Stretch.Uniform,
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        private Button CreateMiniButton(string symbol, string tooltip, Action onClick)
        {
            var btn = new Button
            {
                Content = symbol,
                ToolTip = tooltip,
                Width = 18,
                Height = 18,
                Margin = new Thickness(2, 0, 0, 0),
                Padding = new Thickness(0),
                FontSize = 11,
                FontFamily = FontUi,
                Foreground = BrushMuted,
                Background = WpfBrushes.Transparent,
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand,
                Focusable = false
            };

            // Minimal flat template
            var template = new ControlTemplate(typeof(Button));
            var borderFactory = new FrameworkElementFactory(typeof(Border));
            borderFactory.Name = "bd";
            borderFactory.SetValue(Border.BackgroundProperty, WpfBrushes.Transparent);
            borderFactory.SetValue(Border.CornerRadiusProperty, new CornerRadius(4));
            var presenterFactory = new FrameworkElementFactory(typeof(ContentPresenter));
            presenterFactory.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            presenterFactory.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            borderFactory.AppendChild(presenterFactory);
            template.VisualTree = borderFactory;

            var hoverTrigger = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
            hoverTrigger.Setters.Add(new Setter(Border.BackgroundProperty, new SolidColorBrush(WpfColor.FromArgb(45, 255, 255, 255)), "bd"));
            hoverTrigger.Setters.Add(new Setter(Control.ForegroundProperty, BrushName));
            template.Triggers.Add(hoverTrigger);

            btn.Template = template;
            btn.Click += delegate(object s, RoutedEventArgs args)
            {
                args.Handled = true;
                onClick();
            };
            return btn;
        }

        private void SetHeaderButtonsOpacity(double value)
        {
            if (_headerButtonsPanel != null)
            {
                _headerButtonsPanel.Opacity = value;
            }
        }

        private void OnCardMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2)
            {
                ToggleCompactMode();
                return;
            }

            if (e.LeftButton == MouseButtonState.Pressed)
            {
                try
                {
                    DragMove();
                    SavePosition();
                }
                catch { }
            }
        }

        private ContextMenu BuildContextMenu()
        {
            var menu = new ContextMenu();

            var probeNowItem = new MenuItem { Header = "立即测速并刷新地域" };
            probeNowItem.Click += delegate
            {
                TriggerProbeAsync();
                if (_config.ShowGeoLocation) TriggerGeoFetchAsync();
            };
            menu.Items.Add(probeNowItem);

            var refreshGeoItem = new MenuItem { Header = "刷新当前网络地域" };
            refreshGeoItem.Click += delegate { TriggerGeoFetchAsync(); };
            menu.Items.Add(refreshGeoItem);

            // Mode submenu
            var modeMenu = new MenuItem { Header = "测速模式" };
            modeMenu.Items.Add(CreateModeItem("HTTPS (推荐 / 走系统代理)", "HTTPS"));
            modeMenu.Items.Add(CreateModeItem("TCP (443 端口直连)", "TCP"));
            modeMenu.Items.Add(CreateModeItem("ICMP (传统 Ping)", "ICMP"));
            menu.Items.Add(modeMenu);

            // Interval submenu
            var intervalMenu = new MenuItem { Header = "刷新频率" };
            intervalMenu.Items.Add(CreateIntervalItem("1 秒", 1000));
            intervalMenu.Items.Add(CreateIntervalItem("2 秒 (默认)", 2000));
            intervalMenu.Items.Add(CreateIntervalItem("3 秒", 3000));
            intervalMenu.Items.Add(CreateIntervalItem("5 秒", 5000));
            intervalMenu.Items.Add(CreateIntervalItem("10 秒", 10000));
            menu.Items.Add(intervalMenu);

            // Opacity submenu
            var opacityMenu = new MenuItem { Header = "窗口透明度" };
            opacityMenu.Items.Add(CreateOpacityItem("100%", 1.0));
            opacityMenu.Items.Add(CreateOpacityItem("92% (默认)", 0.92));
            opacityMenu.Items.Add(CreateOpacityItem("80%", 0.80));
            opacityMenu.Items.Add(CreateOpacityItem("65%", 0.65));
            menu.Items.Add(opacityMenu);

            var thresholdMenu = new MenuItem { Header = string.Format("颜色阈值 (绿<{0} / 黄≤{1} ms)", _config.GreenMaxMs, _config.YellowMaxMs) };
            thresholdMenu.Items.Add(CreateThresholdItem("严格: 绿<100 / 黄≤300 ms", 100, 300));
            thresholdMenu.Items.Add(CreateThresholdItem("标准: 绿<300 / 黄≤600 ms", 300, 600));
            thresholdMenu.Items.Add(CreateThresholdItem("宽松: 绿<500 / 黄≤1000 ms", 500, 1000));
            thresholdMenu.Items.Add(CreateThresholdItem("默认: 绿<800 / 黄≤1500 ms", 800, 1500));
            thresholdMenu.Items.Add(new Separator());
            thresholdMenu.Items.Add(new MenuItem { Header = "自定义: 编辑 config.json 的 GreenMaxMs / YellowMaxMs", IsEnabled = false });
            menu.Items.Add(thresholdMenu);

            menu.Items.Add(new Separator());

            var layoutItem = new MenuItem
            {
                Header = _config.CompactHorizontal ? "切换为纵向卡片" : "切换为横向迷你条"
            };
            layoutItem.Click += delegate { ToggleCompactMode(); };
            menu.Items.Add(layoutItem);

            var showGeoItem = new MenuItem
            {
                Header = "显示当前网络地域",
                IsCheckable = true,
                IsChecked = _config.ShowGeoLocation
            };
            showGeoItem.Click += delegate
            {
                _config.ShowGeoLocation = showGeoItem.IsChecked;
                ConfigManager.Save(_config);
                RebuildUi();
                if (_config.ShowGeoLocation)
                {
                    TriggerGeoFetchAsync();
                }
            };
            menu.Items.Add(showGeoItem);

            var topmostItem = new MenuItem
            {
                Header = "窗口置顶",
                IsCheckable = true,
                IsChecked = _config.Topmost
            };
            topmostItem.Click += delegate
            {
                _config.Topmost = topmostItem.IsChecked;
                Topmost = _config.Topmost;
                ConfigManager.Save(_config);
            };
            menu.Items.Add(topmostItem);

            var clickThroughItem = new MenuItem
            {
                Header = "开启鼠标穿透 (从托盘取消)"
            };
            clickThroughItem.Click += delegate { SetClickThrough(true); };
            menu.Items.Add(clickThroughItem);

            menu.Items.Add(new Separator());

            var editCfgItem = new MenuItem { Header = "编辑配置文件 (config.json)" };
            editCfgItem.Click += delegate { OpenConfigFile(); };
            menu.Items.Add(editCfgItem);

            var reloadCfgItem = new MenuItem { Header = "重新加载配置" };
            reloadCfgItem.Click += delegate { ReloadConfig(); };
            menu.Items.Add(reloadCfgItem);

            menu.Items.Add(new Separator());

            var hideItem = new MenuItem { Header = "隐藏到系统托盘" };
            hideItem.Click += delegate { Hide(); UpdateTrayLabels(); };
            menu.Items.Add(hideItem);

            var exitItem = new MenuItem { Header = "退出" };
            exitItem.Click += delegate { ExitApp(); };
            menu.Items.Add(exitItem);

            return menu;
        }

        private MenuItem CreateModeItem(string label, string mode)
        {
            var item = new MenuItem
            {
                Header = label,
                IsCheckable = true,
                IsChecked = string.Equals(_config.Mode, mode, StringComparison.OrdinalIgnoreCase)
            };
            item.Click += delegate
            {
                _config.Mode = mode;
                ConfigManager.Save(_config);
                foreach (var s in _states)
                {
                    s.History.Clear();
                    s.LastResult = null;
                }
                RebuildUi();
                TriggerProbeAsync();
            };
            return item;
        }

        private MenuItem CreateIntervalItem(string label, int ms)
        {
            var item = new MenuItem
            {
                Header = label,
                IsCheckable = true,
                IsChecked = _config.IntervalMs == ms
            };
            item.Click += delegate
            {
                _config.IntervalMs = ms;
                ConfigManager.Save(_config);
                if (_timer != null)
                {
                    _timer.Interval = TimeSpan.FromMilliseconds(ms);
                }
                _cardBorder.ContextMenu = BuildContextMenu();
            };
            return item;
        }

        private MenuItem CreateThresholdItem(string label, int greenMax, int yellowMax)
        {
            var item = new MenuItem
            {
                Header = label,
                IsCheckable = true,
                IsChecked = _config.GreenMaxMs == greenMax && _config.YellowMaxMs == yellowMax
            };
            item.Click += delegate
            {
                _config.GreenMaxMs = greenMax;
                _config.YellowMaxMs = yellowMax;
                ConfigManager.Save(_config);
                foreach (var s in _states) ApplyStateVisuals(s);
                _cardBorder.ContextMenu = BuildContextMenu();
            };
            return item;
        }

        private MenuItem CreateOpacityItem(string label, double opacity)
        {
            var item = new MenuItem
            {
                Header = label,
                IsCheckable = true,
                IsChecked = Math.Abs(_config.Opacity - opacity) < 0.02
            };
            item.Click += delegate
            {
                _config.Opacity = opacity;
                Opacity = opacity;
                ConfigManager.Save(_config);
                _cardBorder.ContextMenu = BuildContextMenu();
            };
            return item;
        }

        private void ToggleCompactMode()
        {
            _config.CompactHorizontal = !_config.CompactHorizontal;
            ConfigManager.Save(_config);
            RebuildUi();
        }

        private void SetClickThrough(bool enabled)
        {
            _clickThrough = enabled;
            ApplyWindowExStyles();
            UpdateTrayLabels();
            if (enabled && _trayIcon != null)
            {
                _trayIcon.ShowBalloonTip(2500, "网络延迟悬浮窗", "已开启鼠标穿透。如需移动或操作窗口，请右键点击右下角托盘图标取消穿透。", Forms.ToolTipIcon.Info);
            }
        }

        private void OpenConfigFile()
        {
            string path = ConfigManager.GetConfigPath();
            if (!File.Exists(path))
            {
                ConfigManager.Save(_config);
            }
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = path,
                    UseShellExecute = true
                });
            }
            catch
            {
                try { Process.Start("notepad.exe", path); } catch { }
            }
        }

        private void ReloadConfig()
        {
            _config = ConfigManager.Load();
            if (_timer != null)
            {
                _timer.Interval = TimeSpan.FromMilliseconds(_config.IntervalMs);
            }
            if (_geoTimer != null)
            {
                _geoTimer.Interval = TimeSpan.FromMilliseconds(_config.GeoIntervalMs);
            }
            RebuildUi();
            TriggerProbeAsync();
            if (_config.ShowGeoLocation)
            {
                TriggerGeoFetchAsync();
            }
        }

        private void SetupTimer()
        {
            _timer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(_config.IntervalMs)
            };
            _timer.Tick += delegate { TriggerProbeAsync(); };
            _timer.Start();

            _geoTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(_config.GeoIntervalMs)
            };
            _geoTimer.Tick += delegate
            {
                if (_config.ShowGeoLocation)
                {
                    TriggerGeoFetchAsync();
                }
            };
            _geoTimer.Start();
        }

        private async void TriggerGeoFetchAsync()
        {
            if (_isFetchingGeo || _isExiting) return;
            _isFetchingGeo = true;

            try
            {
                int timeoutMs = _config.TimeoutMs;
                var info = await Task.Run(delegate { return GeoLocationFetcher.FetchAsync(timeoutMs); });
                if (info != null)
                {
                    // If a transient error occurs after we already had a valid geo, keep showing failure only if needed or update
                    _lastGeo = info;
                    ApplyGeoVisuals();
                }
            }
            catch
            {
                // Ignore transient errors
            }
            finally
            {
                _isFetchingGeo = false;
            }
        }

        private void ApplyGeoVisuals()
        {
            if (_geoText == null) return;

            if (_lastGeo == null)
            {
                _geoText.Text = "获取地域中...";
                _geoText.Foreground = BrushMuted;
                if (_geoPinIcon != null) _geoPinIcon.Fill = BrushMuted;
            }
            else if (!_lastGeo.Success)
            {
                _geoText.Text = "地域获取失败";
                _geoText.Foreground = BrushRed;
                if (_geoPinIcon != null) _geoPinIcon.Fill = BrushRed;
            }
            else
            {
                _geoText.Text = _lastGeo.DisplayText;
                _geoText.Foreground = BrushGeoText;
                if (_geoPinIcon != null) _geoPinIcon.Fill = BrushGeoPin;
            }

            if (_geoContainer != null)
            {
                _geoContainer.ToolTip = _lastGeo != null ? _lastGeo.BuildTooltip() : "正在获取当前网络地域...";
            }
        }

        private async void TriggerProbeAsync()
        {
            if (_isProbing || _isExiting) return;
            _isProbing = true;

            try
            {
                if (_pulseDot != null)
                {
                    _pulseDot.Fill = BrushBadgeFg;
                }

                string mode = _config.Mode;
                int timeoutMs = _config.TimeoutMs;
                var snapshot = new List<TargetState>(_states);

                var tasks = new List<Task<ProbeResult>>();
                for (int i = 0; i < snapshot.Count; i++)
                {
                    var target = snapshot[i].Config;
                    tasks.Add(Task.Run(delegate { return LatencyProber.ProbeAsync(target, mode, timeoutMs); }));
                }

                var results = await Task.WhenAll(tasks);

                bool anySuccess = false;
                for (int i = 0; i < snapshot.Count && i < results.Length; i++)
                {
                    var state = snapshot[i];
                    var res = results[i];
                    if (res.Success) anySuccess = true;
                    state.Record(res);
                    ApplyStateVisuals(state);
                }

                if (_pulseDot != null)
                {
                    _pulseDot.Fill = anySuccess ? BrushGreen : BrushRed;
                }
            }
            catch
            {
                // Keep timer loop alive
            }
            finally
            {
                _isProbing = false;
            }
        }

        private void ApplyStateVisuals(TargetState state)
        {
            if (state.ValueText == null || state.StatusDot == null) return;

            if (state.LastResult == null)
            {
                state.ValueText.Text = "-- ms";
                state.ValueText.Foreground = BrushMuted;
                state.StatusDot.Fill = BrushMuted;
            }
            else if (!state.LastResult.Success)
            {
                state.ValueText.Text = "超时";
                state.ValueText.Foreground = BrushRed;
                state.StatusDot.Fill = BrushRed;
            }
            else
            {
                long ms = state.LastResult.LatencyMs;
                state.ValueText.Text = string.Format("{0} ms", ms);

                WpfBrush colorBrush;
                if (ms < _config.GreenMaxMs)
                {
                    colorBrush = BrushGreen;
                }
                else if (ms <= _config.YellowMaxMs)
                {
                    colorBrush = BrushAmber;
                }
                else
                {
                    colorBrush = BrushRed;
                }

                state.ValueText.Foreground = colorBrush;
                state.StatusDot.Fill = colorBrush;
            }

            if (state.RowElement != null)
            {
                state.RowElement.ToolTip = state.BuildTooltip(_config.Mode);
            }
        }

        private void BuildTrayIcon()
        {
            _trayIcon = new Forms.NotifyIcon
            {
                Text = "网络延迟悬浮窗 (Google / Cloudflare / Oracle)",
                Visible = true,
                Icon = CreateTrayIconGraphic()
            };

            _trayIcon.DoubleClick += delegate
            {
                Dispatcher.Invoke(new Action(ToggleVisibility));
            };

            var menu = new Forms.ContextMenuStrip();

            _trayToggleVisibleItem = new Forms.ToolStripMenuItem("隐藏悬浮窗");
            _trayToggleVisibleItem.Click += delegate
            {
                Dispatcher.Invoke(new Action(ToggleVisibility));
            };
            menu.Items.Add(_trayToggleVisibleItem);

            _trayClickThroughItem = new Forms.ToolStripMenuItem("鼠标穿透");
            _trayClickThroughItem.CheckOnClick = false;
            _trayClickThroughItem.Click += delegate
            {
                Dispatcher.Invoke(new Action(delegate { SetClickThrough(!_clickThrough); }));
            };
            menu.Items.Add(_trayClickThroughItem);

            var layoutItem = new Forms.ToolStripMenuItem("切换横向/纵向布局");
            layoutItem.Click += delegate
            {
                Dispatcher.Invoke(new Action(ToggleCompactMode));
            };
            menu.Items.Add(layoutItem);

            var editItem = new Forms.ToolStripMenuItem("编辑配置 (config.json)");
            editItem.Click += delegate
            {
                Dispatcher.Invoke(new Action(OpenConfigFile));
            };
            menu.Items.Add(editItem);

            var reloadItem = new Forms.ToolStripMenuItem("重新加载配置");
            reloadItem.Click += delegate
            {
                Dispatcher.Invoke(new Action(ReloadConfig));
            };
            menu.Items.Add(reloadItem);

            menu.Items.Add(new Forms.ToolStripSeparator());

            var exitItem = new Forms.ToolStripMenuItem("退出");
            exitItem.Click += delegate
            {
                Dispatcher.Invoke(new Action(ExitApp));
            };
            menu.Items.Add(exitItem);

            _trayIcon.ContextMenuStrip = menu;
        }

        private Icon CreateTrayIconGraphic()
        {
            using (var bmp = new Bitmap(32, 32))
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(System.Drawing.Color.Transparent);

                using (var bgBrush = new SolidBrush(System.Drawing.Color.FromArgb(255, 22, 27, 38)))
                using (var ringPen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(255, 52, 211, 153), 2.5f))
                using (var dotBrush = new SolidBrush(System.Drawing.Color.FromArgb(255, 52, 211, 153)))
                {
                    g.FillEllipse(bgBrush, 2, 2, 28, 28);
                    g.DrawEllipse(ringPen, 4, 4, 24, 24);
                    g.FillEllipse(dotBrush, 11, 11, 10, 10);
                }

                _trayIconHandle = bmp.GetHicon();
                return System.Drawing.Icon.FromHandle(_trayIconHandle);
            }
        }

        private void ToggleVisibility()
        {
            if (IsVisible)
            {
                Hide();
            }
            else
            {
                Show();
                Topmost = _config.Topmost;
                Activate();
            }
            UpdateTrayLabels();
        }

        private void UpdateTrayLabels()
        {
            if (_trayToggleVisibleItem != null)
            {
                _trayToggleVisibleItem.Text = IsVisible ? "隐藏悬浮窗" : "显示悬浮窗";
            }
            if (_trayClickThroughItem != null)
            {
                _trayClickThroughItem.Checked = _clickThrough;
            }
        }

        private void ExitApp()
        {
            _isExiting = true;
            Close();
            Application.Current.Shutdown();
        }

        private void DisposeTrayIcon()
        {
            if (_trayIcon != null)
            {
                _trayIcon.Visible = false;
                _trayIcon.Dispose();
                _trayIcon = null;
            }
            if (_trayIconHandle != IntPtr.Zero)
            {
                DestroyIcon(_trayIconHandle);
                _trayIconHandle = IntPtr.Zero;
            }
        }
    }

    public static class Program
    {
        private static Mutex _singleInstanceMutex;

        [STAThread]
        public static void Main(string[] args)
        {
            // Optional CLI self-test mode: LatencyMonitor.exe --test
            if (args != null && args.Length > 0 && string.Equals(args[0], "--test", StringComparison.OrdinalIgnoreCase))
            {
                var cfg = ConfigManager.Load();
                foreach (var t in cfg.Targets)
                {
                    var res = LatencyProber.ProbeAsync(t, cfg.Mode, cfg.TimeoutMs).GetAwaiter().GetResult();
                    Console.WriteLine(string.Format("{0}: success={1}, ms={2}, detail={3}", t.Name, res.Success, res.LatencyMs, res.Detail));
                }
                var geo = GeoLocationFetcher.FetchAsync(cfg.TimeoutMs).GetAwaiter().GetResult();
                Console.WriteLine(string.Format("Geo: success={0}, display={1}, source={2}, isp={3}, asn={4}",
                    geo.Success, geo.DisplayText, geo.Source, geo.Isp, geo.Asn));
                return;
            }

            bool createdNew;
            _singleInstanceMutex = new Mutex(true, "Global\\Antigravity_LatencyMonitor_SingleInstance", out createdNew);
            if (!createdNew)
            {
                return;
            }

            try
            {
                var app = new Application();
                app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
                var win = new FloatingWindow();
                win.Show();
                app.Run();
            }
            finally
            {
                if (_singleInstanceMutex != null)
                {
                    _singleInstanceMutex.ReleaseMutex();
                    _singleInstanceMutex.Dispose();
                }
            }
        }
    }
}
