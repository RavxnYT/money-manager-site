package com.ravxn.moneymanagement

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge-to-edge on Android 15+; no-op on older versions where not applicable.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
