package com.latencymonitor.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;
import android.text.TextUtils;
import android.util.DisplayMetrics;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class FloatingOverlayService extends Service {

    public static final String ACTION_START = "com.latencymonitor.app.ACTION_START";
    public static final String ACTION_STOP = "com.latencymonitor.app.ACTION_STOP";
    public static final String ACTION_RELOAD = "com.latencymonitor.app.ACTION_RELOAD";
    public static final String ACTION_REFRESH = "com.latencymonitor.app.ACTION_REFRESH";
    public static final String ACTION_TOGGLE_EXPAND = "com.latencymonitor.app.ACTION_TOGGLE_EXPAND";

    private static final String CHANNEL_ID = "latency_monitor_channel";
    private static final int NOTIF_ID = 1001;

    private static final int COLOR_GREEN = Color.parseColor("#34D399");
    private static final int COLOR_AMBER = Color.parseColor("#FBBF24");
    private static final int COLOR_RED = Color.parseColor("#F87171");
    private static final int COLOR_MUTED = Color.parseColor("#94A3B8");
    private static final int COLOR_NAME = Color.parseColor("#F1F5F9");
    private static final int COLOR_GEO_TEXT = Color.parseColor("#CBD5E1");
    private static final int COLOR_BADGE_FG = Color.parseColor("#60A5FA");
    private static final int COLOR_BADGE_BG = Color.parseColor("#B41E293B");
    private static final int COLOR_CARD_BG = Color.parseColor("#E614171F");
    private static final int COLOR_CARD_STROKE = Color.parseColor("#38FFFFFF");
    private static final int COLOR_DIVIDER = Color.parseColor("#20FFFFFF");

    public static volatile boolean isRunning = false;

    private WindowManager windowManager;
    private WindowManager.LayoutParams layoutParams;
    private View overlayView;

    private AppConfig config;
    private boolean isExpanded = false;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private ExecutorService probeExecutor;
    private ExecutorService geoExecutor;

    private View pulseDot;
    private final List<View> targetDots = new ArrayList<>();
    private final List<TextView> targetValues = new ArrayList<>();
    private final List<LatencyProber.ProbeResult> lastResults = new ArrayList<>();
    private TextView geoTextView;
    private GeoLocationFetcher.GeoInfo lastGeo;

    private volatile boolean isProbing = false;
    private volatile boolean isFetchingGeo = false;

    private final Runnable probeRunnable = new Runnable() {
        @Override
        public void run() {
            triggerProbe();
            if (config != null) {
                mainHandler.postDelayed(this, Math.max(1000, config.intervalMs));
            }
        }
    };

    private final Runnable geoRunnable = new Runnable() {
        @Override
        public void run() {
            if (config != null) {
                triggerGeoFetch();
                mainHandler.postDelayed(this, Math.max(5000, config.geoIntervalMs));
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        probeExecutor = Executors.newCachedThreadPool();
        geoExecutor = Executors.newSingleThreadExecutor();
        config = AppConfig.load(this);
        isExpanded = config.defaultExpanded;
        createNotificationChannel();
        startForegroundCompat();
        isRunning = true;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent != null ? intent.getAction() : ACTION_START;
        if (ACTION_STOP.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }

        if (!Settings.canDrawOverlays(this)) {
            stopSelf();
            return START_NOT_STICKY;
        }

        if (ACTION_TOGGLE_EXPAND.equals(action)) {
            toggleExpand();
            return START_STICKY;
        }

        if (ACTION_REFRESH.equals(action)) {
            triggerProbe();
            triggerGeoFetch();
            return START_STICKY;
        }

        if (ACTION_RELOAD.equals(action) || overlayView == null) {
            config = AppConfig.load(this);
            if (overlayView == null) {
                isExpanded = config.defaultExpanded;
            }
            rebuildOverlay();
            restartLoops();
            return START_STICKY;
        }

        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        isRunning = false;
        mainHandler.removeCallbacksAndMessages(null);
        removeOverlay();
        if (probeExecutor != null) probeExecutor.shutdownNow();
        if (geoExecutor != null) geoExecutor.shutdownNow();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void toggleExpand() {
        isExpanded = !isExpanded;
        rebuildOverlay();
        if (isExpanded) {
            triggerProbe();
        }
    }

    private void createNotificationChannel() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm != null) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "网络延迟悬浮窗",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("保持网络延迟与地域悬浮窗在前台运行");
            channel.setShowBadge(false);
            nm.createNotificationChannel(channel);
        }
    }

    private void startForegroundCompat() {
        Intent openIntent = new Intent(this, MainActivity.class);
        PendingIntent openPi = PendingIntent.getActivity(
                this, 0, openIntent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        PendingIntent togglePi = PendingIntent.getService(
                this, 1, new Intent(this, FloatingOverlayService.class).setAction(ACTION_TOGGLE_EXPAND),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        PendingIntent refreshPi = PendingIntent.getService(
                this, 2, new Intent(this, FloatingOverlayService.class).setAction(ACTION_REFRESH),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        PendingIntent stopPi = PendingIntent.getService(
                this, 3, new Intent(this, FloatingOverlayService.class).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification notif = new Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("网络延迟悬浮窗运行中")
                .setContentText("单击悬浮窗展开/收起延迟详情，手指拖动移动位置")
                .setSmallIcon(R.drawable.ic_notif_pulse)
                .setContentIntent(openPi)
                .setOngoing(true)
                .addAction(new Notification.Action.Builder((android.graphics.drawable.Icon) null, "展开/收起", togglePi).build())
                .addAction(new Notification.Action.Builder((android.graphics.drawable.Icon) null, "刷新", refreshPi).build())
                .addAction(new Notification.Action.Builder((android.graphics.drawable.Icon) null, "关闭", stopPi).build())
                .build();

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIF_ID, notif);
        }
    }

    private void restartLoops() {
        mainHandler.removeCallbacks(probeRunnable);
        mainHandler.removeCallbacks(geoRunnable);
        mainHandler.post(probeRunnable);
        mainHandler.post(geoRunnable);
    }

    private void removeOverlay() {
        if (overlayView != null && windowManager != null) {
            try {
                windowManager.removeView(overlayView);
            } catch (Exception ignored) {
            }
            overlayView = null;
        }
    }

    private void rebuildOverlay() {
        removeOverlay();
        targetDots.clear();
        targetValues.clear();
        geoTextView = null;

        layoutParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
        );
        layoutParams.gravity = Gravity.TOP | Gravity.START;
        layoutParams.x = config.overlayX;
        layoutParams.y = config.overlayY;

        View card = isExpanded ? buildExpandedCard() : buildCollapsedPill();
        card.setAlpha(config.opacity);
        attachTouchHandler(card);

        overlayView = card;
        try {
            windowManager.addView(overlayView, layoutParams);
            // Clamp inside screen bounds after measurement (especially when expanding near right/bottom edges)
            overlayView.post(new Runnable() {
                @Override
                public void run() {
                    clampOverlayInBounds();
                }
            });
        } catch (Exception e) {
            stopSelf();
        }

        applyAllResultsToUi();
        applyGeoToUi();
    }

    private void clampOverlayInBounds() {
        if (overlayView == null || layoutParams == null || windowManager == null) return;
        DisplayMetrics dm = getResources().getDisplayMetrics();
        int maxX = Math.max(0, dm.widthPixels - overlayView.getWidth());
        int maxY = Math.max(0, dm.heightPixels - overlayView.getHeight());
        int clampedX = Math.max(0, Math.min(maxX, layoutParams.x));
        int clampedY = Math.max(0, Math.min(maxY, layoutParams.y));
        if (clampedX != layoutParams.x || clampedY != layoutParams.y) {
            layoutParams.x = clampedX;
            layoutParams.y = clampedY;
            try {
                windowManager.updateViewLayout(overlayView, layoutParams);
            } catch (Exception ignored) {
            }
        }
    }

    private View buildCollapsedPill() {
        LinearLayout pill = new LinearLayout(this);
        pill.setOrientation(LinearLayout.HORIZONTAL);
        pill.setGravity(Gravity.CENTER_VERTICAL);
        pill.setPadding(dp(5), dp(2), dp(6), dp(2));
        pill.setBackground(createRoundedBg(COLOR_CARD_BG, COLOR_CARD_STROKE, dp(9), dp(1)));

        pulseDot = createDot(dp(5), COLOR_MUTED);
        LinearLayout.LayoutParams pulseLp = new LinearLayout.LayoutParams(dp(5), dp(5));
        pulseLp.setMarginEnd(dp(4));
        pill.addView(pulseDot, pulseLp);

        geoTextView = new TextView(this);
        geoTextView.setText("...");
        geoTextView.setTextColor(COLOR_GEO_TEXT);
        geoTextView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9.5f);
        geoTextView.setIncludeFontPadding(false);
        geoTextView.setSingleLine(true);
        geoTextView.setEllipsize(TextUtils.TruncateAt.END);
        geoTextView.setMaxWidth(dp(86));
        pill.addView(geoTextView);

        return pill;
    }

    private View buildExpandedCard() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(7), dp(5), dp(7), dp(5));
        root.setBackground(createRoundedBg(COLOR_CARD_BG, COLOR_CARD_STROKE, dp(9), dp(1)));
        root.setMinimumWidth(dp(118));

        // Compact header
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        pulseDot = createDot(dp(5), COLOR_GREEN);
        LinearLayout.LayoutParams pulseLp = new LinearLayout.LayoutParams(dp(5), dp(5));
        pulseLp.setMarginEnd(dp(4));
        header.addView(pulseDot, pulseLp);

        TextView badge = createModeBadge();
        header.addView(badge);

        View spacer = new View(this);
        LinearLayout.LayoutParams spacerLp = new LinearLayout.LayoutParams(dp(6), 1, 1f);
        header.addView(spacer, spacerLp);

        TextView refreshBtn = createMiniAction("↻");
        refreshBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                triggerProbe();
                triggerGeoFetch();
            }
        });
        header.addView(refreshBtn);

        TextView collapseBtn = createMiniAction("−");
        collapseBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                toggleExpand();
            }
        });
        header.addView(collapseBtn);

        TextView closeBtn = createMiniAction("×");
        closeBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                stopSelf();
            }
        });
        header.addView(closeBtn);

        root.addView(header);
        root.addView(createHorizontalDivider(dp(4), dp(4)));

        // Compact target rows
        List<AppConfig.Target> targets = config.getTargets();
        for (int i = 0; i < targets.size(); i++) {
            AppConfig.Target t = targets.get(i);
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            row.setGravity(Gravity.CENTER_VERTICAL);
            LinearLayout.LayoutParams rowLp = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            if (i > 0) rowLp.topMargin = dp(2);

            View dot = createDot(dp(5), COLOR_MUTED);
            LinearLayout.LayoutParams dotLp = new LinearLayout.LayoutParams(dp(5), dp(5));
            dotLp.setMarginEnd(dp(5));
            row.addView(dot, dotLp);

            TextView nameTv = new TextView(this);
            nameTv.setText(t.name);
            nameTv.setTextColor(COLOR_NAME);
            nameTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f);
            nameTv.setIncludeFontPadding(false);
            LinearLayout.LayoutParams nameLp = new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
            nameLp.setMarginEnd(dp(8));
            row.addView(nameTv, nameLp);

            TextView valTv = new TextView(this);
            valTv.setText("--ms");
            valTv.setTextColor(COLOR_MUTED);
            valTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f);
            valTv.setIncludeFontPadding(false);
            valTv.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
            valTv.setGravity(Gravity.END);
            row.addView(valTv);

            targetDots.add(dot);
            targetValues.add(valTv);
            root.addView(row, rowLp);
        }

        // Compact geographic location footer (NO IP)
        root.addView(createHorizontalDivider(dp(4), dp(3)));
        LinearLayout geoRow = new LinearLayout(this);
        geoRow.setOrientation(LinearLayout.HORIZONTAL);
        geoRow.setGravity(Gravity.CENTER_VERTICAL);

        ImageView pin = new ImageView(this);
        pin.setImageResource(R.drawable.ic_location_pin);
        LinearLayout.LayoutParams pinLp = new LinearLayout.LayoutParams(dp(9), dp(9));
        pinLp.setMarginEnd(dp(3));
        geoRow.addView(pin, pinLp);

        geoTextView = new TextView(this);
        geoTextView.setText("定位中...");
        geoTextView.setTextColor(COLOR_GEO_TEXT);
        geoTextView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9.5f);
        geoTextView.setIncludeFontPadding(false);
        geoTextView.setSingleLine(true);
        geoTextView.setEllipsize(TextUtils.TruncateAt.END);
        geoTextView.setMaxWidth(dp(110));
        geoRow.addView(geoTextView);

        root.addView(geoRow);

        return root;
    }

    private TextView createModeBadge() {
        TextView tv = new TextView(this);
        tv.setText(config.mode != null ? config.mode.toUpperCase(Locale.US) : "HTTPS");
        tv.setTextColor(COLOR_BADGE_FG);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 7.5f);
        tv.setIncludeFontPadding(false);
        tv.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        tv.setPadding(dp(3), dp(1), dp(3), dp(1));
        tv.setBackground(createRoundedBg(COLOR_BADGE_BG, Color.TRANSPARENT, dp(3), 0));
        return tv;
    }

    private TextView createMiniAction(String symbol) {
        TextView tv = new TextView(this);
        tv.setText(symbol);
        tv.setTextColor(COLOR_MUTED);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f);
        tv.setIncludeFontPadding(false);
        tv.setPadding(dp(5), 0, dp(2), 0);
        return tv;
    }

    private View createDot(int sizePx, int color) {
        View v = new View(this);
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.OVAL);
        d.setColor(color);
        v.setBackground(d);
        return v;
    }

    private void setDotColor(View dot, int color) {
        if (dot == null) return;
        if (dot.getBackground() instanceof GradientDrawable) {
            ((GradientDrawable) dot.getBackground()).setColor(color);
        }
    }

    private View createHorizontalDivider(int topMargin, int bottomMargin) {
        View line = new View(this);
        line.setBackgroundColor(COLOR_DIVIDER);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(1));
        lp.topMargin = topMargin;
        lp.bottomMargin = bottomMargin;
        line.setLayoutParams(lp);
        return line;
    }

    private GradientDrawable createRoundedBg(int fillColor, int strokeColor, int radiusPx, int strokePx) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(fillColor);
        d.setCornerRadius(radiusPx);
        if (strokePx > 0) {
            d.setStroke(strokePx, strokeColor);
        }
        return d;
    }

    private void attachTouchHandler(View view) {
        view.setOnTouchListener(new View.OnTouchListener() {
            private int initialX;
            private int initialY;
            private float initialTouchX;
            private float initialTouchY;
            private boolean moved;

            @Override
            public boolean onTouch(View v, MotionEvent event) {
                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = layoutParams.x;
                        initialY = layoutParams.y;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        moved = false;
                        return true;

                    case MotionEvent.ACTION_MOVE:
                        int dx = Math.round(event.getRawX() - initialTouchX);
                        int dy = Math.round(event.getRawY() - initialTouchY);
                        if (Math.abs(dx) > dp(5) || Math.abs(dy) > dp(5)) {
                            moved = true;
                        }
                        if (moved && overlayView != null) {
                            DisplayMetrics dm = getResources().getDisplayMetrics();
                            int maxX = Math.max(0, dm.widthPixels - overlayView.getWidth());
                            int maxY = Math.max(0, dm.heightPixels - overlayView.getHeight());
                            layoutParams.x = Math.max(0, Math.min(maxX, initialX + dx));
                            layoutParams.y = Math.max(0, Math.min(maxY, initialY + dy));
                            try {
                                windowManager.updateViewLayout(overlayView, layoutParams);
                            } catch (Exception ignored) {
                            }
                        }
                        return true;

                    case MotionEvent.ACTION_UP:
                        if (moved) {
                            config.overlayX = layoutParams.x;
                            config.overlayY = layoutParams.y;
                            AppConfig.savePosition(FloatingOverlayService.this, layoutParams.x, layoutParams.y);
                        } else {
                            // Single tap toggles between compact region pill and expanded detail card
                            toggleExpand();
                        }
                        return true;
                }
                return false;
            }
        });
    }

    private void triggerProbe() {
        if (isProbing || config == null) return;
        isProbing = true;

        mainHandler.post(new Runnable() {
            @Override
            public void run() {
                setDotColor(pulseDot, COLOR_BADGE_FG);
            }
        });

        final List<AppConfig.Target> targets = config.getTargets();
        final String mode = config.mode;
        final int timeoutMs = config.timeoutMs;

        probeExecutor.execute(new Runnable() {
            @Override
            public void run() {
                try {
                    List<Future<LatencyProber.ProbeResult>> futures = new ArrayList<>();
                    for (final AppConfig.Target t : targets) {
                        futures.add(probeExecutor.submit(new Callable<LatencyProber.ProbeResult>() {
                            @Override
                            public LatencyProber.ProbeResult call() {
                                return LatencyProber.probe(t, mode, timeoutMs);
                            }
                        }));
                    }

                    final List<LatencyProber.ProbeResult> results = new ArrayList<>();
                    for (Future<LatencyProber.ProbeResult> f : futures) {
                        try {
                            results.add(f.get());
                        } catch (Exception e) {
                            results.add(new LatencyProber.ProbeResult(false, -1L, "Error"));
                        }
                    }

                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            lastResults.clear();
                            lastResults.addAll(results);
                            applyAllResultsToUi();
                        }
                    });
                } finally {
                    isProbing = false;
                }
            }
        });
    }

    private void triggerGeoFetch() {
        if (isFetchingGeo || config == null) return;
        isFetchingGeo = true;
        final int timeoutMs = config.timeoutMs;

        geoExecutor.execute(new Runnable() {
            @Override
            public void run() {
                try {
                    final GeoLocationFetcher.GeoInfo info = GeoLocationFetcher.fetch(timeoutMs);
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            lastGeo = info;
                            applyGeoToUi();
                        }
                    });
                } finally {
                    isFetchingGeo = false;
                }
            }
        });
    }

    private void applyAllResultsToUi() {
        int overallColor = COLOR_MUTED;
        if (!lastResults.isEmpty()) {
            boolean anySuccess = false;
            long bestMs = Long.MAX_VALUE;
            for (LatencyProber.ProbeResult res : lastResults) {
                if (res != null && res.success) {
                    anySuccess = true;
                    if (res.latencyMs < bestMs) {
                        bestMs = res.latencyMs;
                    }
                }
            }
            if (!anySuccess) {
                overallColor = COLOR_RED;
            } else {
                overallColor = getLatencyColor(bestMs);
            }
        }

        setDotColor(pulseDot, overallColor);

        for (int i = 0; i < targetValues.size(); i++) {
            TextView tv = targetValues.get(i);
            View dot = targetDots.get(i);
            if (i >= lastResults.size() || lastResults.get(i) == null) {
                tv.setText("--ms");
                tv.setTextColor(COLOR_MUTED);
                setDotColor(dot, COLOR_MUTED);
                continue;
            }

            LatencyProber.ProbeResult res = lastResults.get(i);
            if (!res.success) {
                tv.setText("超时");
                tv.setTextColor(COLOR_RED);
                setDotColor(dot, COLOR_RED);
            } else {
                long ms = res.latencyMs;
                tv.setText(ms + "ms");
                int color = getLatencyColor(ms);
                tv.setTextColor(color);
                setDotColor(dot, color);
            }
        }
    }

    private void applyGeoToUi() {
        if (geoTextView == null) return;
        if (lastGeo == null) {
            geoTextView.setText(isExpanded ? "定位中..." : "...");
            geoTextView.setTextColor(COLOR_MUTED);
        } else if (!lastGeo.success) {
            geoTextView.setText(isExpanded ? "地域未知" : "未知");
            geoTextView.setTextColor(COLOR_RED);
        } else {
            geoTextView.setText(lastGeo.displayText);
            geoTextView.setTextColor(COLOR_GEO_TEXT);
        }
    }

    private int getLatencyColor(long ms) {
        if (ms < 800L) return COLOR_GREEN;
        if (ms <= 1500L) return COLOR_AMBER;
        return COLOR_RED;
    }

    private int dp(int value) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics()));
    }
}
