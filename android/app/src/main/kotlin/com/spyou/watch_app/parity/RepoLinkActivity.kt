package com.spyou.watch_app.parity

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.spyou.watch_app.MainActivity

/** Receives `http(s)://…json` and `stremio:` links and hands them to the app. */
class RepoLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val data = intent?.data?.toString()
        if (!data.isNullOrBlank()) {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    putExtra(EXTRA_REPO_URL, data)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
            )
        }
        finish()
    }

    companion object {
        const val EXTRA_REPO_URL = "zangetsu.repo.url"
    }
}
