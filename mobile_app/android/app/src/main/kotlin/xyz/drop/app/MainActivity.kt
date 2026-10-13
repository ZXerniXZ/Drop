package xyz.drop.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 forza l'edge-to-edge se targetSdk >= 35. enableEdgeToEdge()
        // allinea anche le versioni precedenti. Gli inset restano su MediaQuery:
        // le schermate li consumano con SafeArea, senza un secondo padding nativo.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
    }
}
