package com.oddessentials.probe;

import android.app.Activity;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.webkit.ConsoleMessage;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import java.util.Collections;

/**
 * A verification tool, never shipped: loads the URL in the "url" extra in a WebView, registers the
 * agentGuild listener for that URL's origin, grants every permission the page asks for, and logs what
 * it sees under the AGPROBE tag.
 */
public class MainActivity extends Activity {
    private static final String TAG = "AGPROBE";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        String url = getIntent().getStringExtra("url");
        if (url == null) url = "http://127.0.0.1:8765/probe.html";
        Uri uri = Uri.parse(url);
        String origin = uri.getScheme() + "://" + uri.getHost() + (uri.getPort() > 0 ? ":" + uri.getPort() : "");

        WebView web = new WebView(this);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setMediaPlaybackRequiresUserGesture(false);
        WebView.setWebContentsDebuggingEnabled(true);

        boolean listener = WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER);
        Log.i(TAG, "webview=" + WebViewCompat.getCurrentWebViewPackage(this).versionName + " WEB_MESSAGE_LISTENER=" + listener + " origin=" + origin);
        if (listener) {
            WebViewCompat.addWebMessageListener(web, "agentGuild", Collections.singleton(origin),
                (view, message, sourceOrigin, isMainFrame, reply) ->
                    Log.i(TAG, "message main=" + isMainFrame + " from=" + sourceOrigin + " data=" + message.getData()));
        }
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage m) {
                Log.i(TAG, "console " + m.message());
                return true;
            }

            @Override
            public void onPermissionRequest(PermissionRequest request) {
                Log.i(TAG, "permission " + String.join(",", request.getResources()) + " from " + request.getOrigin());
                request.grant(request.getResources());
            }
        });
        setContentView(web);
        web.loadUrl(url);
    }
}
