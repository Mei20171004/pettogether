import 'package:flutter/widgets.dart';

import '../domain/health_models.dart';
import '../domain/handoff_models.dart';
import '../domain/collaboration_event_models.dart';
import '../domain/models.dart';
import '../domain/notification_models.dart';
import '../domain/report_models.dart';

enum AppLocale {
  english('en', 'English'),
  japanese('ja', '日本語');

  const AppLocale(this.languageCode, this.label);

  final String languageCode;
  final String label;

  Locale get locale => Locale(languageCode);

  static AppLocale fromLanguageCode(String? languageCode) {
    return AppLocale.values.firstWhere(
      (locale) => locale.languageCode == languageCode,
      orElse: () => AppLocale.japanese,
    );
  }
}

class AppStrings {
  const AppStrings(this.locale);

  final AppLocale locale;

  String text(String english, String japanese) {
    return locale == AppLocale.japanese ? japanese : english;
  }

  String get loading => text('Loading your household…', '家族情報を読み込み中…');
  String get startupFailed => text('CoPaw could not start', 'CoPawを起動できませんでした');
  String get startupFailureDetail => text(
    'Try again. If the problem continues, check the app configuration or connection. No household changes were made.',
    'もう一度お試しください。解決しない場合は、アプリの設定または通信状況を確認してください。家族情報は変更されていません。',
  );
  String get configurationFailureDetail => text(
    'This build is missing its Firebase configuration. Install a configured build and try again.',
    'このビルドにはFirebase設定がありません。設定済みのビルドをインストールして、もう一度お試しください。',
  );
  String get startupNetworkFailureDetail => text(
    'CoPaw could not reach Firebase. Check your connection and try again. No household changes were made.',
    'Firebaseに接続できませんでした。通信状況を確認して、もう一度お試しください。家族情報は変更されていません。',
  );
  String get startupPermissionFailureDetail => text(
    'This saved household session is no longer authorized. Try again; if it continues, return with a valid invite.',
    '保存済みの家へのアクセス権を確認できません。もう一度試し、解決しない場合は有効な招待コードで参加し直してください。',
  );
  String get startupDataFailureDetail => text(
    'This household contains older or damaged data that CoPaw cannot safely open yet. No data was changed.',
    'この家には、安全に開けない旧形式または破損したデータがあります。データは変更されていません。',
  );
  String get retry => text('Try again', 'もう一度試す');
  String get tagline =>
      text('Shared care, without the guesswork.', '迷わない、みんなのケア。');
  String get supportingTagline =>
      text('A happier routine for every pet parent', 'すべての飼い主に、もっと楽しい毎日を');
  String get createHome => text('Create a home', '家を作る');
  String get joinHome => text('Join a home', '家に参加');
  String get yourName => text('Your name', 'あなたの名前');
  String get yourNameHint =>
      text('How should your family see you?', '家族に表示する名前');
  String get household => text('Household', '家の名前');
  String get householdHint => text('Household name', '家族の名前');
  String get yourPet => text('Your pet', 'ペット');
  String get petHint => text('Pet name', 'ペットの名前');
  String get inviteCode => text('Invite code', '招待コード');
  String get inviteCodeHint =>
      text('Enter the six-character code', '6文字のコードを入力');
  String get inviteHelp => text(
    'Ask someone in your household for their six-character code.',
    '家族から6文字の招待コードをもらってください。',
  );
  String get createHousehold => text('Create household', '家を作成');
  String get joinHousehold => text('Join household', '家に参加');
  String get phaseTwoNotice => text(
    'Household setup arrives in the next migration phase.',
    '家族の作成・参加は次の移行フェーズで追加されます。',
  );
  String get requiredFields =>
      text('Complete every field before continuing.', 'すべての項目を入力してください。');
  String get invalidInvite => text(
    'That invite code is invalid or no longer active.',
    '招待コードが無効、または利用できなくなっています。',
  );
  String get setupNetworkFailure => text(
    'CoPaw could not reach the service. Check your connection and try again.',
    'サービスに接続できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get setupPermissionFailure => text(
    'This account cannot access that household. Check the invite and try again.',
    'この家にアクセスできません。招待コードを確認して、もう一度お試しください。',
  );
  String get setupUnknownFailure => text(
    'CoPaw could not finish setup. No local household was saved. Try again.',
    '設定を完了できませんでした。家の情報は端末に保存されていません。もう一度お試しください。',
  );
  String get creatingHousehold => text('Creating household…', '家を作成中…');
  String get joiningHousehold => text('Joining household…', '家に参加中…');
  String get firstPet => text('Pet', 'ペット');
  String get pets => text('Pets', 'ペット');
  String get selectedPet => text('Selected pet', '表示するペット');
  String get allPets => text('All pets', 'すべてのペット');
  String get todaysCare => text("Today's care", '今日のケア');
  String todayCareCount(int count) =>
      text('$count items today', '今日は $count 件');
  String get addPet => text('Add pet', 'ペットを追加');
  String get renamePet => text('Rename pet', '名前を変更');
  String get archivePet => text('Archive pet', 'ペットをアーカイブ');
  String get noPets => text('No pets are available.', '利用できるペットがいません。');
  String get noActivePet => text('No active pet', '利用中のペットなし');
  String get noActivePetHelp => text(
    'Add or select an active pet before scheduling new care.',
    '新しいケアを予定する前に、利用中のペットを追加または選択してください。',
  );
  String get unknownPet => text('Unknown pet', 'ペット不明');
  String get retryPets => text('Retry pets', 'ペット情報を再読み込み');
  String get petLoadFailure => text(
    'Pets could not be refreshed. Check your connection and try again.',
    'ペット情報を更新できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get petPermissionFailure => text(
    'This device can no longer access the household pets.',
    'この端末では、この家のペット情報にアクセスできなくなりました。',
  );
  String get petDataFailure => text(
    'Some pet data could not be read safely.',
    '一部のペット情報を安全に読み取れませんでした。',
  );
  String get petSaveFailure => text(
    'The pet change was not confirmed. Check your connection and try again.',
    'ペット情報の変更を確認できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get species => text('Species', '種類');
  String get unspecified => text('Not specified', '未設定');
  String get cancel => text('Cancel', 'キャンセル');
  String archivedPetName(String name) =>
      text('$name (archived)', '$name（アーカイブ済み）');
  String forPet(String name) => text('For $name', '$name のケア');
  String archivePetConfirmation(String name) => text(
    'Archive $name? Existing history stays visible, but new care cannot be scheduled.',
    '$nameをアーカイブしますか？履歴は残りますが、新しいケアは予定できません。',
  );
  String petSpecies(PetSpecies? value) => switch (value) {
    null => unspecified,
    PetSpecies.dog => text('Dog', '犬'),
    PetSpecies.cat => text('Cat', '猫'),
    PetSpecies.rabbit => text('Rabbit', 'うさぎ'),
    PetSpecies.other => text('Other', 'その他'),
  };
  String signedInAs(String name) => text('Caregiver: $name', 'ケア担当: $name');
  String get leaveHousehold => text('Leave this household', 'この家から退出');
  String get disconnectThisDevice =>
      text('Disconnect this device', 'この端末だけを切断');
  String get disconnectingThisDevice =>
      text('Disconnecting this device…', 'この端末を切断中…');
  String get revokingHouseholdAccess =>
      text('Revoking household access…', '家族へのアクセスを無効化中…');
  String get leaveHouseholdConfirmation => text(
    'This revokes your household access on every device. It is different from disconnecting only this device.',
    'すべての端末で、この家族へのアクセスが無効になります。この端末だけの切断とは異なります。',
  );
  String get sessionNotSaved => text(
    'This household was created, but this device could not save the session. Keep the invite code; you may need it after restarting.',
    '家は作成されましたが、この端末にセッションを保存できませんでした。再起動後に必要になる場合があるため、招待コードを控えてください。',
  );
  String get timezoneNeedsRepair => text(
    'This legacy household needs a timezone before new schedules can be saved.',
    '新しい予定を保存する前に、この旧形式の家にタイムゾーンを設定してください。',
  );
  String get leaveFailure => text(
    'CoPaw could not clear this device session. Try again before handing the device to someone else.',
    'この端末のセッションを消去できませんでした。端末を他の人に渡す前に、もう一度お試しください。',
  );
  String get disconnectFailure => text(
    'This device was not disconnected. Notification access and the local session were kept; check the connection and try again.',
    'この端末は切断されませんでした。通知設定と端末内セッションは保持されています。通信状況を確認して、もう一度お試しください。',
  );
  String get disconnectNotificationFailure => text(
    'Notification registration could not be disabled, so the local session was preserved. Check the connection and try again.',
    '通知登録を無効にできなかったため、端末内セッションを保持しました。通信状況を確認して、もう一度お試しください。',
  );
  String get disconnectLocalSessionFailure => text(
    'Notification registration was disabled, but the local session could not be cleared. Try disconnecting this device again.',
    '通知登録は無効になりましたが、端末内セッションを消去できませんでした。この端末の切断をもう一度お試しください。',
  );
  String get leaveRemoteFailure => text(
    'Household access was not revoked. Check the connection and try again.',
    '家族へのアクセスは無効になっていません。通信状況を確認して、もう一度お試しください。',
  );
  String get leaveNetworkFailure => text(
    'You are still a household member. Reconnect, then retry with the same request.',
    '家族メンバーのままです。再接続してから、同じリクエストでもう一度お試しください。',
  );
  String get leavePermissionFailure => text(
    'Membership could not be confirmed. Refresh the household before trying again.',
    'メンバー資格を確認できませんでした。家族情報を更新してから、もう一度お試しください。',
  );
  String get leaveStaleFailure => text(
    'Household responsibilities changed. Review the latest state, then try again.',
    '家族内の担当状況が更新されました。最新の状態を確認してから、もう一度お試しください。',
  );
  String get leaveBlocked => text(
    'Resolve household responsibilities or an active handoff before leaving.',
    '退出する前に、家族内の担当または進行中の引き継ぎを解決してください。',
  );
  String get leaveBlockedOwner => text(
    'The household owner cannot leave yet. Ownership transfer or household deletion must be completed first.',
    '家族のオーナーはまだ退出できません。先にオーナー権限の移行または家族の削除が必要です。',
  );
  String get leaveBlockedAssignedTask => text(
    'Release or complete your assigned care before leaving.',
    '退出する前に、自分が担当中のケアを解除または完了してください。',
  );
  String get leaveBlockedPendingTransfer => text(
    'Resolve your pending responsibility transfer before leaving.',
    '退出する前に、保留中の担当移行を解決してください。',
  );
  String get leaveBlockedActiveHandoff => text(
    'Close, decline, or cancel the active handoff session before leaving.',
    '退出する前に、進行中の引き継ぎセッションを終了・辞退・取消してください。',
  );
  String get today => text('Today', '今日');
  String get calendar => text('Calendar', 'カレンダー');
  String get updates => text('Updates', '更新');
  String get records => text('Records', '記録');
  String get activity => text('Activity', 'アクティビティ');
  String get profile => text('Profile', 'プロフィール');
  String get medication => text('Medication', 'お薬');
  String get medications => text('Medications', 'お薬');
  String get health => text('Health', '健康');
  String get medicationRecordsHelp => text(
    'Manage medication plans and confirm outcomes.',
    '服薬プランを管理し、結果を記録します。',
  );
  String get healthRecordsHelp => text(
    'Add observations, daily check-ins, and medical history.',
    '観察、毎日のチェック、病歴を記録します。',
  );
  String get factualHistory => text('Pet history', 'ペットの履歴');
  String get factualHistoryHelp => text(
    'Review completed care, medication outcomes, and observations.',
    '完了したケア、服薬結果、観察記録を確認します。',
  );
  String get reports => text('Reports', 'レポート');
  String get reportsHelp => text(
    'Review and share 7- or 30-day care summaries.',
    '7日・30日のケア記録を確認、共有します。',
  );
  String get careCoverage => text('Care coverage', 'ケアの抜け漏れ');
  String get careCoverageHelp => text(
    'See where care was left without an owner or an outcome.',
    '担当や結果が記録されていないケアを確認します。',
  );
  String get coveragePurpose => text(
    'These counts show what was recorded. Nothing here concludes that care did '
        'not happen.',
    'ここでは記録された内容のみを数えています。ケアが行われなかったと断定するものではありません。',
  );
  String get coverageNoRange => text(
    'The household timezone is unusable, so no period could be determined.',
    '家庭のタイムゾーンが使用できないため、期間を特定できません。',
  );
  String get coverageNoGaps => text(
    'No gaps recorded for this period.',
    'この期間に抜け漏れの記録はありません。',
  );
  String coverageMedicationWithoutOwner(int count) => text(
    '$count doses with nobody responsible',
    '担当者のいない服薬: $count 件',
  );
  String coverageMedicationWithoutOutcome(int count) => text(
    '$count doses with no recorded outcome',
    '結果が未記録の服薬: $count 件',
  );
  String coverageTasksWithoutOwner(int count) => text(
    '$count overdue tasks with nobody assigned',
    '担当者のいない期限切れタスク: $count 件',
  );
  String coverageDaysWithoutHealth(int count) => text(
    '$count days with no health record',
    '健康記録のない日: $count 日',
  );
  String get coverageContributions => text('Recorded by member', '記録者ごとの件数');
  String get coverageContributionsNote => text(
    'Counts of recorded work. A lower count may simply mean a member was not '
        'on duty.',
    '記録された件数です。少ない場合は担当していなかっただけの可能性があります。',
  );
  String get coverageNoContributions => text(
    'Nothing was recorded by anyone in this period.',
    'この期間に記録はありません。',
  );
  String coverageContributionDetail(int tasks, int medication) => text(
    '$tasks tasks · $medication medication outcomes',
    'タスク $tasks 件 · 服薬結果 $medication 件',
  );
  String get vetVisitPack => text('Visit pack', '受診・引き継ぎ資料');
  String get vetVisitPackHelp => text(
    'Collect what caregivers recorded, with the source of every line.',
    '家族が記録した内容を、出典付きでまとめます。',
  );
  String get vetPackPurpose => text(
    'Every line shows who recorded it and when. Nothing here is interpreted.',
    '各項目には記録者と日時が付きます。解釈は加えていません。',
  );
  String get vetPackContacts => text('Emergency contacts', '緊急連絡先');
  String get vetPackInstructions => text('Care instructions', 'ケアの指示');
  String get vetPackMedications => text('Active medications', '継続中の薬');
  String get vetPackOutcomes => text('Medication given', '服薬の結果');
  String get vetPackObservations => text('Observations', '観察記録');
  String get vetPackNothingRecorded => text(
    'Nothing recorded for this period.',
    'この期間の記録はありません。',
  );
  String get vetPackNoRange => text(
    'The household timezone is unusable, so no period could be determined.',
    '家庭のタイムゾーンが使用できないため、期間を特定できません。',
  );
  String get vetPackNoRecordedSource => text(
    'No recorded source',
    '記録者の情報なし',
  );
  String vetPackRecordedBy(String name) => text(
    'Recorded by $name',
    '記録者: $name',
  );
  String get reportCustomRange => text('Custom range', '期間を指定');
  String get reportSections => text('Include', '含める内容');
  String get reportSectionCare => text('Care', 'ケア');
  String get reportSectionMedication => text('Medication', '服薬');
  String get reportSectionHealth => text('Health', '健康');
  String get reportSectionWater => text('Water', '飲水');
  String reportCustomRangeDays(int days) => text('$days days', '$days 日間');
  String get searchHistory => text('Search history', '履歴を検索');
  String get searchHistoryHelp => text(
    'Find past observations, medication outcomes, and care by date or keyword.',
    '過去の観察、服薬結果、ケアを日付やキーワードで探します。',
  );
  String get searchKeywordLabel => text('Keyword', 'キーワード');
  String get searchAllPets => text('All pets', 'すべてのペット');
  String get searchFromDate => text('From', '開始日');
  String get searchToDate => text('To', '終了日');
  String get searchAnyDate => text('Any date', '日付を指定しない');
  String get searchKindHealth => text('Health', '健康');
  String get searchKindMedication => text('Medication', '服薬');
  String get searchKindTask => text('Care', 'ケア');
  String get searchClear => text('Clear filters', '条件をクリア');
  String get searchEmpty => text(
    'No records match these filters.',
    '条件に一致する記録はありません。',
  );
  String searchResultCount(int count) => text(
    '$count records',
    '$count 件の記録',
  );
  String searchUndatedCount(int count) => text(
    '$count records could not be placed on a household date.',
    '$count 件は家庭の日付を特定できませんでした。',
  );
  String get searchUnconfirmed => text(
    'Not confirmed by the server yet',
    'サーバー未確認',
  );
  String get backToRecords => text('Back to Records', '記録に戻る');
  String get updatesScope => text(
    'Updates show who changed shared care. Pet facts remain in Records.',
    '更新では家族による共同ケアの変更を確認できます。ペットの記録は「記録」に残ります。',
  );
  String get notificationChanges => text('Changes', '変更');
  String get notificationReminders => text('Reminders', 'リマインダー');
  String get notificationUnread => text('Unread', '未読');
  String get notificationInboxTitle => text('Care reminders', 'ケアのリマインダー');
  String get notificationInboxScope => text(
    'Private reminders for this household. Open the source before taking action.',
    'この家族の非公開リマインダーです。操作する前に元の情報を確認してください。',
  );
  String get notificationInboxCached => text(
    'Showing saved reminders. New changes may be missing.',
    '保存済みのリマインダーを表示しています。最新情報が含まれない場合があります。',
  );
  String get notificationInboxCachedItem => text(
    'Saved item; server confirmation is pending.',
    '保存済みの項目です。サーバー確認待ちです。',
  );
  String get notificationInboxDropped => text(
    'Some reminders could not be shown safely. The unread dot stays on.',
    '一部のリマインダーを安全に表示できませんでした。未読の印は残ります。',
  );
  String get notificationInboxPending => text(
    'Reminder state is waiting for server confirmation.',
    'リマインダーの状態はサーバー確認待ちです。',
  );
  String get notificationInboxEmpty =>
      text('No active reminders.', '対応が必要なリマインダーはありません。');
  String get notificationInboxUnavailable =>
      text('This reminder is no longer available.', 'このリマインダーは利用できなくなりました。');
  String get notificationInboxLongError => text(
    'Reminders could not be refreshed. Check the connection and try again; previously loaded reminders remain visible.',
    'リマインダーを更新できませんでした。通信状況を確認してもう一度お試しください。読み込み済みのリマインダーは引き続き表示されます。',
  );
  String get notificationPermissionError => text(
    'This household no longer permits reminder read-state updates. Return to Today and refresh the household.',
    'この家族ではリマインダーの既読状態を更新できません。「今日」に戻って家族情報を更新してください。',
  );
  String get notificationNetworkError => text(
    'The reminder read state could not be confirmed. Check the connection and try again.',
    'リマインダーの既読状態を確認できませんでした。通信状況を確認してもう一度お試しください。',
  );
  String get notificationBackendError => text(
    'The reminder service is temporarily unavailable. Try again without closing this reminder.',
    'リマインダー機能を一時的に利用できません。このリマインダーを閉じずにもう一度お試しください。',
  );
  String get notificationDataError => text(
    'This reminder state needs to be refreshed before it can be marked read.',
    '既読にする前に、このリマインダーの状態を更新する必要があります。',
  );
  String get loadOlderReminders =>
      text('Load older reminders', '過去のリマインダーを読み込む');
  String notificationInboxItem(NotificationInboxCategory category) =>
      switch (category) {
        NotificationInboxCategory.medication => text(
          'Medication care needs attention',
          '服薬ケアの確認が必要です',
        ),
        NotificationInboxCategory.assignment => text(
          'A care assignment needs attention',
          'ケア担当の確認が必要です',
        ),
        NotificationInboxCategory.urgent => text(
          'Urgent care needs attention',
          '緊急ケアの確認が必要です',
        ),
        NotificationInboxCategory.summary => text(
          'Care reminder summary',
          'ケアリマインダーのまとめ',
        ),
      };
  String notificationRouteReason(NotificationRouteReason reason) =>
      switch (reason) {
        NotificationRouteReason.responsible => text(
          'You are responsible for this care.',
          'あなたがこのケアの担当です。',
        ),
        NotificationRouteReason.backup => text(
          'You are the backup caregiver.',
          'あなたは代理のケア担当です。',
        ),
        NotificationRouteReason.medicationOptIn => text(
          'You opted in to medication reminders.',
          '服薬リマインダーを受け取る設定です。',
        ),
        NotificationRouteReason.directTarget => text(
          'This update is directed to you.',
          'あなた宛ての更新です。',
        ),
        NotificationRouteReason.handoffRecipient => text(
          'You are the handoff recipient.',
          'あなたは引き継ぎ先です。',
        ),
        NotificationRouteReason.urgentOptIn => text(
          'You opted in to urgent care alerts.',
          '緊急ケア通知を受け取る設定です。',
        ),
        NotificationRouteReason.summary => text(
          'This is your care summary.',
          'あなた向けのケアまとめです。',
        ),
      };
  String get notificationOpenReminder => text('Review reminder', 'リマインダーを確認');
  String get notificationForegroundBody =>
      text('Care update available', 'ケアの更新があります');
  String get updatesNotAvailable => text(
    'No collaboration updates have been recorded since Updates was enabled.',
    '「更新」の有効化後に記録された共同作業の更新はまだありません。',
  );
  String get updatesIncomplete => text(
    'Updates may be incomplete while older app versions remain in use. Source care records are still authoritative.',
    '旧バージョンのアプリが利用されている間、更新履歴が一部欠ける場合があります。ケア記録の原本が正しい情報です。',
  );
  String get updatesCached => text(
    'Showing saved updates while offline. New changes may be missing.',
    'オフラインのため保存済みの更新を表示しています。最新の変更が含まれない場合があります。',
  );
  String updatesMalformed(int count) => text(
    '$count collaboration update could not be shown safely.',
    '$count 件の共同作業の更新を安全に表示できませんでした。',
  );
  String get updatesLoadFailure => text(
    'Updates could not be refreshed. Check the connection and try again.',
    '更新履歴を読み込めませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get updatesNetworkFailure => text(
    'Updates are offline. Check your connection, then try again.',
    'オフラインのため更新履歴を読み込めません。通信状況を確認して、もう一度お試しください。',
  );
  String get updatesPermissionFailure => text(
    'This account cannot access household updates. Check household access or sign in again, then retry.',
    'このアカウントでは家族の更新履歴にアクセスできません。家族へのアクセス権またはログイン状態を確認して、もう一度お試しください。',
  );
  String get updatesBackendFailure => text(
    'Updates are temporarily unavailable. Try again in a little while.',
    '更新履歴を一時的に利用できません。しばらくしてから、もう一度お試しください。',
  );
  String get updatesDataFailure => text(
    'Updates could not be loaded safely. Restart the app, then try again.',
    '更新履歴を安全に読み込めませんでした。アプリを再起動して、もう一度お試しください。',
  );
  String get updatesReadStateFailure => text(
    'Updates remain visible, but read status could not sync. Check the connection and reopen Updates.',
    '更新履歴は表示できますが、既読状態を同期できませんでした。通信状況を確認して「更新」を開き直してください。',
  );
  String get updatesReadStatePending => text(
    'Read status is waiting to sync. The unread dot will remain until the server confirms it.',
    '既読状態の同期を待っています。サーバーで確認されるまで未読の印は残ります。',
  );
  String get loadOlderUpdates => text('Load older updates', '過去の更新を読み込む');
  String collaborationAction(
    CollaborationEventAction action,
  ) => switch (action) {
    CollaborationEventAction.taskCreated => text('Care added', 'ケアを追加'),
    CollaborationEventAction.taskRequested => text('Help requested', 'ケアを依頼'),
    CollaborationEventAction.taskClaimed => text(
      'Responsibility claimed',
      '担当を引き受け',
    ),
    CollaborationEventAction.taskAccepted => text('Request accepted', '依頼を承認'),
    CollaborationEventAction.taskDeclined => text('Request declined', '依頼を辞退'),
    CollaborationEventAction.taskCancelled => text(
      'Request cancelled',
      '依頼を取消',
    ),
    CollaborationEventAction.taskCompleted => text('Care completed', 'ケアを完了'),
    CollaborationEventAction.taskReleased => text(
      'Responsibility released',
      '担当を解除',
    ),
    CollaborationEventAction.taskReassignRequested => text(
      'Responsibility transfer requested',
      '担当移行を依頼',
    ),
    CollaborationEventAction.taskTakeoverRequested => text(
      'Takeover requested',
      '担当交代を依頼',
    ),
    CollaborationEventAction.taskReassigned => text('Care reassigned', '担当を変更'),
    CollaborationEventAction.taskTakenOver => text('Care taken over', '担当を交代'),
    CollaborationEventAction.taskTransferDeclined => text(
      'Responsibility transfer declined',
      '担当移行を辞退',
    ),
    CollaborationEventAction.taskTransferCancelled => text(
      'Responsibility transfer cancelled',
      '担当移行を取消',
    ),
    CollaborationEventAction.taskTransferSuperseded => text(
      'Transfer closed by completed care',
      'ケア完了により担当移行を終了',
    ),
    CollaborationEventAction.handoffOffered => text(
      'Handoff offered',
      '引き継ぎを提案',
    ),
    CollaborationEventAction.handoffAccepted => text(
      'Handoff accepted',
      '引き継ぎを承認',
    ),
    CollaborationEventAction.handoffDeclined => text(
      'Handoff declined',
      '引き継ぎを辞退',
    ),
    CollaborationEventAction.handoffCancelled => text(
      'Handoff cancelled',
      '引き継ぎを取消',
    ),
    CollaborationEventAction.handoffClosed => text('Handoff closed', '引き継ぎを終了'),
  };
  String collaborationEventDetail({
    required String actor,
    required String? pet,
    required String? target,
    String? responsibilityFrom,
    String? responsibilityTo,
    String? handoffCreator,
    String? handoffRecipient,
  }) => text(
    [
      actor,
      ?pet,
      ?target,
      ?responsibilityFrom,
      ?responsibilityTo,
      ?handoffCreator,
      ?handoffRecipient,
    ].join(' · '),
    [
      actor,
      ?pet,
      ?target,
      ?responsibilityFrom,
      ?responsibilityTo,
      ?handoffCreator,
      ?handoffRecipient,
    ].join('・'),
  );
  String get healthTimeline => text('Medical & health record', '病歴・健康記録');
  String get dailyHealthCheckIn => text('Daily health check-in', '毎日の健康チェック');
  String get dailyHealthCheckInHelp => text(
    'Record changes from this pet’s usual pattern. Do not use this as a diagnosis.',
    'この子の「いつも」と比べた変化を記録します。診断の代わりにはなりません。',
  );
  String dailyHealthCompleted(String petName) =>
      text('$petName is checked in for today.', '$petName は今日のチェックを記録済みです。');
  String dailyHealthMissing(String petName) => text(
    '$petName has not been checked in today.',
    '$petName は今日のチェックがまだです。',
  );
  String get startDailyHealthCheckIn =>
      text('Start daily check-in', '今日のチェックを始める');
  String get saveDailyHealthCheckIn =>
      text('Save daily check-in', '今日のチェックを保存');
  String get dailyHealthWater => text('Drinking', '飲水');
  String get dailyHealthWaterMeasured => text(
    'Total measured so far today (ml, optional)',
    '今日、チェック時点までの累計飲水量（ml・任意）',
  );
  String get dailyHealthAppetite => text('Eating / appetite', '食事・食欲');
  String get dailyHealthUrination => text('Urination', '排尿');
  String get dailyHealthStool => text('Stool', '排便');
  String get dailyHealthEnergy => text('Energy / activity', '元気・活動');
  String get dailyHealthMood => text('Mood / behavior', '気分・行動');
  String get dailyHealthLess => text('Less than usual', 'いつもより少ない');
  String get dailyHealthUsual => text('As usual', 'いつもどおり');
  String get dailyHealthMore => text('More than usual', 'いつもより多い');
  String get dailyHealthChanged => text('Changed', '変化あり');
  String get dailyHealthNotObserved => text('Not observed', '未確認');
  String get dailyHealthNotes =>
      text('Changes, symptoms, or context (optional)', '変化・症状・状況（任意）');
  String get addHealthRecord => text('Add health record', '健康記録を追加');
  String get saveHealthRecord => text('Save health record', '健康記録を保存');
  String get allHealthRecords => text('All records', 'すべての記録');
  String get noHealthRecords =>
      text('No health records for this pet.', 'このペットの健康記録はありません。');
  String get healthNonDiagnostic => text(
    'Shared observations only — not medical advice or a diagnosis.',
    '共有された観察記録です。医療上の助言や診断ではありません。',
  );
  String get healthNotCurrent => text(
    'Showing saved records while offline. New server updates may be missing.',
    'オフラインのため保存済みの記録を表示しています。最新の更新が含まれない場合があります。',
  );
  String get healthDetail => text('Observation or detail', '観察内容・詳細');
  String get healthNoteOptional => text('Note (optional)', 'メモ（任意）');
  String get weightKilograms => text('Weight (kg)', '体重（kg）');
  String get waterMilliliters =>
      text('This single drinking event (ml)', '今回1回分の飲水量（ml）');
  String get healthVisitDetail => text(
    'Visit findings, recorded diagnosis, prescribed medicine, and veterinarian instructions',
    '診察内容・記録された診断・処方薬・獣医師の指示',
  );
  String get healthPhoto => text('Record photo', '記録写真');
  String get healthPhotoAffordance => text(
    'Add a photo of an injury, symptom, prescription label, or test result',
    'けが・症状・処方ラベル・検査結果の写真を追加',
  );
  String get healthSaveFailure => text(
    'Could not save this health record. Check the fields and try again.',
    '健康記録を保存できませんでした。入力内容を確認して、もう一度お試しください。',
  );
  String get healthConflict => text(
    'This health record changed or was already saved. Refresh before trying again.',
    'この健康記録は更新済み、またはすでに保存されています。更新してからもう一度お試しください。',
  );
  String get healthInvalidInput => text(
    'Check the health record fields and try again.',
    '健康記録の入力内容を確認して、もう一度お試しください。',
  );
  String get healthNetworkFailure => text(
    'Health records could not reach the server. Reconnect and try again.',
    'サーバーに接続できませんでした。通信を確認して、もう一度お試しください。',
  );
  String get healthPermissionFailure => text(
    'This household no longer permits access to these health records.',
    'この家の健康記録にアクセスする権限がありません。',
  );
  String get healthDataFailure => text(
    'A health record needs repair before this timeline can be shown safely.',
    '安全に表示するため、健康記録の修復が必要です。',
  );
  String healthRecordsNeedRepair(int count) => text(
    '$count health record${count == 1 ? '' : 's'} could not be read safely. Reports are unavailable until the data is repaired.',
    '$count件の健康記録を安全に読み込めませんでした。データが修復されるまでレポートは利用できません。',
  );
  String get healthLoadFailure =>
      text('Health records could not be loaded.', '健康記録を読み込めませんでした。');
  String get retryHealth => text('Retry health records', '健康記録を再読み込み');
  String healthRecordedBy(String name) =>
      text('Recorded by $name', '$name が記録');
  String healthWeightTrend(double latest, double? change) {
    final latestText = latest.toStringAsFixed(1);
    if (change == null) {
      return text('Latest weight: $latestText kg', '最新の体重：$latestText kg');
    }
    final changeText = '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}';
    return text(
      'Latest weight: $latestText kg ($changeText kg from prior record)',
      '最新の体重：$latestText kg（前回比 $changeText kg）',
    );
  }

  String get healthWeight => text('Weight', '体重');
  String get healthWater => text('Water intake', '飲水量');
  String get healthAppetite => text('Appetite', '食欲');
  String get healthEnergy => text('Energy', '元気');
  String get healthMood => text('Mood', '気分・様子');
  String get healthStool => text('Stool / observation', '便・観察');
  String get healthSymptom => text('Symptom', '症状');
  String get healthVisit => text('Vet visit', '通院');
  String get healthVaccine => text('Vaccine', 'ワクチン');
  String get healthNote => text('Note', 'メモ');
  String get notifications => text('Notifications', '通知');
  String get notificationOsPermission => text('System permission', 'システム通知の許可');
  String get notificationPreferences =>
      text('Reminder preferences', 'リマインダー設定');
  String get notificationInstallation => text('This device', 'この端末');
  String get notificationProviderEvidence =>
      text('Latest provider attempt', '直近の配信試行');
  String get notificationProviderScopeLabel => text('Scope', '対象範囲');
  String get notificationProviderScope => text(
    'Evidence is limited to this installation in this household; it does not prove display.',
    'この世帯のこのインストールに限る記録であり、端末での表示完了を証明するものではありません。',
  );
  String get notificationProviderAttemptTime =>
      text('Attempt recorded', '試行の記録日時');
  String get notificationProviderAttemptTimeUnknown =>
      text('Time unavailable.', '日時を確認できません。');
  String get notificationOsAuthorized => text(
    'Allowed by system. This does not mean reminders are enabled.',
    'システムで許可されています。リマインダー有効とは限りません。',
  );
  String get notificationOsProvisional =>
      text('Quietly allowed by system.', 'システムで仮許可されています。');
  String get notificationOsDenied =>
      text('Blocked in system settings.', 'システム設定で許可されていません。');
  String get notificationOsNotDetermined =>
      text('Permission not requested.', '通知の許可をまだ確認していません。');
  String get notificationOsUnsupported =>
      text('Not supported on this build.', 'このビルドでは利用できません。');
  String get notificationOsError =>
      text('Permission status could not be checked.', '通知許可の状態を確認できませんでした。');
  String get notificationInstallationReady =>
      text('Registered and ready.', '登録済みで受信準備ができています。');
  String get notificationInstallationRegistering =>
      text('Registration is waiting for confirmation.', '端末登録の確認待ちです。');
  String get notificationInstallationDisabled =>
      text('Registration is disabled.', '端末登録は無効です。');
  String get notificationInstallationUnavailable =>
      text('Registration is temporarily unavailable.', '端末登録を一時的に利用できません。');
  String get notificationInstallationUnsupported =>
      text('Registration is not supported.', '端末登録に対応していません。');
  String get notificationInstallationError =>
      text('Registration status could not be checked.', '端末登録の状態を確認できませんでした。');
  String get notificationProviderNotVerified => text(
    'No current provider result for this installation.',
    'この端末について現在の配信結果は確認されていません。',
  );
  String get notificationProviderNotConfigured => text(
    'Provider status is unavailable because notifications are not configured on this device or build.',
    'この端末またはビルドでは通知が設定されていないため、配信状態を確認できません。',
  );
  String get notificationProviderAccepted => text(
    'Provider accepted the latest attempt. Display is not verified.',
    '配信サービスは直近の試行を受け付けました。端末への表示は未確認です。',
  );
  String get notificationProviderUnknown =>
      text('The latest provider result is uncertain.', '直近の配信結果を確認できません。');
  String get notificationProviderFailure =>
      text('The latest attempt definitely failed.', '直近の配信試行は失敗しました。');
  String get notificationProviderCachedUnknown => text(
    'Saved provider status is stale; the current result is unknown.',
    '保存済みの配信状態は古いため、現在の結果は不明です。',
  );
  String get notificationProviderRefreshingStale => text(
    'Refreshing. The last recorded attempt is retained but is not current.',
    '更新中です。直前の試行記録は保持していますが、現在の状態ではありません。',
  );
  String get notificationProviderRefreshErrorStale => text(
    'Refresh failed. The last recorded attempt is retained; current provider status is unknown.',
    '更新できませんでした。直前の試行記録は保持していますが、現在の配信状態は不明です。',
  );
  String get notificationPreferencesMissing => text(
    'Conservative defaults are active until you save preferences.',
    '設定を保存するまで安全側の初期設定を使用します。',
  );
  String get notificationPreferencesCached => text(
    'Showing saved preferences; server confirmation is pending.',
    '保存済みの設定を表示しています。サーバー確認待ちです。',
  );
  String get notificationPreferencesPending =>
      text('Saving preferences…', '設定を保存中…');
  String get notificationPreferencesMalformed => text(
    'Preferences need repair before routing can continue.',
    'リマインダー設定の修復が必要です。',
  );
  String get notificationPreferencesError =>
      text('Preferences could not be refreshed.', 'リマインダー設定を更新できませんでした。');
  String get notificationPreferencesPermissionError => text(
    'This household no longer permits changing reminder preferences. Return to Today and refresh the household.',
    'この世帯ではリマインダー設定を変更できません。「今日」に戻って世帯情報を更新してください。',
  );
  String get notificationPreferencesNetworkError => text(
    'Preferences could not reach the server. Check the connection and retry without discarding your changes.',
    '設定をサーバーに送信できませんでした。変更内容を破棄せず、通信状況を確認して再試行してください。',
  );
  String get notificationPreferencesBackendError => text(
    'Preference saving is temporarily unavailable. Retry without discarding your changes.',
    '設定の保存を一時的に利用できません。変更内容を破棄せずに再試行してください。',
  );
  String get notificationPreferencesDataError => text(
    'Preferences changed or need repair. Refresh before trying again.',
    '設定が更新されたか、修復が必要です。再試行する前に更新してください。',
  );
  String get repairNotificationPreferences =>
      text('Reset to safe defaults', '安全な初期設定に戻す');
  String get notificationMedicationPreference =>
      text('Medication reminders', '服薬リマインダー');
  String get notificationAssignmentPreference =>
      text('Assignment alerts', '担当変更の通知');
  String get notificationUrgentPreference =>
      text('Urgent care alerts', '緊急ケアの通知');
  String get notificationPushPreference =>
      text('Send system notifications', 'システム通知を送る');
  String get notificationQuietPreference => text('Quiet hours', 'おやすみ時間');
  String get notificationQuietStart => text('Quiet hours start', 'おやすみ時間の開始');
  String get notificationQuietEnd => text('Quiet hours end', 'おやすみ時間の終了');
  String get notificationSummaryPreference => text('Daily summary', '1日のまとめ');
  String get notificationSummaryTime => text('Summary time', 'まとめの時刻');
  String get notificationBackupPreference => text('Backup for', '代理通知の対象');
  String get notificationEnabled => text(
    'Reminders are enabled. Lock-screen messages hide pet, medication, dose, and health details.',
    'リマインダーは有効です。ロック画面にはペット名、お薬名、用量、健康情報を表示しません。',
  );
  String get notificationNotDetermined => text(
    'Enable reminders for unresolved care. Notification previews remain private.',
    '未記録のケアのリマインダーを有効にできます。通知プレビューには詳細を表示しません。',
  );
  String get notificationDenied => text(
    'Notifications are off. Open system settings to restore reminders.',
    '通知がオフです。システム設定からリマインダーを再開できます。',
  );
  String get notificationUnavailable => text(
    'Permission is on, but this device is not ready for notifications yet. Try again.',
    '通知は許可されていますが、この端末はまだ通知を受信できません。もう一度お試しください。',
  );
  String get notificationUnsupported => text(
    'Notifications are not available on this device or build.',
    'この端末またはビルドでは通知を利用できません。',
  );
  String get notificationFailure => text(
    'Notification status could not be refreshed. No device token was shown or logged.',
    '通知の状態を更新できませんでした。端末トークンは表示・記録されていません。',
  );
  String get enableNotifications => text('Enable reminders', 'リマインダーを有効にする');
  String get openNotificationSettings => text('Open settings', '設定を開く');
  String get retryNotifications => text('Retry notifications', '通知を再確認');
  String get notificationPolicy => text('When CoPaw notifies', '通知するタイミング');
  String get medicationReminderPolicy => text(
    'Medication: at the scheduled time, then +15 and +30 minutes while unresolved.',
    '服薬：予定時刻に通知し、未記録の場合は15分後・30分後に再通知します。',
  );
  String get urgentReminderPolicy => text(
    'Urgent care and tasks assigned to you: realtime alerts are planned, but not delivered by this build yet.',
    '緊急ケア・自分への担当依頼：リアルタイム通知は準備中で、このビルドではまだ配信されません。',
  );
  String get routineReminderPolicy => text(
    'Routine care: visible in the app without a realtime alert.',
    '通常のケア：アプリ内に表示し、リアルタイム通知は行いません。',
  );
  String get notificationPrivacyPolicy => text(
    'Lock-screen alerts never include pet names, medication names, doses, or health details.',
    'ロック画面には、ペット名・薬名・用量・健康情報を表示しません。',
  );
  String get availableNow => text('Available now', '現在利用可能');
  String get plannedFeature => text('Planned', '準備中');
  String get medicationPlans => text('Medication plans', '服薬プラン');
  String get todaysMedication => text("Today's medication", '今日の服薬');
  String get medicationArchive => text('Medication archive', 'お薬の履歴');
  String get medicationOutcomeHistory =>
      text('Confirmed administration history', '確認済みの服薬実績');
  String get noMedicationOutcomeHistory => text(
    'No confirmed administered or skipped doses yet.',
    '確認済みの投薬・スキップ記録はまだありません。',
  );
  String get activeMedication => text('Current medication', '現在のお薬');
  String get pastMedication => text('Past medication', '過去のお薬');
  String get activePlan => text('Active', '使用中');
  String get stoppedPlan => text('Stopped', '終了');
  String get scheduleHistory => text('Schedule history', '服薬履歴');
  String get effectivePeriod => text('Period', '期間');
  String get openMedicationDetails =>
      text('Open medication record', 'お薬の記録を開く');
  String get addMedication => text('Add medication', 'お薬を追加');
  String get editMedication => text('Edit schedule', '予定を変更');
  String get stopMedication => text('Stop plan', 'プランを終了');
  String get medicationName => text('Medication name', 'お薬の名前');
  String get medicationPurpose =>
      text('Purpose / reason prescribed', '服薬目的・処方理由');
  String get medicationPossibleSideEffects =>
      text('Possible side effects / watch-outs', '副作用・観察する変化');
  String get medicationDetails => text('Medication record', 'お薬の記録');
  String get medicationPhoto => text('Medication photo', 'お薬の写真');
  String get photoNotAdded => text('No photo added', '写真は未追加です');
  String get photoSyncUnavailable => text(
    'Secure photo sync is not available in this build.',
    'このビルドでは写真の安全な同期はまだ利用できません。',
  );
  String get notRecorded => text('Not recorded', '未登録');
  String get dosageSchedule => text('Dose schedule', '服薬スケジュール');
  String get medicationReferenceDisclaimer => text(
    'This is a household record of the veterinary label and instructions, not medication advice.',
    '獣医師の処方ラベルと指示を家族で共有するための記録で、服薬アドバイスではありません。',
  );
  String get dose => text('Dose', '1回量');
  String get instructions => text('Instructions (optional)', 'メモ（任意）');
  String get doseTimes => text('Dose times', '服薬時刻');
  String get addDoseTime => text('Add another time', '時刻を追加');
  String get saveMedication => text('Save medication plan', '服薬プランを保存');
  String get noMedicationDue => text(
    'No medication is due for this pet today.',
    'このペットに今日予定されているお薬はありません。',
  );
  String get medicationNotCurrent => text(
    'Medication status is not current. Reconnect before recording a dose.',
    'お薬の状態が最新ではありません。再接続してから記録してください。',
  );
  String get retryMedication => text('Retry medication', 'お薬情報を再読み込み');
  String get medicationLoadFailure => text(
    'Medication could not be refreshed. Check your connection and try again.',
    'お薬情報を更新できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get medicationPermissionFailure => text(
    'This device can no longer access household medication.',
    'この端末では、この家のお薬情報にアクセスできなくなりました。',
  );
  String get medicationSaveFailure => text(
    'The medication change was not confirmed. The dose remains unresolved. Refresh before trying again.',
    '操作を確認できませんでした。服薬は未記録のままです。更新してからもう一度お試しください。',
  );
  String get medicationConflict => text(
    'Another caregiver already recorded this dose. The latest confirmed result is shown.',
    '別のケア担当者がすでに記録しました。確認済みの最新結果を表示しています。',
  );
  String get medicationResponsibilityConflict => text(
    'Another caregiver is already responsible for this dose. The latest confirmed assignment is shown.',
    '別のケア担当者がすでにこのお薬を担当しています。確認済みの最新担当を表示しています。',
  );
  String get medicationDataFailure => text(
    'This medication schedule could not be read safely. Refresh it before recording a dose.',
    'この服薬予定を安全に読み込めませんでした。記録する前に再読み込みしてください。',
  );
  String get administered => text('Administered', '投薬済み');
  String get recordAdministered => text('Record administered', '投薬済みにする');
  String get skipped => text('Skipped', 'スキップ');
  String get recordSkipped => text('Record skipped', 'スキップを記録');
  String get skipReason => text('Why was it skipped?', 'スキップした理由');
  String get skipReasonPetRefused => text('Pet refused', 'ペットが拒否した');
  String get skipReasonVomited => text('Vomited', '嘔吐した');
  String get skipReasonUnavailable => text('Medication unavailable', 'お薬がなかった');
  String get skipReasonVetInstruction =>
      text('Veterinarian instruction', '獣医師の指示');
  String get skipReasonOther => text('Other', 'その他');
  String get skipReasonNote => text('Reason note', '理由のメモ');
  String get responsible => text('Responsible', '担当');
  String get claimMedication => text('I am responsible', '自分が担当する');
  String get unclaimedMedication => text('Not assigned', '担当者なし');
  String get unresolvedMedication => text('Unresolved', '未記録');
  String get overdueMedication => text('Overdue', '予定時刻超過');
  String medicationRecordedBy(String actor) =>
      text('Recorded by $actor', '$actor が記録');
  String medicationForPet(String name) =>
      text('Medication for $name', '$name のお薬');
  String get noActivity => text('No completed care yet.', '完了したケアはまだありません。');
  String get activityTimeline => text('Household timeline', '家族のタイムライン');
  String get householdAccess => text('Household access', '家族との共有');
  String get languagePreference => text('Language preference', '言語設定');
  String get careCompletionRate => text('Care completion', 'ケア完了率');
  String get medicationAdherenceRate => text('Medication adherence', '服薬実施率');
  String get vetReadySummary => text(
    'Vet-ready summary: confirmed care, medication outcomes, and observations for the selected range.',
    '通院時に共有しやすいよう、選択期間のケア・服薬結果・観察記録をまとめています。',
  );
  String get unknownCaregiver => text('Unknown caregiver', '担当者不明');
  String get timeUnavailable => text('Time unavailable', '時刻不明');
  String get editProfile => text('Edit household profile', '家のプロフィールを編集');
  String get householdHandoff => text('Household handoff', '引き継ぎ情報');
  String get currentHandoffTemplate =>
      text('Current reusable template', '現在の再利用テンプレート');
  String get handoffEmpty => text(
    'Add care instructions and emergency information for other household members.',
    '家族のために、ケア手順と緊急時の情報を追加してください。',
  );
  String get handoffNotCurrent => text(
    'This handoff may not be current. Reconnect before relying on it.',
    'この引き継ぎ情報は最新でない可能性があります。利用前に再接続してください。',
  );
  String get careInstructions => text('Care instructions', 'ケア手順');
  String get emergencyContactName => text('Emergency contact name', '緊急連絡先の名前');
  String get emergencyContactPhone =>
      text('Emergency contact phone', '緊急連絡先の電話番号');
  String get veterinaryHospitalName => text('Veterinary hospital', '動物病院');
  String get veterinaryHospitalPhone => text('Hospital phone', '病院の電話番号');
  String get editHandoff => text('Edit handoff', '引き継ぎ情報を編集');
  String get saveHandoff => text('Save handoff', '引き継ぎ情報を保存');
  String get handoffSaveFailure => text(
    'The handoff was not confirmed. Check the fields and connection, then try again.',
    '引き継ぎ情報を確認できませんでした。入力内容と通信を確認して、もう一度お試しください。',
  );
  String get handoffConflict => text(
    'Someone updated the handoff while this form was open. Close it, review the latest version, and try again.',
    'この画面を開いている間に引き継ぎ情報が更新されました。閉じて最新版を確認してから、もう一度お試しください。',
  );
  String get handoffLoadFailure => text(
    'Handoff information could not be loaded safely.',
    '引き継ぎ情報を安全に読み込めませんでした。',
  );
  String get retryHandoff => text('Retry handoff', '引き継ぎ情報を再読み込み');
  String handoffUpdatedBy(String name) => text('Updated by $name', '$name が更新');
  String get handoffCoverageSession =>
      text('Coverage handoff session', 'ケア引き継ぎセッション');
  String get handoffTemplateSessionHelp => text(
    'The template is reusable. A session is a dated offer that keeps the exact template revision used when offered.',
    'テンプレートは再利用できます。セッションは期間付きの提案で、提案時のテンプレート版を固定して使用します。',
  );
  String get noActiveHandoffSession => text(
    'No active session. Editing the template does not start a handoff.',
    '進行中のセッションはありません。テンプレートを編集しても引き継ぎは開始されません。',
  );
  String get handoffSessionLoadFailure => text(
    'The active handoff session could not be loaded safely.',
    '進行中の引き継ぎセッションを安全に読み込めませんでした。',
  );
  String get handoffSessionNotCurrent => text(
    'Session authority is cached or inconsistent. Reconnect before offering or responding.',
    'セッションの権限情報がキャッシュ済み、または整合していません。提案・返答の前に再接続してください。',
  );
  String get offerHandoffSession => text('Offer handoff', '引き継ぎを提案');
  String get acceptHandoffSession => text('Accept handoff', '引き継ぎを承認');
  String get declineHandoffSession => text('Decline handoff', '引き継ぎを辞退');
  String get cancelHandoffSession => text('Cancel offer', '提案を取消');
  String get closeHandoffSession => text('Close handoff', '引き継ぎを終了');
  String get recoverHandoffSession => text('Owner recovery', 'オーナーとして復旧');
  String get handoffRecipient => text('Recipient', '引き継ぎ先');
  String get handoffPlannedStart => text('Planned start', '開始予定');
  String get handoffPlannedEnd => text('Planned end', '終了予定');
  String get handoffOfferConsentHelp => text(
    'The recipient must accept. Their responsibility does not change from this offer alone.',
    '引き継ぎ先の承認が必要です。提案だけでは担当は変わりません。',
  );
  String get handoffWindowInvalid => text(
    'Choose an end after the start, with a window no longer than 30 days.',
    '終了は開始より後、期間は30日以内に設定してください。',
  );
  String get handoffSessionNetworkFailure => text(
    'The handoff action was not confirmed. Reconnect and retry with the same request.',
    '引き継ぎ操作を確認できませんでした。再接続して、同じリクエストでもう一度お試しください。',
  );
  String get handoffSessionPermissionFailure => text(
    'You are not allowed to perform this handoff action. Refresh the household.',
    'この引き継ぎ操作を行う権限がありません。家族情報を更新してください。',
  );
  String get handoffSessionStaleFailure => text(
    'The template or session changed on another device. Review the latest state before retrying.',
    '別の端末でテンプレートまたはセッションが更新されました。最新の状態を確認してから、もう一度お試しください。',
  );
  String get handoffSessionActionFailure => text(
    'The handoff action was not confirmed. The session remains unchanged on this screen.',
    '引き継ぎ操作を確認できませんでした。この画面上ではセッションは変更されていません。',
  );
  String handoffSessionStatus(HandoffSessionStatus status) => switch (status) {
    HandoffSessionStatus.offered => text(
      'Offered — awaiting consent',
      '提案中・承認待ち',
    ),
    HandoffSessionStatus.accepted => text('Accepted', '承認済み'),
    HandoffSessionStatus.declined => text('Declined', '辞退済み'),
    HandoffSessionStatus.cancelled => text('Cancelled', '取消済み'),
    HandoffSessionStatus.closed => text('Closed', '終了済み'),
  };
  String handoffSessionParticipants(String creator, String recipient) =>
      text('From $creator to $recipient', '$creator から $recipient へ');
  String handoffSessionWindow(String start, String end) =>
      text('$start – $end', '$start ～ $end');
  String handoffSessionTemplateRevision(int revision) => text(
    'Template revision $revision is fixed for this session.',
    'このセッションではテンプレート版 $revision を固定して使用します。',
  );
  String handoffPinnedTemplate(int revision) =>
      text('Pinned template v$revision', '固定テンプレート v$revision');
  String get handoffCoverageCounts =>
      text('Live source counts for [start, end)', '対象期間 [開始, 終了) の最新元データ件数');
  String get handoffCoverageCountsUnavailable => text(
    'Coverage counts are unavailable until care and medication sources are server-confirmed.',
    'ケアと服薬の元データがサーバーで確認されるまで、対象件数は表示できません。',
  );
  String handoffCareSourceCounts(
    int planned,
    int completed,
    int unresolved,
  ) => text(
    'Care tasks: $planned planned · $completed completed · $unresolved unresolved',
    'ケアタスク：予定 $planned件・完了 $completed件・未解決 $unresolved件',
  );
  String handoffMedicationSourceCounts(
    int planned,
    int administered,
    int skipped,
    int unresolved,
  ) => text(
    'Medication: $planned planned · $administered administered · $skipped skipped · $unresolved unresolved',
    '服薬：予定 $planned件・投薬済み $administered件・スキップ $skipped件・未解決 $unresolved件',
  );
  String get careReport => text('Care report', 'ケアレポート');
  String get sevenDays => text('7 days', '7日間');
  String get thirtyDays => text('30 days', '30日間');
  String get reportUnavailable => text(
    'The report could not be reconciled from the current source records.',
    '現在の元データからレポートを照合できませんでした。',
  );
  String get reportNotCurrent => text(
    'Reconnect before relying on this report. Some source records are not server-confirmed.',
    'このレポートを利用する前に再接続してください。一部の元データがサーバーで確認されていません。',
  );
  String get reportNonDiagnostic => text(
    'Household summary only — not medical advice or a diagnosis.',
    '家族向けの記録サマリーです。医療上の助言や診断ではありません。',
  );
  String get careSummary => text('Care tasks', 'ケアタスク');
  String get medicationSummary => text('Medication outcomes', '服薬結果');
  String get healthSummary => text('Health observations', '健康観察');
  String get planned => text('Planned', '予定');
  String get completed => text('Completed', '完了');
  String get unresolved => text('Unresolved', '未解決');
  String get late => text('Late', '遅延');
  String get healthRecords => text('Records', '記録');
  String get recentConfirmedEvents =>
      text('Recent confirmed events', '最近の確認済みイベント');
  String get doctorReadableDetails =>
      text('Captured details for the veterinarian', '動物病院に伝える記録詳細');
  String get exactCareHistory => text('Completed care', '完了したケア');
  String get exactMedicationHistory => text('Medication taken', '服薬したお薬');
  String get exactHealthHistory => text('Health & medical history', '病歴・健康記録');
  String recordedWaterEntries(int count) =>
      text('Recorded water entries: $count', '飲水量の記録：$count件');
  String waterMeasurementLabel(WaterMeasurementBasis? basis) => switch (basis) {
    WaterMeasurementBasis.singleIntake => text(
      'single recorded intake',
      '1回分の飲水記録',
    ),
    WaterMeasurementBasis.localDayToDate => text(
      'day-to-date through check-in',
      'チェック時点までの当日累計',
    ),
    WaterMeasurementBasis.fullLocalDay => text(
      'reviewed full-day total',
      '確認済みの1日合計',
    ),
    WaterMeasurementBasis.legacyUnknown => text(
      'legacy interval unknown; excluded from totals',
      '旧記録の対象時間が不明なため、合計から除外',
    ),
    null => text(
      'measurement interval unavailable; excluded from totals',
      '対象時間が不明なため、合計から除外',
    ),
  };
  String waterDaySummary(WaterDaySummary summary) {
    final value = summary.milliliters.toStringAsFixed(0);
    return switch (summary.basis) {
      WaterDaySummaryBasis.summedSingleIntakes => text(
        '${summary.localDate}: $value ml from ${summary.includedRecordCount} separate intake record${summary.includedRecordCount == 1 ? '' : 's'}',
        '${summary.localDate}：$value ml（${summary.includedRecordCount}件の1回分記録の合計）',
      ),
      WaterDaySummaryBasis.localDayToDate => text(
        '${summary.localDate}: $value ml through check-in time; not a full-day total',
        '${summary.localDate}：チェック時点まで $value ml（1日合計ではありません）',
      ),
      WaterDaySummaryBasis.fullLocalDay => text(
        '${summary.localDate}: $value ml reviewed full-day total',
        '${summary.localDate}：確認済みの1日合計 $value ml',
      ),
    };
  }

  String excludedWaterRecords(int count) => text(
    '$count water value${count == 1 ? '' : 's'} remained source-only and ${count == 1 ? 'was' : 'were'} not added because the interval overlaps or is unknown.',
    '$count件の飲水量は対象時間の重複または不明があるため、元記録のみ表示して合計には含めていません。',
  );
  String get noWaterRecorded => text(
    'No structured water intake was recorded for this range.',
    'この期間の飲水量は記録されていません。',
  );
  String get capturedDataOnly => text(
    'Only captured source records are shown; missing values are not inferred.',
    '入力された元記録のみを表示し、未記録の値は推測しません。',
  );
  String get shareReport => text('Share PDF', 'PDFを共有');
  String get sharingReport => text('Preparing PDF…', 'PDFを作成中…');
  String get shareReportFailure => text(
    'The PDF could not be prepared or the system share sheet was unavailable.',
    'PDFを作成できないか、システムの共有画面を開けませんでした。',
  );
  String reportRange(String start, String end) =>
      text('$start to $end', '$start〜$end');
  String get householdName => text('Household name', '家の名前');
  String get petName => text('Pet name', 'ペットの名前');
  String get caregiverName => text('Caregiver name', 'ケア担当者名');
  String get saveChanges => text('Save changes', '変更を保存');
  String get profileSaveFailure => text(
    'Profile changes were not confirmed. Check your connection and try again.',
    'プロフィールの変更を確認できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get oneTime => text('One time', '単発');
  String get recurring => text('Recurring', '繰り返し');
  String get daily => text('Every day', '毎日');
  String get selectedDays => text('Selected days', '曜日を選ぶ');
  String get category => text('Category', 'カテゴリー');
  String get scheduledDate => text('Scheduled date', '予定日');
  String get scheduledTime => text('Scheduled time', '予定時刻');
  String get routineStartDate => text('Starts on', '開始日');
  String get noCareToday => text(
    'Nothing is scheduled yet. Add a one-time task to start sharing care.',
    '今日の予定はまだありません。単発タスクを追加してケアを共有しましょう。',
  );
  String get addTask => text('Add one-time task', '単発タスクを追加');
  String get taskTitle => text('Task title', 'タスク名');
  String get urgent => text('Urgent', '緊急');
  String get saveTask => text('Save task', 'タスクを保存');
  String get savingTask => text('Saving…', '保存中…');
  String get claimTask => text('I’ll do it', '自分が担当する');
  String get requestOpenTask => text('Ask household', 'みんなにお願いする');
  String get requestDirectTask => text('Assign to…', '担当者を選ぶ…');
  String get acceptTask => text('Accept', '引き受ける');
  String get declineTask => text('Decline', '断る');
  String get cancelRequest => text('Cancel request', '依頼を取り消す');
  String get completeTask => text('Mark complete', '完了にする');
  String get releaseResponsibility => text('Release responsibility', '担当を解除');
  String get requestResponsibilityReassign => text('Transfer to…', '担当を移行…');
  String get requestResponsibilityTakeover =>
      text('Ask to take over', '担当交代を依頼');
  String get acceptResponsibilityTransfer => text('Accept transfer', '担当移行を承認');
  String get declineResponsibilityTransfer =>
      text('Decline transfer', '担当移行を辞退');
  String get cancelResponsibilityTransfer => text('Cancel transfer', '担当移行を取消');
  String responsibilityTransferSummary(String from, String to) =>
      text('$from → $to', '$from → $to');
  String responsibilityConsentPending(String name) => text(
    'Responsibility stays unchanged until $name accepts.',
    '$name が承認するまで担当は変わりません。',
  );
  String get responsibilityNotCurrent => text(
    'Responsibility changes are unavailable until the latest server state is confirmed.',
    'サーバーの最新状態を確認できるまで、担当変更は利用できません。',
  );
  String get responsibilityNetworkFailure => text(
    'The responsibility change was not confirmed. Reconnect and retry; responsibility has not been changed on this screen.',
    '担当変更を確認できませんでした。再接続してもう一度お試しください。この画面上では担当は変更されていません。',
  );
  String get responsibilityPermissionFailure => text(
    'You no longer have permission for this responsibility action. Refresh the household.',
    'この担当操作を行う権限がありません。家族情報を更新してください。',
  );
  String get responsibilityStaleFailure => text(
    'The task or transfer changed on another device. Review the latest state before retrying.',
    '別の端末でタスクまたは担当移行が更新されました。最新の状態を確認してから、もう一度お試しください。',
  );
  String get responsibilityFailure => text(
    'The responsibility action was not confirmed. No success is shown until the server confirms it.',
    '担当操作を確認できませんでした。サーバーで確認されるまで成功として表示しません。',
  );
  String get taskActionFailure => text(
    'This task changed or the action was not confirmed. Check the latest status and try again.',
    'タスクの状態が変わったか、操作を確認できませんでした。最新の状態を確認して、もう一度お試しください。',
  );
  String get taskStaleFailure => text(
    'This task changed on another device. Wait for the latest status, then try again.',
    '別の端末でタスクが変更されました。最新の状態を待ってから、もう一度お試しください。',
  );
  String get taskPermissionFailure => text(
    'This task changed or your access changed. Wait for the latest status before trying again.',
    'タスクまたはアクセス状態が変わりました。最新の状態を待ってから、もう一度お試しください。',
  );
  String get taskSaveFailure => text(
    'The task was not confirmed. Check your connection and try again.',
    'タスクを確認できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get careLoadFailure => text(
    'Care could not be refreshed. Check your connection and try again.',
    'ケア情報を更新できませんでした。通信状況を確認して、もう一度お試しください。',
  );
  String get carePermissionFailure => text(
    'This device no longer has access to this household.',
    'この端末はこの家にアクセスできなくなりました。',
  );
  String get retryCare => text('Retry care', 'ケア情報を再読み込み');
  String get retryHousehold => text('Retry household', '家族情報を再読み込み');
  String get householdSyncNetworkFailure => text(
    'Household updates are offline. Check your connection and try again.',
    '家族情報の更新を受信できません。通信状況を確認して、もう一度お試しください。',
  );
  String get householdSyncPermissionFailure => text(
    'This device can no longer receive updates for this household.',
    'この端末では、この家の更新を受信できなくなりました。',
  );
  String get householdSyncDataFailure => text(
    'A household update could not be read safely. No data was changed.',
    '家族情報の更新を安全に読み取れませんでした。データは変更されていません。',
  );
  String get householdSyncFailure => text(
    'Household updates stopped. Try reconnecting.',
    '家族情報の更新が停止しました。再接続してください。',
  );
  String get careDataNeedsRepair => text(
    'Some stored care could not be shown safely. Repair the legacy data before making changes.',
    '一部のケア情報を安全に表示できませんでした。変更する前に旧形式データを修復してください。',
  );
  String get legacyTaskWarning => text(
    'Some older tasks are read-only until their stored data is repaired.',
    '一部の旧形式タスクは、保存データを修復するまで読み取り専用です。',
  );
  String get footer => text(
    'One shared place for meals, walks, medicine, and handoffs.',
    '食事、散歩、薬、引き継ぎをひとつに。',
  );
  String get language => text('Language', '言語');

  String taskStatus(CareTaskStatus status) => switch (status) {
    CareTaskStatus.unclaimed => text('Unassigned', '未担当'),
    CareTaskStatus.claimed => text('Assigned', '担当済み'),
    CareTaskStatus.completed => text('Completed', '完了'),
  };

  String taskKind(CareTaskKind kind) => switch (kind) {
    CareTaskKind.routine => text('Recurring', '繰り返し'),
    CareTaskKind.oneOff => text('One time', '単発'),
  };

  String careCategory(CareCategory value) => switch (value) {
    CareCategory.feeding => text('Feeding', '食事'),
    CareCategory.walking => text('Walking', '散歩'),
    CareCategory.medication => text('Medication', '投薬'),
    CareCategory.grooming => text('Grooming', 'お手入れ'),
    CareCategory.other => text('Other', 'その他'),
  };

  String carePriority(CarePriority value) => switch (value) {
    CarePriority.normal => text('Normal priority', '通常'),
    CarePriority.urgent => text('Urgent', '緊急'),
  };

  String routineFrequency(CareRoutineFrequency value) => switch (value) {
    CareRoutineFrequency.daily => text('Every day', '毎日'),
    CareRoutineFrequency.selectedDays => text('Selected days', '曜日指定'),
  };

  String weekday(int appleWeekday) {
    const english = <String>[
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const japanese = <String>['日', '月', '火', '水', '木', '金', '土'];
    final index = appleWeekday.clamp(1, 7) - 1;
    return locale == AppLocale.japanese ? japanese[index] : english[index];
  }

  List<String> get calendarWeekdayHeaders => locale == AppLocale.japanese
      ? const ['月', '火', '水', '木', '金', '土', '日']
      : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String completedByAt(String actor, String dateTime) =>
      text('Completed by $actor · $dateTime', '$actorが完了 · $dateTime');
}
