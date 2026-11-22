package com.latencymonitor.app;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

public class MainActivity extends Activity {

    private static final int REQ_NOTIF_PERM = 2001;

    private static final int BG_DARK = Color.parseColor("#0F1219");
    private static final int CARD_BG = Color.parseColor("#181C26");
    private static final int CARD_STROKE = Color.parseColor("#26FFFFFF");
    private static final int TEXT_PRIMARY = Color.parseColor("#F1F5F9");
    private static final int TEXT_MUTED = Color.parseColor("#94A3B8");
    private static final int ACCENT_GREEN = Color.parseColor("#34D399");
    private static final int ACCENT_RED = Color.parseColor("#F87171");
    private static final int ACCENT_BLUE = Color.parseColor("#38BDF8");
    private static final int INPUT_BG = Color.parseColor("#11151E");

    private AppConfig config;
    private TextView permStatusTv;
    private Button toggleOverlayBtn;
    private Button grantPermBtn;

    private RadioGroup modeGroup;
    private RadioButton rbHttps;
    private RadioButton rbTcp;

    private RadioGroup intervalGroup;
    private RadioButton rb2s;
    private RadioButton rb3s;
    private RadioButton rb5s;
    private RadioButton rb10s;

    private Switch defaultExpandedSwitch;
    private SeekBar opacitySeek;
    private TextView opacityLabel;

    private EditText googleUrlEt;
    private EditText cloudflareUrlEt;
    private EditText oracleUrlEt;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        config = AppConfig.load(this);
        setContentView(buildUi());
        bindConfigToUi();
        refreshStatusUi();
    }

    @Override
    protected void onResume() {
        super.onResume();
        config = AppConfig.load(this);
        bindConfigToUi();
        refreshStatusUi();
    }

    private View buildUi() {
        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(BG_DARK);
        scroll.setFillViewport(true);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(22), dp(16), dp(28));

        // Header
        TextView title = new TextView(this);
        title.setText("网络延迟悬浮窗");
        title.setTextColor(TEXT_PRIMARY);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("实时显示 Google / Cloudflare / Oracle 延迟（<800ms 绿色）与当前网络地域");
        subtitle.setTextColor(TEXT_MUTED);
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        LinearLayout.LayoutParams subLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        subLp.topMargin = dp(4);
        subLp.bottomMargin = dp(16);
        root.addView(subtitle, subLp);

        // Card 1: Control
        LinearLayout controlCard = createCard();
        permStatusTv = new TextView(this);
        permStatusTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        controlCard.addView(permStatusTv);

        grantPermBtn = createActionButton("前往开启「悬浮窗权限」", ACCENT_BLUE, Color.parseColor("#0B1120"));
        LinearLayout.LayoutParams grantLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(44));
        grantLp.topMargin = dp(10);
        grantPermBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openOverlayPermissionSettings();
            }
        });
        controlCard.addView(grantPermBtn, grantLp);

        toggleOverlayBtn = createActionButton("开启悬浮窗", ACCENT_GREEN, Color.parseColor("#052E16"));
        LinearLayout.LayoutParams toggleLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(46));
        toggleLp.topMargin = dp(10);
        toggleOverlayBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onToggleOverlayClicked();
            }
        });
        controlCard.addView(toggleOverlayBtn, toggleLp);

        TextView tipTv = new TextView(this);
        tipTv.setText("提示：默认以超小胶囊仅显示当前地域（含健康状态灯），单击展开/收起延迟详情，手指拖动移动位置。");
        tipTv.setTextColor(TEXT_MUTED);
        tipTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        LinearLayout.LayoutParams tipLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        tipLp.topMargin = dp(10);
        controlCard.addView(tipTv, tipLp);

        root.addView(controlCard);

        // Card 2: Settings
        LinearLayout settingsCard = createCard();
        settingsCard.addView(createSectionTitle("显示与测速设置"));

        settingsCard.addView(createFieldLabel("测速模式"));
        modeGroup = new RadioGroup(this);
        modeGroup.setOrientation(RadioGroup.HORIZONTAL);
        rbHttps = createRadio("HTTPS (走代理/VPN)");
        rbTcp = createRadio("TCP (443)");
        modeGroup.addView(rbHttps);
        modeGroup.addView(rbTcp);
        settingsCard.addView(modeGroup);

        settingsCard.addView(createFieldLabel("刷新频率"));
        intervalGroup = new RadioGroup(this);
        intervalGroup.setOrientation(RadioGroup.HORIZONTAL);
        rb2s = createRadio("2秒");
        rb3s = createRadio("3秒");
        rb5s = createRadio("5秒");
        rb10s = createRadio("10秒");
        intervalGroup.addView(rb2s);
        intervalGroup.addView(rb3s);
        intervalGroup.addView(rb5s);
        intervalGroup.addView(rb10s);
        settingsCard.addView(intervalGroup);

        defaultExpandedSwitch = createSwitchRow("启动时默认展开延迟详情");
        settingsCard.addView(defaultExpandedSwitch);

        opacityLabel = createFieldLabel("窗口透明度：92%");
        settingsCard.addView(opacityLabel);

        opacitySeek = new SeekBar(this);
        opacitySeek.setMax(40); // 60% .. 100%
        opacitySeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                int pct = 60 + progress;
                opacityLabel.setText("窗口透明度：" + pct + "%");
            }

            @Override
            public void onStartTrackingTouch(SeekBar seekBar) {
            }

            @Override
            public void onStopTrackingTouch(SeekBar seekBar) {
            }
        });
        settingsCard.addView(opacitySeek);

        root.addView(settingsCard);

        // Card 3: Targets
        LinearLayout targetsCard = createCard();
        targetsCard.addView(createSectionTitle("自定义测速地址"));

        targetsCard.addView(createFieldLabel("Google"));
        googleUrlEt = createEditText();
        targetsCard.addView(googleUrlEt);

        targetsCard.addView(createFieldLabel("Cloudflare"));
        cloudflareUrlEt = createEditText();
        targetsCard.addView(cloudflareUrlEt);

        targetsCard.addView(createFieldLabel("Oracle（可改成你自己的 Oracle Cloud 地址）"));
        oracleUrlEt = createEditText();
        targetsCard.addView(oracleUrlEt);

        Button saveBtn = createActionButton("保存并应用设置", Color.parseColor("#2563EB"), TEXT_PRIMARY);
        LinearLayout.LayoutParams saveLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(44));
        saveLp.topMargin = dp(14);
        saveBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                saveSettingsFromUi();
                if (FloatingOverlayService.isRunning) {
                    startOverlayService(FloatingOverlayService.ACTION_RELOAD);
                }
                Toast.makeText(MainActivity.this, "设置已保存", Toast.LENGTH_SHORT).show();
            }
        });
        targetsCard.addView(saveBtn, saveLp);

        root.addView(targetsCard);

        scroll.addView(root);
        return scroll;
    }

    private void bindConfigToUi() {
        if ("TCP".equalsIgnoreCase(config.mode)) {
            rbTcp.setChecked(true);
        } else {
            rbHttps.setChecked(true);
        }

        if (config.intervalMs <= 2000) {
            rb2s.setChecked(true);
        } else if (config.intervalMs <= 3000) {
            rb3s.setChecked(true);
        } else if (config.intervalMs <= 5000) {
            rb5s.setChecked(true);
        } else {
            rb10s.setChecked(true);
        }

        defaultExpandedSwitch.setChecked(config.defaultExpanded);

        int pct = Math.max(60, Math.min(100, Math.round(config.opacity * 100f)));
        opacitySeek.setProgress(pct - 60);
        opacityLabel.setText("窗口透明度：" + pct + "%");

        googleUrlEt.setText(config.googleUrl);
        cloudflareUrlEt.setText(config.cloudflareUrl);
        oracleUrlEt.setText(config.oracleUrl);
    }

    private void saveSettingsFromUi() {
        config.mode = rbTcp.isChecked() ? "TCP" : "HTTPS";
        if (rb2s.isChecked()) config.intervalMs = 2000;
        else if (rb3s.isChecked()) config.intervalMs = 3000;
        else if (rb5s.isChecked()) config.intervalMs = 5000;
        else config.intervalMs = 10000;

        config.defaultExpanded = defaultExpandedSwitch.isChecked();
        config.showGeoLocation = true;
        config.opacity = (60 + opacitySeek.getProgress()) / 100f;

        config.googleUrl = googleUrlEt.getText().toString().trim();
        config.cloudflareUrl = cloudflareUrlEt.getText().toString().trim();
        config.oracleUrl = oracleUrlEt.getText().toString().trim();
        config.save(this);
    }

    private void refreshStatusUi() {
        boolean hasOverlay = Settings.canDrawOverlays(this);
        if (hasOverlay) {
            permStatusTv.setText(FloatingOverlayService.isRunning
                    ? "状态：悬浮窗权限已授予 · 运行中"
                    : "状态：悬浮窗权限已授予 · 未开启");
            permStatusTv.setTextColor(ACCENT_GREEN);
            grantPermBtn.setVisibility(View.GONE);
        } else {
            permStatusTv.setText("状态：尚未授予「在其他应用上层显示」权限");
            permStatusTv.setTextColor(ACCENT_RED);
            grantPermBtn.setVisibility(View.VISIBLE);
        }

        if (FloatingOverlayService.isRunning) {
            toggleOverlayBtn.setText("关闭悬浮窗");
            toggleOverlayBtn.setBackground(createButtonBg(ACCENT_RED));
            toggleOverlayBtn.setTextColor(Color.parseColor("#450A0A"));
        } else {
            toggleOverlayBtn.setText("开启悬浮窗");
            toggleOverlayBtn.setBackground(createButtonBg(ACCENT_GREEN));
            toggleOverlayBtn.setTextColor(Color.parseColor("#052E16"));
        }
    }

    private void onToggleOverlayClicked() {
        if (FloatingOverlayService.isRunning) {
            Intent stopIntent = new Intent(this, FloatingOverlayService.class);
            stopIntent.setAction(FloatingOverlayService.ACTION_STOP);
            startService(stopIntent);
            toggleOverlayBtn.postDelayed(new Runnable() {
                @Override
                public void run() {
                    refreshStatusUi();
                }
            }, 250);
            return;
        }

        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "请先授予悬浮窗权限", Toast.LENGTH_SHORT).show();
            openOverlayPermissionSettings();
            return;
        }

        requestNotificationPermissionIfNeeded();
        saveSettingsFromUi();
        startOverlayService(FloatingOverlayService.ACTION_START);
        toggleOverlayBtn.postDelayed(new Runnable() {
            @Override
            public void run() {
                refreshStatusUi();
            }
        }, 300);
    }

    private void startOverlayService(String action) {
        Intent intent = new Intent(this, FloatingOverlayService.class);
        intent.setAction(action);
        startForegroundService(intent);
    }

    private void openOverlayPermissionSettings() {
        Intent intent = new Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + getPackageName())
        );
        startActivity(intent);
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIF_PERM);
            }
        }
    }

    private LinearLayout createCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(14), dp(14), dp(14));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(CARD_BG);
        bg.setCornerRadius(dp(14));
        bg.setStroke(dp(1), CARD_STROKE);
        card.setBackground(bg);

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(14);
        card.setLayoutParams(lp);
        return card;
    }

    private TextView createSectionTitle(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextColor(TEXT_PRIMARY);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(6);
        tv.setLayoutParams(lp);
        return tv;
    }

    private TextView createFieldLabel(String text) {
        TextView tv = new TextView(this);
        tv.setText(text);
        tv.setTextColor(TEXT_MUTED);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(10);
        lp.bottomMargin = dp(4);
        tv.setLayoutParams(lp);
        return tv;
    }

    private RadioButton createRadio(String label) {
        RadioButton rb = new RadioButton(this);
        rb.setText(label);
        rb.setTextColor(TEXT_PRIMARY);
        rb.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        rb.setPadding(dp(2), 0, dp(10), 0);
        return rb;
    }

    private Switch createSwitchRow(String label) {
        Switch sw = new Switch(this);
        sw.setText(label);
        sw.setTextColor(TEXT_PRIMARY);
        sw.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(10);
        sw.setLayoutParams(lp);
        return sw;
    }

    private EditText createEditText() {
        EditText et = new EditText(this);
        et.setTextColor(TEXT_PRIMARY);
        et.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f);
        et.setSingleLine(true);
        et.setPadding(dp(10), dp(8), dp(10), dp(8));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(INPUT_BG);
        bg.setCornerRadius(dp(8));
        bg.setStroke(dp(1), CARD_STROKE);
        et.setBackground(bg);
        return et;
    }

    private Button createActionButton(String label, int bgColor, int textColor) {
        Button btn = new Button(this);
        btn.setText(label);
        btn.setTextColor(textColor);
        btn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f);
        btn.setTypeface(Typeface.DEFAULT_BOLD);
        btn.setAllCaps(false);
        btn.setGravity(Gravity.CENTER);
        btn.setBackground(createButtonBg(bgColor));
        return btn;
    }

    private GradientDrawable createButtonBg(int color) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(10));
        return d;
    }

    private int dp(int value) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics()));
    }
}
