package com.lyokone.location;

import android.Manifest;
import android.app.Activity;
import android.provider.Settings;
import android.content.IntentSender;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationManager;
import android.location.OnNmeaMessageListener;
import android.content.Context;
import android.os.Build;
import android.os.Looper;
import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import android.util.Log;
import android.annotation.TargetApi;
import android.app.PendingIntent;
import android.content.SharedPreferences;

import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.Status;

import com.google.android.gms.common.api.ResolvableApiException;
import com.google.android.gms.location.FusedLocationProviderClient;
import com.google.android.gms.location.LocationCallback;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationSettingsRequest;
import com.google.android.gms.location.LocationSettingsResponse;
import com.google.android.gms.location.LocationSettingsStatusCodes;
import com.google.android.gms.location.SettingsClient;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.LocationServices;
import com.google.android.gms.tasks.OnSuccessListener;
import com.google.android.gms.tasks.OnFailureListener;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.EventChannel.StreamHandler;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener;
import io.flutter.view.FlutterCallbackInformation;
import io.flutter.view.FlutterMain;
import io.flutter.view.FlutterNativeView;
import io.flutter.view.FlutterRunArguments;

/**
 * HeadlessPlugin
 */
public class HeadlessPlugin implements MethodCallHandler {
    private static final String STREAM_CHANNEL_NAME = "lyokone/locationstream";
    private static final String METHOD_CHANNEL_NAME = "lyokone/location";

    private static final int REQUEST_PERMISSIONS_REQUEST_CODE = 34;
    private static final int REQUEST_CHECK_SETTINGS = 0x1;
    private static final int GPS_ENABLE_REQUEST = 0x1001;

    private static final String TAG = "FlutterLocation";

    final static String HANDLER_KEY = "background_location_handler";
    final static String CALLBACK_KEY = "background_location_callback";

    private static ArrayDeque<List<Object>> queue = new ArrayDeque<List<Object>>();

    private static LocationRequest mLocationRequest;
    private LocationSettingsRequest mLocationSettingsRequest;
    private LocationCallback mLocationCallback;
    private PluginRegistry.RequestPermissionsResultListener mPermissionsResultListener;

    private EventChannel backgroundChannel; 

    @TargetApi(Build.VERSION_CODES.N)
    private OnNmeaMessageListener mMessageListener;

    private static Double mLastMslAltitude;

    // Parameters of the request
    private static long update_interval_in_milliseconds = 5000;
    private static long fastest_update_interval_in_milliseconds = update_interval_in_milliseconds / 2;
    private static Integer location_accuray = LocationRequest.PRIORITY_HIGH_ACCURACY;
    private static float distanceFilter = 0f;


    private static MethodChannel channel;
    private static MethodChannel mBackgroundChannel;
    private static PluginRegistry.PluginRegistrantCallback mPluginRegistrantCallback;

    private EventSink events;
    private Result result;

    private int locationPermissionState;

    private boolean waitingForPermission = false;
    private LocationManager locationManager;

    private Context mContext;

    private HashMap<Integer, Integer> mapFlutterAccuracy = new HashMap<>();

    private static FlutterNativeView mFlutterNativeView;

    private static final AtomicBoolean mSynchronizer = new AtomicBoolean(false);

    HeadlessPlugin(Context context) {
        this.mContext = context;
        if (mFlutterNativeView == null) {
            initFlutterNativeView();
        }
        synchronized(mSynchronizer) {
            if (!mSynchronizer.get()) {
                // Queue up events while background isolate is starting
                Log.d(TAG, "Waiting for Flutter Native View");
                return;
            }
        }
    }

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        HeadlessPlugin locationWithMethodChannel = new HeadlessPlugin(registrar.context());
    }

    @Override
    public void onMethodCall(MethodCall call, final Result result) {
        result.notImplemented();   
    }

    // Called by Application#onCreate
    static void setPluginRegistrant(PluginRegistry.PluginRegistrantCallback callback) {
        Log.i(TAG, "PluginRegistrantCallback");
        mPluginRegistrantCallback = callback;
    }


    public static HashMap<String, Double> locationToHash(Location location) {
        HashMap<String, Double> loc = new HashMap<>();
        loc.put("latitude", location.getLatitude());
        loc.put("longitude", location.getLongitude());
        loc.put("accuracy", (double) location.getAccuracy());

        // Using NMEA Data to get MSL level altitude
        if (mLastMslAltitude == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            loc.put("altitude", location.getAltitude());
        } else {
            loc.put("altitude", mLastMslAltitude);
        }

        loc.put("speed", (double) location.getSpeed());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            loc.put("speed_accuracy", (double) location.getSpeedAccuracyMetersPerSecond());
        }
        loc.put("heading", (double) location.getBearing());
        loc.put("time", (double) location.getTime());

        return loc;
    }

    public void handleNewBackgroundLocations(Context context, List<Location> locations) {
        //TODO queue if not ready queue.add(locations);

        List<HashMap<String, Double>> res = new ArrayList<>();

        for (Location location: locations) {
            res.add(locationToHash(location));
        }
        
        SharedPreferences prefs = context.getSharedPreferences(TAG, Context.MODE_PRIVATE);
        Long mCallbackHandle = prefs.getLong(CALLBACK_KEY, -1);

        List<Object> result = Arrays.asList(mCallbackHandle, res);
        Log.i("FlutterLocation", "Trying to send result to host");

        if (mBackgroundChannel != null) {
            mBackgroundChannel.invokeMethod("", result);
        } else {
            Log.i(TAG, "No channel :'('");
            this.initFlutterNativeView();
        }
    }

    private void initFlutterNativeView() {
        FlutterMain.ensureInitializationComplete(mContext, null);

        SharedPreferences prefs = mContext.getSharedPreferences(TAG, Context.MODE_PRIVATE);
        Long mCallbackHandle = prefs.getLong(HANDLER_KEY, -1);

        FlutterCallbackInformation callbackInfo = FlutterCallbackInformation
                .lookupCallbackInformation(mCallbackHandle);

        Log.i(TAG, "callbackInfo: " + callbackInfo.callbackClassName +  " " + callbackInfo.callbackName + " " + callbackInfo.callbackLibraryPath) ;

        if (callbackInfo == null) {
            Log.e(TAG, "Fatal: failed to find callback");
            return;
        }

        mFlutterNativeView = new FlutterNativeView(mContext.getApplicationContext(), true);

        // Create the Transmitter channel
        mBackgroundChannel = new MethodChannel(mFlutterNativeView, METHOD_CHANNEL_NAME);
        mBackgroundChannel.setMethodCallHandler(this);

        if (mPluginRegistrantCallback == null) {
            return;
        }
        mPluginRegistrantCallback.registerWith(mFlutterNativeView.getPluginRegistry());

        // Dispatch back to client for initialization.
        FlutterRunArguments args = new FlutterRunArguments();
        args.bundlePath = FlutterMain.findAppBundlePath(mContext);
        args.entrypoint = callbackInfo.callbackName;
        args.libraryPath = callbackInfo.callbackLibraryPath;
        mFlutterNativeView.runFromBundle(args);
        mSynchronizer.set(true);
    }
}
