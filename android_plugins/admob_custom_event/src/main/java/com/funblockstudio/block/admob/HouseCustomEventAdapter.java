package com.funblockstudio.block.admob;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.VersionInfo;
import com.google.android.gms.ads.mediation.Adapter;
import com.google.android.gms.ads.mediation.InitializationCompleteCallback;
import com.google.android.gms.ads.mediation.MediationAdLoadCallback;
import com.google.android.gms.ads.mediation.MediationConfiguration;
import com.google.android.gms.ads.mediation.MediationInterstitialAd;
import com.google.android.gms.ads.mediation.MediationInterstitialAdCallback;
import com.google.android.gms.ads.mediation.MediationInterstitialAdConfiguration;

import java.util.List;

/**
 * Self-owned custom event used to validate the AdMob Next-Gen custom-event
 * waterfall without a third-party SDK. Replace the HouseInterstitialAd body
 * with the real network SDK when one is selected.
 *
 * AdMob class name:
 *   com.funblockstudio.block.admob.HouseCustomEventAdapter
 * AdMob parameter:
 *   house-test (the adapter also accepts any optional label)
 */
public final class HouseCustomEventAdapter extends Adapter {
    private static final String DOMAIN = "block_house_custom_event";
    private static final String DEFAULT_PARAMETER = "house-test";
    private static final int ERROR_LOAD = 1001;
    private static final int ERROR_SHOW = 1002;
    private static final VersionInfo VERSION = new VersionInfo(1, 0, 0);

    @Override
    public void initialize(
            Context context,
            InitializationCompleteCallback callback,
            List<MediationConfiguration> configurations) {
        callback.onInitializationSucceeded();
    }

    @Override
    public VersionInfo getVersionInfo() {
        return VERSION;
    }

    @Override
    public VersionInfo getSDKVersionInfo() {
        return VERSION;
    }

    @Override
    public void loadInterstitialAd(
            MediationInterstitialAdConfiguration configuration,
            MediationAdLoadCallback<MediationInterstitialAd, MediationInterstitialAdCallback> callback) {
        String parameter = DEFAULT_PARAMETER;
        Bundle serverParameters = configuration.getServerParameters();
        if (serverParameters != null) {
            String configured = serverParameters.getString(
                    MediationConfiguration.CUSTOM_EVENT_SERVER_PARAMETER_FIELD);
            if (configured != null && !configured.trim().isEmpty()) {
                parameter = configured.trim();
            }
        }
        HouseInterstitialAd ad = new HouseInterstitialAd(configuration.getContext(), parameter, callback);
        new Handler(Looper.getMainLooper()).postDelayed(ad::load, 150L);
    }

    private static final class HouseInterstitialAd implements MediationInterstitialAd {
        private final Context context;
        private final String parameter;
        private final MediationAdLoadCallback<MediationInterstitialAd, MediationInterstitialAdCallback> loadCallback;
        private MediationInterstitialAdCallback adCallback;
        private Dialog dialog;
        private boolean dismissed;

        HouseInterstitialAd(
                Context context,
                String parameter,
                MediationAdLoadCallback<MediationInterstitialAd, MediationInterstitialAdCallback> loadCallback) {
            this.context = context;
            this.parameter = parameter;
            this.loadCallback = loadCallback;
        }

        void load() {
            if (!(context instanceof Activity)) {
                loadCallback.onFailure(new AdError(
                        ERROR_LOAD, DOMAIN, "House custom event requires an Activity context"));
                return;
            }
            adCallback = loadCallback.onSuccess(this);
        }

        @Override
        public void showAd(Context showContext) {
            new Handler(Looper.getMainLooper()).post(() -> showOnMainThread(showContext));
        }

        private void showOnMainThread(Context showContext) {
            if (dialog != null || dismissed) {
                return;
            }
            Context baseContext = showContext instanceof Activity ? showContext : context;
            if (!(baseContext instanceof Activity)) {
                failShow("House custom event requires an Activity context");
                return;
            }
            Activity activity = (Activity) baseContext;
            if (activity.isFinishing() || activity.isDestroyed()) {
                failShow("House custom event host Activity is not available");
                return;
            }
            dialog = new Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen);
            dialog.setCancelable(false);
            dialog.setContentView(buildContentView(activity));
            Window window = dialog.getWindow();
            if (window != null) {
                window.setBackgroundDrawable(new ColorDrawable(Color.BLACK));
                window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            }
            dialog.setOnShowListener(ignored -> {
                if (adCallback != null) {
                    adCallback.reportAdImpression();
                    adCallback.onAdOpened();
                }
            });
            dialog.setOnDismissListener(ignored -> {
                dialog = null;
                if (!dismissed) {
                    dismissed = true;
                    if (adCallback != null) {
                        adCallback.onAdClosed();
                    }
                }
            });
            dialog.show();
        }

        private LinearLayout buildContentView(Activity activity) {
            LinearLayout layout = new LinearLayout(activity);
            layout.setOrientation(LinearLayout.VERTICAL);
            layout.setGravity(Gravity.CENTER);
            layout.setBackgroundColor(Color.BLACK);
            int padding = (int) (24 * activity.getResources().getDisplayMetrics().density);
            layout.setPadding(padding, padding, padding, padding);

            TextView title = new TextView(activity);
            title.setText("自定义事件测试广告\nHouse custom event ad");
            title.setTextColor(Color.WHITE);
            title.setTextSize(24);
            title.setGravity(Gravity.CENTER);
            layout.addView(title, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

            TextView detail = new TextView(activity);
            detail.setText("Class: HouseCustomEventAdapter\nParameter: " + parameter
                    + "\n\n这是用于验证 AdMob 自定义事件链路的自有测试广告。");
            detail.setTextColor(Color.LTGRAY);
            detail.setTextSize(16);
            detail.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams detailParams = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            detailParams.topMargin = padding;
            layout.addView(detail, detailParams);

            Button close = new Button(activity);
            close.setText("关闭广告 / Close ad");
            close.setGravity(Gravity.CENTER);
            LinearLayout.LayoutParams closeParams = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            closeParams.topMargin = padding * 2;
            close.setOnClickListener(ignored -> {
                if (dialog != null) {
                    dialog.dismiss();
                }
            });
            layout.addView(close, closeParams);
            return layout;
        }

        private void failShow(String message) {
            if (adCallback != null) {
                adCallback.onAdFailedToShow(new AdError(ERROR_SHOW, DOMAIN, message));
            }
        }
    }
}
