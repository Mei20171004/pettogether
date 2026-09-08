// 多语言显示层。
// 关键约定：字典以「简体中文原文」为 key，简体即规范值。
// input.value 永远保持中文原文，翻译只替换显示文本，
// 因此 functions/survey.js 的中文白名单校验与 BigQuery 口径完全不受影响。

export const LOCALES = ["zh-CN", "zh-TW", "ja", "en"];

export const LOCALE_NAMES = {
  "zh-CN": "简体中文",
  "zh-TW": "繁體中文",
  ja: "日本語",
  en: "English",
};

// 第一题的国家 → 官方/行政工作语言
export const COUNTRY_LOCALE = {
  中国大陆: "zh-CN",
  台湾: "zh-TW",
  香港: "zh-TW",
  日本: "ja",
  美国: "en",
  英国: "en",
  加拿大: "en", // 英法双官方，取英文
  澳大利亚: "en",
  新加坡: "en", // 四种官方语言，取行政工作语言
  其他: "en",
};

const DICT = {
  "zh-TW": {
    // —— 国家 ——
    "中国大陆": "中國大陸", 日本: "日本", 美国: "美國", 台湾: "台灣", 香港: "香港",
    "新加坡": "新加坡", 英国: "英國", 加拿大: "加拿大", 澳大利亚: "澳洲", 其他: "其他",
    // —— 14 项功能 ——
    "谁负责什么·任务认领指派": "誰負責什麼・任務認領指派",
    "重复例行日程": "重複例行行程",
    "推送提醒": "推播通知",
    "跳过某次 + 撤销": "略過單次 + 復原",
    "日历 + 活动图表": "行事曆 + 活動圖表",
    "二维码邀请 + 主人审批": "QR Code 邀請 + 飼主審核",
    "多宠物管理": "多寵物管理",
    "用药疗程管理": "用藥療程管理",
    "服药依从性统计": "服藥依從性統計",
    "完整医疗档案": "完整醫療紀錄",
    "疫苗/驱虫到期提醒": "疫苗／驅蟲到期提醒",
    "就诊资料包 PDF": "就診資料包 PDF",
    "AI 一句话添加任务": "AI 一句話新增任務",
    "多语言": "多語言",
    // —— 13 项待补功能 ——
    "体重曲线和趋势图": "體重曲線與趨勢圖",
    "宠物开销记账与预算": "寵物開銷記帳與預算",
    "把记录直接分享给兽医": "將紀錄直接分享給獸醫",
    "照片日记时间线": "照片日記時間軸",
    "桌面小组件 / Apple Watch": "桌面小工具 / Apple Watch",
    "遛狗 GPS 路线记录": "遛狗 GPS 路線紀錄",
    "连接自动喂食器或猫砂盆": "連接自動餵食器或貓砂盆",
    "宠物保姆限时权限": "寵物保母限時權限",
    "数据导出 CSV / 备份": "資料匯出 CSV / 備份",
    "无人认领时升级提醒": "無人認領時升級提醒",
    "AI 症状初筛：要不要去医院": "AI 症狀初篩：要不要就醫",
    "多家庭 / 多住址切换": "多家庭 / 多住址切換",
    "按国家品种的疫苗时间表": "依國家與品種的疫苗時程",
    // —— 题干 ——
    "你在哪个国家/地区？": "你在哪個國家／地區？",
    "你现在养宠物吗？": "你現在有養寵物嗎？",
    "你养几只宠物？": "你養幾隻寵物？",
    "你养的是？": "你養的是？",
    "有几个人和你一起照顾宠物？": "有幾個人和你一起照顧寵物？",
    "你的宠物有长期在吃的药或需要定期治疗吗？": "你的寵物有長期在吃的藥或需要定期治療嗎？",
    "你现在怎么记录宠物的照顾和健康情况？": "你現在怎麼記錄寵物的照顧與健康狀況？",
    "下面哪些情况发生过？": "下面哪些情況發生過？",
    "如果这个 App 有免费版和 Pro 付费版，下面哪 3 个功能你最愿意为它付费？":
      "如果這個 App 有免費版和 Pro 付費版，下面哪 3 個功能你最願意為它付費？",
    "假设 Pro 版包含你刚才选的那 3 个功能，每月多少钱你会订阅？":
      "假設 Pro 版包含你剛才選的那 3 個功能，每月多少錢你會訂閱？",
    "什么价格会让你觉得「太贵了，不考虑」？": "什麼價格會讓你覺得「太貴了，不考慮」？",
    "比起按月订阅，你更接受哪种？": "比起按月訂閱，你更能接受哪一種？",
    "下面哪些功能是你希望有、但前面没有提到的？": "下面哪些功能是你希望有、但前面沒有提到的？",
    "这些功能里，哪一个是你最想要的？": "這些功能裡，哪一個是你最想要的？",
    "有没有什么我们完全没想到的功能？": "有沒有什麼我們完全沒想到的功能？",
    "你会为刚才选出的那个最想要的功能单独付费吗？": "你會為剛才選出的那個最想要的功能單獨付費嗎？",
    "如需接收内测邀请，可以留下邮箱（选填）": "如需接收內測邀請，可以留下 Email（選填）",
    // —— 选项 ——
    "是，我是主要照顾者": "有，我是主要照顧者",
    "是，但主要是别人在照顾": "有，但主要是別人在照顧",
    "以前养过，现在没有": "以前養過，現在沒有",
    "从来没养过": "從來沒養過",
    "4 只以上": "4 隻以上",
    "狗": "狗", 猫: "貓", 兔子: "兔子", 仓鼠: "倉鼠", 鸟: "鳥", 鱼: "魚",
    "爬虫": "爬蟲", 其他动物: "其他動物",
    "只有我一个人": "只有我一個人",
    "2 人（伴侣或家人）": "2 人（伴侶或家人）",
    "3-4 人": "3-4 人",
    "5 人以上": "5 人以上",
    "会临时请宠物保姆或寄养": "會臨時請寵物保母或寄養",
    "有，长期用药": "有，長期用藥",
    "有过，是短期疗程": "有過，是短期療程",
    "没有": "沒有",
    "完全靠记忆": "完全靠記憶",
    "手机备忘录": "手機備忘錄",
    "家人之间发消息": "家人之間傳訊息",
    "纸质本子": "紙本筆記",
    "日历 App 提醒": "行事曆 App 提醒",
    "专门的宠物 App": "專門的寵物 App",
    "其他方式": "其他方式",
    "宠物被喂两次 / 药吃两次": "寵物被餵兩次／藥吃兩次",
    "该做的事没人做 —— 都以为对方做了": "該做的事沒人做 —— 都以為對方做了",
    "想不起上次驱虫/疫苗是什么时候": "想不起上次驅蟲／疫苗是什麼時候",
    "不知道家人今天有没有遛狗/喂药": "不知道家人今天有沒有遛狗／餵藥",
    "为了对账在聊天群里翻记录": "為了對帳在聊天群裡翻紀錄",
    "看兽医时说不清症状从何时开始": "看獸醫時說不清症狀從何時開始",
    "因为照顾分工产生过摩擦": "因為照顧分工產生過摩擦",
    "找不到之前的化验单或病历": "找不到之前的檢驗報告或病歷",
    "以上都没发生过": "以上都沒發生過",
    "按月订阅": "按月訂閱",
    "按年订阅（更便宜）": "按年訂閱（更便宜）",
    "一次性买断 —— 永久使用": "一次性買斷 —— 永久使用",
    "只在需要时单次购买 —— 例如看兽医前生成一次就诊资料包":
      "只在需要時單次購買 —— 例如看獸醫前產生一次就診資料包",
    "都不接受 —— 只用免费功能": "都不接受 —— 只用免費功能",
    "会，愿意每月多付一点": "會，願意每月多付一點",
    "只有它包含在 Pro 里我才会订": "只有它包含在 Pro 裡我才會訂",
    "不会，但有了会更常用": "不會，但有了會更常用",
    "不会，我不在意": "不會，我不在意",
    "不付费": "不付費",
    // —— 章节 ——
    "基本信息": "基本資料", 养宠背景: "養寵背景", 日常困扰: "日常困擾",
    "功能重要性": "功能重要性", 订阅与价格: "訂閱與價格", 其他需求: "其他需求",
    "联系方式": "聯絡方式",
    // —— 界面 ——
    "宠物照顾习惯调研": "寵物照顧習慣調查",
    "本问卷约需 6 分钟，匿名填写，答案仅用于产品研究与统计分析。":
      "本問卷約需 6 分鐘，匿名填寫，答案僅用於產品研究與統計分析。",
    "约 6 分钟": "約 6 分鐘", "共 7 部分": "共 7 部分", 无需注册: "無需註冊",
    "返回": "返回", 下一步: "下一步", 提交问卷: "提交問卷", "正在提交…": "正在提交…",
    "我同意将本问卷答案用于匿名产品研究和统计分析。": "我同意將本問卷答案用於匿名產品研究與統計分析。",
    "提交前请确认同意。": "提交前請確認同意。",
    "提交成功": "提交成功",
    "感谢参与，你的答案已记录。": "感謝參與，你的答案已記錄。",
    "本问卷主要面向养宠人群，以下仅剩一个选填问题。": "本問卷主要針對養寵人士，以下僅剩一個選填問題。",
    "问卷匿名收集 · 仅用于产品研究": "問卷匿名收集 · 僅用於產品研究",
    "不重要": "不重要", 非常重要: "非常重要",
    "仅用于发送 PetTogether 内测邀请。": "僅用於寄送 PetTogether 內測邀請。",
    "you@example.com（选填）": "you@example.com（選填）",
    "选填，最多 1000 字": "選填，最多 1000 字", 选填: "選填",
    "请选择一个国家或地区。": "請選擇一個國家或地區。",
    "请至少选择一项。": "請至少選擇一項。",
    "请完成这一题。": "請完成這一題。",
    "请正好选择 {n} 项。": "請正好選擇 {n} 項。",
    "最多选择 {n} 项。": "最多選擇 {n} 項。",
    "请正好选择 3 项。": "請正好選擇 3 項。",
    "最多选择 5 项。": "最多選擇 5 項。",
    "请输入有效的邮箱地址，或留空后提交。": "請輸入有效的 Email，或留空後提交。",
    "匿名会话还没有准备好，请稍后再试。": "匿名工作階段尚未就緒，請稍後再試。",
    "无法建立匿名问卷会话，请刷新页面后重试。": "無法建立匿名問卷工作階段，請重新整理頁面後再試。",
    "提交失败，请检查网络后再试。你的答案仍保留在当前页面。":
      "提交失敗，請檢查網路後再試。你的答案仍保留在目前頁面。",
  },

  ja: {
    "中国大陆": "中国本土", 日本: "日本", 美国: "アメリカ", 台湾: "台湾", 香港: "香港",
    "新加坡": "シンガポール", 英国: "イギリス", 加拿大: "カナダ",
    "澳大利亚": "オーストラリア", 其他: "その他",
    "谁负责什么·任务认领指派": "誰が何を担当するか・タスクの割り当て",
    "重复例行日程": "繰り返しの定期スケジュール",
    "推送提醒": "プッシュ通知",
    "跳过某次 + 撤销": "1回スキップ + 取り消し",
    "日历 + 活动图表": "カレンダー + アクティビティグラフ",
    "二维码邀请 + 主人审批": "QRコード招待 + 飼い主の承認",
    "多宠物管理": "複数ペットの管理",
    "用药疗程管理": "投薬コースの管理",
    "服药依从性统计": "服薬アドヒアランスの統計",
    "完整医疗档案": "完全な医療記録",
    "疫苗/驱虫到期提醒": "ワクチン・駆虫の期限リマインダー",
    "就诊资料包 PDF": "受診用資料パック（PDF）",
    "AI 一句话添加任务": "AIで一文からタスク追加",
    "多语言": "多言語対応",
    "体重曲线和趋势图": "体重の推移グラフ",
    "宠物开销记账与预算": "ペット費用の記録と予算",
    "把记录直接分享给兽医": "記録を獣医に直接共有",
    "照片日记时间线": "写真日記のタイムライン",
    "桌面小组件 / Apple Watch": "ウィジェット / Apple Watch",
    "遛狗 GPS 路线记录": "散歩のGPSルート記録",
    "连接自动喂食器或猫砂盆": "自動給餌器・猫トイレとの連携",
    "宠物保姆限时权限": "ペットシッターへの期間限定アクセス",
    "数据导出 CSV / 备份": "データのCSVエクスポート・バックアップ",
    "无人认领时升级提醒": "未対応時のエスカレーション通知",
    "AI 症状初筛：要不要去医院": "AI症状チェック：受診すべきか",
    "多家庭 / 多住址切换": "複数世帯・複数住所の切り替え",
    "按国家品种的疫苗时间表": "国・品種別のワクチンスケジュール",
    "你在哪个国家/地区？": "お住まいの国・地域は？",
    "你现在养宠物吗？": "現在ペットを飼っていますか？",
    "你养几只宠物？": "何匹飼っていますか？",
    "你养的是？": "飼っているのは？",
    "有几个人和你一起照顾宠物？": "何人でペットのお世話をしていますか？",
    "你的宠物有长期在吃的药或需要定期治疗吗？": "継続的な投薬や定期的な治療が必要ですか？",
    "你现在怎么记录宠物的照顾和健康情况？": "ペットのお世話や健康状態をどう記録していますか？",
    "下面哪些情况发生过？": "次のうち、経験したことがあるものは？",
    "如果这个 App 有免费版和 Pro 付费版，下面哪 3 个功能你最愿意为它付费？":
      "このアプリに無料版と有料のPro版があるとしたら、どの3つの機能にお金を払いたいですか？",
    "假设 Pro 版包含你刚才选的那 3 个功能，每月多少钱你会订阅？":
      "Pro版に先ほど選んだ3つの機能が含まれる場合、月額いくらなら加入しますか？",
    "什么价格会让你觉得「太贵了，不考虑」？": "「高すぎて検討しない」と感じるのはいくらからですか？",
    "比起按月订阅，你更接受哪种？": "月額サブスクと比べて、どれが受け入れやすいですか？",
    "下面哪些功能是你希望有、但前面没有提到的？": "前半で出てこなかった機能のうち、あったらいいものは？",
    "这些功能里，哪一个是你最想要的？": "この中で最も欲しい機能はどれですか？",
    "有没有什么我们完全没想到的功能？": "私たちが思いつかなかった機能はありますか？",
    "你会为刚才选出的那个最想要的功能单独付费吗？": "先ほど選んだ最も欲しい機能に、単体でお金を払いますか？",
    "如需接收内测邀请，可以留下邮箱（选填）":
      "ベータ版の招待をご希望の場合、メールアドレスをご記入ください（任意）",
    "是，我是主要照顾者": "はい、私が主にお世話をしています",
    "是，但主要是别人在照顾": "はい、ただし主に他の人がお世話をしています",
    "以前养过，现在没有": "以前飼っていましたが、今はいません",
    "从来没养过": "飼ったことがありません",
    "4 只以上": "4匹以上",
    "狗": "犬", 猫: "猫", 兔子: "ウサギ", 仓鼠: "ハムスター", 鸟: "鳥", 鱼: "魚",
    "爬虫": "爬虫類", 其他动物: "その他の動物",
    "只有我一个人": "私一人だけ",
    "2 人（伴侣或家人）": "2人（パートナーまたは家族）",
    "3-4 人": "3〜4人",
    "5 人以上": "5人以上",
    "会临时请宠物保姆或寄养": "一時的にペットシッターや預かりを利用",
    "有，长期用药": "はい、継続的に投薬しています",
    "有过，是短期疗程": "短期の治療コースがありました",
    "没有": "いいえ",
    "完全靠记忆": "記憶だけ",
    "手机备忘录": "スマホのメモ",
    "家人之间发消息": "家族間のメッセージ",
    "纸质本子": "紙のノート",
    "日历 App 提醒": "カレンダーアプリのリマインダー",
    "专门的宠物 App": "ペット専用アプリ",
    "其他方式": "その他",
    "宠物被喂两次 / 药吃两次": "ペットに2回餌をあげた・薬を2回飲ませた",
    "该做的事没人做 —— 都以为对方做了": "やるべきことを誰もやらなかった（相手がやったと思っていた）",
    "想不起上次驱虫/疫苗是什么时候": "前回の駆虫・ワクチンがいつか思い出せない",
    "不知道家人今天有没有遛狗/喂药": "家族が今日散歩や投薬をしたか分からない",
    "为了对账在聊天群里翻记录": "確認のためチャット履歴をさかのぼった",
    "看兽医时说不清症状从何时开始": "受診時に症状がいつ始まったか説明できなかった",
    "因为照顾分工产生过摩擦": "お世話の分担でもめたことがある",
    "找不到之前的化验单或病历": "過去の検査結果やカルテが見つからない",
    "以上都没发生过": "どれも経験がない",
    "按月订阅": "月額サブスク",
    "按年订阅（更便宜）": "年額サブスク（割安）",
    "一次性买断 —— 永久使用": "買い切り —— 永続利用",
    "只在需要时单次购买 —— 例如看兽医前生成一次就诊资料包":
      "必要なときだけ単発購入 —— 例：受診前に資料パックを1回作成",
    "都不接受 —— 只用免费功能": "どれも受け入れない —— 無料機能のみ利用",
    "会，愿意每月多付一点": "はい、月額を少し上乗せしてもよい",
    "只有它包含在 Pro 里我才会订": "Proに含まれる場合のみ加入する",
    "不会，但有了会更常用": "払わないが、あれば使う頻度は増える",
    "不会，我不在意": "払わない、特に必要ない",
    "不付费": "課金しない",
    "基本信息": "基本情報", 养宠背景: "ペットについて", 日常困扰: "日々の困りごと",
    "功能重要性": "機能の重要度", 订阅与价格: "サブスクと価格", 其他需求: "その他の要望",
    "联系方式": "連絡先",
    "宠物照顾习惯调研": "ペットのお世話に関する調査",
    "本问卷约需 6 分钟，匿名填写，答案仅用于产品研究与统计分析。":
      "所要時間は約6分です。匿名で回答でき、回答は製品研究と統計分析にのみ使用されます。",
    "约 6 分钟": "約6分", "共 7 部分": "全7パート", 无需注册: "登録不要",
    "返回": "戻る", 下一步: "次へ", 提交问卷: "送信する", "正在提交…": "送信中…",
    "我同意将本问卷答案用于匿名产品研究和统计分析。":
      "回答が匿名の製品研究および統計分析に使用されることに同意します。",
    "提交前请确认同意。": "送信前に同意してください。",
    "提交成功": "送信完了",
    "感谢参与，你的答案已记录。": "ご協力ありがとうございました。回答を記録しました。",
    "本问卷主要面向养宠人群，以下仅剩一个选填问题。":
      "本調査は主にペットを飼っている方向けです。残りは任意の質問が1問のみです。",
    "问卷匿名收集 · 仅用于产品研究": "匿名で収集 · 製品研究のみに使用",
    "不重要": "重要でない", 非常重要: "とても重要",
    "仅用于发送 PetTogether 内测邀请。": "PetTogetherのベータ招待の送信にのみ使用します。",
    "you@example.com（选填）": "you@example.com（任意）",
    "选填，最多 1000 字": "任意・1000文字まで", 选填: "任意",
    "请选择一个国家或地区。": "国・地域を選択してください。",
    "请至少选择一项。": "少なくとも1つ選択してください。",
    "请完成这一题。": "この質問にご回答ください。",
    "请正好选择 {n} 项。": "ちょうど{n}つ選択してください。",
    "最多选择 {n} 项。": "最大{n}つまで選択できます。",
    "请正好选择 3 项。": "ちょうど3つ選択してください。",
    "最多选择 5 项。": "最大5つまで選択できます。",
    "请输入有效的邮箱地址，或留空后提交。":
      "有効なメールアドレスを入力するか、空欄のまま送信してください。",
    "匿名会话还没有准备好，请稍后再试。":
      "匿名セッションの準備ができていません。しばらくしてからお試しください。",
    "无法建立匿名问卷会话，请刷新页面后重试。":
      "匿名セッションを開始できません。ページを再読み込みしてください。",
    "提交失败，请检查网络后再试。你的答案仍保留在当前页面。":
      "送信に失敗しました。ネットワークを確認して再度お試しください。回答はこのページに残っています。",
  },

  en: {
    "中国大陆": "Chinese Mainland", 日本: "Japan", 美国: "United States", 台湾: "Taiwan",
    "香港": "Hong Kong", 新加坡: "Singapore", 英国: "United Kingdom", 加拿大: "Canada",
    "澳大利亚": "Australia", 其他: "Other",
    "谁负责什么·任务认领指派": "Who does what — task claiming & assignment",
    "重复例行日程": "Recurring routines",
    "推送提醒": "Push reminders",
    "跳过某次 + 撤销": "Skip once + undo",
    "日历 + 活动图表": "Calendar + activity charts",
    "二维码邀请 + 主人审批": "QR invite + owner approval",
    "多宠物管理": "Multi-pet management",
    "用药疗程管理": "Medication course tracking",
    "服药依从性统计": "Medication adherence stats",
    "完整医疗档案": "Full medical records",
    "疫苗/驱虫到期提醒": "Vaccine / deworming due reminders",
    "就诊资料包 PDF": "Vet visit summary PDF",
    "AI 一句话添加任务": "Add a task with one AI sentence",
    "多语言": "Multi-language",
    "体重曲线和趋势图": "Weight curve & trends",
    "宠物开销记账与预算": "Pet expense tracking & budget",
    "把记录直接分享给兽医": "Share records directly with the vet",
    "照片日记时间线": "Photo diary timeline",
    "桌面小组件 / Apple Watch": "Home screen widget / Apple Watch",
    "遛狗 GPS 路线记录": "Dog walk GPS route tracking",
    "连接自动喂食器或猫砂盆": "Connect an auto feeder or litter box",
    "宠物保姆限时权限": "Time-limited access for pet sitters",
    "数据导出 CSV / 备份": "CSV export / backup",
    "无人认领时升级提醒": "Escalate a reminder when no one claims it",
    "AI 症状初筛：要不要去医院": "AI symptom triage: is a vet visit needed?",
    "多家庭 / 多住址切换": "Switch between households / addresses",
    "按国家品种的疫苗时间表": "Vaccine schedule by country & breed",
    "你在哪个国家/地区？": "Which country or region are you in?",
    "你现在养宠物吗？": "Do you currently have a pet?",
    "你养几只宠物？": "How many pets do you have?",
    "你养的是？": "What kind of pet do you have?",
    "有几个人和你一起照顾宠物？": "How many people share the care with you?",
    "你的宠物有长期在吃的药或需要定期治疗吗？":
      "Is your pet on long-term medication or regular treatment?",
    "你现在怎么记录宠物的照顾和健康情况？":
      "How do you currently keep track of care and health?",
    "下面哪些情况发生过？": "Which of these has happened to you?",
    "如果这个 App 有免费版和 Pro 付费版，下面哪 3 个功能你最愿意为它付费？":
      "If this app had a free tier and a paid Pro tier, which 3 features would you most pay for?",
    "假设 Pro 版包含你刚才选的那 3 个功能，每月多少钱你会订阅？":
      "If Pro included the 3 features you just picked, what monthly price would you subscribe at?",
    "什么价格会让你觉得「太贵了，不考虑」？":
      "At what price would it feel too expensive to consider?",
    "比起按月订阅，你更接受哪种？":
      "Compared with a monthly subscription, which would you prefer?",
    "下面哪些功能是你希望有、但前面没有提到的？":
      "Which of these would you want that weren't mentioned earlier?",
    "这些功能里，哪一个是你最想要的？": "Which one of these do you want most?",
    "有没有什么我们完全没想到的功能？": "Is there anything we haven't thought of?",
    "你会为刚才选出的那个最想要的功能单独付费吗？":
      "Would you pay separately for that most-wanted feature?",
    "如需接收内测邀请，可以留下邮箱（选填）":
      "Leave your email if you'd like a beta invite (optional)",
    "是，我是主要照顾者": "Yes, I'm the primary caregiver",
    "是，但主要是别人在照顾": "Yes, but someone else is the main caregiver",
    "以前养过，现在没有": "I used to, but not now",
    "从来没养过": "I've never had one",
    "4 只以上": "4 or more",
    "狗": "Dog", 猫: "Cat", 兔子: "Rabbit", 仓鼠: "Hamster", 鸟: "Bird", 鱼: "Fish",
    "爬虫": "Reptile", 其他动物: "Other animal",
    "只有我一个人": "Just me",
    "2 人（伴侣或家人）": "2 (partner or family)",
    "3-4 人": "3–4 people",
    "5 人以上": "5 or more",
    "会临时请宠物保姆或寄养": "Sometimes a pet sitter or boarding",
    "有，长期用药": "Yes, ongoing medication",
    "有过，是短期疗程": "Yes, a short course in the past",
    "没有": "No",
    "完全靠记忆": "Just memory",
    "手机备忘录": "Phone notes",
    "家人之间发消息": "Messaging between family",
    "纸质本子": "A paper notebook",
    "日历 App 提醒": "Calendar app reminders",
    "专门的宠物 App": "A dedicated pet app",
    "其他方式": "Some other way",
    "宠物被喂两次 / 药吃两次": "Pet got fed twice / medicated twice",
    "该做的事没人做 —— 都以为对方做了": "A task got skipped — each of us assumed the other did it",
    "想不起上次驱虫/疫苗是什么时候": "Couldn't recall the last deworming / vaccination",
    "不知道家人今天有没有遛狗/喂药": "Didn't know if family had walked or medicated the pet",
    "为了对账在聊天群里翻记录": "Scrolled back through group chat to check",
    "看兽医时说不清症状从何时开始": "Couldn't tell the vet when the symptoms started",
    "因为照顾分工产生过摩擦": "Friction over splitting up the care",
    "找不到之前的化验单或病历": "Couldn't find past lab results or records",
    "以上都没发生过": "None of these",
    "按月订阅": "Monthly subscription",
    "按年订阅（更便宜）": "Annual subscription (cheaper)",
    "一次性买断 —— 永久使用": "One-time purchase — lifetime access",
    "只在需要时单次购买 —— 例如看兽医前生成一次就诊资料包":
      "Pay per use — e.g. generate one vet summary before a visit",
    "都不接受 —— 只用免费功能": "None of these — I'd only use free features",
    "会，愿意每月多付一点": "Yes, I'd pay a bit more each month",
    "只有它包含在 Pro 里我才会订": "Only if it's included in Pro",
    "不会，但有了会更常用": "No, but I'd use the app more if it existed",
    "不会，我不在意": "No, I don't care about it",
    "不付费": "Wouldn't pay",
    "基本信息": "Basic info", 养宠背景: "Your pets", 日常困扰: "Everyday problems",
    "功能重要性": "Feature importance", 订阅与价格: "Subscription & pricing",
    "其他需求": "Other needs", 联系方式: "Contact",
    "宠物照顾习惯调研": "Pet Care Habits Survey",
    "本问卷约需 6 分钟，匿名填写，答案仅用于产品研究与统计分析。":
      "Takes about 6 minutes. Anonymous — answers are used only for product research and statistical analysis.",
    "约 6 分钟": "~6 minutes", "共 7 部分": "7 sections", 无需注册: "No sign-up",
    "返回": "Back", 下一步: "Next", 提交问卷: "Submit", "正在提交…": "Submitting…",
    "我同意将本问卷答案用于匿名产品研究和统计分析。":
      "I agree my answers may be used for anonymous product research and statistical analysis.",
    "提交前请确认同意。": "Please confirm your consent before submitting.",
    "提交成功": "Submitted",
    "感谢参与，你的答案已记录。": "Thank you — your answers have been recorded.",
    "本问卷主要面向养宠人群，以下仅剩一个选填问题。":
      "This survey is mainly for pet owners — just one optional question left.",
    "问卷匿名收集 · 仅用于产品研究": "Collected anonymously · product research only",
    "不重要": "Not important", 非常重要: "Very important",
    "仅用于发送 PetTogether 内测邀请。": "Used only to send PetTogether beta invites.",
    "you@example.com（选填）": "you@example.com (optional)",
    "选填，最多 1000 字": "Optional, up to 1000 characters", 选填: "Optional",
    "请选择一个国家或地区。": "Please select a country or region.",
    "请至少选择一项。": "Please select at least one.",
    "请完成这一题。": "Please answer this question.",
    "请正好选择 {n} 项。": "Please select exactly {n}.",
    "最多选择 {n} 项。": "Select up to {n}.",
    "请正好选择 3 项。": "Please select exactly 3.",
    "最多选择 5 项。": "Select up to 5.",
    "请输入有效的邮箱地址，或留空后提交。":
      "Enter a valid email address, or leave it blank.",
    "匿名会话还没有准备好，请稍后再试。":
      "The anonymous session isn't ready yet. Please try again shortly.",
    "无法建立匿名问卷会话，请刷新页面后重试。":
      "Couldn't start an anonymous session. Please reload the page.",
    "提交失败，请检查网络后再试。你的答案仍保留在当前页面。":
      "Submission failed. Check your connection and try again — your answers are still here.",
  },
};

let current = "zh-CN";

export function getLocale() {
  return current;
}

export function setLocale(locale) {
  current = LOCALES.includes(locale) ? locale : "zh-CN";
  return current;
}

// text 是简体中文原文；找不到译文时回落到原文，绝不返回空串
export function t(text, vars) {
  const table = DICT[current];
  let out = (table && table[text]) || text;
  if (vars) {
    for (const [key, value] of Object.entries(vars)) {
      out = out.replaceAll(`{${key}}`, value);
    }
  }
  return out;
}

export function detectLocale() {
  const tags = navigator.languages?.length ? navigator.languages : [navigator.language || ""];
  for (const raw of tags) {
    const tag = raw.toLowerCase();
    if (tag.startsWith("ja")) return "ja";
    if (tag.startsWith("zh")) {
      return /hant|tw|hk|mo/.test(tag) ? "zh-TW" : "zh-CN";
    }
    if (tag.startsWith("en")) return "en";
  }
  return "zh-CN";
}

// 覆盖率自检：任一语言缺条目时在控制台列出
export function missingKeys() {
  const base = Object.keys(DICT.en);
  const report = {};
  for (const locale of ["zh-TW", "ja"]) {
    report[locale] = base.filter((key) => !DICT[locale][key]);
  }
  report.enMissingFromOthers = Object.keys(DICT["zh-TW"]).filter((key) => !DICT.en[key]);
  return report;
}
