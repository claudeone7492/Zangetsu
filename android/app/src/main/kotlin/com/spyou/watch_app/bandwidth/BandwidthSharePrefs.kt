package com.spyou.watch_app.bandwidth

import android.content.Context
import android.content.SharedPreferences

/**
 * The opt-in flag for bandwidth sharing, kept in plain SharedPreferences so the
 * boot receiver can read it with nothing but a Context (no Flutter engine, no
 * Hive, no DI). [ENABLED] is the user's own choice, written the moment they
 * accept the consent sheet or flip the Settings switch, and cleared the moment
 * they turn it off.
 *
 * [ANSWERED] records that the sheet has been shown and dismissed either way, so
 * it appears exactly once.
 */
object BandwidthSharePrefs {
    private const val FILE = "zangetsu_bandwidth_share"
    const val ENABLED = "enabled"
    const val ANSWERED = "answered_consent"

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(ENABLED, false)

    fun isAnswered(context: Context): Boolean =
        prefs(context).getBoolean(ANSWERED, false)

    // commit(), not apply(): the consent answer is written the instant the
    // sheet is dismissed, and a process killed right afterwards must still find
    // it on the next launch. apply() flushes asynchronously and can be lost.
    @Suppress("ApplySharedPref")
    fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(ENABLED, value).commit()
    }

    @Suppress("ApplySharedPref")
    fun setAnswered(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(ANSWERED, value).commit()
    }
}
