package com.nox1020.invest

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.security.MessageDigest

/**
 * Bank-withdrawal SMS → heads-up / full-screen notification that opens the
 * prefilled confirm sheet (or the sheet directly when the app is open).
 * The SMS text stays on the device: it only travels inside a local intent.
 * Nothing is logged.
 */
class SmsReceiver : BroadcastReceiver() {
    companion object {
        const val EXTRA_BODY = "invest_sms_body"
        const val EXTRA_ADDR = "invest_sms_addr"
        const val EXTRA_DATE = "invest_sms_date"
        const val EXTRA_FP = "invest_sms_fp"
        private const val CHANNEL = "bank_sms"
        private const val NATIVE = "invest_bank_sms_native"

        private val debit = Regex("برداشت|خرید|انتقال|کسر|پرداخت|[0-9۰-۹][0-9۰-۹,٬]*\\s*-|-\\s*[0-9۰-۹]")
        private val skip = Regex("رمز|کد\\s*(تایید|تأیید|یکبار|پویا)|otp", RegexOption.IGNORE_CASE)

        fun looksLikeWithdrawal(body: String) = debit.containsMatchIn(body) && !skip.containsMatchIn(body)

        fun fingerprint(addr: String, body: String): String {
            val d = MessageDigest.getInstance("SHA-1").digest("${addr.trim()}\n${body.trim()}".toByteArray(Charsets.UTF_8))
            return d.joinToString("") { "%02x".format(it) }
        }

        /** Native flag committed synchronously (null = never set here). */
        fun storedEnabled(ctx: Context): Boolean? {
            val p = ctx.getSharedPreferences(NATIVE, Context.MODE_PRIVATE)
            return if (p.contains("enabled")) p.getBoolean("enabled", false) else null
        }

        /** commit(): written to disk before returning, survives a process kill. */
        fun storeEnabled(ctx: Context, on: Boolean) {
            ctx.getSharedPreferences(NATIVE, Context.MODE_PRIVATE).edit().putBoolean("enabled", on).commit()
            ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
                .putBoolean("flutter.bank_sms_enabled", on).commit()
        }

        fun enabled(ctx: Context) = storedEnabled(ctx)
            ?: ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.bank_sms_enabled", false)

        fun readInbox(ctx: Context, since: Long): List<Map<String, Any>> {
            val out = mutableListOf<Map<String, Any>>()
            ctx.contentResolver.query(
                Uri.parse("content://sms/inbox"), arrayOf("address", "body", "date"),
                "date > ?", arrayOf(since.toString()), "date DESC"
            )?.use { c ->
                while (c.moveToNext() && out.size < 300) {
                    val body = c.getString(1) ?: continue
                    if (!looksLikeWithdrawal(body)) continue
                    out.add(mapOf("address" to (c.getString(0) ?: ""), "body" to body, "date" to c.getLong(2)))
                }
            }
            return out
        }

        fun takeRejected(ctx: Context): List<String> {
            val p = ctx.getSharedPreferences(NATIVE, Context.MODE_PRIVATE)
            val s = p.getStringSet("rejected", emptySet())!!.toList()
            p.edit().remove("rejected").apply()
            return s
        }

        /** Fingerprint only (no SMS text); commit() survives a process kill. */
        fun rememberHandled(ctx: Context, fp: String) {
            val p = ctx.getSharedPreferences(NATIVE, Context.MODE_PRIVATE)
            val s = HashSet(p.getStringSet("rejected", emptySet())!!)
            s.add(fp)
            p.edit().putStringSet("rejected", s).commit()
        }

        fun cancel(ctx: Context, fp: String) = NotificationManagerCompat.from(ctx).cancel(fp.hashCode())

        private fun notify(ctx: Context, addr: String, body: String, date: Long) {
            val fp = fingerprint(addr, body)
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(NotificationChannel(CHANNEL, "برداشت بانکی (پیامک)", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "پنجرهٔ ثبت برداشت هنگام دریافت پیامک بانک"
                })
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val open = Intent(ctx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(EXTRA_BODY, body); putExtra(EXTRA_ADDR, addr); putExtra(EXTRA_DATE, date)
            }
            val pi = PendingIntent.getActivity(ctx, fp.hashCode(), open, flags)
            val rej = Intent(ctx, SmsDismissReceiver::class.java).putExtra(EXTRA_FP, fp)
            val rpi = PendingIntent.getBroadcast(ctx, fp.hashCode(), rej, flags)
            val n = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("برداشت بانکی جدید")
                .setContentText("برای ثبت در برداشت‌ها لمس کنید")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .setFullScreenIntent(pi, true)
                .addAction(0, "ثبت", pi)
                .addAction(0, "رد", rpi)
                .build()
            try { NotificationManagerCompat.from(ctx).notify(fp.hashCode(), n) } catch (_: SecurityException) {}
        }
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!enabled(ctx)) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val addr = parts[0].originatingAddress ?: ""
        val body = parts.joinToString("") { it.messageBody ?: "" }
        val date = System.currentTimeMillis()
        if (!looksLikeWithdrawal(body)) return
        val ch = MainActivity.channel
        if (MainActivity.resumed && ch != null) {
            val sms = mapOf<String, Any>("address" to addr, "body" to body, "date" to date)
            Handler(Looper.getMainLooper()).post { ch.invokeMethod("smsArrived", sms) }
            return
        }
        notify(ctx, addr, body, date)
    }
}

/** «رد» on the notification: remembered so it is never offered again. */
class SmsDismissReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val fp = intent.getStringExtra(SmsReceiver.EXTRA_FP) ?: return
        val p = ctx.getSharedPreferences("invest_bank_sms_native", Context.MODE_PRIVATE)
        val s = HashSet(p.getStringSet("rejected", emptySet())!!)
        s.add(fp)
        p.edit().putStringSet("rejected", s).apply()
        SmsReceiver.cancel(ctx, fp)
    }
}
