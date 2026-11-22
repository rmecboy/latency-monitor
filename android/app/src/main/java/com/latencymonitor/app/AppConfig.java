package com.latencymonitor.app;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.List;

public class AppConfig {
    private static final String PREF_NAME = "latency_monitor_prefs";

    public static class Target {
        public final String name;
        public final String url;
        public final String host;
        public final int port;
        public final String method;

        public Target(String name, String url, String host, int port, String method) {
            this.name = name;
            this.url = url;
            this.host = host;
            this.port = port;
            this.method = method;
        }
    }

    public String mode;
    public int intervalMs;
    public int timeoutMs;
    public int geoIntervalMs;
    public float opacity;
    public boolean defaultExpanded;
    public boolean showGeoLocation;
    public int overlayX;
    public int overlayY;

    public String googleUrl;
    public String cloudflareUrl;
    public String oracleUrl;

    public static AppConfig load(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        AppConfig cfg = new AppConfig();
        cfg.mode = prefs.getString("mode", "HTTPS");
        cfg.intervalMs = prefs.getInt("interval_ms", 3000);
        cfg.timeoutMs = prefs.getInt("timeout_ms", 3000);
        cfg.geoIntervalMs = prefs.getInt("geo_interval_ms", 15000);
        cfg.opacity = prefs.getFloat("opacity", 0.92f);
        cfg.defaultExpanded = prefs.getBoolean("default_expanded", false);
        cfg.showGeoLocation = prefs.getBoolean("show_geo_location", true);
        cfg.overlayX = prefs.getInt("overlay_x", 24);
        cfg.overlayY = prefs.getInt("overlay_y", 140);

        cfg.googleUrl = prefs.getString("google_url", "https://www.google.com/generate_204");
        cfg.cloudflareUrl = prefs.getString("cloudflare_url", "https://cp.cloudflare.com/generate_204");
        cfg.oracleUrl = prefs.getString("oracle_url", "https://www.oracle.com/favicon.ico");
        return cfg;
    }

    public void save(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putString("mode", mode)
                .putInt("interval_ms", intervalMs)
                .putInt("timeout_ms", timeoutMs)
                .putInt("geo_interval_ms", geoIntervalMs)
                .putFloat("opacity", opacity)
                .putBoolean("default_expanded", defaultExpanded)
                .putBoolean("show_geo_location", showGeoLocation)
                .putInt("overlay_x", overlayX)
                .putInt("overlay_y", overlayY)
                .putString("google_url", googleUrl)
                .putString("cloudflare_url", cloudflareUrl)
                .putString("oracle_url", oracleUrl)
                .apply();
    }

    public static void savePosition(Context context, int x, int y) {
        SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
        prefs.edit()
                .putInt("overlay_x", x)
                .putInt("overlay_y", y)
                .apply();
    }

    public List<Target> getTargets() {
        List<Target> list = new ArrayList<>();
        list.add(new Target("Google", safeUrl(googleUrl, "https://www.google.com/generate_204"),
                extractHost(googleUrl, "www.google.com"), extractPort(googleUrl, 443), "GET"));
        list.add(new Target("Cloudflare", safeUrl(cloudflareUrl, "https://cp.cloudflare.com/generate_204"),
                extractHost(cloudflareUrl, "1.1.1.1"), extractPort(cloudflareUrl, 443), "GET"));
        list.add(new Target("Oracle", safeUrl(oracleUrl, "https://www.oracle.com/favicon.ico"),
                extractHost(oracleUrl, "www.oracle.com"), extractPort(oracleUrl, 443), "HEAD"));
        return list;
    }

    private static String safeUrl(String url, String fallback) {
        if (url == null || url.trim().isEmpty()) {
            return fallback;
        }
        String trimmed = url.trim();
        if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
            return "https://" + trimmed;
        }
        return trimmed;
    }

    private static String extractHost(String url, String fallback) {
        try {
            java.net.URI uri = new java.net.URI(safeUrl(url, "https://" + fallback));
            String host = uri.getHost();
            return (host != null && !host.isEmpty()) ? host : fallback;
        } catch (Exception e) {
            return fallback;
        }
    }

    private static int extractPort(String url, int fallback) {
        try {
            java.net.URI uri = new java.net.URI(safeUrl(url, "https://example.com"));
            int port = uri.getPort();
            if (port > 0) return port;
            return "http".equalsIgnoreCase(uri.getScheme()) ? 80 : fallback;
        } catch (Exception e) {
            return fallback;
        }
    }
}
