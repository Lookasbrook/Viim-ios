package com.yamstack.viim

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.yamstack.viim.ui.ViimRoot
import com.yamstack.viim.ui.ViimTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { ViimTheme { ViimRoot() } }
    }
}
