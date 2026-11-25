package com.example.situationship

import android.util.Log

class CupidNativeLlm {
    companion object {
        private const val TAG = "CupidNativeLlm"
        var isLibraryLoaded = false
            private set

        init {
            try {
                System.loadLibrary("cupid_llm")
                isLibraryLoaded = true
                Log.i(TAG, "Native library 'cupid_llm' successfully loaded.")
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "Native library 'cupid_llm' not found on current architecture/ABI: ${e.message}")
                isLibraryLoaded = false
            } catch (e: Exception) {
                Log.e(TAG, "Unexpected error loading 'cupid_llm': ${e.message}")
                isLibraryLoaded = false
            }
        }
    }

    interface TokenCallback {
        fun onToken(token: String)
        fun onComplete(totalTokens: Int, latencyMs: Long)
        fun onError(error: String)
    }

    external fun nativeIsRuntimeReady(): Boolean
    external fun nativeLoadModel(modelPath: String, contextLength: Int, threads: Int): Long
    external fun nativeStartInference(
        handle: Long,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        stopSequences: Array<String>,
        callback: TokenCallback
    ): Boolean
    external fun nativeCancelInference(handle: Long)
    external fun nativeUnloadModel(handle: Long)
}
