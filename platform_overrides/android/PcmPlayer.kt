package __PACKAGE__

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit

/**
 * Reproduz o som PCM 16-bit que chega do Host.
 * Junta [delayMs] de som antes de começar, para acertar com o vídeo
 * (que chega um pouco atrasado por ser descodificado).
 */
class PcmPlayer(private val rate: Int, channels: Int, private val delayMs: Int) {
    private val channelMask =
        if (channels >= 2) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
    private val bytesPerSecond = rate * (if (channels >= 2) 2 else 1) * 2
    private val queue = LinkedBlockingDeque<ByteArray>()
    @Volatile private var queuedBytes = 0
    @Volatile private var running = true
    private var track: AudioTrack? = null
    private val thread = Thread({ loop() }, "partilhaecra-audio")

    init {
        val minBuffer = AudioTrack.getMinBufferSize(rate, channelMask, AudioFormat.ENCODING_PCM_16BIT)
        val bufferSize = maxOf(minBuffer, bytesPerSecond / 10)
        track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(rate)
                    .setChannelMask(channelMask)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        thread.start()
    }

    fun write(data: ByteArray) {
        if (!running) return
        queue.offer(data)
        queuedBytes += data.size
        // Nunca deixa acumular mais de ~1 s de atraso (rede lenta, etc.).
        while (queuedBytes > bytesPerSecond + bytesPerSecond * delayMs / 1000) {
            val dropped = queue.pollFirst() ?: break
            queuedBytes -= dropped.size
        }
    }

    private fun loop() {
        val t = track ?: return
        // Espera até ter o atraso pedido em memória antes de começar a tocar.
        val prefill = bytesPerSecond * delayMs / 1000
        while (running && queuedBytes < prefill) {
            Thread.sleep(5)
        }
        t.play()
        while (running) {
            val chunk = queue.poll(200, TimeUnit.MILLISECONDS) ?: continue
            queuedBytes -= chunk.size
            t.write(chunk, 0, chunk.size)
        }
    }

    fun stop() {
        running = false
        try {
            thread.join(500)
        } catch (_: InterruptedException) {
        }
        track?.let {
            try {
                it.pause()
                it.flush()
                it.release()
            } catch (_: Throwable) {
            }
        }
        track = null
        queue.clear()
    }
}
