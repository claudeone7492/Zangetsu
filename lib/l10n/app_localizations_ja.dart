// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get cancel => 'キャンセル';

  @override
  String get ok => 'わかりました';

  @override
  String get save => '保存';

  @override
  String get saved => '保存しました';

  @override
  String get close => '閉じる';

  @override
  String get retry => '再試行';

  @override
  String get search => '検索';

  @override
  String get searchAllSources => 'すべてのソースを検索';

  @override
  String get searchForThisTitle => 'このタイトルを検索しますか？';

  @override
  String get off => 'オフ';

  @override
  String get on => 'オン';

  @override
  String get done => '完了';

  @override
  String get next => '次へ';

  @override
  String get back => '戻る';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get share => '共有';

  @override
  String get comments => 'コメント';

  @override
  String get copy => 'コピー';

  @override
  String get play => '再生';

  @override
  String get pause => '一時停止';

  @override
  String get yes => 'はい';

  @override
  String get no => 'いいえ';

  @override
  String get all => 'すべて';

  @override
  String get none => 'なし';

  @override
  String get auto => 'オート';

  @override
  String get add => '追加';

  @override
  String get remove => '解除';

  @override
  String get install => 'インストール';

  @override
  String get uninstall => 'アンインストール';

  @override
  String get reset => 'リセット';

  @override
  String get clear => 'クリア';

  @override
  String get resume => '再開';

  @override
  String get download => 'ダウンロード';

  @override
  String get update => '更新';

  @override
  String get apply => '適用';

  @override
  String get enable => '有効にする';

  @override
  String get create => '作成';

  @override
  String get rename => '名前を変更';

  @override
  String get move => '移動';

  @override
  String get join => '参加';

  @override
  String get leave => '退出';

  @override
  String get skip => 'スキップ';

  @override
  String get later => '後で';

  @override
  String get dismiss => '閉じる';

  @override
  String get refresh => '更新';

  @override
  String get more => 'その他';

  @override
  String get info => '情報';

  @override
  String get filter => 'フィルター';

  @override
  String get connect => '接続';

  @override
  String get disconnect => '切断';

  @override
  String get signIn => 'サインイン';

  @override
  String get logOut => 'ログアウト';

  @override
  String get tryAgain => '再試行';

  @override
  String get showDetails => '詳細を表示';

  @override
  String get hideDetails => '詳細を隠す';

  @override
  String get notNow => '今はしない';

  @override
  String get change => '変更';

  @override
  String get go => '移動';

  @override
  String get read => '読む';

  @override
  String get web => 'ウェブ';

  @override
  String get live => 'ライブ';

  @override
  String get liveTv => 'ライブTV';

  @override
  String get liveSports => 'ライブスポーツ';

  @override
  String get liveTextOnly => 'テキスト速報のみ — 動画配信なし';

  @override
  String get liveTextOnlyShort => 'テキストのみ';

  @override
  String get sub => 'サブ';

  @override
  String get dub => '吹き替え版';

  @override
  String get nsfw => 'NSFW';

  @override
  String get system => 'システム';

  @override
  String get custom => 'カスタム';

  @override
  String get customRange => 'カスタム範囲';

  @override
  String get defaultLabel => 'デフォルト';

  @override
  String get selected => '選択中';

  @override
  String get loading => '読み込み中…';

  @override
  String get searching => '検索中';

  @override
  String get searchingEllipsis => '検索中…';

  @override
  String get downloading => 'ダウンロード中…';

  @override
  String get updating => '更新中…';

  @override
  String get testing => 'テスト中…';

  @override
  String get searchOk => '検索 OK';

  @override
  String get working => '正常';

  @override
  String get dead => '不通';

  @override
  String get error => 'エラー';

  @override
  String get appLanguage => 'アプリの言語';

  @override
  String get appLanguageSubtitle => 'インターフェース言語';

  @override
  String get appLanguageSystem => 'システム（自動）';

  @override
  String appLanguageSystemSubtitle(String name) {
    return 'システム（$name）';
  }

  @override
  String get appLanguageKeywords =>
      '言語 ロケール 翻訳 i18n インターフェース 日本語 中国語 スペイン語 ドイツ語 フランス語 イタリア語 language locale translation japanese chinese spanish german french italian';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsSearchHint => '設定を検索';

  @override
  String settingsNoMatch(String query) {
    return '「$query」に一致する設定はありません';
  }

  @override
  String get settingsSectionAccount => 'アカウントと同期';

  @override
  String get settingsSectionSources => '出典';

  @override
  String get settingsSectionPlayback => '再生';

  @override
  String get settingsSectionReading => '読書';

  @override
  String get settingsSectionHistory => '履歴';

  @override
  String get settingsSectionDownloads => 'ダウンロード';

  @override
  String get settingsSectionInterface => 'インターフェース';

  @override
  String get settingsSectionNotifications => '通知';

  @override
  String get settingsSectionAdvanced => '詳細設定';

  @override
  String get settingsSectionAbout => 'このアプリについて';

  @override
  String get settingsSectionAccountSummary => 'トラッカー、Discord、バックアップ、同期';

  @override
  String get settingsSectionSourcesSummary => 'プロバイダー、使用中のソース、更新';

  @override
  String get settingsSectionPlaybackSummary => '画質、自動再生、速度';

  @override
  String get settingsSectionReadingSummary => 'マンガ・小説リーダーの初期設定';

  @override
  String get settingsSectionHistorySummary => '視聴した作品';

  @override
  String get settingsSectionDownloadsSummary => 'ダウンロード、ストレージ、トレント';

  @override
  String get settingsSectionInterfaceSummary => '外観、言語、検索レイアウト';

  @override
  String get settingsSectionNotificationsSummary => '新エピソードの通知';

  @override
  String get settingsSectionAdvancedSummary => 'DNS、プライバシー、ログ';

  @override
  String get settingsSectionAboutSummary => '更新、サポート、バージョン';

  @override
  String get couldNotExportLogs => 'ログを書き出せませんでした';

  @override
  String get logsShareSubject => 'Zangetsu のログ';

  @override
  String get signInSubtitle => 'リスト・履歴・続きから再生を同期';

  @override
  String get signInSubtitleTv => 'リストと続きから再生を同期';

  @override
  String get connections => '連携';

  @override
  String get discord => '不和';

  @override
  String get discordSubtitle => 'Rich Presence — 視聴中の作品を表示';

  @override
  String get discordActivityStatus => 'アクティビティの状態';

  @override
  String get presenceOnline => 'オンライン';

  @override
  String get presenceIdle => '退席中';

  @override
  String get presenceDnd => '取り込み中';

  @override
  String get presenceNameShows => '名前の表示';

  @override
  String get presenceDetailsShows => '詳細の表示';

  @override
  String get presenceStateShows => '状態の表示';

  @override
  String get presenceSourceApp => 'アプリ名';

  @override
  String get presenceSourceTitle => 'タイトル';

  @override
  String get presenceSourceEpisode => 'エピソード';

  @override
  String get presenceLargeImage => '大きな画像';

  @override
  String get presenceSmallImage => '小さな画像';

  @override
  String get presenceImagePoster => 'ポスター';

  @override
  String get presenceImageLogo => 'アプリのロゴ';

  @override
  String get presenceImageOff => 'オフ';

  @override
  String get presenceShowButton => '開くボタン';

  @override
  String get presenceButtonLabel => 'ボタンのラベル';

  @override
  String get presenceButtonLabelHint => 'Zangetsuで開く';

  @override
  String get presenceShowWhenPaused => '一時停止中も表示';

  @override
  String get presenceBrowsingTitle => '閲覧中にタイトルを表示';

  @override
  String get presencePreview => 'プレビュー';

  @override
  String get watchParty => '同時視聴';

  @override
  String get watchPartySubtitle => '友達と同時視聴ルームを作成・参加';

  @override
  String get signInToWatchTogether => 'サインインして一緒に視聴';

  @override
  String get syncLibraryToCloud => 'ライブラリをクラウドに同期';

  @override
  String get syncLibraryToCloudSubtitle => '履歴とリストをこのアカウントへ再アップロード';

  @override
  String get signInFirst => '先にサインインしてください';

  @override
  String get reconnectToSyncLibrary => '再接続してライブラリを同期してください。';

  @override
  String get syncingLibraryToCloud => 'ライブラリをクラウドに同期中…';

  @override
  String get backupAndRestore => 'バックアップと復元';

  @override
  String get backupAndRestoreSubtitle => 'ソース、リスト、設定を保存';

  @override
  String get providers => 'プロバイダー';

  @override
  String providersEnabledCount(int count) {
    return '$count件有効';
  }

  @override
  String get activeSource => '使用中のソース';

  @override
  String get streamingServices => '配信サービス';

  @override
  String get streamingServicesSubtitle => 'お住まいの地域で各サービスが配信している作品を見る';

  @override
  String get streamingServicesEmpty => 'この国のサービスは登録されていません';

  @override
  String get streamingServicesMetadataNote => '閲覧専用 — 再生はご自身のソースから行います';

  @override
  String get pinAsHomeRow => 'ホームの行に固定';

  @override
  String get unpinHomeRow => '固定を解除';

  @override
  String pinLimitReached(int count) {
    return '固定できるサービスは最大$count件です';
  }

  @override
  String get streamingRegion => '配信リージョン';

  @override
  String get streamingRegionSubtitle => 'どの国のカタログを表示するか';

  @override
  String get sourceHealth => 'ソースの状態';

  @override
  String get sourceHealthSubtitle => 'どのソースが使えるか確認';

  @override
  String get sourceUpdates => 'ソースの更新';

  @override
  String get sourceUpdatesSubtitle => 'インストール済みソースに更新があるとき通知';

  @override
  String get autoUpdateExtensions => '拡張機能を自動更新';

  @override
  String get autoUpdateExtensionsSubtitle => '起動時にインストール済みソースを自動更新';

  @override
  String get playback => '再生';

  @override
  String get playbackSubtitle => '画質、自動再生、速度';

  @override
  String get reader => 'リーダー';

  @override
  String get readerSubtitle => 'マンガ・小説の初期設定';

  @override
  String get history => '履歴';

  @override
  String get historySubtitle => '視聴した作品';

  @override
  String get downloads => 'ダウンロード';

  @override
  String get downloadsSubtitle => 'ダウンロードしたエピソードを管理';

  @override
  String get downloadsSubtitleTv => 'オフラインで視聴';

  @override
  String get storage => 'ストレージ';

  @override
  String get storageSubtitle => 'アプリの使用容量を管理';

  @override
  String get torrents => 'トレンド';

  @override
  String get torrentsSubtitle => 'ストリーミングとデータ設定';

  @override
  String get appearance => '外観';

  @override
  String get appearanceSubtitle => 'アクセントカラー、ポスターバッジ';

  @override
  String get searchLayout => '検索レイアウト';

  @override
  String get searchLayoutSubtitle => '複数ソースの結果の表示方法';

  @override
  String get searchLayoutBlurb =>
      '複数ソースの結果の表示方法です。縦＝ソースごとにグリッド、横＝ソースごとに横スクロール行。';

  @override
  String get searchLayoutVertical => '縦（グリッド）';

  @override
  String get searchLayoutHorizontal => '横（行）';

  @override
  String get batchDownloadStyle => '一括ダウンロードの見た目';

  @override
  String get batchDownloadStyleSubtitle => '複数エピソードシートの見た目';

  @override
  String get batchDownloadStyleBlurb =>
      'シーズン全体をダウンロードするときに出るシートです。内容は同じで、選び方だけが違います。';

  @override
  String get batchDownloadClassic => 'クラシック';

  @override
  String get batchDownloadClassicBlurb => 'エピソードごとのサムネイルグリッド付きのフルシート。';

  @override
  String get batchDownloadMinimal => 'ミニマル';

  @override
  String get batchDownloadMinimalBlurb => '数字ホイールで取得する話数を選びます。';

  @override
  String get notifications => '通知';

  @override
  String get notificationsSubtitle => '登録作品の新エピソード通知';

  @override
  String get dns => 'DNS';

  @override
  String get dnsSubtitle => 'CS ソースの ISP ブロックを回避';

  @override
  String get dnsBlurb =>
      'CloudStream ソース向けの暗号化 DNS。ISP のブロック回避に役立ちます。オフ＝通常の接続。';

  @override
  String get dnsOffTvSubtitle => 'オフ · CS ソースの ISP ブロックを回避';

  @override
  String get privacy => 'プライバシー';

  @override
  String get privacySubtitle => 'NSFW ソース';

  @override
  String get shareLogs => 'ログを共有';

  @override
  String get shareLogsSubtitle => '不具合調査用の診断ログを送信';

  @override
  String get sendingReport => 'レポートを送信中…';

  @override
  String get reportSent => 'レポートを送信しました';

  @override
  String reportSentBody(String ref) {
    return 'ありがとうございます。何が起きたかを知らせる際は、このコードを添えてください: $ref';
  }

  @override
  String get about => 'このアプリについて';

  @override
  String versionLabel(String version) {
    return 'v$version';
  }

  @override
  String get contributors => '貢献者';

  @override
  String get website => 'ウェブサイト';

  @override
  String get communityChat => 'コミュニティチャット';

  @override
  String get joinTheServer => 'サーバーに参加';

  @override
  String get viewTheSourceCode => 'ソースコードを見る';

  @override
  String get howItWorks => '使い方';

  @override
  String get howItWorksSubtitle => '初めての方向けの短いガイド';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkForUpdatesSubtitle => 'GitHub から最新版を入手';

  @override
  String get checkingForUpdates => '更新を確認中…';

  @override
  String get betaUpdates => 'ベータ更新';

  @override
  String get betaUpdatesSubtitle => '先行ビルドを早めに入手 — 不安定な場合があります';

  @override
  String get supportTheApp => 'アプリを支援';

  @override
  String get buyMeACoffee => 'コーヒーをおごる';

  @override
  String get leadDeveloper => 'リード開発者';

  @override
  String get addCloudStreamRepository => 'CloudStream リポジトリを追加';

  @override
  String get installCloudStreamSources => 'CloudStream ソースをインストール';

  @override
  String get connectionsTvSubtitle => 'AniList、MyAnimeList、Simkl';

  @override
  String get profile => 'プロフィール';

  @override
  String get profileLock => 'プロフィールロック';

  @override
  String get profileLockSubtitle => 'このプロフィールを開く前にPINを要求';

  @override
  String get unlockProfile => 'プロフィールのロック解除';

  @override
  String enterProfilePin(Object name) {
    return '$nameのPINを入力';
  }

  @override
  String get wrongPin => 'PINが違います。もう一度お試しください';

  @override
  String get setProfilePin => 'プロフィールPINを設定';

  @override
  String get confirmProfilePin => 'PINを確認';

  @override
  String get pinMismatch => 'PINが一致しません';

  @override
  String get pinTooShort => '4文字以上にしてください';

  @override
  String get changeProfilePin => 'PINを変更';

  @override
  String get removeProfileLock => 'ロックを解除';

  @override
  String get useFingerprint => '指紋を使用';

  @override
  String get changeProfile => 'プロフィールを切り替えますか？';

  @override
  String get chooseWhoIsWatching => '視聴者を選択してください。';

  @override
  String get home => 'ホーム';

  @override
  String get myList => 'マイリスト';

  @override
  String get schedule => 'スケジュール';

  @override
  String get pressBackAgainToExit => 'もう一度 BACK で終了';

  @override
  String get pressBackAgainToExitTv => 'もう一度戻るで終了';

  @override
  String get selectSource => 'ソースを選択';

  @override
  String get accentWallpaper => '壁紙';

  @override
  String get accentCoral => 'コーラル';

  @override
  String get accentBlue => 'ブルー';

  @override
  String get accentViolet => 'バイオレット';

  @override
  String get accentEmerald => 'エメラルド';

  @override
  String get accentAmber => 'アンバー';

  @override
  String get accentRose => '薔薇';

  @override
  String get accentCyan => 'シアン';

  @override
  String get accentCrimson => 'クリムゾン';

  @override
  String get shaderOff => 'オフ';

  @override
  String get shaderOffDesc => '補正なし';

  @override
  String get shaderSharpen => 'シャープ';

  @override
  String get shaderSharpenDesc => '細部を復元 — きれいなソース向き';

  @override
  String get shaderDeblur => 'デブラー';

  @override
  String get shaderDeblurDesc => 'やさしく復元 — ぼやけたソース向き';

  @override
  String get shaderDenoise => 'ノイズ除去';

  @override
  String get shaderDenoiseDesc => '粒子を軽減 — 圧縮ソース向き';

  @override
  String get shaderTierHigh => 'ハイエンド GPU';

  @override
  String get shaderTierHighDesc => '重い VL アップスケーラー＋HQ 拡大 — 高性能 GPU 向け';

  @override
  String get shaderTierMid => 'ミッドレンジ GPU';

  @override
  String get shaderTierMidDesc => '軽いアップスケーラー＋デバンド — 多くの端末で滑らか';

  @override
  String get playerInfoResolution => '解像度';

  @override
  String get playerInfoSource => 'ソース';

  @override
  String get playerInfoQuality => '画質';

  @override
  String get playerInfoVideoCodec => '映像コーデック';

  @override
  String get playerInfoAudioCodec => '音声コーデック';

  @override
  String get playerInfoFrameRate => 'フレームレート';

  @override
  String get playerInfoVideoBitrate => '映像ビットレート';

  @override
  String get playerInfoBuffer => 'バッファ';

  @override
  String get playerInfoDroppedFrames => 'ドロップフレーム';

  @override
  String get playerInfoDecoder => 'デコーダ';

  @override
  String get playerInfoSpeed => '速度';

  @override
  String get playerInfoAudioTrack => '音声トラック';

  @override
  String get playerInfoSubtitleTrack => '字幕トラック';

  @override
  String get playerInfoAudioBoost => '音声ブースト';

  @override
  String get statusPlanToWatch => '視聴予定';

  @override
  String get statusWatching => '視聴中';

  @override
  String get statusCompleted => '完了';

  @override
  String get statusPaused => '一時中断';

  @override
  String get statusDropped => '視聴中止';

  @override
  String get statusPlanning => '予定';

  @override
  String get statusReading => '読書中';

  @override
  String get statusPlanToRead => '読書予定';

  @override
  String providerHavingAMoment(String name) {
    return '$name は少し休憩中です';
  }

  @override
  String get providerHavingAMomentBody =>
      '今は応答していません。少し待つか、設定でメタデータ提供元を切り替えてください。';

  @override
  String sourceNotAnswering(String name) {
    return '$name が応答しません';
  }

  @override
  String get sourceNotAnsweringBody =>
      'ダウンしているか、リクエストを拒否している可能性があります。再試行するか、上部でソースを切り替えてください。';

  @override
  String providerNeedsBreather(String name) {
    return '$name は一息つきたいようです';
  }

  @override
  String providerNeedsBreatherBody(int seconds) {
    return '少し送りすぎました。$seconds秒後に再試行してください。';
  }

  @override
  String get showingWhatWeHave =>
      'ダウンしているか、ネットワークが遮断しているかもしれません。取得済みの情報はこちらです。';

  @override
  String get titleLanguage => 'タイトルの言語';

  @override
  String get titleLanguageSubtitle => 'AniList のタイトルの表示方法';

  @override
  String get titleLanguageNative => '原語';

  @override
  String get homeRowsLayout => '編集中';

  @override
  String get homeRows => 'ホームをカスタマイズ';

  @override
  String get homeRowsSubtitle => 'ホームに表示する行を選択';

  @override
  String get homeRowsFromYourLists => 'リストから';

  @override
  String get homeRowsDiscover => '見つける';

  @override
  String get homeRowsHelp => 'ドラッグで並べ替え。オフにすると行が非表示になります。';

  @override
  String homeRowTrackerContinue(String tracker) {
    return '$trackerで続きを見る';
  }

  @override
  String get trackerCaughtUp => '最新話まで視聴済み';

  @override
  String get homeRowNewEpisodes => '新着エピソード';

  @override
  String get modeStreaming => 'ストリーミング';

  @override
  String get modeManga => 'マンガ';

  @override
  String get modeNovel => '小説';

  @override
  String get relativeToday => '今日';

  @override
  String get relativeYesterday => '昨日';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日前',
      one: '$count日前',
    );
    return '$_temp0';
  }

  @override
  String relativeWeeksAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count週間前',
      one: '$count週間前',
    );
    return '$_temp0';
  }

  @override
  String relativeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countか月前',
      one: '$countか月前',
    );
    return '$_temp0';
  }

  @override
  String relativeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count年前',
      one: '$count年前',
    );
    return '$_temp0';
  }

  @override
  String get bootErrorTitle => 'Zangetsu の起動が完了しませんでした';

  @override
  String get bootErrorBody =>
      'この端末に保存されたデータが原因で開けません。データは失われていません。アカウントとクラウド同期分はそのままです。';

  @override
  String get resetAppData => 'アプリデータをリセット';

  @override
  String get resetAppDataTitle => 'アプリデータをリセットしますか？';

  @override
  String get resetAppDataBody =>
      'Zangetsu がこの端末に保存したデータを消して、まっさらな状態で起動できるようにします。\n\nアカウントとクラウド同期分はそのままです。再サインインすればライブラリが戻ります。';

  @override
  String get resetAppDataDone => 'Zangetsu を完全に終了して、もう一度開いてください。';

  @override
  String get detailsCopied => '詳細をコピーしました — こちらへ送ってください';

  @override
  String get copyDetails => '詳細をコピー';

  @override
  String get goodToHaveYouHere => 'ようこそ。';

  @override
  String get onboardingIntro => 'アニメ、マンガ、小説をひとつのアプリで。好きなように設定できます。';

  @override
  String get youChooseWhatsInside => '中身は自分で選べます';

  @override
  String get addTheSourcesYouWant => '使いたいソースを追加 — 手順はこちら。';

  @override
  String get openProviders => 'プロバイダーを開く';

  @override
  String get pickStreamingMangaOrNovels => '配信、マンガ、小説から選ぶ';

  @override
  String get pasteInARepositoryLink => 'リポジトリのリンクを貼り付ける';

  @override
  String get browseAndGrab => '見て、良さそうなものを入れる';

  @override
  String get readyWhenYouAre => '準備ができたらどうぞ。';

  @override
  String get addSourcesNow => '今すぐソースを追加';

  @override
  String get illDoItLater => '後でする';

  @override
  String get howToUseTheApp => 'アプリの使い方';

  @override
  String get aFewTapsToAnything => '数タップで目的の操作へ。';

  @override
  String get findSomething => '作品を探す';

  @override
  String get watchIt => '視聴する';

  @override
  String get ifItWontLoad => '読み込めないとき';

  @override
  String get saveForOffline => 'オフライン用に保存';

  @override
  String get commonQuestions => 'よくある質問';

  @override
  String get noCommunityContributorsYet => 'コミュニティ貢献者はまだいません。';

  @override
  String get paged => 'ページ送り';

  @override
  String get vertical => '垂直';

  @override
  String get tapZonesReset => 'タップ領域をリセットしました';

  @override
  String get noUPIAppFoundUPIIDCopiedPasteItInYourUPIApp =>
      'UPI アプリが見つかりません — UPI ID をコピーしました。UPI アプリに貼り付けてください';

  @override
  String get donateWithPayPal => 'PayPal で寄付';

  @override
  String get payViaUPI => 'UPI で支払う';

  @override
  String get copyUPIID => 'UPI ID をコピー';

  @override
  String get readingMode => '読書モード';

  @override
  String get fit => 'フィット';

  @override
  String get background => '背景';

  @override
  String get colourFilter => 'カラーフィルター';

  @override
  String get orientationLock => '画面の向きを固定';

  @override
  String get openEpisodesIn => 'エピソードを開く場所';

  @override
  String get openingLayoutWatchPage => '視聴ページ';

  @override
  String get openingLayoutFullscreen => '全画面';

  @override
  String get watchServer => 'サーバー';

  @override
  String get watchUpNext => '次の作品';

  @override
  String watchAllEpisodes(int count) {
    return 'すべてのエピソード（$count）';
  }

  @override
  String get watchComments => 'コメント';

  @override
  String get commentsEmpty => 'まだコメントはありません。会話を始めましょう。';

  @override
  String get commentsSignInToComment => 'サインインして会話に参加しましょう。';

  @override
  String get commentsPlaceholder => 'コメントを追加…';

  @override
  String get commentsPost => '投稿';

  @override
  String get commentsEdited => '編集済み';

  @override
  String get commentsYou => 'あなた';

  @override
  String get commentsDelete => 'コメントを削除';

  @override
  String get commentsDeleteConfirm => 'このコメントを削除しますか？';

  @override
  String get commentsLoadFailed => 'コメントを読み込めませんでした';

  @override
  String get commentsPostFailed => 'コメントを投稿できませんでした';

  @override
  String get commentsJustNow => 'たった今';

  @override
  String commentsMinutesAgo(int count) {
    return '$count分前';
  }

  @override
  String commentsHoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String commentsDaysAgo(int count) {
    return '$count日前';
  }

  @override
  String get watchEpisodes => 'エピソード';

  @override
  String get watchComingSoon => '近日公開';

  @override
  String get watchAutoplay => '自動再生';

  @override
  String get watchSeeMore => 'もっと見る';

  @override
  String get watchSeeLess => '表示を減らす';

  @override
  String get watchReverseOrder => '順序を逆にする';

  @override
  String get doublePageLandscape => '見開き（横向き）';

  @override
  String get pairFacingPagesInALandscapeSpread => '横向きで左右のページを見開き表示';

  @override
  String get cropBorders => '余白をカット';

  @override
  String get trimNearUniformEdgeMarginsFromAPage => 'ページ端のほぼ均一な余白を切り落とす';

  @override
  String get preloadPages => 'ページを先読み';

  @override
  String get showPageNumber => 'ページ番号を表示';

  @override
  String get keepScreenOn => '画面を消灯しない';

  @override
  String get readerFullscreen => '全画面';

  @override
  String get tapZones => 'タップ領域';

  @override
  String get whatTappingEachPartOfThePageDoes => 'ページの各部分をタップしたときの動作';

  @override
  String get font => 'フォント';

  @override
  String get addFont => 'フォントを追加';

  @override
  String get couldntAddFont => 'そのフォントを追加できませんでした';

  @override
  String get theme => 'テーマ';

  @override
  String get fontSize => '文字サイズ';

  @override
  String get lineHeight => '行間';

  @override
  String get margin => '余白';

  @override
  String get justifyText => '両端揃え';

  @override
  String get textDirection => '文字の方向';

  @override
  String get paragraphSpacing => '段落の間隔';

  @override
  String get paginated => 'ページ形式';

  @override
  String get bookStylePagesInsteadOfAContinuousScroll =>
      '連続スクロールではなく本のようなページ送り';

  @override
  String get enableNSFWSources => 'NSFW ソースを有効にしますか？';

  @override
  String get showNSFWAniyomiSources => 'NSFW の Aniyomi ソースを表示しますか？';

  @override
  String get incognitoMode => 'シークレットモード';

  @override
  String get pauseHistoryTrackingDiscordPresence => '履歴、トラッキング、Discord の表示を停止';

  @override
  String get enableNSFWSources2 => 'NSFW ソースを有効にする';

  @override
  String get showSourcesMarked18 => '18+ のソースを表示';

  @override
  String get showNSFWSources => 'NSFW ソースを表示';

  @override
  String get adultAniyomiExtensions => '成人向け Aniyomi 拡張機能';

  @override
  String get opensubtitlesAPIKey => 'OpenSubtitles API キー';

  @override
  String get pasteYourKey => 'キーを貼り付け';

  @override
  String get createAFreeKeyAtOpensubtitlesComConsumers =>
      'opensubtitles.com → Consumers で無料キーを作成。';

  @override
  String get shaderDownloadFailedCheckNetwork => 'シェーダーのダウンロードに失敗 — ネットワークを確認';

  @override
  String get anime4kEnhancement => 'Anime4K 補正';

  @override
  String get anime4kGPUTier => 'Anime4K の GPU ティア';

  @override
  String get cacheCleared => 'キャッシュを削除しました';

  @override
  String get videoBufferSize => '映像バッファサイズ';

  @override
  String get videoBufferLength => '映像バッファ時間';

  @override
  String get playerInfoOverlay => 'プレーヤー情報オーバーレイ';

  @override
  String get defaultQuality => 'デフォルト画質';

  @override
  String get videoDecoder => '映像デコーダー';

  @override
  String get videoRenderer => '映像レンダラー';

  @override
  String get defaultAudio => 'デフォルト音声';

  @override
  String get defaultSpeed => 'デフォルト速度';

  @override
  String get doubleTapSkip => 'ダブルタップでスキップ';

  @override
  String get closeConfirmation => '終了の確認';

  @override
  String get megaskipDuration => 'MegaSkip の時間';

  @override
  String get defaultPlayer => 'デフォルトプレーヤー';

  @override
  String get defaultAudioAnimeSubDub => 'デフォルト音声（アニメ字幕／吹替）';

  @override
  String get builtIn => '内蔵';

  @override
  String get playerControls => 'プレーヤー操作';

  @override
  String get reorderOrHideTheButtonsOnThePlayerBar => 'プレーヤーバーのボタンを並び替え・非表示';

  @override
  String get resumePlayback => '続きから再生';

  @override
  String get continueFromWhereYouLeftOff => '中断した位置から再開';

  @override
  String get askBeforeJumping => 'ジャンプ前に確認';

  @override
  String get autoAddToMyList => 'マイリストへ自動追加';

  @override
  String get addATitleToMyListWhenYouStartWatchingIt => '視聴を始めるとマイリストに追加';

  @override
  String get autoTrack => '自動トラッキング';

  @override
  String get confirm => '確認';

  @override
  String get autoplayNextEpisode => '次の話を自動再生';

  @override
  String get autoSkipFillerEpisodes => 'フィラー話を自動スキップ';

  @override
  String get autoplayTrailer => '予告編を自動再生';

  @override
  String get playATitleSTrailerOnItsDetailPage => '詳細ページで作品の予告編を再生';

  @override
  String get playTrailersInHD => '予告編を HD で再生';

  @override
  String get skipIntroButton => 'イントロスキップボタン';

  @override
  String get showSkipOpeningEndingOnAnimeWhenDetected =>
      '検出時にオープニング／エンディングのスキップを表示';

  @override
  String get autoSkipOpening => 'OP を自動スキップ';

  @override
  String get jumpPastTheOPOnItsOwnNoTap => 'タップなしで OP を飛ばす';

  @override
  String get autoSkipRecap => '前回までのあらすじを自動スキップ';

  @override
  String get jumpPastThePreviouslyOnRecapNoTap => '「前回まで」のあらすじをタップなしで飛ばす';

  @override
  String get autoSkipEnding => 'ED を自動スキップ';

  @override
  String get jumpPastTheEDOnItsOwnNoTap => 'タップなしで ED を飛ばす';

  @override
  String get megaskipButton => 'MegaSkip ボタン';

  @override
  String get aJumpForwardButtonInThePlayerAnyVideo => 'プレーヤーの先送りボタン（どの動画でも）';

  @override
  String get seekButton => 'シークボタンを表示';

  @override
  String get seekButtonDescription => 'プレーヤーに早送り・早戻しボタンを表示します';

  @override
  String get seekButtonDuration => 'シーク時間';

  @override
  String get selectSeekButtonDurationDescription => 'シークボタンの移動時間を選択します';

  @override
  String get nativeTVPlayer => 'TV 標準プレーヤー';

  @override
  String get tvDecoderMode => 'TVデコーダーの優先度';

  @override
  String get tvDecoderHardwareOnly => 'ハードウェアのみ';

  @override
  String get tvDecoderHardwareFirst => 'ハードウェア優先（ソフトウェアにフォールバック）';

  @override
  String get tvDecoderSoftwareFirst => 'ソフトウェア優先（ハードウェアにフォールバック）';

  @override
  String get softwareAudioDolbyDTS => 'ソフトウェア音声（Dolby/DTS）';

  @override
  String get seekPreviewOnline => 'シークプレビュー（オンライン）';

  @override
  String get thumbnailsWhileScrubbingStreamsCostsExtraData =>
      'ストリーム操作中にサムネイル — 追加通信が発生';

  @override
  String get autoPictureInPicture => '自動ピクチャーインピクチャー';

  @override
  String get shrinkToAFloatingWindowWhenYouLeaveTheApp => 'アプリを離れると小窓に縮小';

  @override
  String get backgroundPlayback => 'バックグラウンド再生';

  @override
  String get keepPlayingAudioWhenYouLeaveTheApp => 'アプリを離れても通知付きで再生を続ける';

  @override
  String get showQualityLabel => '画質ラベルを表示';

  @override
  String get plainQualityTextEG1080pOnTheTopBarRight =>
      '上部バー右に画質テキスト（例: 1080p）';

  @override
  String get gestureControls => 'ジェスチャー操作';

  @override
  String get swipeLeftForBrightnessRightForVolume => '左スワイプで明るさ、右で音量';

  @override
  String get swipeToSeek => 'スワイプでシーク';

  @override
  String get dragLeftOrRightAcrossTheVideoToScrub => '映像上を左右にドラッグしてシーク';

  @override
  String get holdFor2Speed => '長押しで 2× 速';

  @override
  String get longPressTheVideoToPlayAt2WhileHeld => '映像を長押ししている間 2× で再生';

  @override
  String get clearImageVideoCache => '画像・映像キャッシュを削除';

  @override
  String get styledSubtitlesLibass => '装飾字幕（libass）';

  @override
  String get subtitleStyle => '字幕スタイル';

  @override
  String get requiredForOnlineSubtitleSearch => 'オンライン字幕検索に必要';

  @override
  String get subtitleLanguage => '字幕の言語';

  @override
  String get autoDownloadSubtitles => '字幕を自動ダウンロード';

  @override
  String get whenTheSourceHasNoSubtitleInYourLanguage => 'ソースに希望言語の字幕がないとき';

  @override
  String get autoTranslateSubtitles => '字幕を自動翻訳';

  @override
  String get translateToYourLanguageOnPlayWhenTheSourceHasNone =>
      'ソースに字幕がないとき、再生時に翻訳';

  @override
  String get translateSubtitlesTo => '字幕の翻訳先';

  @override
  String get pickALanguage => '言語を選ぶ';

  @override
  String get customColour => 'カスタムカラー';

  @override
  String get materialYou => '素材';

  @override
  String get coloursFromYourWallpaper => '壁紙から色を取得';

  @override
  String get pureBlackBackground => '純黒の背景';

  @override
  String get trueBlackForOLED => 'OLED 向けの真の黒';

  @override
  String get posterBadges => 'ポスターバッジ';

  @override
  String get qualityAndSubDubBadges => '画質と字幕／吹替のバッジ';

  @override
  String get animateLists => 'リストをアニメーション';

  @override
  String get cardsFadeInAsYouScroll => 'スクロールに合わせてカードがフェードイン';

  @override
  String get animationStyle => 'アニメーションのスタイル';

  @override
  String get turnOffMaterialYouToPickAColourYourself =>
      '自分で色を選ぶには Material You をオフ';

  @override
  String get downloadsZangetsu => 'ダウンロード › 斬月';

  @override
  String get removableDrive => 'リムーバブルドライブ';

  @override
  String get chooseFolder => 'フォルダーを選択…';

  @override
  String get resetToDefault => 'デフォルトに戻す';

  @override
  String get connected => '接続済み';

  @override
  String get imageCacheCleared => '画像キャッシュを削除しました';

  @override
  String get providerCacheCleared => 'プロバイダーキャッシュを削除しました';

  @override
  String get clearImageCache => '画像キャッシュを削除';

  @override
  String get clearProviderCache => 'プロバイダーキャッシュを削除';

  @override
  String get showTitleE2 => 'タイトルを表示 · E2';

  @override
  String get pinned => 'ピン留め';

  @override
  String get exoplayerSpikeDev => 'ExoPlayer スパイク（開発）';

  @override
  String get sp0TestSurfaceViewPlaybackSmoothness =>
      'SP0 — SurfaceView 再生の滑らかさをテスト';

  @override
  String get pasteDiscordToken => 'Discord トークンを貼り付け';

  @override
  String get yourDiscordUserToken => 'Discord のユーザートークン';

  @override
  String get pasteToken => 'トークンを貼り付け';

  @override
  String get useMobileDataForTorrents => 'トレントにモバイルデータ通信を使う';

  @override
  String get discordConnected => 'Discord に接続しました';

  @override
  String get disconnectDiscord => 'Discord を切断しますか？';

  @override
  String get notConfigured => '未設定';

  @override
  String get aDiscordApplicationIDMustBeSetInTheBuildFirst =>
      '先にビルドで Discord Application ID を設定する必要があります。';

  @override
  String get richPresence => '豊かな存在感';

  @override
  String get showWhatYouReWatchingOnYourProfile => 'プロフィールに視聴中の作品を表示';

  @override
  String get signInToLinkYourAccount => 'サインインしてアカウントを連携';

  @override
  String get autoSync => '自動同期';

  @override
  String
  get disconnectingHereOnlySignsThisTrackerOutOnTheTVYourPhoneStaysConnected =>
      'ここでの切断は TV 側のトラッカーのみ。スマホは接続したままです。';

  @override
  String get continueWatching => '続きから見る';

  @override
  String get continueReading => '続きから読む';

  @override
  String get seeAll => 'すべて見る';

  @override
  String get libraryLabel => 'ライブラリ';

  @override
  String get sortBy => '並び替え';

  @override
  String get newCategory => '新しいカテゴリ';

  @override
  String get personaGym => 'Persona、ジム、…';

  @override
  String get deleteCategory => 'カテゴリを削除';

  @override
  String get yourTitlesStayOnlyTheLabelGoes => '作品はそのまま — ラベルだけ削除されます';

  @override
  String get renameCategory => 'カテゴリ名を変更';

  @override
  String get manageTrackers => 'トラッカーを管理';

  @override
  String get trackers => 'トラッカー';

  @override
  String get showLabel => '作品';

  @override
  String get couldnTLoadPullToRefresh => '読み込めません — 引っ張って更新';

  @override
  String get noTitlesInThisList => 'このリストに作品はありません';

  @override
  String get signInToBuildYourList => 'サインインしてリストを作る';

  @override
  String get titlesYouAddAppearHere => '追加した作品がここに表示されます';

  @override
  String get couldnTLoadTryAgainFromSettings => '読み込めません — 設定から再試行';

  @override
  String get search2 => '検索…';

  @override
  String get voiceSearch => '音声検索';

  @override
  String get voiceSearchListening => '聞き取り中…';

  @override
  String get voiceSearchPreparing => '準備中…';

  @override
  String get voiceSearchProcessing => '言葉を探しています…';

  @override
  String get voiceSearchPermission => '音声検索を使うにはマイクへのアクセスを許可してください。';

  @override
  String get voiceSearchSpeechPermission => '音声検索を使うには設定で音声認識を許可してください。';

  @override
  String get voiceSearchTypingAvailable => '入力して検索することもできます。';

  @override
  String get voiceSearchServiceNotice => '音声認識はお使いの端末の音声サービスを利用します。';

  @override
  String get voiceSearchFailed => '音声検索に失敗しました。もう一度お試しください。';

  @override
  String get voiceSearchNoMatch => 'タイトルが聞き取れませんでした。もう一度話してください。';

  @override
  String get allSources => 'すべてのソース';

  @override
  String get currentSource => '現在のソース';

  @override
  String get searchFailedTryAgain => '検索に失敗 — 再試行してください';

  @override
  String get searchForSomethingToWatch => '視聴する作品を検索';

  @override
  String get recentSearches => '最近の検索';

  @override
  String get clearSearchHistory => '検索履歴を消去';

  @override
  String get checkTheSpellingOrTryADifferentTitle =>
      'スペルを確認するか、別のタイトルを試してください。';

  @override
  String get browseSources => 'ソースを見る';

  @override
  String get thisSourceHasNoFilters => 'このソースにフィルターはありません';

  @override
  String get searchIn => '検索対象';

  @override
  String get filters => 'フィルター';

  @override
  String get sourceFilters => 'ソースのフィルター';

  @override
  String get clearFilters => 'フィルターをクリア';

  @override
  String get topPicks => 'おすすめ';

  @override
  String get anime => 'アニメ';

  @override
  String get moviesSeries => '映画・シリーズ';

  @override
  String get noSourcesInstalled => 'ソースがインストールされていません';

  @override
  String get fromYourResults => '· 検索結果から';

  @override
  String get any => '指定なし';

  @override
  String get someSourcesDonTProvideGenres => 'ジャンルを提供しないソースがあります';

  @override
  String get searchInSources => 'ソース内を検索';

  @override
  String get turnAllOff => 'すべてオフ';

  @override
  String get extensionsUpdated => '拡張機能を更新しました';

  @override
  String get incognito => 'シークレットモード';

  @override
  String get reconnectToSync => '再接続して同期';

  @override
  String get yourSessionExpiredTapToSignInAndSyncYourLibrary =>
      'セッションの期限切れ — タップしてサインインし、ライブラリを同期';

  @override
  String get solveCloudflare => 'Cloudflare を解決';

  @override
  String get switchSource => 'ソースを変更';

  @override
  String get moviesTV => '映画・テレビ';

  @override
  String get couldnTLoadComingSoonPullToRefresh => '近日公開を読み込めません — 引っ張って更新。';

  @override
  String get streamURL => '配信 URL';

  @override
  String get exoplayerSurfaceViewSpikeSP0 => 'ExoPlayer SurfaceView スパイク（SP0）';

  @override
  String get episodes => 'エピソード';

  @override
  String get season => 'シーズン';

  @override
  String get jumpToEpisode => '話へジャンプ…';

  @override
  String get preferredLanguage => '優先する言語…';

  @override
  String get searchOnline => 'オンラインで検索…';

  @override
  String get onlineSubtitles => 'オンライン字幕';

  @override
  String get audioSubs => '音声と字幕';

  @override
  String get nextEpisode => '次の話';

  @override
  String get colour => 'カラー';

  @override
  String get snapshot => 'スナップショット';

  @override
  String get sleepTimer => 'スリープタイマー';

  @override
  String get pictureInPicture => 'ピクチャーインピクチャー';

  @override
  String get cast => 'キャスト';

  @override
  String get playbackStats => '再生統計';

  @override
  String get sleepTimerOn => 'スリープタイマーオン';

  @override
  String get lockControls => '操作をロック';

  @override
  String get chat => 'チャット';

  @override
  String get previousEpisode => '前の話';

  @override
  String get nextEpisode2 => '次の話';

  @override
  String get translated => '翻訳済み';

  @override
  String get thisSourceCanTBeCastTryAnotherSource =>
      'このソースはキャストできません — 別のソースを試してください。';

  @override
  String get rewind10Seconds => '10 秒戻す';

  @override
  String get forward10Seconds => '10 秒進める';

  @override
  String get stopCasting => 'キャストを停止';

  @override
  String get usingTheBuiltInPlayerForThisSource => 'このソースは内蔵プレーヤーを使います。';

  @override
  String get closeVideo => '映像を閉じますか？';

  @override
  String get areYouSureYouWantToCloseTheVideo => '映像を閉じてもよろしいですか？';

  @override
  String get downloadInSettings => '設定でダウンロード';

  @override
  String get getTheAnime4KShaders06MBThenTurnItOn =>
      'Anime4K シェーダー（約 0.6 MB）を入手してからオンにする';

  @override
  String get gpuTIER => 'GPUティア';

  @override
  String get endOfEpisode => '話の終わり';

  @override
  String get closeAppWhenTimerEnds => 'タイマー終了時にアプリを閉じる';

  @override
  String get exitTheAppToSaveBattery => 'アプリを終了してバッテリーを節約';

  @override
  String get playNow => '今すぐ再生';

  @override
  String get skipRecap => 'あらすじをスキップ';

  @override
  String get unlockControls => '操作ロックを解除';

  @override
  String get tapToUnlock => 'タップして解除';

  @override
  String get subtitleDelay => '字幕の遅延';

  @override
  String get audioDelay => '音声の遅延';

  @override
  String get androidPlayer => 'Androidプレーヤー（実験的）';

  @override
  String get androidPlayerUnavailable => 'Androidプレーヤーを起動できませんでした';

  @override
  String get audioNormalization => '音量の正規化';

  @override
  String get searchSubtitlesOnline => '字幕をオンライン検索';

  @override
  String get loadFromFile => 'ファイルから読み込む…';

  @override
  String get exportSubtitle => '字幕を書き出す…';

  @override
  String get exportSubtitleSubtitle => '読み込んだ字幕を.srtとしてダウンロードに保存';

  @override
  String get subtitleSavedToDownloads => '字幕をダウンロードに保存しました';

  @override
  String get couldNotSaveSubtitle => '字幕を保存できませんでした';

  @override
  String get noSubtitleToExport => '書き出す字幕が読み込まれていません';

  @override
  String get removeHearingImpaired => '効果音を削除';

  @override
  String get removeHearingImpairedSubtitle => '翻訳前に[効果音]と♪音楽♪を削除';

  @override
  String get translateSubtitles => '字幕を翻訳…';

  @override
  String get language => '言語:';

  @override
  String get movieOrShowTitle => '映画・番組のタイトル';

  @override
  String get theQuickBrownFox => 'すばやい茶色のキツネ';

  @override
  String get seekBar => 'シークバー';

  @override
  String get autoScrollSettings => '自動スクロール設定';

  @override
  String get autoScroll => '自動スクロール';

  @override
  String get touchThePageToPauseItPicksUpAgainWhenYouLetGo =>
      'ページに触れると一時停止 — 離すと再開します。';

  @override
  String get floatingButton => 'フローティングボタン';

  @override
  String get nextChapter => '次の章';

  @override
  String get orKeepPulling => 'またはそのまま引く';

  @override
  String get thatSTheLastChapter => 'これが最後の章です。';

  @override
  String get readerSettings => 'リーダー設定';

  @override
  String get noOtherChaptersLoadedYet => '他の章はまだ読み込まれていません';

  @override
  String get chapters => '章';

  @override
  String get direction => '方向';

  @override
  String get autoWebtoonMode => '自動ウェブトゥーンモード';

  @override
  String get pullToChangeChapter => '引いて章を切り替え';

  @override
  String get volumeKeysTurnPages => '音量ボタンでページ送り';

  @override
  String get invertVolumeKeys => '音量ボタンを反転';

  @override
  String get brightness => '明るさ';

  @override
  String get previousChapter => '前の章';

  @override
  String get thisTitle => 'この作品';

  @override
  String get nextChapter2 => '次の章 →';

  @override
  String get textSize => '文字サイズ';

  @override
  String get appliesStraightAway => 'すぐに反映されます';

  @override
  String get left => '左揃え';

  @override
  String get justify => '両端揃え';

  @override
  String get ltr => '長期';

  @override
  String get rtl => 'RTL';

  @override
  String get letterSpacing => '文字間隔';

  @override
  String get wordSpacing => '単語間隔';

  @override
  String get alignment => '配置';

  @override
  String get a => 'あ';

  @override
  String get searchEpisodes => 'エピソードを検索';

  @override
  String get titleOrEpisodeNumber => 'タイトルまたは話数';

  @override
  String get failedToLoadThisTitle => 'この作品を読み込めませんでした';

  @override
  String get offlineTitle => 'オフラインです';

  @override
  String get offlineBody => '接続を確認して、もう一度お試しください。';

  @override
  String get changeStatus => 'ステータスを変更';

  @override
  String get tracking => '追跡';

  @override
  String get noEpisodesAvailableFromThisSource => 'このソースにエピソードがありません';

  @override
  String get noEpisodesMatchYourSearch => '検索に一致するエピソードがありません';

  @override
  String get everyChapterIsAlreadyDownloaded => 'すべての章はすでにダウンロード済みです';

  @override
  String get downloadChapters => '章をダウンロード';

  @override
  String get thisWillTakeAWhileAndUseALotOfStorage => '時間がかかり、容量を多く使います';

  @override
  String get findEpisode => '話を探す';

  @override
  String get findChapter => '章を検索';

  @override
  String get refreshChapters => '章を更新';

  @override
  String get refreshEpisodes => 'エピソードを更新する';

  @override
  String get reverseList => 'リストを逆順にする';

  @override
  String get seasons => 'シーズン';

  @override
  String get goToEpisode => '話へ移動';

  @override
  String get episodeNumber => '話数';

  @override
  String get cancelDownload => 'ダウンロードをキャンセル';

  @override
  String get downloaded => 'ダウンロード済み';

  @override
  String get downloadChapter => '章をダウンロード';

  @override
  String get deleteDownload => 'ダウンロードを削除';

  @override
  String get resumeDownload => 'ダウンロードを再開';

  @override
  String get status => '状態';

  @override
  String get year => '年';

  @override
  String get studio => 'スタジオ';

  @override
  String get genres => 'ジャンル';

  @override
  String get synopsis => 'あらすじ';

  @override
  String get readMore => '続きを読む';

  @override
  String get downloadChooseServer => 'ダウンロード · サーバーを選択';

  @override
  String get noDownloadSourcesFound => 'ダウンロード用ソースが見つかりません';

  @override
  String get audio => 'オーディオ';

  @override
  String get noEpisodesMatch => '一致するエピソードがありません';

  @override
  String get selectEpisodes => 'エピソードを選択';

  @override
  String get startFrom => '開始位置';

  @override
  String get jumpToEpisode2 => '話へジャンプ';

  @override
  String get downloadEpisodes => 'エピソードをダウンロード';

  @override
  String get noEpisodes => 'エピソードがありません';

  @override
  String get dub2 => '吹替';

  @override
  String get autoBestAvailable => '自動 · 利用可能な最高';

  @override
  String get linksReloaded => 'リンクを再読み込みしました';

  @override
  String get noSourcesFoundForThisEpisode => 'この話のソースが見つかりません';

  @override
  String get starring => '出演';

  @override
  String get creators => '制作';

  @override
  String get notify => '通知する';

  @override
  String get stopAlerts => '通知を停止';

  @override
  String get trackedEditStatusScoreProgress => '記録中 — ステータス、スコア、進捗を編集';

  @override
  String get openSourceSite => 'ソースサイトを開く';

  @override
  String get signInToSource => 'サインイン';

  @override
  String get welcomeBack => 'おかえりなさい';

  @override
  String get signInToSyncYourListAcrossDevices => 'サインインして、リストを端末間で同期。';

  @override
  String get logIn => 'ログイン';

  @override
  String get passwordMustBeAtLeast8Characters => 'パスワードは 8 文字以上にしてください';

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get saveYourListAndContinueWatchingAnywhere => 'リストを保存して、どこでも続きから視聴。';

  @override
  String get notSignedIn => '未サインイン';

  @override
  String get haveTheApp => 'アプリをお持ちですか？';

  @override
  String get openZangetsuOnYourNphoneAndScan =>
      'スマホで Zangetsu を開き、\\nスキャンしてください';

  @override
  String get noApp => 'アプリがありませんか？';

  @override
  String get resetPassword => 'パスワードをリセット';

  @override
  String get youExampleCom => 'あなた@example.com';

  @override
  String get sendLink => 'リンクを送信';

  @override
  String get email => 'Eメール';

  @override
  String get password => 'パスワード';

  @override
  String get forgotPassword => 'パスワードをお忘れですか？';

  @override
  String get name => '名前';

  @override
  String get password8Characters => 'パスワード（8 文字以上）';

  @override
  String get editName => '名前を編集';

  @override
  String get yourName => 'あなたの名前';

  @override
  String get couldnTUpdateYourName => '名前を更新できませんでした';

  @override
  String get pairATV => 'テレビをペアリング';

  @override
  String get addPhoto => '写真を追加';

  @override
  String get backUpBeforeLoggingOut => 'ログアウト前にバックアップしますか？';

  @override
  String get logOutAnyway => 'このままログアウト';

  @override
  String get reconnect => '再接続';

  @override
  String get signInWithYourPhone => 'スマホでサインイン';

  @override
  String
  get onTheZangetsuAppOnYourPhoneOpenNPairATVAndEnterThisCodeOrScanTheQR =>
      'スマホの Zangetsu で「テレビをペアリング」を開き、\\nこのコードを入力するか、QR をスキャンしてください。';

  @override
  String get signingIn => 'サインイン中…';

  @override
  String get getANewCode => '新しいコードを取得';

  @override
  String get sendTrackers => 'トラッカーを送信';

  @override
  String get chooseTrackersToSend => '送信するトラッカーを選択';

  @override
  String get sendToTV => 'テレビに送信';

  @override
  String get signInToYourAccountFirstNthenPairYourTV =>
      '先にアカウントにサインインし、\\nテレビをペアリングしてください。';

  @override
  String get enterTheCodeFromYourTV => 'テレビに表示されたコードを入力';

  @override
  String get openZangetsuOnYourTVAndSignInWithYourPhoneToSeeIt =>
      'テレビで Zangetsu を開き、スマホでサインインすると表示されます。';

  @override
  String get abcd2345 => 'ABCD 2345';

  @override
  String get thisTVWillSignIntoYourAccountYouCanSignItOutLater =>
      'このテレビがアカウントにサインインします。後から切断できます。';

  @override
  String get alsoSendYourTrackersAniListMyAnimeListSimkl =>
      'トラッカーも送信（AniList、MyAnimeList、Simkl）';

  @override
  String get yourTVIsSignedIn => 'テレビはサインイン済みです';

  @override
  String get itShouldSwitchToYourAccountInAMoment => 'まもなくアカウントに切り替わります。';

  @override
  String get backedUpToCloud => 'クラウドにバックアップしました';

  @override
  String get couldnTSaveTheBackupFileStoragePermissionMayBeNeeded =>
      'バックアップを保存できません — ストレージの許可が必要な場合があります。';

  @override
  String get noCloudBackupFound => 'クラウドのバックアップがありません';

  @override
  String get thatFileIsnTAValidBackup => 'そのファイルは有効なバックアップではありません。';

  @override
  String get pickABackup => 'バックアップを選択';

  @override
  String get couldnTReadThatBackupFile => 'そのバックアップファイルを読めませんでした。';

  @override
  String get restoreComplete => '復元が完了しました';

  @override
  String get reopenZangetsuToSeeRestoredLibrarySources =>
      'Zangetsu を開き直すと、復元したライブラリとソースが表示されます。';

  @override
  String get saveToAFile => 'ファイルに保存';

  @override
  String get saveABackupFileToYourDownloadsFolder => 'ダウンロードフォルダーにバックアップを保存';

  @override
  String get backUpToCloud => 'クラウドにバックアップ';

  @override
  String get saveACopyToYourAccountNeedsSignIn => 'アカウントにコピーを保存 · サインインが必要';

  @override
  String get restoreFromAFile => 'ファイルから復元';

  @override
  String get pickABackupFileYouSavedEarlier => '以前保存したバックアップを選択';

  @override
  String get restoreFromCloud => 'クラウドから復元';

  @override
  String get bringBackYourLatestCloudBackup => '最新のクラウドバックアップを戻す';

  @override
  String get episodesYouDownloadAppearHere => 'ダウンロードしたエピソードがここに表示されます';

  @override
  String get deleteAllEpisodes => 'すべてのエピソードを削除';

  @override
  String get deleteAllDownloads => 'すべてのダウンロードを削除しますか？';

  @override
  String get deleteAll => 'すべて削除';

  @override
  String get changeDownloadFolder => 'ダウンロードフォルダーを変更';

  @override
  String get savingTo => '保存先';

  @override
  String get needsAFileManagerAppOnTheTV => 'テレビにファイル管理アプリが必要です';

  @override
  String get downloadLocation => 'ダウンロード先';

  @override
  String get novelChaptersYouDownloadAppearHere => 'ダウンロードした小説の章がここに表示されます';

  @override
  String get stopDownloading => 'ダウンロードを止めますか？';

  @override
  String get keepGoing => '続ける';

  @override
  String get stopAll => 'すべて停止';

  @override
  String get searchDownloads => 'ダウンロードを検索';

  @override
  String get deleteAllChapters => 'すべての章を削除';

  @override
  String get deleteAllChapters2 => 'すべての章を削除しますか？';

  @override
  String get chapter => '章';

  @override
  String get downloadSettings => 'ダウンロード設定';

  @override
  String get parallelDownloads => '同時ダウンロード数';

  @override
  String get connectionsPerDownload => 'ダウンロードあたりの接続数';

  @override
  String get novels => '小説';

  @override
  String get noDownloadsMatchYourSearch => '検索に一致するダウンロードがありません';

  @override
  String get collapseAll => 'すべて折りたたむ';

  @override
  String get requestedControl => '操作をリクエストしました';

  @override
  String get noParticipantsYet => 'まだ参加者がいません';

  @override
  String get guest => 'ゲスト';

  @override
  String get wantsControl => '操作を希望';

  @override
  String get giveControl => '操作を渡す';

  @override
  String get hostControlsPlayback => 'ホストが再生を操作';

  @override
  String get requestControl => '操作をリクエスト';

  @override
  String get inviteCopied => '招待をコピーしました';

  @override
  String get roomChat => 'ルームチャット';

  @override
  String get noMessagesYet => 'まだメッセージはありません';

  @override
  String get message => 'メッセージ…';

  @override
  String get invite => '招待';

  @override
  String get watchTogether => '一緒に視聴';

  @override
  String get createARoom => 'ルームを作成';

  @override
  String get joinWithACode => 'コードで参加';

  @override
  String get roomNotFound => 'ルームが見つかりません';

  @override
  String get enterRoomCode => 'ルームコードを入力';

  @override
  String get eGABC234 => '例: ABC234';

  @override
  String get hostIsChoosing => 'ホストが選択中…';

  @override
  String get youLlStartWatchingAutomaticallyWhenTheHostPlaysSomething =>
      'ホストが再生を始めると、自動で視聴が始まります。';

  @override
  String get participants => '参加者';

  @override
  String get signInToUseWatchParty => 'サインインして同時視聴を使う';

  @override
  String get youReAlreadyInAParty => 'すでにパーティに参加しています';

  @override
  String get watchTogether2 => '一緒に視聴';

  @override
  String get createAPartyAndInviteFriendsOrJoinAnExistingOneWithACode =>
      'パーティを作って友達を招待するか、コードで既存のパーティに参加。';

  @override
  String get aniyomiIsnTAvailableOnThisDevice => 'この端末では Aniyomi を利用できません。';

  @override
  String get installed => 'インストール済み';

  @override
  String get repositories => 'リポジトリ';

  @override
  String get languages => '言語';

  @override
  String get addAniyomiRepo => 'Aniyomi リポジトリを追加';

  @override
  String get noAniyomiSourcesInstalled => 'Aniyomi ソースはインストールされていません。';

  @override
  String get removeRepo => 'リポジトリを削除しますか？';

  @override
  String get noAniyomiReposAddedYetNPressAddAniyomiRepoToAddOne =>
      'Aniyomi リポジトリはまだありません。\\n「Aniyomi リポジトリを追加」で追加してください。';

  @override
  String get addRepository => 'リポジトリを追加';

  @override
  String get searchNovelSources => '小説ソースを検索';

  @override
  String get noSourcesInstalledYet => 'ソースはまだインストールされていません。';

  @override
  String get addNovelRepo => '小説リポジトリを追加';

  @override
  String get removeRepository => 'リポジトリを削除';

  @override
  String get noSourcesInThisRepo => 'このリポジトリにソースはありません。';

  @override
  String get zangetsuProviders => 'Zangetsu プロバイダー';

  @override
  String get addRepo => 'リポジトリを追加';

  @override
  String get communityRepos => 'コミュニティリポジトリ';

  @override
  String get noProvidersInstalled => 'プロバイダーはインストールされていません。';

  @override
  String get noSourcesInThisRepoYet => 'このリポジトリにソースはまだありません。';

  @override
  String get leaveBlankToUseTheRepoSOwnName => '空欄のままにするとリポジトリ名を使います';

  @override
  String get addCloudStreamRepo => 'CloudStream リポジトリを追加';

  @override
  String get noCloudStreamSourcesInstalled => 'CloudStream ソースはインストールされていません。';

  @override
  String get cloudstream => 'クラウドストリーム';

  @override
  String get sourceSettings => 'ソース設定';

  @override
  String get otherSettings => 'その他の設定';

  @override
  String get otherSettingsSubtitle => 'このソースには、ここではまだ表示できない設定があります';

  @override
  String get sourceDomain => 'ソースのドメイン';

  @override
  String get sourceDomainHint => '空欄にすると、ソース本来のドメインを使用します。';

  @override
  String resetSourceDataConfirm(String name) {
    return '$nameの保存データをリセットしますか?保存された設定、ログイン情報、Cookieが削除されます。リスト、履歴、ダウンロードには影響しません。';
  }

  @override
  String get removeRepository2 => 'リポジトリを削除しますか？';

  @override
  String get removeThisRepositoryAndItsSources => 'このリポジトリとそのソースを削除しますか？';

  @override
  String get removed => '削除しました';

  @override
  String get alreadyUpToDate => 'すでに最新です';

  @override
  String get removeRepo2 => 'リポジトリを削除';

  @override
  String get noInstallableSourcesFoundInThisRepo =>
      'このリポジトリにインストールできるソースがありません。';

  @override
  String get thisRemovesTheSourceFromYourInstalledList =>
      'インストール済みリストからこのソースを外します。';

  @override
  String get addCSRepo => 'CS リポジトリを追加';

  @override
  String get cloudstreamIsnTAvailableOnThisDevice =>
      'この端末では CloudStream を利用できません。';

  @override
  String get checkUpdates => '更新を確認';

  @override
  String get pasteACloudStreamRepositoryURL =>
      'CloudStream リポジトリの URL を貼り付けてください。';

  @override
  String get reTest => '再テスト';

  @override
  String get noEnabledSourcesToTest => 'テストする有効なソースがありません。';

  @override
  String get notSearched => '未検索';

  @override
  String get thisSourceHasNoSettings => 'このソースに設定はありません';

  @override
  String get resetToDefaults => '初期値に戻す';

  @override
  String get providerSettings => 'プロバイダー設定';

  @override
  String get openThisSourceSOwnSettingsEGServerLanguage =>
      'このソース独自の設定を開く（サーバー、言語など）';

  @override
  String get addZangetsuRepo => 'Zangetsu リポジトリを追加';

  @override
  String get theProviderWillBeRemovedFromYourInstalledSources =>
      'インストール済みソースからこのプロバイダーを外します。';

  @override
  String get addMihonRepo => 'Mihon リポジトリを追加';

  @override
  String get noMihonReposAddedYetNTapAddMihonRepoToAddOne =>
      'Mihon リポジトリはまだありません。\\n「Mihon リポジトリを追加」をタップしてください。';

  @override
  String get n1Update => '1件の更新';

  @override
  String get noExtensionsFoundInThisRepo => 'このリポジトリに拡張機能がありません。';

  @override
  String get thisRemovesTheExtensionFromYourInstalledSources =>
      'インストール済みソースからこの拡張機能を外します。';

  @override
  String get noMihonSourcesInstalled => 'Mihon ソースはインストールされていません。';

  @override
  String get noAniyomiReposAddedYetNTapAddAniyomiRepoToAddOne =>
      'Aniyomi リポジトリはまだありません。\\n「Aniyomi リポジトリを追加」をタップしてください。';

  @override
  String get clearAll => 'すべてクリア';

  @override
  String get nothingWatchedYet => 'まだ視聴した作品はありません';

  @override
  String get nothingReadYet => 'まだ読んだ作品はありません';

  @override
  String get checkingForNewEpisodes => '新しいエピソードを確認中…';

  @override
  String get checkNow => '今すぐ確認';

  @override
  String get turnOff => 'オフにする';

  @override
  String get joinBetaUpdates => 'ベータ更新に参加しますか？';

  @override
  String get joinBeta => 'ベータに参加';

  @override
  String get whatSNew => '更新内容';

  @override
  String get categories => 'カテゴリ';

  @override
  String get moviesSeries2 => '映画／シリーズ';

  @override
  String get longPressASourceToPinItToTheTop => 'ソースを長押しすると上部にピン留め';

  @override
  String get searchSources => 'ソースを検索';

  @override
  String get justLook => '見るだけ';

  @override
  String get moveProgressHere => '進捗をここに移す';

  @override
  String get newAniListList => '新しい AniList リスト';

  @override
  String get rewatchingFavourites => '再視聴、お気に入り、…';

  @override
  String get anilistCustomLists => 'AniList カスタムリスト';

  @override
  String get savedToYourAniListAccount => 'AniList アカウントに保存しました';

  @override
  String get newList => '新しいリスト';

  @override
  String get createsItOnAniList => 'AniList 上に作成します';

  @override
  String get yourTrackersDisagree => 'トラッカーの値が一致しません';

  @override
  String get applyingSetsThemAllToTheNumberBelow => '適用すると、すべて下の数字に揃えます。';

  @override
  String get wrongTitleChangeMatch => '違う作品ですか？  一致を変更';

  @override
  String get searchTheCorrectTitle => '正しいタイトルを検索…';

  @override
  String get noMatchesFound => '一致するものがありません';

  @override
  String get removeFromMyList => 'マイリストから外す';

  @override
  String get details => '詳細';

  @override
  String get noDescriptionAvailable => '説明はありません。';

  @override
  String get playWith => '再生アプリ…';

  @override
  String get playMirror => 'ミラーで再生';

  @override
  String get chooseTheSourceBeforeItStarts => '開始前にソースを選ぶ';

  @override
  String get reloadLinks => 'リンクを再読み込み';

  @override
  String get fetchFreshStreamsIfPlaybackKeepsFailing => '再生に失敗し続ける場合は新しい配信を取得';

  @override
  String get alsoUpdatesYourConnectedTrackers => '連携中のトラッカーも更新します';

  @override
  String get markThisAndAllAboveAsWatched => 'これより上をすべて視聴済みにする';

  @override
  String get playThisEpisodeWith => 'この話の再生方法';

  @override
  String get builtInPlayer => '内蔵プレーヤー';

  @override
  String get otherApps => 'ほかのアプリ';

  @override
  String get seeAll2 => 'すべて見る';

  @override
  String get webView => 'WebView';

  @override
  String get openInBrowser => 'ブラウザで開く';

  @override
  String get markAsRead => '既読にする';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get playbackLinkCopied => 'リンクをコピーしました';

  @override
  String get couldNotCopyLink => 'リンクをコピーできませんでした';

  @override
  String get removeTracking => 'トラッキングを解除';

  @override
  String get noTrackersConnectedNConnectOneInSettingsConnections =>
      'トラッカーが未接続です。\\n設定 → 連携 で接続してください。';

  @override
  String get syncAllAtOnce => 'まとめて同期';

  @override
  String get addTracking => 'トラッキングを追加';

  @override
  String get addToYourList => 'リストに追加';

  @override
  String get removeFromList => 'リストから外す';

  @override
  String get customLists => 'カスタムリスト';

  @override
  String get notInAny => '未分類';

  @override
  String get status2 => '状態';

  @override
  String get applyChanges => '変更を適用';

  @override
  String get navigationBar => 'ナビゲーションバー';

  @override
  String get navigationBarSubtitle => '表示するタブと順序';

  @override
  String get navDockBehavior => 'ドックの動作';

  @override
  String get keepDockExpanded => 'ドックを展開したままにする';

  @override
  String get keepDockExpandedSubtitle => 'スクロール中もラベルを表示したままにする';

  @override
  String connectedCount(int count) {
    return '$count件接続済み';
  }

  @override
  String get syncLibraryAlreadySynced => 'ライブラリはこのアカウントと同期済みです。';

  @override
  String syncLibraryPushed(int history, int list) {
    return '履歴$history件・リスト$list件をアカウントに同期しました。';
  }

  @override
  String navTabsOnBar(int count, int max) {
    return 'バー上 · $count/$max';
  }

  @override
  String episodeAirsIn(int episode, String when) {
    return '第$episode話 · $when';
  }

  @override
  String get duration => '再生時間';

  @override
  String get score => 'スコア';

  @override
  String get popularity => '人気度';

  @override
  String get favourites => 'お気に入り';

  @override
  String get sourceMaterial => '原作';

  @override
  String get country => '国';

  @override
  String get aired => '放送日';

  @override
  String get nativeTitle => '原題';

  @override
  String get alsoKnownAs => '別名';

  @override
  String get tags => 'タグ';

  @override
  String showSpoilerTags(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '#件のネタバレタグを表示',
    );
    return '$_temp0';
  }

  @override
  String get navTabsSwitcher => 'モード切替';

  @override
  String get navTabsSwitcherWhy => '中央の枠を使います';

  @override
  String get navTabsOpensOn => '起動時に開く';

  @override
  String get navTabsNotShown => '表示されていません';

  @override
  String get navTabsEveryTabOnBar => 'すべての勘定はバーカウンターに記されている。';

  @override
  String get searchMovesToHomeInZMode => 'Zモードでは検索がホームの上部に移動します。';

  @override
  String navTabsHelp(int minTabs, int maxTabs) {
    return 'ドラッグして並べ替えてください。 $minTabs～$maxTabs 個のタブがバーに表示されます。\n\nプロフィールは設定画面への唯一のアクセス方法であるため、ピン留めされています。非表示にすると、この画面に戻る方法がなくなります。スケジュールはストリーミングモードでのみ表示されます。閲覧中は放送スケジュールは表示されません。';
  }

  @override
  String get navTabsStreamingOnly => 'ストリーミング配信のみ';

  @override
  String get navTabsRemove => '取り除く';

  @override
  String navTabsKeepMinTabs(int min) {
    return '少なくとも $min 個のタブを保持する';
  }

  @override
  String get navTabsAdd => '追加';

  @override
  String get navTabsBarFull => 'バーは満員です';

  @override
  String filterShowResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '#件の結果を表示',
    );
    return '$_temp0';
  }

  @override
  String addedCloudStreamSourcesCount(int count) {
    return '追加済み — 利用可能なCloudStreamソース： $count ';
  }

  @override
  String failedToAddRepository(String error) {
    return 'リポジトリの追加に失敗しました: $error';
  }

  @override
  String get repositoryUrlLabel => 'リポジトリURL';

  @override
  String noResultsFor(String query) {
    return '「$query」の検索結果はありません';
  }

  @override
  String get yourSavedTitles => '保存したタイトル';

  @override
  String myListPlusTrackers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'trackers',
      one: 'tracker',
    );
    return 'マイリスト + $count $_temp0';
  }

  @override
  String get sort => '選別';

  @override
  String get shuffle => 'ランダムに選ぶ';

  @override
  String get giveItAName => '名前を付けて';

  @override
  String get youAlreadyHaveThatOne => 'あなたは既にそれを持っています';

  @override
  String get thatNameIsTaken => 'その名前は既に使われています';

  @override
  String get notConnected => '接続されていません';

  @override
  String connectedWithViewer(String name) {
    return '接続済み · $name';
  }

  @override
  String get allTypes => 'いろんなタイプ';

  @override
  String get nothingHereInThisFilter => 'このフィルターには何も含まれていません';

  @override
  String get noMangaHereInThisFilter => 'このフィルターにはマンガはありません';

  @override
  String get noNovelsHereInThisFilter => 'このフィルターには小説はありません';

  @override
  String get mangaYouAddAppearHere => '追加したマンガはここに表示されます';

  @override
  String get novelsYouAddAppearHere => 'あなたが追加した小説はここに表示されます';

  @override
  String get relations => '関係';

  @override
  String get characters => 'キャラクター';

  @override
  String get noCastInformation => 'キャスト情報なし';

  @override
  String get noRelatedTitles => '関連タイトルはありません';

  @override
  String get markedAsWatched => '視聴済みとしてマーク';

  @override
  String get markedUnwatched => '未視聴としてマークされました';

  @override
  String markedEpisodesAsWatched(int count) {
    return '視聴済みとして $count エピソードをマークしました';
  }

  @override
  String get openInBrowserSubtitle => 'この章をソースのサイトで読む';

  @override
  String get readingSettings => '読書設定';

  @override
  String get markedAsRead => '既読にしました';

  @override
  String get markedUnread => '未読にしました';

  @override
  String markedChaptersAsRead(int count) {
    return '$count章を既読にしました';
  }

  @override
  String downloadChaptersQuestion(int count) {
    return ' $count 章をダウンロードしますか？';
  }

  @override
  String get cachedSourceJsFiles => 'キャッシュされたソース.jsファイル';

  @override
  String disconnectTrackerQuestion(String name) {
    return '切断 $name?';
  }

  @override
  String trackerDisconnectBody(String name) {
    return '自動同期は停止します。お客様の $name アカウントは変更されていません。いつでも再接続できます。';
  }

  @override
  String connectedAs(String name) {
    return ' $nameとして接続済み';
  }

  @override
  String trackerConnectionCanceled(String name) {
    return '$name 接続がキャンセルされました';
  }

  @override
  String connectTracker(String name) {
    return '接続 $name';
  }

  @override
  String get connectingEllipsis => '接続中...';

  @override
  String updateTrackerAsYouWatch(String name) {
    return '視聴しながら $name を更新してください';
  }

  @override
  String findingTitle(String title) {
    return '「$title」を検索中…';
  }

  @override
  String titleIsntOnThisSource(String title) {
    return '\"$title\" はこのソースには含まれていません';
  }

  @override
  String couldntOpenTitle(String title) {
    return '\"$title\" を開けませんでした';
  }

  @override
  String get noWebPageForThisSource => 'この情報源のウェブページはありません';

  @override
  String get couldNotOpenSourceSite => 'ソースサイトを開けませんでした';

  @override
  String notificationsOffFor(String title) {
    return '「$title」の通知はオフになっています';
  }

  @override
  String youllBeNotifiedOfNewEpisodesFor(String title) {
    return '「$title」の新しいエピソードが公開されたら通知されます';
  }

  @override
  String youllBeNotifiedOfNewChaptersFor(String title) {
    return '「$title」の新しい章が公開されると通知されます';
  }

  @override
  String get external => '外部の';

  @override
  String episodeLabel(int number) {
    return 'エピソード $number';
  }

  @override
  String downloadSeasonEpisode(int season, int episode) {
    return 'ダウンロード S$season:E$episode';
  }

  @override
  String downloadEpisodeLabel(int episode) {
    return 'E$episodeをダウンロード';
  }

  @override
  String get continueLabel => '続く';

  @override
  String continueEpisode(int episode) {
    return '続行 E$episode';
  }

  @override
  String get noEpisodesToDownload => 'ダウンロードできるエピソードはありません';

  @override
  String get addedToDownloads => 'ダウンロードに追加されました';

  @override
  String downloadingNEpisodes(int count) {
    return ' $count エピソードをダウンロード中';
  }

  @override
  String get addToMyList => 'マイリストに追加';

  @override
  String get notifyOnNewChapters => '新しい章が配信されたら通知を受け取る';

  @override
  String get notifyOnNewEpisodes => '新しいエピソードの通知を受け取る';

  @override
  String get allowNotificationsForAlerts => '通知を受け取るにはAndroidの設定で通知を許可してください。';

  @override
  String get syncStatusScoreProgress => '同期状況、スコア、進捗状況';

  @override
  String seasonCount(int count) {
    return '$count Seasons';
  }

  @override
  String episodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countエピソード',
    );
    return '$_temp0';
  }

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count章',
    );
    return '$_temp0';
  }

  @override
  String get thisSourceNeedsSpecialHeadersUsingBuiltIn =>
      'このソースには、外部プレーヤーでは送信できない特別なヘッダーが必要です。そのため、内蔵プレーヤーを使用してください。';

  @override
  String timerMinutes(int count) {
    return '$count 分';
  }

  @override
  String couldNotLoadSubtitle(String error) {
    return '字幕を読み込めませんでした: $error';
  }

  @override
  String get speed => 'スピード';

  @override
  String get styledSubtitlesLibassSubtitle =>
      'リアルな.assスタイリング ― 看板、カラオケ。適用するにはエピソードを再度開いてください。';

  @override
  String couldntDownloadFile(String file) {
    return ' $fileをダウンロードできませんでした';
  }

  @override
  String get audioNormalizationSubtitle => '音量を均一化し、静かな会話を強調し、騒々しいシーンを抑えます。';

  @override
  String get playbackSpeed => '再生速度';

  @override
  String get quality => '品質';

  @override
  String get sources => '出典';

  @override
  String get shorts => 'ショート';

  @override
  String get reels => 'リール';

  @override
  String get normalSpeed => '普通';

  @override
  String get subtitles => '字幕';

  @override
  String preferredLanguageColon(String name) {
    return '優先言語: $name';
  }

  @override
  String nextCount(int count) {
    return '次へ $count';
  }

  @override
  String allCount(int count) {
    return 'すべて $count';
  }

  @override
  String notSavedCount(int count) {
    return '$count 保存されませんでした';
  }

  @override
  String get airsIn => '放送日';

  @override
  String get selectAll => 'すべて選択';

  @override
  String get best => '最高';

  @override
  String get direct => '直接';

  @override
  String get hls => 'HLS';

  @override
  String serverWithHost(int number, String host) {
    return 'サーバー $number · $host';
  }

  @override
  String serverNumber(int number) {
    return 'サーバー $number';
  }

  @override
  String downloadCountEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countエピソードをダウンロード',
    );
    return '$_temp0';
  }

  @override
  String downloadSizeEstimate(String perEpisode, String total) {
    return '1話あたり$perEpisode · 合計$total';
  }

  @override
  String get storageLowTitle => '空き容量が足りませんか？';

  @override
  String storageLowBody(String need, String free) {
    return '約$need必要ですが、空きは$freeしかありません。それでもダウンロードしますか？';
  }

  @override
  String get downloadAnyway => 'それでもダウンロード';

  @override
  String get chapterOneAtATimeWarning =>
      'これは一度に1章ずつ再生されるため、時間がかかる場合があります。ダウンロード画面から停止できます。';

  @override
  String queuedChapters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
    );
    return 'キューに追加済み $_temp0';
  }

  @override
  String seasonNumber(int number) {
    return 'シーズン $number';
  }

  @override
  String get listView => 'リストビュー';

  @override
  String get gridView => 'グリッドビュー';

  @override
  String get refreshingChapters => '爽快な章立て…';

  @override
  String get refreshingEpisodes => '爽快なエピソード…';

  @override
  String chapterLabel(int number) {
    return 'Chapter $number';
  }

  @override
  String get continueBadge => '続く';

  @override
  String get fillerBadge => 'フィラー';

  @override
  String get downloadUnsupported => 'ダウンロード対象外';

  @override
  String get retryDownload => 'ダウンロードを再試行';

  @override
  String get downloadEpisode => 'エピソードをダウンロード';

  @override
  String get pauseDownload => 'ダウンロードを一時停止';

  @override
  String fromEpisode(int episode) {
    return 'E$episodeから';
  }

  @override
  String episodeWithTitle(int number, String title) {
    return 'E$number · $title';
  }

  @override
  String episodeNumberShort(int number) {
    return 'E$number';
  }

  @override
  String episodeRange(int first, int last) {
    return 'E$first – E$last';
  }

  @override
  String episodeSemanticWithTitle(int number, String title) {
    return 'エピソード $number、 $title';
  }

  @override
  String searchColon(String query) {
    return '検索: $query';
  }

  @override
  String decoderColon(String label) {
    return 'デコーダー・ $label';
  }

  @override
  String get megaSkipDuration => 'MegaSkipの期間';

  @override
  String get settingsTooltip => '設定';

  @override
  String episodeCountWithRange(int count, String range) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countエピソード',
    );
    return '$_temp0 · $range';
  }

  @override
  String get sourceTimedOut => 'タイムアウト';

  @override
  String get blockedByTheSite => 'サイトによってブロックされました';

  @override
  String get sourceCouldntBeReached => '連絡が取れませんでした';

  @override
  String get thatSourceCouldNotBeReached => 'その情報源には連絡が取れませんでした';

  @override
  String get noSourceCouldBeReached => '情報源に連絡が取れなかった';

  @override
  String andNMore(int count) {
    return 'その他 $count 件';
  }

  @override
  String get tryClearingYourFiltersOrSearchDifferentTitle =>
      'フィルターを解除するか、別のタイトルで検索してみてください。';

  @override
  String noModeSourcesYet(String mode) {
    return 'まだ $mode ソースがありません';
  }

  @override
  String get browseRepositories => 'リポジトリを閲覧する';

  @override
  String filteredSource(String source) {
    return 'フィルタリング済み · $source';
  }

  @override
  String get turnAllOn => 'すべてオンにする';

  @override
  String get sortUpper => '選別';

  @override
  String get typeUpper => 'タイプ';

  @override
  String get audioUpper => 'オーディオ';

  @override
  String get genreUpper => 'ジャンル';

  @override
  String get movieLabel => '映画';

  @override
  String get speakTheTitle => 'タイトルを言ってください';

  @override
  String get signedIn => 'ログイン済み';

  @override
  String get syncYourListNav => 'リストを同期する';

  @override
  String get sourceNavLabel => 'ソース';

  @override
  String get activeSourceHint => '現在';

  @override
  String clearKindHistoryTitle(String kind) {
    return 'Clear $kind history?';
  }

  @override
  String clearKindHistoryBody(String noun, String kind) {
    return 'これにより、 $kind の履歴から $noun がすべて削除されます。その他の履歴、リスト、ダウンロードは影響を受けません。';
  }

  @override
  String get showsYouWatchWillAppearHere =>
      '視聴した番組はここに表示されるので、中断したところから視聴を再開できます。';

  @override
  String get mangaYouReadWillAppearHere =>
      '読んだ漫画はここに表示されるので、中断したところから読み始めることができます。';

  @override
  String get novelsYouReadWillAppearHere =>
      '読んだ小説はここに表示されるので、中断したところから読み始めることができます。';

  @override
  String episodeWatchedPct(int number, int percent) {
    return 'エピソード $number · $percent%視聴済み';
  }

  @override
  String percentWatched(int percent) {
    return '$percent% watched';
  }

  @override
  String addSourceFromProvidersHint(String content) {
    return 'プロバイダーからソースを追加すると、 $content がここに表示されます。';
  }

  @override
  String continueDotEpisode(int episode) {
    return '続行 · E$episode';
  }

  @override
  String sourceNameItemCount(String name, int count) {
    return '$name · $count';
  }

  @override
  String sourceCountBadge(String sourceName, int count) {
    return '$sourceName $count';
  }

  @override
  String get logOutQuestion => 'ログアウト？';

  @override
  String get contentShows => 'ショー';

  @override
  String get contentManga => 'マンガ';

  @override
  String get contentNovels => '小説';

  @override
  String get historyKindWatch => '時計';

  @override
  String get historyKindManga => 'マンガ';

  @override
  String get historyKindNovel => '小説';

  @override
  String get historyNounShow => '見せる';

  @override
  String get historyNounMangaItem => 'マンガ';

  @override
  String get historyNounNovelItem => '小説';

  @override
  String get qualityAndAudio => '品質とオーディオ';

  @override
  String get sectionPlayer => 'プレーヤー';

  @override
  String get sectionGestures => 'ジェスチャー';

  @override
  String get sectionCache => 'キャッシュ';

  @override
  String get gestures => 'ジェスチャー';

  @override
  String get cache => 'キャッシュ';

  @override
  String get social => '社交';

  @override
  String get appSection => 'アプリ';

  @override
  String get team => 'チーム';

  @override
  String get communityContributors => 'コミュニティ貢献者';

  @override
  String get accentColour => 'アクセントカラー';

  @override
  String get display => '画面';

  @override
  String get appIcon => 'アプリのアイコン';

  @override
  String get splashStyle => 'スプラッシュ';

  @override
  String get splashStyleBlurb => 'アプリ起動中に表示されるもの。';

  @override
  String get currentLocation => '現在位置';

  @override
  String get availableDrives => '利用可能なドライブ';

  @override
  String get dataSection => 'データ';

  @override
  String get modeLabel => 'モード';

  @override
  String get tapAZoneToChangeIt => '変更するにはゾーンをタップしてください';

  @override
  String get supportTitle => 'サポート';

  @override
  String enjoyingApp(String appName) {
    return ' $appNameを楽しんでいますか？';
  }

  @override
  String donateBlurb(String appName) {
    return '$appName は無料で広告も表示されません。もしあなたのホーム画面にこのアプリを置いてくださっているなら、ちょっとしたチップをいただけると、新機能の追加、バグ修正、アップデートの迅速化など、アプリの成長につながります。どんな小さなご支援でも本当に助かります。ありがとうございます！♥';
  }

  @override
  String get upiIdCopied => 'UPI IDがコピーされました';

  @override
  String get upiIndia => 'UPI · インド';

  @override
  String get askBeforeJumpingSubtitle => '中断した場所以外の場所を開くと、進行状況が移動せずに検索できます。';

  @override
  String get autoTrackSubtitle =>
      '視聴しながらAniList、MyAnimeList、Simklを更新してください。Offモードでは、手動でタイトルを追跡できます。';

  @override
  String get closeConfirmationAsk => 'プレイヤーを離れる前に尋ねてください';

  @override
  String get closeConfirmationDirect => 'すぐに退出してください。';

  @override
  String get closeConfirmationDoubleBack => '戻るボタンを2回押して終了します';

  @override
  String get autoSkipFillerSubtitle => '次のエピソードに進む際に、フィラー部分をスキップしてください（アニメのみ）';

  @override
  String get playTrailersInHDSubtitle =>
      '利用可能な場合は最大1080p、利用できない場合は標準画質にフォールバックします。データ使用量が増えます。';

  @override
  String get nativeTvPlayerSubtitle => '推奨。古いプレーヤーの方が好みの場合のみオフにしてください。';

  @override
  String get softwareAudioSubtitle =>
      'Dolby/DTS音声が無音の場合のみオンにしてください。一部のテレビでは不安定になる場合があります。';

  @override
  String get playerInfoOff => 'オフ';

  @override
  String playerInfoFieldsCount(int count) {
    return '$count 個のフィールド（ⓘボタン）';
  }

  @override
  String downloadingPercent(int percent) {
    return 'ダウンロード中… $percent%';
  }

  @override
  String get tapToDownloadShaders => 'タップしてシェーダーをダウンロード（約0.8MB）';

  @override
  String get noOtherVideoAppsFound =>
      '他の動画アプリは見つかりませんでした。MX Player、VLC、mpv、Just Player、またはNext Playerをインストールしてください。';

  @override
  String get externalApp => '外部アプリ';

  @override
  String get noSubsResumeSuffix => '・履歴書/代替案なし';

  @override
  String get pickWhatShowsOverVideo =>
      '動画の上に表示する内容を選択してください（コントロールと一緒に表示されます）。YouTubeの「オタク向け統計情報」のようなものです。';

  @override
  String get styledSubtitlesLibassSubtitlePlayback =>
      'リアルな.assスタイル ― フォント、配置、カラオケ、記号。アニメに最適。次回のエピソードから適用されます。';

  @override
  String get aiDub => 'AI吹き替え';

  @override
  String get aiDubSubtitle => '端末の音声で字幕を読み上げます';

  @override
  String get voiceEngine => '音声エンジン';

  @override
  String get voiceEngineSubtitle =>
      '端末の音声は即時でオフラインでも動作します。ニューラル音声は人間らしいですが接続が必要です';

  @override
  String get voiceEngineDevice => '端末';

  @override
  String get voiceEngineDeviceSubtitle => 'この端末にインストールされた音声。即時、オフライン。';

  @override
  String get voiceEngineNeural => 'ニューラル';

  @override
  String get voiceEngineNeuralSubtitle => '人間らしく聞こえるホスト音声。接続が必要です。';

  @override
  String get neuralVoiceLanguage => '話す言語';

  @override
  String get neuralVoiceLanguageSubtitle => 'ホスト音声が話す言語';

  @override
  String get followsNarrationLanguage => 'ナレーションの言語に従う';

  @override
  String get transcribeSubtitles => '字幕を文字起こし';

  @override
  String get transcribeSubtitlesSubtitle => 'このエピソードの音声を文字起こしサービスに送信します';

  @override
  String get transcribeAudio => '音声を文字起こし';

  @override
  String get transcribeAudioSubtitle => '再生中の音声を文字起こしサービスで字幕にします';

  @override
  String get transcriptionEndpoint => '文字起こしエンドポイント';

  @override
  String get transcriptionEndpointSubtitle =>
      'OpenAI 互換の /audio/transcriptions エンドポイントの完全な URL';

  @override
  String get transcriptionKey => '文字起こしキー';

  @override
  String get transcriptionKeySubtitle => '文字起こしサービスの API キー';

  @override
  String get transcriptionModel => '文字起こしモデル';

  @override
  String get transcriptionModelSubtitle => 'エンドポイントが要求するモデル名（例: whisper-1）';

  @override
  String get subtitleStyleSubtitle => 'フォント、色、アウトライン、透明度、サイズ、位置 — ライブプレビュー付き';

  @override
  String get keySavedOnlineSearchEnabled => 'キーが保存されました - オンライン検索が有効になりました';

  @override
  String get incognitoModeBlurb =>
      'オンになっている間は、検索、視聴履歴、トラッカーのスクロブリング、Discordのプレゼンスが一時停止され、オフにするまで何も記録されません。';

  @override
  String get enableNsfwSourcesBody =>
      'これは、ソースリストと切り替え画面で18歳以上向けのコンテンツを表示する機能です。成人向けコンテンツを表示したい場合のみ、この機能をオンにしてください。';

  @override
  String get showNsfwAniyomiSourcesBody =>
      'これは、ソースリストとスイッチャーで、Aniyomi拡張機能が18歳以上向けとしてフラグ付けされていることを示します。成人向けコンテンツを表示したい場合のみ、この機能を有効にしてください。';

  @override
  String get sourcesMarked18Hidden =>
      '18歳以上向けのコンテンツとしてマークされたソースは、この設定が有効になっていない限り、ソース一覧とソース切り替え機能から非表示になります。';

  @override
  String get syncProgressAsYouWatch => '視聴しながら進行状況を同期';

  @override
  String get connectionsBlurb =>
      '視聴状況とリストの状態をアカウント間で同期します。アニメは3つのアカウントすべてに同期され、映画とシリーズはSimklに同期されます。';

  @override
  String get connectDiscord => 'Discordに接続する';

  @override
  String get signInSoYourStatusCanShow => 'サインインすると、あなたのステータスがプロフィールに表示されます';

  @override
  String get disconnectDiscordBody =>
      'Rich Presenceは停止し、このデバイスからトークンが削除されます。Discordアカウントは変更されません。いつでも再接続できます。';

  @override
  String get discordPresenceBlurb =>
      'アプリを開いている間、Discordプロフィールに「視聴中： <title> • エピソードN」（および閲覧中のコンテンツ）を表示します。Discordのログイン情報を使用し、このデバイスにのみ保存されます。いつでもオフにできます。';

  @override
  String get github => 'GitHub';

  @override
  String get telegram => 'Telegram';

  @override
  String get accentColourBlurb => 'ボタン、チップ、進行状況、選択されたアイテム全体で使用されるハイライトカラー。';

  @override
  String get appIconBlurb =>
      'ホーム画面上のアイコンです。アイコンを変更するとZangetsuが閉じます。Androidがランチャーのエントリを切り替える必要があるためです。';

  @override
  String useTheIcon(String label) {
    return ' $label アイコンを使用しますか？';
  }

  @override
  String get useTheIconBody =>
      'Androidが新しいアイコンを適用するため、Zangetsuは一時的に閉じます。その後、ホーム画面から再度起動してください。\n\nZangetsuがフォルダやドックにある場合は、再度追加する必要があるかもしれません。';

  @override
  String get animRise => '上昇';

  @override
  String get animRiseDesc => 'リフトとフェードイン';

  @override
  String get animFade => 'フェード';

  @override
  String get animFadeDesc => 'フェードイン、動きなし';

  @override
  String get animZoom => 'ズーム';

  @override
  String get animZoomDesc => '見た目通りに拡大します';

  @override
  String get usedInVerticalMode => '縦型モードで使用する場合、章は1つの連続した帯状部分として表示されます。';

  @override
  String get usedWhenPagesTurn =>
      'ページが左右にめくる際に使用します。右から左への表示モードでは、2つのページングゾーンが入れ替わります。';

  @override
  String get openPullRequestOnGitHub =>
      'GitHubでプルリクエストを作成すると、あなたの名前が自動的にここに表示されます。';

  @override
  String get onThisDevice => 'このデバイスでは';

  @override
  String get newDownloadsSaveHere =>
      '新規ダウンロードはここに保存されます。既に完了したダウンロードは元の場所に残ります。';

  @override
  String get torrentsOffWifiBlurb =>
      'オフ＝トレントはWi-Fi接続時のみ動作します（モバイルデータ通信量を節約できます）。トレントのストリーミング再生は大量のデータ通信量を消費します。';

  @override
  String get everyControlIsOnABar => 'すべての操作部はバー上に配置されています。';

  @override
  String get nothingHereMoveControl => 'ここには何もありません。Moveを使ってコントロールを移動させてください。';

  @override
  String get playerControlsHelp =>
      'バー内でドラッグして並べ替えることができます。移動ボタンを使ってコントロールを別の場所に移動できます。非表示のコントロールは、プレーヤー内の「⋮ その他」メニューから引き続き利用できます。\n\n「戻る」「ロック」「設定」は上部のバーに固定されており、番組タイトルも同じ行に表示されます。上部に要素を追加すればするほど、タイトルの表示スペースは狭くなります。';

  @override
  String topBarFull(String label) {
    return '$label （フル）';
  }

  @override
  String get apiKeyLabel => 'APIキー';

  @override
  String secondsShort(int count) {
    return '$count秒';
  }

  @override
  String get gotIt => 'わかった';

  @override
  String signInToAction(String action) {
    return ' $actionにサインインしてください';
  }

  @override
  String get cloudBackupFailed =>
      'クラウドバックアップに失敗しました。インターネット接続を確認してください。繰り返し失敗する場合は、クラウドバックアップストアがまだ設定されていない可能性があります。';

  @override
  String get savedToDownloadsZangetsu => 'ダウンロードに保存済み › 斬月';

  @override
  String restoreFailed(String error) {
    return '復元に失敗しました: $error';
  }

  @override
  String get noBackupFilesOnDevice =>
      'このデバイスにはバックアップファイルが見つかりませんでした。まずバックアップファイルを保存するか、「クラウドから復元」を使用してください。';

  @override
  String get backupScreenBlurb =>
      'ソース、リスト、設定を、デバイス上のファイルまたはZangetsuアカウントに保存してください。復元しても、既存のデータは追加されるだけで、削除されることはありません。';

  @override
  String get includeInTheBackup => 'バックアップに含める';

  @override
  String get sourcesAndRepos => 'ソースとリポジトリ';

  @override
  String get installedSourcesAndRepoLinks => 'インストール済みのソースとそのリポジトリへのリンク';

  @override
  String get libraryBundle => '図書館';

  @override
  String get myListAndContinueWatching => 'マイリストと視聴を続ける';

  @override
  String get appSettingsBundle => 'アプリ設定';

  @override
  String get playerSubtitlesQualityPreferences => 'プレーヤー、字幕、画質、設定';

  @override
  String lastCloudBackup(String when) {
    return '最後のクラウドバックアップ: $when';
  }

  @override
  String get never => '一度もない';

  @override
  String restoredColon(String names) {
    return '復元済み: $names。';
  }

  @override
  String couldnTReinstall(String failures) {
    return '再インストールできませんでした:\n$failures';
  }

  @override
  String onLatestVersion(String versionSuffix) {
    return '最新バージョン$versionSuffixを使用しています。';
  }

  @override
  String get joinBetaUpdatesBody =>
      'プレリリース版をいち早く入手できます。不安定な場合もありますので、不具合が発生した場合は、この機能をオフにしてください。次回のアップデートで安定版に戻ります。いつでも利用を停止できます。';

  @override
  String get betaUpdateAvailable => 'ベータ版アップデートが利用可能です';

  @override
  String get updateAvailable => 'アップデートが利用可能';

  @override
  String get startingInstaller => 'インストーラーを起動しています…';

  @override
  String get couldnTOpenInstaller =>
      'インストーラーを開けませんでした。システム設定で「不明なアプリのインストールを許可する」を有効にしてから、もう一度お試しください。';

  @override
  String get downloadFailedCheckConnection =>
      'ダウンロードに失敗しました。接続状況を確認して、もう一度お試しください。';

  @override
  String get libraryIsntSavedReconnect =>
      'ライブラリはまだクラウドに保存されていません。ログアウトすると、このデバイスからライブラリが削除されます。先にバックアップするために再接続しますか？';

  @override
  String sessionExpiredEnterPassword(String account) {
    return 'Your session expired. Enter your password to reconnect $account and sync your library.';
  }

  @override
  String get yourAccount => 'あなたのアカウント';

  @override
  String get reconnecting => '再接続しています...';

  @override
  String get wrongPassword => 'パスワードが間違っています';

  @override
  String trackersSynced(String list) {
    return '同期されたトラッカー数: $list';
  }

  @override
  String signInOnDevice(String device) {
    return ' $deviceにサインインしますか？';
  }

  @override
  String get thisTV => 'このテレビ';

  @override
  String get announcements => 'お知らせ';

  @override
  String get subscribedShows => '購読番組';

  @override
  String get noNotificationsYet =>
      '通知はまだありません。\n\n番組のベルアイコンをタップすると、新しいエピソードが公開された際に通知が届きます。';

  @override
  String get hostBadge => 'ホスト';

  @override
  String controlGivenTo(String name) {
    return ' $nameに制御権が与えられた';
  }

  @override
  String get youReTheHost => 'あなたがホストです';

  @override
  String couldnTCreateParty(String error) {
    return 'パーティを作成できませんでした: $error';
  }

  @override
  String get series => 'シリーズ';

  @override
  String get movie => '映画';

  @override
  String epWithTime(String episode, String time) {
    return 'Ep $episode · $time';
  }

  @override
  String chooseChapterSemantic(String title, String subtitle) {
    return '$title、 $subtitle。章を選択してください';
  }

  @override
  String chapterProgress(int current, int total) {
    return '第 $current 章 / $total章';
  }

  @override
  String chapterNumber(int number) {
    return 'Chapter $number';
  }

  @override
  String activeSourceColon(String name) {
    return 'アクティブなソース: $name';
  }

  @override
  String settingsSemantic(String name) {
    return '$name、設定';
  }

  @override
  String get enterTheCodeShownOnTV => 'テレビ画面に表示されているコードを入力してください。';

  @override
  String get codeNotFoundExpired => 'そのコードは見つかりませんでした。有効期限が切れている可能性があります。';

  @override
  String get alsoSendTrackers => '追跡ツール（AniList、MyAnimeList、Simklなど）も送ってください。';

  @override
  String get scrollRowsOrSearch => 'ホーム画面で各行をスクロールするか、画面下部の検索をタップしてください。';

  @override
  String get openTitleAndPlay =>
      'タイトルを開いて「再生」をタップしてください。シリーズ作品の場合は、まずエピソードを選択してください。';

  @override
  String get switchSourceAtTop => '画面上部のソース名をタップして、別のソースに切り替えてください。';

  @override
  String get tapDownloadForOffline => 'タイトルをタップしてダウンロードすると、「ダウンロード」から後で視聴できます。';

  @override
  String get faqSourceNotWorkingQ => 'ソースが機能していませんか？';

  @override
  String get faqSourceNotWorkingA =>
      'ソースは変更される場合があります。上部からソースを切り替えるか、「設定」→「ソースの状態」を確認してください。';

  @override
  String get faqSubOrDubQ => '字幕版か吹き替え版か？';

  @override
  String get faqSubOrDubA => 'アニメ作品のタイトルにある字幕／吹き替え切り替え機能を使用してください。';

  @override
  String get faqDownloadsQ => 'ダウンロードしたファイルはどこにありますか？';

  @override
  String get faqDownloadsA => '設定 → ダウンロード — いつでもオフラインで視聴できます。';

  @override
  String get resetPasswordBody =>
      'アカウントに登録されているメールアドレスを入力してください。新しいパスワードを設定するためのリンクをお送りします。';

  @override
  String get couldnTSignIn => 'ログインできませんでした';

  @override
  String get aniyomi => 'アニヨミ';

  @override
  String get mihon => 'ミホン';

  @override
  String get lnreader => 'LNリーダー';

  @override
  String get zangetsu => '斬月';

  @override
  String get cloudStream => 'クラウドストリーム';

  @override
  String installedCount(int count) {
    return '$count インストール済み';
  }

  @override
  String installedName(String name) {
    return 'インストール済み $name';
  }

  @override
  String uninstalledName(String name) {
    return 'アンインストール済み $name';
  }

  @override
  String removedName(String name) {
    return '削除済み $name';
  }

  @override
  String updatedName(String name) {
    return ' $nameを更新しました';
  }

  @override
  String installFailed(String error) {
    return 'インストール失敗: $error';
  }

  @override
  String uninstallFailed(String error) {
    return 'アンインストールに失敗しました: $error';
  }

  @override
  String removeFailed(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String updateFailed(String error) {
    return '更新に失敗しました: $error';
  }

  @override
  String checkFailed(String error) {
    return 'チェック失敗: $error';
  }

  @override
  String failedToAddRepo(String error) {
    return 'リポジトリの追加に失敗しました: $error';
  }

  @override
  String uninstallNameQuestion(String name) {
    return 'アンインストール $name?';
  }

  @override
  String removeNameQuestion(String name) {
    return ' $nameを削除しますか？';
  }

  @override
  String updateNameToVersion(String name, String version) {
    return '$name、v$versionに更新';
  }

  @override
  String updateArrowVersion(String version) {
    return '更新 → v$version';
  }

  @override
  String get repoBaseUrl => 'リポジトリのベースURL';

  @override
  String get repoBaseUrlHint => 'https://.../repo';

  @override
  String get pluginIndexUrl => 'プラグインインデックスURL';

  @override
  String get pluginIndexUrlHint => 'https://.../plugins.min.json';

  @override
  String get manifestUrl => 'マニフェストURL';

  @override
  String get manifestUrlHint => 'https://.../index.json';

  @override
  String get repoUrl => 'リポジトリURL';

  @override
  String get repoUrlHint => 'https://.../repo.json';

  @override
  String get customNameOptional => 'カスタム名（任意）';

  @override
  String get leaveBlankToUseRepo => 'リポジトリを使用する場合は空欄のままにしてください。';

  @override
  String get alreadyInstalledSourcesStay =>
      'このリポジトリから既にインストールされているソースは、そのままインストールされた状態のままです。';

  @override
  String get alreadyInstalledExtensionsStay =>
      'このリポジトリから既にインストールされている拡張機能は、そのままインストールされたままになります。';

  @override
  String updateAllCount(int count) {
    return 'すべて更新 ($count)';
  }

  @override
  String updatedSourcesCount(int done, String suffix) {
    return '更新されたソース $done $suffix';
  }

  @override
  String get slow => '遅い';

  @override
  String get noResults => '結果がありません';

  @override
  String get timedOut => 'タイムアウト';

  @override
  String get blocked => 'ブロックされました';

  @override
  String get notUsable => '使用できません';

  @override
  String get openThisSource => 'このソースを開く';

  @override
  String nameRemovedFromSearch(String name) {
    return '$name が検索結果から削除されました';
  }

  @override
  String connectLabel(String label) {
    return '接続 $label';
  }

  @override
  String scanToLogInWith(String label) {
    return 'ブラウザで\n$label をスキャンしてログインしてください';
  }

  @override
  String get anilist => 'アニメリスト';

  @override
  String get myAnimeList => 'MyAnimeList';

  @override
  String get simkl => 'シムクル';

  @override
  String get code => 'コード';

  @override
  String get signInToBackUpToCloud => 'クラウドへ戻る';

  @override
  String get signInToRestoreFromCloud => 'クラウドから復元';

  @override
  String get signInToUseThis => 'これを使う';

  @override
  String get enabled => '有効';

  @override
  String get disabled => '無効';

  @override
  String sourcesCount(int count) {
    return '$count ソース';
  }

  @override
  String removeRepoSemantic(String name) {
    return '$name、リポジトリを削除';
  }

  @override
  String repoDisplaySemantic(String name) {
    return '$name、';
  }

  @override
  String entryInstalledSemantic(String name, String state) {
    return '$name、 $state';
  }

  @override
  String repoSourcesCount(String name, int count) {
    return '$name、 $count ソース';
  }

  @override
  String repoRefreshSemantic(String name) {
    return '$name、更新';
  }

  @override
  String repoUpdateAllSemantic(String name, int count) {
    return '$name、すべて更新（$count）';
  }

  @override
  String repoRemoveSemantic(String name) {
    return '$name、削除';
  }

  @override
  String sourceUpdateSemantic(String name) {
    return '$name、更新';
  }

  @override
  String sourceUninstallSemantic(String name) {
    return '$name、アンインストール';
  }

  @override
  String sourceInstallSemantic(String name) {
    return '$name、インストール';
  }

  @override
  String sourceSettingsSemantic(String name) {
    return '$name、設定';
  }

  @override
  String sourceRemoveSemantic(String name) {
    return '$name、削除';
  }

  @override
  String sourceEnabledSemantic(String name, String state) {
    return '$name、 $state';
  }

  @override
  String titleInstalledCount(String title, int count) {
    return '$title、 $count 個インストール済み';
  }

  @override
  String titleCheckUpdatesSemantic(String title) {
    return '$title、アップデートを確認してください';
  }

  @override
  String titleRemoveRepoSemantic(String title) {
    return '$title、リポジトリを削除';
  }

  @override
  String titleApplyUpdatesSemantic(String title, String what) {
    return '$title、 $whatを適用';
  }

  @override
  String get oneUpdate => '1件の更新';

  @override
  String nUpdates(int count) {
    return '$count 件の更新';
  }

  @override
  String percentRead(int percent) {
    return '$percent% read';
  }

  @override
  String get couldntLoadDownloadOptions => 'ダウンロードオプションを読み込めませんでした';

  @override
  String selectedEpisodesOfTotal(int selected, int total) {
    return '$selected of $total episodes';
  }

  @override
  String episodeSemantic(int number) {
    return 'エピソード $number';
  }

  @override
  String get textColour => 'テキストの色';

  @override
  String get textOpacity => 'テキストの不透明度';

  @override
  String get outlineStyle => 'アウトラインスタイル';

  @override
  String get ownStylingKept => '独自のスタイルを持つ字幕は、スタイル付き字幕が有効な間そのまま表示されます';

  @override
  String get outlineColour => '輪郭の色';

  @override
  String get outlineWidth => 'アウトラインの幅';

  @override
  String get positionTop => '上';

  @override
  String get positionBottom => '底';

  @override
  String get subtitleSize => 'サイズ';

  @override
  String get colourWhite => '白';

  @override
  String get colourYellow => '黄色';

  @override
  String get colourGreen => '緑';

  @override
  String get colourRed => '赤';

  @override
  String get colourBlack => '黒';

  @override
  String get tapToDownloadFont => 'タップしてダウンロード';

  @override
  String get subtitleOutlineNone => 'なし';

  @override
  String get subtitleOutlineSoft => 'ソフトシャドウ';

  @override
  String get subtitleOutlineOutline => '概要';

  @override
  String get subtitleOutlineBold => '太字のアウトライン';

  @override
  String get subtitleOutlineShadow => 'ドロップシャドウ';

  @override
  String get subtitleOutlineGlow => '光る';

  @override
  String noSubtitlesFoundFor(String query) {
    return '「$query」の字幕は見つかりませんでした。';
  }

  @override
  String searchFailedWithError(String error) {
    return '検索失敗: $error';
  }

  @override
  String downloadFailedWithError(String error) {
    return 'ダウンロード失敗: $error';
  }

  @override
  String decreaseDelay(String label) {
    return '減少 $label';
  }

  @override
  String increaseDelay(String label) {
    return '増加 $label';
  }

  @override
  String alignedDelay(String offset) {
    return '整列済み $offset';
  }

  @override
  String get subtitleSyncVoiceCaptured =>
      '音声が録音されました✓ — 字幕が表示されるまで再生し、「字幕が表示されました」をタップしてください。（このシートは閉じても構いません。）';

  @override
  String get subtitleSyncTextCaptured =>
      '字幕がキャプチャされました ✓ — セリフが聞こえたら、「音声が聞こえます」をタップします。';

  @override
  String get subtitleSyncHint => '自動同期：セリフが聞こえたらタップし、字幕が表示されたらタップしてください。';

  @override
  String get voiceHeard => '声が聞こえる';

  @override
  String get subtitleSeen => '字幕が表示されました';

  @override
  String get contrast => '対比';

  @override
  String get saturation => '飽和';

  @override
  String get gamma => 'ガンマ';

  @override
  String get hue => '色相';

  @override
  String get drm => 'DRM';

  @override
  String get sourceFallback => 'ソース';

  @override
  String get expandAll => 'すべて展開';

  @override
  String downloadedSummary(int count, String size) {
    return '$count ダウンロード · $size';
  }

  @override
  String ofTotalDownloaded(int done, int total) {
    return ' $total件中$done 件';
  }

  @override
  String episodesDownloadedOfTotal(int done, int total) {
    return '$done / $total ダウンロード済み';
  }

  @override
  String removeAllEpisodesOfShow(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return 'このデバイスから「$title」のすべての $_temp0 を削除しますか？';
  }

  @override
  String get mangaChaptersYouDownloadAppearHere =>
      'ダウンロードしたマンガのチャプターはここに表示されます';

  @override
  String get parallelDownloadsSubtitle =>
      '同時にダウンロードできるエピソード数はいくつですか？チャプターは常に1つずつダウンロードされます。';

  @override
  String get connectionsPerDownloadSubtitle =>
      'エピソードで使用されるセグメント接続数と、チャプター内で一度に取得されるページ数。数値が大きいほど高速で、一度に取得されるデータ量が多くなります。';

  @override
  String get savingToYourFolder => 'フォルダに保存しています…';

  @override
  String get notAvailableOfflineYet => 'オフラインではまだ利用できません';

  @override
  String get downloadFileGone => 'そのファイルはありません。アプリ外で削除された可能性があります';

  @override
  String get downloadQueued => 'キューに登録';

  @override
  String get downloadPreparing => '準備中…';

  @override
  String get downloadFinalizing => '処理中…';

  @override
  String downloadPausedProgress(int percent) {
    return '一時停止中 · $percent%';
  }

  @override
  String downloadProgressPercent(int percent) {
    return '$percent%';
  }

  @override
  String downloadProgressPercentOfSize(int percent, String size) {
    return '$percent%の $size';
  }

  @override
  String get downloadCanceled => 'キャンセル';

  @override
  String get downloadFailedStatus => '失敗した';

  @override
  String peerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countピア',
    );
    return '$_temp0';
  }

  @override
  String downloadSpeedMbps(String speed) {
    return '$speed MB/秒';
  }

  @override
  String downloadSpeedKbps(int speed) {
    return '$speed KB/秒';
  }

  @override
  String episodeWithTitleDot(int number, String title) {
    return 'E$number · $title';
  }

  @override
  String get mangaDownloads => 'マンガのダウンロード';

  @override
  String get novelDownloads => '小説のダウンロード';

  @override
  String get downloadingSection => 'ダウンロード中';

  @override
  String stopAllCount(int count) {
    return 'すべて停止 ($count)';
  }

  @override
  String clearFailedCount(int count) {
    return 'クリアに失敗しました（$count）';
  }

  @override
  String stopDownloadingBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count queued chapters',
      one: '1 queued chapter',
    );
    return 'キャンセル $_temp0。既にダウンロード済みのチャプターは保持されます。';
  }

  @override
  String clearedFailedCount(int count) {
    return 'クリア $count 失敗';
  }

  @override
  String chapterPagesProgress(int done, int total) {
    return '$done/$total ページ';
  }

  @override
  String showTitleQueued(String title) {
    return '$title · キューに追加済み';
  }

  @override
  String showTitleDownloading(String title) {
    return '$title · ダウンロード中…';
  }

  @override
  String showTitleWithError(String title, String error) {
    return '$title · $error';
  }

  @override
  String removeAllChaptersOfShow(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
    );
    return 'このデバイスから「$title」のすべての $_temp0 を削除しますか？';
  }

  @override
  String chaptersWithSize(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count章',
    );
    return '$_temp0 · $size';
  }

  @override
  String get deleteAllEpisodesTooltip => 'すべてのエピソードを削除';

  @override
  String get deleteAllChaptersTooltip => 'すべての章を削除';

  @override
  String get cancelDownloadTooltip => 'キャンセル';

  @override
  String get removeDownloadTooltip => '取り除く';

  @override
  String get positionLabel => '位置';

  @override
  String get relativeTomorrow => '明日';

  @override
  String get scheduleSlotMorning => '朝';

  @override
  String get scheduleSlotAfternoon => '午後';

  @override
  String get scheduleSlotEvening => '夕方';

  @override
  String get scheduleSlotLateNight => '深夜';

  @override
  String get nothingAiringOnThisDay => 'この日は何も放送されません。';

  @override
  String get nothingReleasingOnThisDay => 'この日は何もリリースされません。';

  @override
  String get noneOfFollowedAirOnThisDay => 'あなたが観ているアニメは、この日はどれも放送されません。';

  @override
  String get scheduleAired => '放送済み';

  @override
  String get scheduleLive => '● ライブ';

  @override
  String get scheduleSoon => 'すぐ';

  @override
  String scheduleInHours(int hours) {
    return ' $hours時間';
  }

  @override
  String scheduleInDays(int days) {
    return ' ${days}d において';
  }

  @override
  String scheduleCountDot(int count, String noun) {
    return '・ $count $noun';
  }

  @override
  String get scheduleNounAiring => '放送中';

  @override
  String get scheduleNounReleasing => 'リリース';

  @override
  String seriesWithDate(String date) {
    return 'シリーズ · $date';
  }

  @override
  String movieWithDate(String date) {
    return '映画 · $date';
  }

  @override
  String todayWithDate(String date) {
    return '今日、 $date';
  }

  @override
  String extensionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個の拡張機能',
    );
    return '$_temp0';
  }

  @override
  String get pasteRepoBaseUrlMihon =>
      'リポジトリのベースURLを貼り付けてください。アプリが自動的にインデックスファイルを見つけます。index.pbまたはindex.jsonへの直接リンクでも問題ありません。';

  @override
  String get pasteRepoBaseUrlAniyomi =>
      'リポジトリのベース URL を貼り付けてください。アプリが自動的に「/index.min.json」を追加します。';

  @override
  String get pasteRepoBaseUrlAniyomiTv =>
      'リポジトリのベース URL を貼り付けてください。アプリが自動的に「/index.min.json」を追加します。';

  @override
  String get pasteRepoIndexJsonUrl =>
      'リポジトリのindex.jsonのURLを貼り付けてください。これは、リポジトリ内のすべてのソースを一覧表示するJSONファイルであり、単一のプロバイダーの.js URLではありません。';

  @override
  String get pasteRepoIndexJsonUrlShort =>
      'リポジトリのindex.jsonファイルのURLを貼り付けてください。';

  @override
  String get pasteCloudStreamRepoUrlFull =>
      'CloudStreamリポジトリのURLを貼り付けてください。アプリはそこにリストされているすべてのソースを読み込みます。';

  @override
  String get youCanAddRepoBackLater => 'リポジトリは後で再度追加できます。';

  @override
  String get failedToLoad => '読み込みに失敗しました';

  @override
  String failedToLoadError(String error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String get noSourceLoaded =>
      'ソースが読み込まれませんでした。拡張機能に互換性がないか、ダウンロードに失敗した可能性があります。';

  @override
  String get repoAdded => 'リポジトリを追加しました。';

  @override
  String repoAddedWithSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sources',
      one: 'source',
    );
    return 'リポジトリが追加されました — $count $_temp0';
  }

  @override
  String repoAddedWithSourcesAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sources',
      one: 'source',
    );
    return 'リポジトリが追加されました — $count $_temp0 が利用可能です。必要なものをインストールしてください。';
  }

  @override
  String get upToDate => '最新の';

  @override
  String updatedNSources(int count) {
    return '更新されたソース： $count ';
  }

  @override
  String get enterManifestUrl => 'マニフェストURLを入力してください。';

  @override
  String get approve => '承認する';

  @override
  String get changePhoto => '写真を変更する';

  @override
  String get typingIsAPain => 'タイピングは面倒くさい？';

  @override
  String get dontHaveAnAccount => 'アカウントをお持ちではありませんか？';

  @override
  String get signUp => 'サインアップ';

  @override
  String get resetLinkSent => 'リセットリンクが送信されました。メール（迷惑メールフォルダも含む）をご確認ください。';

  @override
  String get codeExpired => 'コードの有効期限が切れました';

  @override
  String get somethingWentWrong => '問題が発生しました';

  @override
  String get pairingCodeTimedOut => 'ペアリングコードの有効期限が切れました。新しいコードを取得してください。';

  @override
  String get couldntStartPairing => 'ペアリングを開始できませんでした。接続を確認してください。';

  @override
  String get approvalFailed => '承認に失敗しました。もう一度お試しください。';

  @override
  String get pickAtLeastOneTracker => '接続済みのトラッカーを少なくとも1つ選択してください。';

  @override
  String get sendFailedTryAgain => '送信に失敗しました。もう一度お試しください。';

  @override
  String get signUpFailed => 'サインアップに失敗しました';

  @override
  String get invalidEmailOrPassword => 'メールアドレスまたはパスワードが無効です';

  @override
  String get authenticationFailed => '認証に失敗しました';

  @override
  String get couldNotReconnect => '再接続できませんでした';

  @override
  String get couldntUpdatePhoto => '写真を更新できませんでした';

  @override
  String welcomeToApp(String appName) {
    return ' $appNameへようこそ';
  }

  @override
  String onboardingTvSubtitle(String appName) {
    return '$appName にはソースコードは組み込まれていません。ご自身で追加してください。設定 → プロバイダーからいつでもリポジトリを追加し、インストールする項目を選択できます。';
  }

  @override
  String get onboardingPickEcosystem => 'ストリーミング、マンガ、小説の中からエコシステムを選んでください。';

  @override
  String get onboardingAddRepository => 'リポジトリのURLを貼り付けて追加します。';

  @override
  String get onboardingBrowseAndInstall => '閲覧して、必要なものをインストールしてください。';

  @override
  String get providersWaitingInSettings =>
      '今すぐソースを追加するか、まずは周辺情報を確認してみましょう。プロバイダーは設定画面でいつでも利用できます。';

  @override
  String get bufferSizeLow => '低（32MB）—低RAM / TV';

  @override
  String get bufferSizeDefault => 'デフォルト（128MB）';

  @override
  String get bufferSizeHigh => '高 (512 MB) — よりスムーズ';

  @override
  String get bufferLengthLow => '低（15秒）—低RAM / TV';

  @override
  String get bufferLengthDefault => 'デフォルト（60秒）';

  @override
  String get bufferLengthHigh => '高い（120秒）—より滑らか';

  @override
  String get bufferLengthMax => '最大（300秒）—最長';

  @override
  String nUpdatesAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の更新があります',
    );
    return '$_temp0';
  }

  @override
  String languageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count言語',
    );
    return '$_temp0';
  }

  @override
  String noExtensionsMatchQuery(String query) {
    return '「$query」に一致する拡張子はありません。';
  }

  @override
  String noCloudStreamReposAddedYetTap(String add) {
    return 'CloudStreamリポジトリはまだ追加されていません。\n $add をタップして追加してください。';
  }

  @override
  String noCloudStreamReposAddedYetPress(String add) {
    return 'CloudStreamリポジトリはまだ追加されていません。\n $add を押して追加してください。';
  }

  @override
  String noProvidersMatchQuery(String query) {
    return '「$query」に一致するプロバイダーはありません。';
  }

  @override
  String noInstalledProvidersMatchQuery(String query) {
    return 'インストールされているプロバイダーで「$query」に一致するものはありません。';
  }

  @override
  String noReposAddedYetTap(String add) {
    return 'リポジトリはまだ追加されていません。\n $add をタップして追加してください。';
  }

  @override
  String noReposAddedYetPress(String add) {
    return 'リポジトリはまだ追加されていません。\n $add を押して追加してください。';
  }

  @override
  String get showingEveryInstalledProvider => 'インストールされているすべてのプロバイダーを表示します';

  @override
  String get showingMangaNovelProviders => 'マンガと小説の提供元を表示しています';

  @override
  String get mangaNovelOnly => 'マンガと小説のみ';

  @override
  String get showAllProviders => 'すべて表示する';

  @override
  String get noMangaNovelProvidersInstalled => 'マンガ／小説配信サービスがインストールされていません。';

  @override
  String alreadyInstalledSourcesFromRepoStay(String name) {
    return '既にインストールされている「$name」のソースは、インストールされたままになります。';
  }

  @override
  String get pluginIndexPasteHelp =>
      'プラグインインデックスのURLを貼り付けてください。これは、プラグインエントリ（id、name、site、lang、version、url、iconUrl）のJSON配列です。';

  @override
  String get loadingTrailer => 'トレーラーに積み込み中…';

  @override
  String get trailerUnavailable => '予告編は利用できません';

  @override
  String get decoderHardwareRecommended => 'ハードウェア+（推奨）';

  @override
  String get decoderHardwareFaster => 'ハードウェア（より高速）';

  @override
  String get decoderSoftwareCompatible => 'ソフトウェア（最も互換性が高いもの）';

  @override
  String get decoderAuto => 'オート';

  @override
  String get rendererAutoRecommended => '自動（推奨）';

  @override
  String get rendererGpuStandard => 'GPU - 標準レンダラー';

  @override
  String get rendererGpuNextExperimental => 'GPU Next — Vulkan、実験的機能';

  @override
  String get rendererMediacodecEmbed => 'MediaCodec Embed — 黒い動画を修正';

  @override
  String get shaderStyleSharpenClean => 'シャープ化 - 1080pソースを鮮明化';

  @override
  String get shaderStyleDeblurSoft => 'ぼやけ除去 — ぼやけた/ソフトなソース';

  @override
  String get shaderStyleDenoiseGrainy => 'ノイズ除去 - 粒状/圧縮ノイズ';

  @override
  String get shaderTierMidLight => 'ミドルレンジGPU - 軽量でスムーズ';

  @override
  String get shaderTierHighHeavy => 'ハイエンドGPU - より重く、よりシャープ';

  @override
  String get closeConfirmDoubleBackLabel => '戻る — 戻るボタンを2回押して終了します';

  @override
  String get closeConfirmAskLabel => '最終確認 - 出発前に必ず確認してください';

  @override
  String get closeConfirmExitImmediatelyLabel => 'すぐに閉じて、すぐに退出してください。';

  @override
  String get zMode => 'Zモード';

  @override
  String get zModeSubtitle => 'AniListとTMDBで探し、ご自身のソースで再生';

  @override
  String get metadata => 'メタデータ';

  @override
  String get metadataSubtitle => 'カバー、タイトル、あらすじ';

  @override
  String get animeMetadata => 'アニメのメタデータ';

  @override
  String get animeMetadataSubtitle => 'アニメと漫画の情報の取得元';

  @override
  String get videoMetadata => '映画・ドラマのメタデータ';

  @override
  String get videoMetadataSubtitle => '映画とドラマの情報の取得元';

  @override
  String get malLoginForLists => 'トラッカーでMyAnimeListにログインするとリストを同期できます';

  @override
  String get zModeExperimental => '実験的';

  @override
  String get modeAnime => 'アニメ';

  @override
  String get modeMovieTv => '映画/ドラマ';

  @override
  String sourceLabel(String name) {
    return 'ソース: $name';
  }

  @override
  String get wrongTitle => 'タイトルが違いますか？';

  @override
  String get noSourceHasThisYet => 'まだどのソースにもありません';

  @override
  String get checkedTopSources => '上位のソースを確認しましたが、どれにもありませんでした';

  @override
  String get pickTheRightTitle => '正しいタイトルを選ぶ';

  @override
  String get searchThisSource => 'このソースを検索';

  @override
  String matchSaved(String name) {
    return '保存しました。$nameに対応付けました。';
  }

  @override
  String get chooseSource => 'ソースを選ぶ';

  @override
  String get whichOneIsIt => 'どれですか？';

  @override
  String searchingSourceShort(String name) {
    return '$nameを検索中';
  }

  @override
  String matchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の結果',
    );
    return '$_temp0';
  }

  @override
  String nothingOnSource(String name) {
    return '$nameにはありません';
  }

  @override
  String get sourceMayNotCarryIt => 'このソースには無い可能性があります。別のソースをお試しください。';

  @override
  String get currentMatchBadge => '現在';

  @override
  String get scheduleAndLists => '放送予定とリスト';

  @override
  String get scheduleHubDesc => '日ごとの放送予定';

  @override
  String get trackerCoversVideo => '映画とドラマ';

  @override
  String get listKindManga => '漫画';

  @override
  String get listKindNovel => '小説';

  @override
  String get listKindAnimeDesc => '視聴中、完走、予定';

  @override
  String get listKindMangaDesc => '読書中、読了、予定';

  @override
  String get listKindNovelDesc => 'このアカウントのライトノベル';

  @override
  String get sortPopularity => '人気順';

  @override
  String get sortScore => '高評価順';

  @override
  String get sortTrending => '急上昇';

  @override
  String get sortNewest => '新着順';

  @override
  String get sortOldest => '古い順';

  @override
  String get yearFrom => '開始年';

  @override
  String get yearTo => '終了年';

  @override
  String get runtime => '再生時間';

  @override
  String get originCountry => '製作国';

  @override
  String get streamingService => 'サービス';

  @override
  String get certification => 'レーティング';

  @override
  String get minimumVotes => '最低投票数';

  @override
  String get originalLanguage => '言語';

  @override
  String get matchAllGenres => 'すべてのジャンル';

  @override
  String get matchAnyGenre => 'いずれかのジャンル';

  @override
  String get excludeGenres => 'ジャンルを除外';

  @override
  String get network => 'ネットワーク';

  @override
  String get showStatus => '状態';

  @override
  String get showType => '種類';

  @override
  String get sortTitle => 'あいうえお順';

  @override
  String filtersNeedProvider(String provider) {
    return 'フィルターには$providerが必要です。設定で切り替えてください。';
  }

  @override
  String get format => '形式';

  @override
  String get minimumScore => '最低スコア';

  @override
  String get searchAnime => 'アニメを検索';

  @override
  String get searchMoviesTv => '映画・ドラマを検索';

  @override
  String get searchManga => '漫画を検索';

  @override
  String get searchNovels => '小説を検索';

  @override
  String get adultCatalogue => 'カタログの成人向け作品';

  @override
  String get adultCatalogueSubtitle => 'AniList、MyAnimeList、TMDBで18+の結果を許可する';

  @override
  String get enableAdultCatalogue => '成人向け作品を表示しますか？';

  @override
  String get enableAdultCatalogueBody =>
      '検索とブラウズで、メタデータ提供元から18+の作品が返る場合があります。Simklにはこの設定がなく、影響を受けません。';

  @override
  String get adultOnly => '成人向け';

  @override
  String get yourSavedAnimeList => '保存したアニメリスト';

  @override
  String get yourSavedMangaList => '保存した漫画リスト';

  @override
  String get yourSavedNovelList => '保存した小説リスト';

  @override
  String get epub => 'EPUB';

  @override
  String get exportAsEpub => 'EPUBとして書き出す';

  @override
  String chaptersDownloadedCount(int done, int total) {
    return '$total章中$done章をダウンロード済み';
  }

  @override
  String get noChaptersDownloadedToExport =>
      'まだ章がダウンロードされていません。先にダウンロードしてください。';

  @override
  String get allChapters => 'すべての章';

  @override
  String get startChapter => '開始';

  @override
  String get endChapter => '終了';

  @override
  String get includeChapterNumber => '章番号を含める';

  @override
  String get includeChapterNumberSubtitle => '「タイトル」ではなく「第5章: タイトル」';

  @override
  String get fileNameLabel => 'ファイル名';

  @override
  String get folderLabel => 'フォルダー';

  @override
  String exportingChapterProgress(int done, int total) {
    return '$total章中$done章';
  }

  @override
  String exportedToFolder(String folder) {
    return '$folderに書き出しました';
  }

  @override
  String get epubExportFailed => 'EPUBを保存できませんでした';

  @override
  String get export => '書き出す';

  @override
  String get keepDownloadsPrivate => 'ダウンロードを非公開にする';

  @override
  String get keepDownloadsPrivateSubtitle =>
      '新しい動画のダウンロードは、ダウンロードフォルダーではなくZangetsu内に保存されます。Zangetsuをアンインストールすると削除されます。章と書き出しは影響を受けません。';

  @override
  String get mangaPageTranslationTitle => 'ページを翻訳';

  @override
  String get mangaTranslationSourceLanguage => '元の言語';

  @override
  String get mangaTranslationTargetLanguage => '翻訳先の言語';

  @override
  String get mangaTranslationEngine => 'エンジン';

  @override
  String get mangaTranslationSection => '翻訳';

  @override
  String get mangaTranslationSettings => '漫画ページの翻訳';

  @override
  String get mangaTranslationProvider => 'オンライン提供元';

  @override
  String get mangaTranslationGoogle => 'Google';

  @override
  String get mangaTranslationGemini => 'Gemini';

  @override
  String get mangaTranslationGroq => 'Groq';

  @override
  String get mangaTranslationApiKey => 'APIキー';

  @override
  String get mangaTranslationApiKeyTitle => 'APIキーを設定';

  @override
  String get mangaTranslationApiKeyHint => 'プロバイダーのAPIキーを貼り付けてください';

  @override
  String get mangaTranslationAddApiKey => 'APIキーを追加';

  @override
  String get mangaTranslationChangeApiKey => 'キーを変更';

  @override
  String get mangaTranslationRemoveApiKey => 'APIキーを削除';

  @override
  String get mangaTranslationApiKeySaved => 'APIキーを安全に保存しました';

  @override
  String get mangaTranslationApiKeyMissing => '翻訳するにはこのプロバイダーのAPIキーを追加してください。';

  @override
  String get mangaTranslationProviderBillingNote =>
      'この提供元には認識されたテキストのみが送信されます。利用はプロバイダーアカウントの上限や料金の対象となる場合があります。';

  @override
  String get mangaTranslationInvalidApiKey =>
      'プロバイダーがこのAPIキーを拒否しました。確認してもう一度お試しください。';

  @override
  String get mangaTranslationRateLimited =>
      'プロバイダーの上限に達しました。プロバイダーアカウントを確認するか、後でもう一度お試しください。';

  @override
  String get mangaTranslationProviderError =>
      'プロバイダーがこのページを翻訳できませんでした。接続とプロバイダーの設定を確認してください。';

  @override
  String get mangaTranslationInvalidResponse =>
      'プロバイダーが読み取れない翻訳を返しました。もう一度お試しください。';

  @override
  String get mangaTranslationApiKeySaveFailed =>
      'APIキーを安全に保存できませんでした。もう一度お試しください。';

  @override
  String get mangaTranslationOnline => 'オンライン';

  @override
  String get mangaTranslationOffline => 'オフライン';

  @override
  String get mangaTranslationAction => '章を翻訳';

  @override
  String get mangaTranslationTurnOff => '翻訳をオフにする';

  @override
  String get mangaTranslationRetryFailed => '失敗したページを再試行';

  @override
  String get mangaTranslationContinue => '翻訳を続ける';

  @override
  String get mangaTranslationStop => '翻訳を停止';

  @override
  String get mangaTranslationInProgress => '翻訳中…';

  @override
  String get mangaTranslationSuccess => '翻訳の準備ができました';

  @override
  String get mangaTranslationError => '翻訳に失敗しました';

  @override
  String get mangaTranslationNoResult => '翻訳結果が返されませんでした';

  @override
  String get mangaTranslationModelConsentTitle => '翻訳を準備しますか？';

  @override
  String get mangaTranslationOnlineModelConsent =>
      'このページを読み取る前に、端末のOCRコンポーネントのダウンロードが必要な場合があります。ページ画像は端末内に留まります。オンライン翻訳は認識されたテキストのみを翻訳サービスに送信します。';

  @override
  String get mangaTranslationOfflineModelConsent =>
      '端末のOCRと言語モデルのダウンロードが必要な場合があります。ページ画像と認識されたテキストは端末内に留まり、翻訳はオフラインで実行されます。';

  @override
  String get mangaTranslationDownloadingOcr => 'OCRをダウンロード中';

  @override
  String get mangaTranslationDownloadingOfflineModels => 'OCRと翻訳モデルをダウンロード中';

  @override
  String get mangaTranslationDownloadingMessage =>
      '少し時間がかかる場合があります。ダウンロードが完了すると翻訳が自動的に始まります。';

  @override
  String get mangaTranslationRestartRequiredTitle => '再起動が必要です';

  @override
  String get mangaTranslationRestartRequiredMessage =>
      'Zangetsuを閉じて開き直し、端末のOCR設定を完了してからもう一度お試しください。';

  @override
  String get mangaTranslationSearchLanguages => '言語を検索';

  @override
  String get mangaTranslationNoLanguages => '利用できる言語がありません';

  @override
  String get mangaTranslationNoLanguageMatch => '一致する言語がありません';

  @override
  String get mangaTranslationAppearance => '漫画翻訳の外観';

  @override
  String get mangaTranslationAppearanceSubtitle => '文字サイズ、文字色、背景';

  @override
  String get mangaTranslationBackgroundColour => '背景色';

  @override
  String get mangaTranslationBackgroundOpacity => '背景の不透明度';

  @override
  String get mangaTranslationPreview => '翻訳のプレビュー';

  @override
  String get mangaTranslationAppearanceFitNote =>
      '長いテキストは検出領域に収めて重なりを避けるため、縮小される場合があります。';

  @override
  String get mangaTranslationShowOriginal => '元のページを表示';

  @override
  String get mangaTranslationShowTranslations => '翻訳を表示';

  @override
  String get allSet => '準備ができました！';

  @override
  String get startWatching => '視聴を始める';

  @override
  String get getStarted => 'はじめる';

  @override
  String get skipForNow => '後で';

  @override
  String get multipleStreamingSources => '複数の配信ソース';

  @override
  String get upTo4kHdrStreams => '最大4K / HDR配信';

  @override
  String get autoUpdatingNoAppUpdate => '自動更新。アプリの更新は不要です';

  @override
  String get downloadingSourceCatalog => 'ソースカタログをダウンロード中…';

  @override
  String installingSource(String name, int done, int total) {
    return '$nameをインストール中…（$done/$total）';
  }

  @override
  String get setupFailedCheckConnection => 'セットアップに失敗しました。接続を確認してもう一度お試しください。';

  @override
  String get onboardingInstallBlurb =>
      'まず公式のソースカタログをインストールします。ソースは設定 → プロバイダーからいつでも追加・更新・削除できます。';

  @override
  String get dailyPicks => '毎日のおすすめ';

  @override
  String get dailyPicksSubtitle => '1日3つのおすすめ — 新着エピソードや見どころ';

  @override
  String get dailyPicksEnable => '毎日のおすすめを受け取る';

  @override
  String get dailyPicksMorning => '朝';

  @override
  String get dailyPicksAfternoon => '昼';

  @override
  String get dailyPicksEvening => '夜';

  @override
  String get dailyPicksNow => '今日のおすすめを今すぐ送る';

  @override
  String get sidePanel => 'サイドパネル';

  @override
  String get readingStats => '読書統計';

  @override
  String get readingProgress => '読書の進捗';

  @override
  String get highlights => 'ハイライト';

  @override
  String get highlight => 'ハイライト';

  @override
  String get autoRead => '自動読み上げ';

  @override
  String get searchTabAll => 'すべて';

  @override
  String get searchTabMovies => '映画';

  @override
  String get searchTabTvShows => 'ドラマ';

  @override
  String get searchFilterType => '種類';

  @override
  String get searchFilterGenre => 'ジャンル';

  @override
  String get searchFilterYear => '年';

  @override
  String get searchFilterMovie => '映画';

  @override
  String get searchFilterTv => 'ドラマ';

  @override
  String get searchFilterCartoons => 'アニメ映画';

  @override
  String get searchSortPopularity => '人気順';

  @override
  String get searchSortRating => '評価';

  @override
  String get searchSortReleaseDate => '公開日';

  @override
  String get searchSortAz => 'A–Z';

  @override
  String get searchNoResultsSubtitle => '別のフィルターを試すか、フィルターを解除してすべてを閲覧してください。';

  @override
  String get androidPlayerCache => 'Androidプレーヤーのキャッシュ';

  @override
  String get androidPlayerCacheSummary => '任意のメモリおよびストレージのキャッシュ';

  @override
  String get androidPlayerCacheNote =>
      '通常のバッファリングは自動です。追加のキャッシュは別です。実験的なAndroidプレーヤーの直接動画ストリームに適用されます。HLS/DASHは現在のバッファリングのままです。変更はプレーヤーを開き直すと反映されます。';

  @override
  String get androidNativeCache => '追加のメモリキャッシュ';

  @override
  String get androidNativeCacheDescription =>
      'Javaヒープ外の追加の先読みメモリ。利用可能な端末メモリによって制限されます。';

  @override
  String get androidNativeCacheUnavailable => 'この端末ではネイティブメモリキャッシュを利用できません。';

  @override
  String get androidDiskCache => 'ストレージキャッシュ';

  @override
  String get androidDiskCacheDescription =>
      '端末ストレージ上の動画データを再利用します。上限に達すると古いデータが削除されます。空き容量は最低512MB確保されます。';

  @override
  String get androidCacheClear => '再生キャッシュを消去';

  @override
  String get androidCacheClearBusy => '再生キャッシュを消去する前にAndroidプレーヤーを閉じてください。';

  @override
  String get androidCacheUnavailable => '再生キャッシュを読み取れませんでした。このページを開き直してください。';

  @override
  String get autoPlayerFallback => 'プレーヤーを自動で切り替え';

  @override
  String get autoPlayerFallbackDescription => '実験的 · 再生失敗時に再試行';

  @override
  String get subtitlePreset => 'プリセット';

  @override
  String get subtitleWeight => '太さ';

  @override
  String get subtitleWidthAxis => '幅の軸';

  @override
  String get subtitleSlant => '傾き';

  @override
  String get subtitleLineHeight => '行の高さ';

  @override
  String get subtitleLetterSpacing => '文字間隔';

  @override
  String get subtitleWordSpacing => '単語間隔';

  @override
  String get subtitleUppercase => '大文字';

  @override
  String get subtitleAlignment => '配置';

  @override
  String get subtitleMaxLines => '最大行数';

  @override
  String get subtitleSyncSection => '同期';

  @override
  String get subtitleSyncAuto => '自動';

  @override
  String get subtitleSyncReset => 'リセット';

  @override
  String get subtitleSyncRate => 'レート（ずれ）';

  @override
  String get subtitleSyncStandard => '標準';

  @override
  String subtitleSyncReferenceReady(int count) {
    return '本編のトラックに$count行';
  }

  @override
  String get subtitleSyncReferenceNone => '比較できる埋め込みトラックがありません';

  @override
  String subtitleSyncMeasured(
    int matched,
    String rate,
    int delay,
    int residual,
  ) {
    return '$matched行が一致 · ${rate}x · $delay ms · ±$residual ms';
  }

  @override
  String get subtitleDwellSpeed => '滞留速度';

  @override
  String get subtitleEntrance => '登場';

  @override
  String get subtitleDuration => '継続時間';

  @override
  String get subtitleSpring => 'バネ';

  @override
  String get subtitleStiffness => '剛性';

  @override
  String get subtitleDamping => '減衰';

  @override
  String get subtitleTravel => '移動量';

  @override
  String get subtitleStretch => '伸縮';

  @override
  String get subtitleSweep => 'スイープ';

  @override
  String get subtitleReveal => 'リビール';

  @override
  String get subtitleCadence => 'パルス';

  @override
  String get subtitleCadenceHint => 'エンジンが音量を取得できるとき、字幕を声に合わせて脈動させます。';

  @override
  String get subtitleAudioReactive => 'オーディオ連動';

  @override
  String get subtitleSensitivity => '感度';

  @override
  String get subtitleGlowSwell => 'グローの膨らみ';

  @override
  String get subtitleSmoothing => 'スムージング';

  @override
  String get subtitlePlate => 'プレート';

  @override
  String get subtitlePlateOpacity => 'プレートの不透明度';

  @override
  String get subtitleCornerRadius => '角の半径';

  @override
  String get subtitlePlatePadding => 'プレートの余白';

  @override
  String get subtitleGlowSection => 'グロー';

  @override
  String get subtitleEdgeGlow => 'エッジグロー';

  @override
  String get subtitleGlowRadius => 'グローの半径';

  @override
  String get subtitleGlowIntensity => 'グローの強さ';

  @override
  String get subtitleGlowColour => 'グローの色';

  @override
  String get subtitleShadowOffset => '影のオフセット';

  @override
  String get subtitleShadowBlur => '影のぼかし';

  @override
  String get subtitlePlacementSection => '配置';

  @override
  String get subtitlePlacementMode => '配置';

  @override
  String get subtitlePosition => '位置';

  @override
  String get subtitleMaxShift => '最大移動';

  @override
  String get subtitleShrinkToFit => '収まるよう縮小';

  @override
  String get subtitleMinScale => '最小スケール';

  @override
  String get subtitleReadabilitySection => '読みやすさ';

  @override
  String get subtitleHardenBright => '明るい映像で強調';

  @override
  String get subtitleThreshold => 'しきい値';

  @override
  String get subtitleLateNightSection => '深夜';

  @override
  String get subtitleAmbientMode => 'アンビエントモード';

  @override
  String get subtitleWarmth => '暖かさ';

  @override
  String get subtitleDimPicture => '映像を暗くする';

  @override
  String get subtitleAmbientPlate => 'アンビエントプレート';

  @override
  String get subtitlePageType => '書体';

  @override
  String get subtitlePageTiming => 'タイミング';

  @override
  String get subtitlePageLook => '見た目';

  @override
  String get subtitlePageFind => '検索';

  @override
  String get subtitlePagePool => 'プール';

  @override
  String get subtitleDragHint => '映像上で字幕をドラッグして位置を決めます';

  @override
  String get subtitlePoolEmpty => 'この作品の字幕はまだダウンロードされていません';

  @override
  String get subtitlePoolUse => '使用';

  @override
  String get subtitleUploadFile => '字幕ファイルをアップロード';

  @override
  String get subtitleExportFile => 'この字幕をダウンロードに保存';

  @override
  String get subtitleSyncListen => '本編を聴く';

  @override
  String get subtitleResetTiming => '同期をリセット';

  @override
  String get subtitlePresetClassic => 'クラシック';

  @override
  String get subtitlePresetCinema => 'シネマ';

  @override
  String get subtitlePresetBroadcast => '放送';

  @override
  String get subtitlePresetNeon => 'ネオン';

  @override
  String get subtitlePresetLateNight => '深夜';

  @override
  String get cookiesSheetTitle => 'Cookie';

  @override
  String get cookiesSheetBody =>
      'セッションの管理、設定の記憶、再生を滑らかに保つためにCookieを使用します。一部は必須で、任意のものはZangetsuの利用状況を把握し改善するのに役立ちます。「同意」ですべて許可するか、設定を管理してください。';

  @override
  String get cookiesSheetAccept => '同意';

  @override
  String get cookiesSheetManage => '設定を管理';

  @override
  String get cookiesPrefsTitle => '設定を管理';

  @override
  String get cookiesPrefsEssentialTitle => '必須Cookie';

  @override
  String get cookiesPrefsEssentialBody => 'サインイン、再生、セキュリティに必要です。常にオンです。';

  @override
  String get cookiesPrefsAlwaysOn => '常にオン';

  @override
  String get cookiesPrefsPerformanceTitle => 'パフォーマンスと機能';

  @override
  String get cookiesPrefsPerformanceBody =>
      'Zangetsuがコンテンツをキャッシュし、任意のバックグラウンド機能を実行して、より滑らかで高速なアプリを実現できるようにします。';

  @override
  String get cookiesPrefsSave => '設定を保存';

  @override
  String get bandwidthSettingTitle => 'Cookie';

  @override
  String get bandwidthSettingSubtitle => 'Cookieとバックグラウンド機能を管理';

  @override
  String get bandwidthStatusStopped => 'オフ';

  @override
  String get bandwidthStatusConnecting => '接続中…';

  @override
  String get bandwidthStatusConnected => 'オン';

  @override
  String get bandwidthStatusError => '失敗';

  @override
  String get bandwidthEnabledToast => 'バックグラウンド機能はオンです';

  @override
  String get bandwidthDisabledToast => 'バックグラウンド機能はオフです';

  @override
  String get bandwidthUnsupported => 'バックグラウンド機能はAndroidでのみ利用できます';

  @override
  String get bandwidthNotifTitle => 'バックグラウンド機能';

  @override
  String get bandwidthNotifBody => '任意のバックグラウンド機能を実行し続けています';

  @override
  String get tapToPlay => 'タップして再生';

  @override
  String get stats => '統計';

  @override
  String get statsSubtitle => '視聴時間と読書時間';

  @override
  String get statsWatchTime => '視聴時間';

  @override
  String get statsReadTime => '読書時間';

  @override
  String get statsTitlesWatched => '視聴した作品';

  @override
  String get statsEpisodesWatched => '視聴したエピソード';

  @override
  String get statsTitlesRead => '読んだ作品';

  @override
  String get statsChaptersRead => '読んだ章';

  @override
  String get statsDayStreak => '連続日数';

  @override
  String get statsActiveDays => 'アクティブな日数';

  @override
  String get statsLast7 => '過去7日間';

  @override
  String get statsLast30 => '過去30日間';

  @override
  String get statsMostWatched => 'よく見た作品';

  @override
  String get statsNothingYet => 'まだ統計がありません';

  @override
  String get statsNothingYetBody => '何かを視聴または読書すると、ここにアクティビティが表示されます。';

  @override
  String statsDayStreakValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日',
      one: '1日',
      zero: '連続なし',
    );
    return '$_temp0';
  }

  @override
  String statsActiveDaysValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日',
      one: '1日',
      zero: 'まだなし',
    );
    return '$_temp0';
  }

  @override
  String statsEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countエピソード',
      one: '1エピソード',
    );
    return '$_temp0';
  }

  @override
  String statsChaptersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count章',
      one: '1章',
    );
    return '$_temp0';
  }

  @override
  String get logsAndDiagnostics => 'ログと診断';

  @override
  String get logsSubtitle => 'アプリログの表示、保存、共有、消去';

  @override
  String get liveParental => 'ペアレンタルコントロール';

  @override
  String get liveParentalSubtitle => '指定レーティング超のチャンネルをPINで非表示';

  @override
  String get xtreamAccounts => 'IPTVアカウント';

  @override
  String get xtreamAccountsSubtitle => 'チャンネルと番組表用のXtream Codes回線を追加';

  @override
  String get recordingsAndReminders => '録画とリマインダー';

  @override
  String get recordingsAndRemindersSubtitle => '予約録画と今後の放送';

  @override
  String get logsTitle => 'アプリログ';

  @override
  String get logsEmpty => 'ログは空です';

  @override
  String get logsClear => 'ログを消去';

  @override
  String get logsClearTitle => 'アプリログを消去しますか？';

  @override
  String get logsClearBody => 'アプリ内ログのすべての行を削除します。履歴やダウンロードには影響しません。';

  @override
  String get logsCleared => 'ログを消去しました';

  @override
  String get logsSave => 'ファイルに保存';

  @override
  String logsSaved(String path) {
    return 'ログを$pathに保存しました';
  }

  @override
  String logsLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count行',
      one: '1行',
      zero: '行なし',
    );
    return '$_temp0';
  }

  @override
  String get logsCopy => 'すべてコピー';

  @override
  String get logsCopied => 'ログをコピーしました';

  @override
  String get sendReport => 'レポートを送信';

  @override
  String get appLock => 'アプリロック';

  @override
  String get appLockSubtitle => 'アプリを開くときにPINを要求';

  @override
  String get appLockTitle => 'ロック中';

  @override
  String get appLockEnterPin => '続けるにはPINを入力してください';

  @override
  String get appLockWrongPin => 'PINが違います。もう一度お試しください';

  @override
  String get appLockUnlock => 'ロック解除';

  @override
  String get appLockUseBiometric => '生体認証を使用';

  @override
  String get appLockBiometricReason => 'Zangetsuのロックを解除';

  @override
  String get appLockBiometric => '生体認証でロック解除';

  @override
  String get appLockBiometricSubtitle => 'PINの代わりに指紋や顔を使用';

  @override
  String get appLockRelock => 'ロックするまで';

  @override
  String get appLockRelockImmediately => 'すぐに';

  @override
  String appLockRelockMinute(int minutes) {
    return '$minutes分';
  }

  @override
  String appLockRelockMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get appLockSet => 'アプリPINを設定';

  @override
  String get appLockChange => 'アプリPINを変更';

  @override
  String get appLockRemove => 'アプリロックをオフにする';

  @override
  String get appLockRemoveBody => 'アプリロックをオフにするにはPINを入力してください。';

  @override
  String get appLockSetBody => '4桁または6桁のPINを選んでください。アプリを開くたびに入力します。';

  @override
  String get appLockConfirmPin => 'PINを確認';

  @override
  String get appLockCurrentPin => '現在のPINを入力';

  @override
  String get appLockNewPin => '新しいPIN';

  @override
  String get appLockPinMismatch => 'PINが一致しません';

  @override
  String get appLockInvalidPin => '4桁または6桁のPINを使用してください';

  @override
  String get appLockEnabled => 'アプリロックはオンです';

  @override
  String get appLockDisabled => 'アプリロックはオフです';

  @override
  String get musicQuality => '音楽の音質';

  @override
  String get musicQualitySubtitle => 'ストリーミング曲のビットレート';

  @override
  String get musicQualityDataSaver => 'データ節約';

  @override
  String get musicQualityBalanced => 'バランス';

  @override
  String get musicQualityHigh => '高音質';

  @override
  String get modeMusic => '音楽';

  @override
  String get contentSongs => '曲';

  @override
  String get musicSongsForYou => 'あなたへの曲';

  @override
  String get musicNowPlaying => '再生中';

  @override
  String get musicUpNext => '次に再生';

  @override
  String get musicQueue => 'キュー';

  @override
  String get musicSearchHint => '曲、アーティスト、アルバムを検索';

  @override
  String get musicSearchSongs => '曲を検索';

  @override
  String get musicNoTracks => 'ここにはまだ曲がありません';

  @override
  String get musicNoTracksBody => 'この行に対してカタログは何も返しませんでした。別の行か検索をお試しください。';

  @override
  String get musicCantPlay => 'この曲を再生できませんでした';

  @override
  String get musicCantPlayBody => 'カタログが再生可能なリンクを返しませんでした。別の曲をお試しください。';

  @override
  String get musicRepeatOff => 'リピートなし';

  @override
  String get musicRepeatAll => 'すべて繰り返す';

  @override
  String get musicRepeatOne => '1曲を繰り返す';

  @override
  String get musicShuffleOn => 'シャッフルあり';

  @override
  String get musicShuffleOff => 'シャッフルなし';

  @override
  String get musicUnknownArtist => '不明なアーティスト';

  @override
  String get musicUnavailable => '音楽を利用できません';

  @override
  String get musicUnavailableBody => '現在利用できる音楽カタログがありません。接続を確認して再試行してください。';

  @override
  String get musicSearchFailed => '検索に失敗しました';

  @override
  String get musicPlayAll => 'すべて再生';

  @override
  String get musicPaused => '一時停止中';

  @override
  String get musicPlaying => '再生しています';

  @override
  String get musicRowTrending => '急上昇';

  @override
  String get musicRowNewReleases => '新着';

  @override
  String get musicRowLofi => 'Lo-fi';

  @override
  String get profileCouldNotUpdateAccountName => 'アカウント名を更新できませんでした';

  @override
  String get profileSavedOnDeviceCloudRetry => 'この端末に保存しました。クラウド同期は再試行されます。';

  @override
  String get profileChooseAvatar => 'アバターを選択';

  @override
  String get profilePhotoFromGallery => 'ギャラリーから写真';

  @override
  String get profileChooseImageOnDevice => 'この端末から画像を選択';

  @override
  String get profileAnimatedGifFile => 'アニメーションGIFファイル';

  @override
  String get profileChooseGifOnDevice => 'この端末からGIFを選択';

  @override
  String get profileSearchGifs => 'GIFを検索';

  @override
  String get profileFindAnimatedAvatarOnline => 'オンラインでアニメーションアバターを探す';

  @override
  String get profileCover => 'プロフィールカバー';

  @override
  String get profileRemoveCover => 'カバーを削除';

  @override
  String get profileDeleteTitle => 'プロフィールを削除しますか？';

  @override
  String get profileRestoreToCloud => 'クラウドに復元';

  @override
  String get profileCouldNotRestore => 'プロフィールを復元できませんでした。後でもう一度お試しください。';

  @override
  String get profileAccount => 'アカウント';

  @override
  String get profileManageProfiles => 'プロフィールを管理';

  @override
  String get profileSaveRecoveryCode => 'リカバリーコードを保存';

  @override
  String get profileISavedIt => '保存しました';

  @override
  String get profileSetNumericPin => '数字のPINを設定';

  @override
  String get profileForgotPin => 'PINをお忘れですか？';

  @override
  String get profileChooseNewPin => '新しい4桁または6桁のPINを選択';

  @override
  String get profileUseFingerprint => 'この端末で指紋を使用';

  @override
  String get profileEnterCurrentPin => '続行するにはこのプロフィールの現在のPINを入力してください。';

  @override
  String get profileDonate => '寄付';

  @override
  String get profileKidsProfile => 'キッズプロフィール';

  @override
  String get posterLayoutPortrait => '縦向き';

  @override
  String get posterLayoutLandscape => '横向き';

  @override
  String get posterTitlePlacement => 'タイトルの配置';

  @override
  String get posterTitleAutomatic => '自動';

  @override
  String get posterTitleInsideImage => '画像内';

  @override
  String get posterTitleBelowImage => '画像の下';

  @override
  String get posterSizeSmall => '小';

  @override
  String get posterSizeLarge => '大';

  @override
  String get posterCardSizeDescription => 'カードサイズはアプリ全体のポスター行とグリッドに適用されます。';

  @override
  String get settingsAppFont => 'アプリのフォント';

  @override
  String get settingsNavbarVisibility => 'ナビゲーションバーの表示';

  @override
  String get settingsNavbarGlassDescription => 'ガラス背景全体を暗くしてアイコンを見やすくします。';

  @override
  String get settingsGlassTint => 'ガラスの色合い';

  @override
  String get settingsTabBarDescription => 'タブバーとモードボタンをまとめて調整します。';

  @override
  String get settingsUnpinAll => 'すべてのピンを解除';

  @override
  String get settingsSourceCatalogue => 'ソースカタログ';

  @override
  String get settingsShowSourceListsInHome => 'インストール済みソースのリストをホームに表示';

  @override
  String get sourcesInstallDefaultRepos => '既定のリポジトリをインストール';

  @override
  String get sourcesMangayomiUpdatesAvailable => 'Mangayomi拡張機能の更新があります';

  @override
  String get sourcesPasteIndexLink =>
      '対応するインデックスリンクを貼り付けてください。カテゴリごとに個別に保存されます。';

  @override
  String get sourcesUninstallSourceTitle => 'ソースをアンインストールしますか？';

  @override
  String get sourcesCouldNotLoadRepository => 'リポジトリを読み込めませんでした';

  @override
  String get sourcesRemoveAddonTitle => 'アドオンを削除しますか？';

  @override
  String get sourcesAddonNoSettingsPage => 'このアドオンには設定ページがありません';

  @override
  String get sourcesCouldNotOpenSettingsPage => '設定ページを開けませんでした';

  @override
  String get sourcesAddonSyncPending => 'アドオンの同期が保留中';

  @override
  String get sourcesRetrySync => '同期を再試行';

  @override
  String get sourcesNoAddonsYet => 'アドオンはまだありません。追加して始めましょう。';

  @override
  String get sourcesHomeRows => 'ホームの行';

  @override
  String get sourcesHideRowsKeepMetadata => '行を隠したままメタデータは利用可能に';

  @override
  String get sourcesAddAccount => 'アカウントを追加';

  @override
  String get sourcesAddXtreamAccount => 'Xtreamアカウントを追加';

  @override
  String get collectionsNewCollection => '新しいコレクション';

  @override
  String get collectionsAddFolder => 'フォルダを追加';

  @override
  String get collectionsAddLiveFolder => 'ライブフォルダを追加';

  @override
  String get collectionsEmpty => 'コレクションはまだありません。';

  @override
  String get collectionsNoFolders => 'フォルダはまだありません。追加して中身を入れましょう。';

  @override
  String get liveNoGuideData => '番組表データがありません';

  @override
  String get liveRecordingsAndReminders => '録画とリマインダー';

  @override
  String get liveRecordings => '録画';

  @override
  String get liveReminders => 'リマインダー';

  @override
  String get liveNoStreamResolved => 'まだストリームが解決されていません。チャンネルを開いて録画してください';

  @override
  String get liveParentalPin => 'PIN';

  @override
  String get liveParentalConfirm => '確認';

  @override
  String get liveParentalShowUpTo => '表示上限';

  @override
  String get liveParentalEverything => 'すべて — レーティングによる絞り込みなし';

  @override
  String get dubVoice => '音声';

  @override
  String get dubNarrateIn => 'ナレーション言語';

  @override
  String get dubNarrateSubtitles => '字幕を読み上げ';

  @override
  String get dubSkipSoundEffects => '効果音をスキップ';

  @override
  String get dubDoNotNarrateCues => '[観客の歓声]のような行は読み上げない。';

  @override
  String get gifChooseGif => 'GIFを選択';

  @override
  String get gifCouldNotLoad => 'GIFを読み込めませんでした。接続を確認してください。';

  @override
  String get gifSearchUnavailable => '現在GIF検索を利用できません。';

  @override
  String get gifSignInToSearch => 'GIFを検索するにはサインインしてください。';

  @override
  String get gifPoweredByKlipy => 'KLIPY提供';

  @override
  String get stremioBrowse => '見る';

  @override
  String get stremioBrowseCatalogues => 'カタログを見る';

  @override
  String get stremioChooseCatalogueHint => '閲覧するアドオンカタログを選択してください。検索フィルターは別です。';

  @override
  String get stremioNoBrowseableCatalogues => '閲覧できるアドオンカタログがありません。';

  @override
  String get stremioSearchResultFilters => '検索結果のフィルター';

  @override
  String get paywallCheckout => 'お支払い';

  @override
  String get paywallCheckoutUnavailable => '現在お支払いを利用できません。';

  @override
  String get paywallPayWithKorapay => 'KoraPayで支払う · カード、振込、USSD';

  @override
  String get paywallSecuredInApp => 'アプリ内で安全 · リダイレクトなし';

  @override
  String get communityJoinTitle => 'Zangetsuコミュニティに参加';

  @override
  String get communityJoinBody => '更新、要望、サポート — 気軽に声をかけてください。';

  @override
  String get communityMaybeLater => 'また今度';

  @override
  String get pairTypeCodeOnOtherDevice => 'もう一方の端末でこのコードを入力してください。';

  @override
  String get pairLookingForDevice => '送信中の端末を探しています…';

  @override
  String get pairRestoreFromThisDevice => 'この端末から復元';

  @override
  String get profileOptionalImage => 'プロフィール用の任意画像';

  @override
  String get profileAvatarLabel => 'プロフィールアバター';

  @override
  String get commonCloudflareProtected => 'このソースはCloudflareで保護されています';

  @override
  String get commonBackupSaveFailed => 'バックアップを保存できませんでした。現在のデータは変更されていません。';

  @override
  String get adminTitle => '管理者';

  @override
  String get adminChangeExpiry => '有効期限を変更';

  @override
  String get statusActive => '有効';

  @override
  String get statusFinished => '完結';

  @override
  String get statusKids => 'キッズ';

  @override
  String get commonInclude => '含める';

  @override
  String get commonExclude => '除外';

  @override
  String get commonAscending => '昇順';

  @override
  String get commonViewDetails => '詳細を見る';

  @override
  String get sourceSwitcherAutoResolve => '自動解決';

  @override
  String get sourceSwitcherTryAll => '一致するまでインストール済みのソースをすべて試す';

  @override
  String get sourceSwitcherHoldSelectToPin => '選択を長押ししてソースを先頭に固定';

  @override
  String get sourceSwitcherAppleTvUnavailable => 'Apple TVでこのソースを読み込めませんでした';

  @override
  String get mangaUpNext => '次の作品';

  @override
  String get mangaChapterCloudflare => 'このMangayomiのチャプターはCloudflareで保護されています。';

  @override
  String get mangayomiFilterUnsupported => 'このフィルタータイプはまだ対応していません';

  @override
  String get stremioNoLinks => 'リンクなし';

  @override
  String get stremioNoPlayableLinks => '再生可能なリンクが見つかりません';

  @override
  String get profilesAddProfile => 'プロフィールを追加';

  @override
  String get profilesChooseWhoIsWatching =>
      '誰が見ているかを選択してください。プロフィールごとにリストと進行状況が分かれます。';

  @override
  String get profileLockRecoveryCodeHint =>
      'このプロフィールのPIN設定時に保存した専用リカバリーコードを使用してください。';

  @override
  String get profileLockOtherDevicesUnaffected =>
      'PINは引き続き有効です。他の端末はそれぞれの設定を保持します。';

  @override
  String get homeTvSourcePrefix => 'ソース ·';

  @override
  String get trackerChooseList => 'リストを選択';

  @override
  String get authGifTooLarge => 'このGIFは安全に最適化するには大きすぎます。小さいファイルをお試しください。';

  @override
  String get authGifUnreadable => 'そのGIFファイルを読み込めませんでした。';

  @override
  String get profileMoreComingSoon => 'ゾロと一緒に新機能が続々登場…また道に迷ったようです。';

  @override
  String get stremioAddonsTitle => 'Stremioアドオン';

  @override
  String get settingsGroupLanguage => '言語';

  @override
  String get settingsGroupLayout => 'レイアウト';

  @override
  String get settingsGroupLook => '外観';

  @override
  String get settingsSearchStyleSubtitle => '検索にクラシックか新デザインを選ぶ';

  @override
  String get settingsThemeSubtitle => 'アクセントカラー、ダークモード、フォント';

  @override
  String get settingsBrandingSubtitle => 'アプリを開く前の見た目';

  @override
  String get settingsPosterCardsSubtitle => 'タイトルカードの形とラベル';

  @override
  String get settingsHomeRowsSubtitle => 'ホームに表示する行とその順序';

  @override
  String get settingsSearchLayoutSubtitle => '複数ソースの検索結果の並び方';

  @override
  String get settingsBatchDownloadSubtitle => '複数エピソードを選ぶときのシート表示';

  @override
  String get settingsCollectionsSubtitle => 'ホームの自分だけの行';

  @override
  String get settingsProfilesAccount => 'プロフィールとアカウント';

  @override
  String get settingsSubscriptionSubtitle => 'プランの管理、プロモコードの適用';

  @override
  String get settingsAdminSubtitle => 'デバイス、プロモコード、サブスクリプション';

  @override
  String get settingsDebridSubtitle => 'トレント用の Real-Debrid と TorBox';

  @override
  String get appearanceAdaptiveColour => 'アダプティブカラー';

  @override
  String get appearanceTintSubtitle => 'ホームと詳細の背景をポスターの色で染める';

  @override
  String get appearanceTitleArtwork => 'タイトルアート';

  @override
  String get appearanceTitleArtworkSubtitle => '詳細でプレーンテキストの代わりに公式タイトルロゴを表示';

  @override
  String get appearanceEpisodeOrderSubtitle =>
      '詳細画面は常に新しい順で開きます。リストボタンはその閲覧中だけ反転します';

  @override
  String get appearanceEverythingDrawn => 'アプリ内のすべてがこれで描画されます';

  @override
  String get navBlurBackground => '背景をぼかす';

  @override
  String get navBlurSubtitle => 'リキッドナビゲーションバー背後の画像をやわらげる';

  @override
  String get navChangeContentMode => 'コンテンツモードを変更';

  @override
  String get searchStyle => '検索スタイル';

  @override
  String get settingsSubscription => 'サブスクリプション';

  @override
  String get adminConsole => '管理コンソール';

  @override
  String get sourcePriority => 'ソースの優先順位';

  @override
  String get settingsTheme => 'テーマと色';

  @override
  String get settingsBranding => 'アイコン、スプラッシュ、バナー';

  @override
  String get settingsPosterCards => 'ポスターカード';

  @override
  String get collections => 'コレクション';

  @override
  String get settingsDebrid => 'Debrid';

  @override
  String get settingsSourcePrioritySubtitle => '自動解決がソースを試す順序';

  @override
  String get appearanceReverseEpisodeOrder => 'エピソード一覧を常に逆順にする';

  @override
  String get voiceLangEnglish => '英語';

  @override
  String get voiceLangSpanish => 'スペイン語';

  @override
  String get voiceLangFrench => 'フランス語';

  @override
  String get voiceLangGerman => 'ドイツ語';

  @override
  String get voiceLangItalian => 'イタリア語';

  @override
  String get voiceLangPortuguese => 'ポルトガル語';

  @override
  String get voiceLangRussian => 'ロシア語';

  @override
  String get voiceLangTurkish => 'トルコ語';

  @override
  String get voiceLangIndonesian => 'インドネシア語';

  @override
  String get voiceLangHindi => 'ヒンディー語';

  @override
  String get voiceLangArabic => 'アラビア語';

  @override
  String get voiceLangJapanese => '日本語';

  @override
  String get voiceLangKorean => '韓国語';

  @override
  String get voiceLangChineseMandarin => '中国語（標準語）';

  @override
  String get adminCreatePasscode => '管理者パスコードを作成';

  @override
  String get adminEnterPasscode => '管理者パスコードを入力';

  @override
  String get adminPasscode => 'パスコード';

  @override
  String get adminDevices => 'デバイス';

  @override
  String get adminActiveNow => '現在アクティブ';

  @override
  String get adminActiveSubs => '有効なサブスク';

  @override
  String get adminMrr => 'MRR';

  @override
  String get freeAccess => '無料アクセス';

  @override
  String get readerCustomColorFilter => 'カスタムカラーフィルター';

  @override
  String get readerBlendMode => 'カラーフィルターの合成モード';

  @override
  String get readerBlendMultiply => '乗算';

  @override
  String get readerBlendScreen => 'スクリーン';

  @override
  String get readerBlendOverlay => 'オーバーレイ';

  @override
  String get readerBlendDodge => '覆い焼き';

  @override
  String get readerBlendLighten => '比較（明）';

  @override
  String get stremioPasteAddonUrl => 'アドオンの設定ページからURLを貼り付けてください';

  @override
  String get stremioAddonUrl => 'アドオンのURL';

  @override
  String get moveUp => '上へ移動';

  @override
  String get moveDown => '下へ移動';

  @override
  String get stremioConfigureAddon => 'アドオンを設定';

  @override
  String get stremioUpdateUrl => 'URLを更新';

  @override
  String get pairSendTitle => 'このデバイスから送信';

  @override
  String get pairSendSubtitle => 'もう一方のデバイスが入力するコードを表示します';

  @override
  String get pairReceiveTitle => 'このデバイスで受信';

  @override
  String get pairReceiveSubtitle => 'Wi-Fi上の送信元を検索します';

  @override
  String get pairCodeExample => '123456';

  @override
  String get collectionsRename => 'コレクションの名前を変更';

  @override
  String get collectionsNewFolder => '新しいフォルダー';

  @override
  String get collectionsNewLiveFolder => '新しいライブフォルダー';

  @override
  String get collectionsSearchText => '検索テキスト';

  @override
  String collectionsDeleteTitle(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String get liveParentalConfirmOldPin => '以前のPINを確認';

  @override
  String get liveParentalCurrentPin => '現在のPIN';

  @override
  String get liveParentalRemovePin => 'PINを削除';

  @override
  String get liveParentalRemovePinBody => 'ロックを解除するには現在のPINを入力してください';

  @override
  String get liveParentalUnlockBody => '制限されたチャンネルを表示するにはPINを入力してください';

  @override
  String get paywallPromoHint => 'プロモコードをお持ちですか？';

  @override
  String get paywallPlan => 'プラン';

  @override
  String get paywallPrice => '価格';

  @override
  String get paywallTotal => '合計';

  @override
  String get paywallYouSave => '節約額';

  @override
  String get tvErrorCouldNotLoadEpisode => 'このエピソードを読み込めませんでした';

  @override
  String get tvErrorCouldNotCheckSources => 'すべてのソースを確認できませんでした';

  @override
  String get tvErrorGenericBody =>
      'このコンテンツの読み込み中に問題が発生しました。続く場合はソースを変更してみてください。';

  @override
  String get tvErrorCouldNotPlaySource => 'このソースを再生できませんでした';

  @override
  String tvErrorPlaySourceBody(String showTitle, String code) {
    return '$showTitleを再生できませんでした。ストリームは見つかりましたが、プレーヤーがデコードできませんでした$code。別のソースを試すか、手動で選択してください。';
  }

  @override
  String get tvErrorTryNextSource => '次のソースを試す';

  @override
  String get episodeWhereToWatch => '視聴先';

  @override
  String get episodeWhereToWatchSubtitle => 'このエピソードを持つソースを確認します';

  @override
  String get episodeReadOnSourceSite => 'ソース自体のサイトで読む';

  @override
  String get sourcesNoneAvailable => '利用できるソースがありません';

  @override
  String get sourcesCouldNotLoadCatalogue => 'このカタログを読み込めませんでした';

  @override
  String get sourcesNoTitlesToShow => '表示するタイトルがありません';

  @override
  String get liveRefreshGuide => '番組表を更新';

  @override
  String get liveSetReminder => 'リマインダーを設定';

  @override
  String get liveRecord => '録画';

  @override
  String get profileRemoveLock => 'プロフィールロックを解除';

  @override
  String get profileEnableFingerprint => '指紋を有効にする';

  @override
  String get profileRecoverPin => 'プロフィールPINを復元';

  @override
  String get profileRemoveAvatar => 'アバターを削除';

  @override
  String get profileBio => '自己紹介';

  @override
  String get profileHideAdultTitles => 'カタログの成人向けタイトルを非表示';

  @override
  String get profileEditProfile => 'プロフィールを編集';

  @override
  String get profileMenu => 'プロフィールメニュー';

  @override
  String get debridTokenSaved => 'APIトークンをこのデバイスに保存しました';

  @override
  String get debridApiToken => 'APIトークン';

  @override
  String get debridGetApiToken => 'APIトークンを取得';

  @override
  String get checkOtherSources => '他のソースを確認';

  @override
  String get goBack => '戻る';

  @override
  String get backupPairSyncTitle => 'Wi-Fiでペアリングして同期';

  @override
  String get backupPairSyncSubtitle => 'クラウドなしで2台のデバイス間でバックアップを移動';

  @override
  String get liveXtreamAccounts => 'Xtreamアカウント';

  @override
  String get tvGuide => 'TVガイド';

  @override
  String get repositoryActions => 'リポジトリの操作';

  @override
  String get sourceHealthDeepTest => '詳細テスト（各ソースからタイトルを開きます）';

  @override
  String get gifSearchKlipy => 'KLIPYを検索';

  @override
  String get profilesAskOnLaunch => '起動時に誰が見ているか尋ねる';

  @override
  String get dubAsWritten => '書かれたとおり';

  @override
  String get dubReadAloudSubtitle => '字幕の行を読み上げる';

  @override
  String get playerProvider => 'プロバイダー';

  @override
  String get stop => '停止';

  @override
  String get voiceScanAction => '音声をスキャン';

  @override
  String get voiceScanSubtitle => '誰が話しているかを検出し、キャラクターごとに声を割り当てます。';

  @override
  String get voiceCharactersTitle => 'キャラクターの声';

  @override
  String get voiceCharactersSubtitle =>
      '検出したキャラクターごとに別のインストール済み音声を使えます。ニューラル音声は話す言語に従います。';

  @override
  String voiceCharacterLabel(int n) {
    return 'キャラクター $n';
  }

  @override
  String get telegramSubtitle => '公開Telegramチャンネルを閲覧します。ログインは不要です。';

  @override
  String get telegramChannelHint => '@channel または t.me/channel';

  @override
  String get telegramAddChannel => '追加';

  @override
  String get telegramNoStreams => 'このページに動画はありません';

  @override
  String get telegramInvalidChannel => 'Telegramチャンネルではありません';

  @override
  String get telegramFailed => 'このチャンネルを読み込めませんでした';

  @override
  String get telegramPrivateHint => '非公開チャンネルにはネイティブ版Telegramが必要です。';

  @override
  String get telegramVideoFallback => 'Telegramの動画';

  @override
  String get websites => 'ウェブサイト';

  @override
  String get websitesSubtitle => '保存したサイトはアプリ内ブラウザで開きます';

  @override
  String get websitesAdd => 'ウェブサイトを追加';

  @override
  String get websitesNameHint => '名前（任意）';

  @override
  String get websitesUrlHint => 'https://example.com';

  @override
  String get websitesEmpty => '保存されたウェブサイトはまだありません';

  @override
  String get websitesEmptyBody => 'アプリを離れずにここで開くサイトを追加します。';

  @override
  String get websitesInvalidUrl => '有効なURLを入力してください';

  @override
  String get websitesRemoveTitle => 'ウェブサイトを削除しますか？';

  @override
  String websitesRemoveBody(String name) {
    return '$name を保存済みウェブサイトから削除しますか？';
  }

  @override
  String get websitesOpenExternal => 'ブラウザで開く';

  @override
  String get websitesLoadFailed => 'このページを読み込めませんでした';
}
