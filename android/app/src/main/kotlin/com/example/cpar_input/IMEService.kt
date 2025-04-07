package com.example.cpar_input

import android.inputmethodservice.InputMethodService
import android.view.inputmethod.InputConnection

class IMEService : InputMethodService() {
    override fun onCreateInputView(): android.view.View {
        return android.view.LayoutInflater.from(this).inflate(
            resources.getIdentifier("keyboard", "layout", packageName),
            null
        )
    }
}