#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <chrono>
#include <memory>
#include <android/log.h>

#define TAG "CupidNativeLlm"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

#if defined(HAS_LLAMA_CPP) || __has_include("llama.h")
#define LLAMA_SUPPORTED 1
#include "llama.h"
#else
#define LLAMA_SUPPORTED 0
#endif

struct CupidLlmContext {
    std::string modelPath;
    int contextLength = 2048;
    int threads = 4;
    std::atomic<bool> isCancelled{false};
    std::atomic<bool> isGenerating{false};

#if LLAMA_SUPPORTED
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
#endif

    ~CupidLlmContext() {
#if LLAMA_SUPPORTED
        if (ctx) {
            llama_free(ctx);
            ctx = nullptr;
        }
        if (model) {
            llama_model_free(model);
            model = nullptr;
        }
#endif
    }
};

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_example_situationship_CupidNativeLlm_nativeIsRuntimeReady(
    JNIEnv* env,
    jobject /* this */) {
#if LLAMA_SUPPORTED
    return JNI_TRUE;
#else
    return JNI_FALSE;
#endif
}

JNIEXPORT jlong JNICALL
Java_com_example_situationship_CupidNativeLlm_nativeLoadModel(
    JNIEnv* env,
    jobject /* this */,
    jstring jModelPath,
    jint contextLength,
    jint threads) {

    if (!jModelPath) {
        LOGE("nativeLoadModel: null model path provided");
        return 0;
    }

    const char* pathChars = env->GetStringUTFChars(jModelPath, nullptr);
    std::string modelPath(pathChars);
    env->ReleaseStringUTFChars(jModelPath, pathChars);

    LOGI("Loading model from: %s (ctx: %d, threads: %d)", modelPath.c_str(), contextLength, threads);

    auto cupidCtx = std::make_unique<CupidLlmContext>();
    cupidCtx->modelPath = modelPath;
    cupidCtx->contextLength = contextLength;
    cupidCtx->threads = threads > 0 ? threads : 4;

#if LLAMA_SUPPORTED
    llama_backend_init();

    llama_model_params model_params = llama_model_default_params();
    cupidCtx->model = llama_model_load_from_file(modelPath.c_str(), model_params);
    if (!cupidCtx->model) {
        LOGE("Failed to load llama model from: %s", modelPath.c_str());
        return 0;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = contextLength > 0 ? contextLength : 2048;
    ctx_params.n_threads = cupidCtx->threads;
    ctx_params.n_threads_batch = cupidCtx->threads;

    cupidCtx->ctx = llama_init_from_model(cupidCtx->model, ctx_params);
    if (!cupidCtx->ctx) {
        LOGE("Failed to create llama context from model");
        return 0;
    }

    LOGI("Model successfully loaded into memory!");
#else
    LOGW("Compiled without direct llama.cpp source. Modular native stub active.");
#endif

    return reinterpret_cast<jlong>(cupidCtx.release());
}

JNIEXPORT jboolean JNICALL
Java_com_example_situationship_CupidNativeLlm_nativeStartInference(
    JNIEnv* env,
    jobject /* this */,
    jlong handle,
    jstring jPrompt,
    jint maxTokens,
    jfloat temperature,
    jobjectArray jStopSequences,
    jobject jCallback) {

    if (!handle) {
        LOGE("nativeStartInference: invalid model handle");
        return JNI_FALSE;
    }

    auto cupidCtx = reinterpret_cast<CupidLlmContext*>(handle);
    if (cupidCtx->isGenerating.exchange(true)) {
        LOGW("nativeStartInference: inference already in progress on this context");
        return JNI_FALSE;
    }
    cupidCtx->isCancelled = false;

    // Resolve callback methods
    jclass callbackClass = env->GetObjectClass(jCallback);
    jmethodID onTokenMethod = env->GetMethodID(callbackClass, "onToken", "(Ljava/lang/String;)V");
    jmethodID onCompleteMethod = env->GetMethodID(callbackClass, "onComplete", "(IJ)V");
    jmethodID onErrorMethod = env->GetMethodID(callbackClass, "onError", "(Ljava/lang/String;)V");

    if (!onTokenMethod || !onCompleteMethod || !onErrorMethod) {
        LOGE("nativeStartInference: callback methods not resolved");
        cupidCtx->isGenerating = false;
        return JNI_FALSE;
    }

    const char* promptChars = env->GetStringUTFChars(jPrompt, nullptr);
    std::string prompt(promptChars);
    env->ReleaseStringUTFChars(jPrompt, promptChars);

    // Extract stop sequences
    std::vector<std::string> stopSequences;
    if (jStopSequences) {
        jsize count = env->GetArrayLength(jStopSequences);
        for (jsize i = 0; i < count; ++i) {
            auto jStr = (jstring)env->GetObjectArrayElement(jStopSequences, i);
            if (jStr) {
                const char* s = env->GetStringUTFChars(jStr, nullptr);
                stopSequences.emplace_back(s);
                env->ReleaseStringUTFChars(jStr, s);
                env->DeleteLocalRef(jStr);
            }
        }
    }

    auto startTime = std::chrono::steady_clock::now();
    int generatedTokens = 0;

#if LLAMA_SUPPORTED
    try {
        const struct llama_vocab* vocab = llama_model_get_vocab(cupidCtx->model);
        std::vector<llama_token> tokens;
        tokens.resize(prompt.size() + 16);
        int n_tokens = llama_tokenize(vocab, prompt.c_str(), prompt.length(), tokens.data(), tokens.size(), true, false);
        if (n_tokens < 0) {
            tokens.resize(-n_tokens);
            n_tokens = llama_tokenize(vocab, prompt.c_str(), prompt.length(), tokens.data(), tokens.size(), true, false);
        }
        tokens.resize(n_tokens);

        llama_batch batch = llama_batch_get_one(tokens.data(), tokens.size());

        if (llama_decode(cupidCtx->ctx, batch) != 0) {
            jstring errStr = env->NewStringUTF("llama_decode failed on prompt eval");
            env->CallVoidMethod(jCallback, onErrorMethod, errStr);
            env->DeleteLocalRef(errStr);
            cupidCtx->isGenerating = false;
            return JNI_FALSE;
        }

        // Sampling loop
        llama_sampler* smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature > 0.0f ? temperature : 0.7f));
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

        std::string accumulatedText;

        for (int i = 0; i < maxTokens; ++i) {
            if (cupidCtx->isCancelled.load()) {
                LOGI("Inference cancelled by user at token %d", i);
                break;
            }

            llama_token new_token = llama_sampler_sample(smpl, cupidCtx->ctx, -1);
            if (llama_vocab_is_eog(vocab, new_token)) {
                break;
            }

            char buf[128];
            int n_piece = llama_token_to_piece(vocab, new_token, buf, sizeof(buf), 0, true);
            if (n_piece > 0) {
                std::string piece(buf, n_piece);
                accumulatedText += piece;

                // Check stop sequences
                bool hitStop = false;
                for (const auto& stop : stopSequences) {
                    if (accumulatedText.find(stop) != std::string::npos) {
                        hitStop = true;
                        break;
                    }
                }
                if (hitStop) break;

                // Stream token to callback
                jstring jPiece = env->NewStringUTF(piece.c_str());
                env->CallVoidMethod(jCallback, onTokenMethod, jPiece);
                env->DeleteLocalRef(jPiece);
                generatedTokens++;
            }

            batch = llama_batch_get_one(&new_token, 1);
            if (llama_decode(cupidCtx->ctx, batch) != 0) {
                break;
            }
        }

        llama_sampler_free(smpl);

    } catch (const std::exception& ex) {
        LOGE("Exception during native inference: %s", ex.what());
        jstring errStr = env->NewStringUTF(ex.what());
        env->CallVoidMethod(jCallback, onErrorMethod, errStr);
        env->DeleteLocalRef(errStr);
        cupidCtx->isGenerating = false;
        return JNI_FALSE;
    }
#else
    // Modular execution fallback when full C++ source is not compiled
    std::string fallbackReply = "I hear you! I am ready to help you meet great people once the on-device model weights are loaded.";
    jstring jToken = env->NewStringUTF(fallbackReply.c_str());
    env->CallVoidMethod(jCallback, onTokenMethod, jToken);
    env->DeleteLocalRef(jToken);
    generatedTokens = 1;
#endif

    auto endTime = std::chrono::steady_clock::now();
    long latencyMs = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();

    env->CallVoidMethod(jCallback, onCompleteMethod, generatedTokens, (jlong)latencyMs);
    cupidCtx->isGenerating = false;
    return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_example_situationship_CupidNativeLlm_nativeCancelInference(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle) {
    if (handle) {
        auto cupidCtx = reinterpret_cast<CupidLlmContext*>(handle);
        cupidCtx->isCancelled = true;
        LOGI("nativeCancelInference called for handle %lld", (long long)handle);
    }
}

JNIEXPORT void JNICALL
Java_com_example_situationship_CupidNativeLlm_nativeUnloadModel(
    JNIEnv* /* env */,
    jobject /* this */,
    jlong handle) {
    if (handle) {
        auto cupidCtx = reinterpret_cast<CupidLlmContext*>(handle);
        LOGI("Unloading model for handle %lld", (long long)handle);
        delete cupidCtx;
    }
}

} // extern "C"
