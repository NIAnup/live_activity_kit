package com.nianup.live_activity_kit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LiveActivityActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        when (intent.action) {
            ACTION_TAP -> {
                val url = intent.getStringExtra(EXTRA_URL)
                LiveActivityKitPlugin.managerOrNull?.onTapped(id, url)
                if (!url.isNullOrEmpty()) {
                    val launch = Intent(Intent.ACTION_VIEW).apply {
                        data = android.net.Uri.parse(url)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        `package` = context.packageName
                    }
                    try {
                        context.startActivity(launch)
                    } catch (_: Exception) {
                        val launcher = context.packageManager.getLaunchIntentForPackage(context.packageName)
                        launcher?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        launcher?.data = android.net.Uri.parse(url)
                        if (launcher != null) context.startActivity(launcher)
                    }
                }
            }
            ACTION_DISMISS -> LiveActivityKitPlugin.managerOrNull?.onUserDismissed(id)
        }
    }

    companion object {
        const val ACTION_TAP = "com.nianup.live_activity_kit.TAP"
        const val ACTION_DISMISS = "com.nianup.live_activity_kit.DISMISS"
        const val EXTRA_ID = "id"
        const val EXTRA_URL = "url"
    }
}
