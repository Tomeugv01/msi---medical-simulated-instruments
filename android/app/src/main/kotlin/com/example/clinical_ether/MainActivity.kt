package com.example.clinical_ether

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val channelName = "msi_native_ptt"

    @Volatile
    private var pttRunning = false

    private var pttThread: Thread? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null

    private var previousAudioMode: Int = AudioManager.MODE_NORMAL
    private var previousSpeakerphoneOn: Boolean = false

    private val sampleRate = 16000

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPtt" -> {
                    val leftVolume = call.argument<Double>("leftVolume") ?: 1.0
                    startNativePtt(leftVolume, result)
                }

                "stopPtt" -> {
                    stopNativePtt()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startNativePtt(
        leftVolume: Double,
        result: MethodChannel.Result
    ) {
        if (pttRunning) {
            result.success(true)
            return
        }

        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error(
                "NO_MIC_PERMISSION",
                "RECORD_AUDIO permission is not granted",
                null
            )
            return
        }

        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            previousAudioMode = audioManager.mode
            previousSpeakerphoneOn = audioManager.isSpeakerphoneOn

            /*
             * Importante:
             * No usamos MODE_IN_COMMUNICATION.
             * No usamos USAGE_VOICE_COMMUNICATION.
             *
             * Esos modos pueden pasar Bluetooth a SCO/mono y romper la separación
             * izquierda/derecha que ya tienes funcionando para las pistas.
             */
            audioManager.mode = AudioManager.MODE_NORMAL
            audioManager.isSpeakerphoneOn = false

            val minRecordBuffer = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val minTrackBuffer = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val recordBufferBytes = max(minRecordBuffer, sampleRate)
            val trackBufferBytes = max(minTrackBuffer, sampleRate * 2)

            audioRecord = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                AudioRecord.Builder()
                    .setAudioSource(MediaRecorder.AudioSource.MIC)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(recordBufferBytes)
                    .build()
            } else {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    recordBufferBytes
                )
            }

            audioTrack = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build()
                    )
                    .setBufferSizeInBytes(trackBufferBytes)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
            } else {
                AudioTrack(
                    AudioManager.STREAM_MUSIC,
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_STEREO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    trackBufferBytes,
                    AudioTrack.MODE_STREAM
                )
            }

            val recorder = audioRecord
            val player = audioTrack

            if (recorder == null || player == null) {
                stopNativePtt()
                result.error("PTT_INIT_ERROR", "Could not create AudioRecord/AudioTrack", null)
                return
            }

            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                stopNativePtt()
                result.error("RECORDER_ERROR", "AudioRecord not initialized", null)
                return
            }

            if (player.state != AudioTrack.STATE_INITIALIZED) {
                stopNativePtt()
                result.error("PLAYER_ERROR", "AudioTrack not initialized", null)
                return
            }

            pttRunning = true

            pttThread = Thread {
                runPttLoop(leftVolume)
            }

            pttThread?.priority = Thread.MAX_PRIORITY
            pttThread?.start()

            result.success(true)
        } catch (e: Exception) {
            stopNativePtt()
            result.error("PTT_START_ERROR", e.message, null)
        }
    }

    private fun runPttLoop(leftVolume: Double) {
        val recorder = audioRecord ?: return
        val player = audioTrack ?: return

        val monoBuffer = ShortArray(1024)
        val stereoBuffer = ShortArray(monoBuffer.size * 2)

        try {
            recorder.startRecording()
            player.play()

            while (pttRunning && !Thread.currentThread().isInterrupted) {
                val read = recorder.read(monoBuffer, 0, monoBuffer.size)

                if (read > 0) {
                    for (i in 0 until read) {
                        val amplified = (monoBuffer[i] * leftVolume)
                            .roundToInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort()

                        val dst = i * 2

                        // Canal izquierdo: micrófono.
                        stereoBuffer[dst] = amplified

                        // Canal derecho: silencio absoluto.
                        stereoBuffer[dst + 1] = 0
                    }

                    player.write(
                        stereoBuffer,
                        0,
                        read * 2,
                        AudioTrack.WRITE_BLOCKING
                    )
                }
            }
        } catch (_: Exception) {
            // Al parar el PTT, recorder/player pueden lanzar excepciones normales
            // porque se están cerrando desde otro hilo.
        }
    }

    private fun stopNativePtt() {
        pttRunning = false

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }

        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
        } catch (_: Exception) {
        }

        try {
            pttThread?.interrupt()
            pttThread?.join(500)
        } catch (_: Exception) {
        }

        pttThread = null

        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }

        try {
            audioTrack?.release()
        } catch (_: Exception) {
        }

        audioRecord = null
        audioTrack = null

        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.mode = previousAudioMode
            audioManager.isSpeakerphoneOn = previousSpeakerphoneOn
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        stopNativePtt()
        super.onDestroy()
    }
}