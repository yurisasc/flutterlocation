package com.lyokone.location;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.location.Location;
import android.util.Log;
import io.flutter.view.FlutterMain;
import com.google.android.gms.location.LocationResult;

import java.util.List;

public class BackgroundLocationBroadcastReceiver extends BroadcastReceiver {
    private static final String TAG = "BackgroundLocationBroadcastReceiver";

    static final String ACTION_PROCESS_UPDATES = "com.lyokone.location.BackgroundLocationBroadcastReceiver.ACTION_PROCESS_UPDATES";

    @Override
    public void onReceive(Context context, Intent intent) {
        FlutterMain.ensureInitializationComplete(context, null);
        if (intent != null) {
            final String action = intent.getAction();
            if (ACTION_PROCESS_UPDATES.equals(action)) {
                // long handlerRaw = intent.getLongExtra(LocationPlugin.HANDLER_KEY, 0L);
                LocationResult result = LocationResult.extractResult(intent);
                if (result != null) {
                    List<Location> locations = result.getLocations();
                    HeadlessPlugin headLess = new HeadlessPlugin(context);
                    headLess.handleNewBackgroundLocations(context, locations);
                    Log.i(TAG, locations.toString());
                }
            }
        }
    }
}