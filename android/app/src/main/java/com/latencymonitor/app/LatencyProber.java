package com.latencymonitor.app;

import android.os.SystemClock;

import java.net.HttpURLConnection;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URL;

public class LatencyProber {

    public static class ProbeResult {
        public final boolean success;
        public final long latencyMs;
        public final String detail;

        public ProbeResult(boolean success, long latencyMs, String detail) {
            this.success = success;
            this.latencyMs = latencyMs;
            this.detail = detail;
        }
    }

    public static ProbeResult probe(AppConfig.Target target, String mode, int timeoutMs) {
        if ("TCP".equalsIgnoreCase(mode)) {
            return probeTcp(target, timeoutMs);
        }
        return probeHttps(target, timeoutMs);
    }

    private static ProbeResult probeHttps(AppConfig.Target target, int timeoutMs) {
        HttpURLConnection conn = null;
        long start = SystemClock.elapsedRealtime();
        try {
            URL url = new URL(target.url);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod(target.method != null ? target.method : "GET");
            conn.setConnectTimeout(timeoutMs);
            conn.setReadTimeout(timeoutMs);
            conn.setInstanceFollowRedirects(false);
            conn.setUseCaches(false);
            conn.setRequestProperty("Connection", "close");
            conn.setRequestProperty("User-Agent",
                    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36");

            int code = conn.getResponseCode();
            long elapsed = Math.max(1L, SystemClock.elapsedRealtime() - start);
            return new ProbeResult(true, elapsed, "HTTP " + code);
        } catch (Exception e) {
            return new ProbeResult(false, -1L, e.getClass().getSimpleName());
        } finally {
            if (conn != null) {
                try {
                    conn.disconnect();
                } catch (Exception ignored) {
                }
            }
        }
    }

    private static ProbeResult probeTcp(AppConfig.Target target, int timeoutMs) {
        long start = SystemClock.elapsedRealtime();
        try (Socket socket = new Socket()) {
            int port = target.port > 0 ? target.port : 443;
            socket.connect(new InetSocketAddress(target.host, port), timeoutMs);
            long elapsed = Math.max(1L, SystemClock.elapsedRealtime() - start);
            return new ProbeResult(true, elapsed, "TCP :" + port);
        } catch (Exception e) {
            return new ProbeResult(false, -1L, e.getClass().getSimpleName());
        }
    }
}
