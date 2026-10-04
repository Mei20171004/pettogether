import { initializeApp } from "https://www.gstatic.com/firebasejs/12.18.0/firebase-app.js";
import {
  getAuth,
  onAuthStateChanged,
  signInAnonymously,
} from "https://www.gstatic.com/firebasejs/12.18.0/firebase-auth.js";
import {
  getFunctions,
  httpsCallable,
} from "https://www.gstatic.com/firebasejs/12.18.0/firebase-functions.js";
import {
  initializeAppCheck,
  ReCaptchaEnterpriseProvider,
} from "https://www.gstatic.com/firebasejs/12.18.0/firebase-app-check.js";
import {
  LOCALES,
  LOCALE_NAMES,
  getLocale,
  setLocale,
  detectLocale,
  t,
} from "/i18n.js";

const firebaseConfig = {
  apiKey: "AIzaSyDMAN-xYmtg99_9FfZjC8GZYgOh9Wdoar4",
  authDomain: "pettogether-analysis.firebaseapp.com",
  projectId: "pettogether-analysis",
  storageBucket: "pettogether-analysis.firebasestorage.app",
  messagingSenderId: "206129916121",
  appId: "1:206129916121:web:e5facf78923caec0a176c8",
};
const recaptchaEnterpriseSiteKey = "6Lf1mrAtAAAAAJDoEYPoR2n7FOhB7tB60njpdecy";

const countries = [
  "中国大陆",
  "日本",
  "美国",
  "台湾",
  "香港",
  "新加坡",
  "英国",
  "加拿大",
  "澳大利亚",
  "其他",
];

const features = [
  ["f_shared_tasks", "谁负责什么·任务认领指派"],
  ["f_routines", "重复例行日程"],
  ["f_notifications", "推送提醒"],
  ["f_skip_undo", "跳过某次 + 撤销"],
  ["f_calendar_activity", "日历 + 活动图表"],
  ["f_invite_approval", "二维码邀请 + 主人审批"],
  ["f_multi_pet", "多宠物管理"],
  ["f_med_course", "用药疗程管理"],
  ["f_med_adherence", "服药依从性统计"],
  ["f_med_history", "完整医疗档案"],
  ["f_vaccine_due", "疫苗/驱虫到期提醒"],
  ["f_vet_pack", "就诊资料包 PDF"],
  ["f_ai_parse", "AI 一句话添加任务"],
  ["f_multilang", "多语言"],
];

const missingFeatures = [
  "体重曲线和趋势图",
  "宠物开销记账与预算",
  "把记录直接分享给兽医",
  "照片日记时间线",
  "桌面小组件 / Apple Watch",
  "遛狗 GPS 路线记录",
  "连接自动喂食器或猫砂盆",
  "宠物保姆限时权限",
  "数据导出 CSV / 备份",
  "无人认领时升级提醒",
  "AI 症状初筛：要不要去医院",
  "多家庭 / 多住址切换",
  "按国家品种的疫苗时间表",
];

// 仅影响显示。提交值始终是 monthlyPriceValues / highPriceValues 里的美元基准档。
// 新增市场只要在这两张表里加一个同名 key 即可，updatePriceLabels 会自动认。
const monthlyPriceLabels = {
  中国大陆: ["不付费", "¥15", "¥22", "¥36", "¥50", "¥72+"],
  日本: ["不付費", "¥300", "¥450", "¥750", "¥1000", "¥1500+"],
  台湾: ["不付費", "NT$60", "NT$90", "NT$150", "NT$210", "NT$300+"],
  香港: ["不付費", "HK$15", "HK$25", "HK$39", "HK$55", "HK$78+"],
  新加坡: ["不付费", "S$2.99", "S$3.99", "S$6.99", "S$9.99", "S$13.99+"],
  英国: ["不付费", "£1.99", "£2.99", "£4.99", "£6.99", "£9.99+"],
  加拿大: ["不付费", "C$2.99", "C$3.99", "C$6.99", "C$9.99", "C$13.99+"],
  澳大利亚: ["不付费", "A$2.99", "A$4.99", "A$7.99", "A$10.99", "A$14.99+"],
  other: ["不付费", "$1.99", "$2.99", "$4.99", "$6.99", "$9.99+"],
};

const highPriceLabels = {
  中国大陆: ["¥22", "¥36", "¥50", "¥72", "¥108", "¥144+"],
  日本: ["¥450", "¥750", "¥1000", "¥1500", "¥2250", "¥3000+"],
  台湾: ["NT$90", "NT$150", "NT$210", "NT$300", "NT$450", "NT$600+"],
  香港: ["HK$25", "HK$39", "HK$55", "HK$78", "HK$118", "HK$158+"],
  新加坡: ["S$3.99", "S$6.99", "S$9.99", "S$13.99", "S$20.99", "S$27.99+"],
  英国: ["£2.99", "£4.99", "£6.99", "£9.99", "£14.99", "£19.99+"],
  加拿大: ["C$3.99", "C$6.99", "C$9.99", "C$13.99", "C$19.99", "C$26.99+"],
  澳大利亚: ["A$4.99", "A$7.99", "A$10.99", "A$14.99", "A$21.99", "A$29.99+"],
  other: ["$2.99", "$4.99", "$6.99", "$9.99", "$14.99", "$19.99+"],
};

const monthlyPriceValues = ["不付费", "$1.99", "$2.99", "$4.99", "$6.99", "$9.99+"];
const highPriceValues = ["$2.99", "$4.99", "$6.99", "$9.99", "$14.99", "$19.99+"];

const form = document.querySelector("#survey-form");
let steps = [...document.querySelectorAll(".form-step")];
const stepTitle = document.querySelector("#step-title");
const segments = [...document.querySelectorAll("#progress-segments li")];
const backButton = document.querySelector("#back-button");
const nextButton = document.querySelector("#next-button");
const submitButton = document.querySelector("#submit-button");
const formMessage = document.querySelector("#form-message");
const successState = document.querySelector("#success-state");
const skipNote = document.querySelector("#skip-note");
const consent = document.querySelector("#consent");
const consentError = document.querySelector("#consent-error");
const surveyCard = document.querySelector(".survey-card");

const stepIcon = document.querySelector("#step-icon");
const surveyHead = document.querySelector(".survey-head");

let autoAdvanceTimer;

let currentStep = 0;
let authReady = false;
let submitting = false;
let submitSurveyResponseCall;

setLocale(detectLocale());
renderQuestionnaire();
splitIntoScreens();
applyLocale();
configureFirebase();
showStep(0, false);

nextButton.addEventListener("click", () => {
  clearTimeout(autoAdvanceTimer);
  if (!validateStep(steps[currentStep])) return;
  showStep(findStep(currentStep + 1, 1));
});

backButton.addEventListener("click", () => {
  clearTimeout(autoAdvanceTimer);
  showStep(findStep(currentStep - 1, -1));
});

form.addEventListener("change", (event) => {
  const input = event.target;
  input.closest(".question")?.classList.remove("is-invalid");
  hideMessage();

  if (input.name === "q_lang") {
    setLocale(input.value);
    applyLocale();
  }
  if (input.name === "q_country") updatePriceLabels();
  if (input.name === "q_has_pet") updateScreening();
  if (input.name === "q_pain_list") enforceExclusivePainOption(input);
  updateSelectionCounter(input.closest(".question"));
  if (input === consent) consentError.classList.remove("is-visible");
  maybeAutoAdvance(input);
});

form.addEventListener("input", (event) => {
  event.target.closest(".question")?.classList.remove("is-invalid");
  hideMessage();
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!validateStep(steps[currentStep]) || submitting) return;
  if (!consent.checked) {
    consentError.classList.add("is-visible");
    consent.focus();
    return;
  }
  if (!authReady) {
    showMessage(t("匿名会话还没有准备好，请稍后再试。"));
    return;
  }

  setSubmitting(true);
  try {
    await submitSurveyResponseCall(collectResponse());
    form.hidden = true;
    document.querySelector(".progress-header").hidden = true;
    document.querySelector("#progress-segments").hidden = true;
    surveyHead.classList.remove("is-compact");
    successState.hidden = false;
    successState.focus?.();
    window.scrollTo({ top: document.querySelector(".survey-card").offsetTop - 24, behavior: "smooth" });
  } catch (error) {
    const message = error?.message?.includes("请")
      ? error.message.replace(/^FirebaseError:\s*/, "")
      : t("提交失败，请检查网络后再试。你的答案仍保留在当前页面。");
    showMessage(message);
    setSubmitting(false);
  }
});

function renderQuestionnaire() {
  document.querySelector("#language-question").append(languageQuestion());

  renderChoices(document.querySelector("#country-options"), "q_country", countries, "radio");

  const background = document.querySelector("#background-questions");
  background.append(
    choiceQuestion({
      code: "S1",
      label: "你现在养宠物吗？",
      name: "q_has_pet",
      options: [
        "是，我是主要照顾者",
        "是，但主要是别人在照顾",
        "以前养过，现在没有",
        "从来没养过",
      ],
    }),
    choiceQuestion({
      code: "S2",
      label: "你养几只宠物？",
      name: "q_pet_count",
      options: ["1", "2", "3", "4 只以上"],
      ownerOnly: true,
      compact: true,
    }),
    choiceQuestion({
      code: "S3",
      label: "你养的是？",
      name: "q_pet_types",
      options: ["狗", "猫", "兔子", "仓鼠", "鸟", "鱼", "爬虫", "其他动物"],
      type: "checkbox",
      min: 1,
      ownerOnly: true,
      compact: true,
    }),
    choiceQuestion({
      code: "S4",
      label: "有几个人和你一起照顾宠物？",
      name: "q_cocare_count",
      options: [
        "只有我一个人",
        "2 人（伴侣或家人）",
        "3-4 人",
        "5 人以上",
        "会临时请宠物保姆或寄养",
      ],
      ownerOnly: true,
    }),
    choiceQuestion({
      code: "S5",
      label: "你的宠物有长期在吃的药或需要定期治疗吗？",
      name: "q_has_medication",
      options: ["有，长期用药", "有过，是短期疗程", "没有"],
      ownerOnly: true,
    }),
    choiceQuestion({
      code: "S6",
      label: "你现在怎么记录宠物的照顾和健康情况？",
      name: "q_current_tool",
      options: [
        "完全靠记忆",
        "手机备忘录",
        "家人之间发消息",
        "纸质本子",
        "日历 App 提醒",
        "专门的宠物 App",
        "其他方式",
      ],
      type: "checkbox",
      min: 1,
      ownerOnly: true,
    }),
  );

  renderChoices(
    document.querySelector("#pain-options"),
    "q_pain_list",
    [
      "宠物被喂两次 / 药吃两次",
      "该做的事没人做 —— 都以为对方做了",
      "想不起上次驱虫/疫苗是什么时候",
      "不知道家人今天有没有遛狗/喂药",
      "为了对账在聊天群里翻记录",
      "看兽医时说不清症状从何时开始",
      "因为照顾分工产生过摩擦",
      "找不到之前的化验单或病历",
      "以上都没发生过",
    ],
    "checkbox",
  );

  const ratings = document.querySelector("#feature-ratings");
  for (const [name, label] of features) ratings.append(ratingQuestion(name, label));

  const payments = document.querySelector("#payment-questions");
  payments.append(
    choiceQuestion({
      code: "C1",
      label: "如果这个 App 有免费版和 Pro 付费版，下面哪 3 个功能你最愿意为它付费？",
      hint: "请正好选择 3 项。",
      name: "q_pay_top3",
      options: features.map(([, label]) => label),
      type: "checkbox",
      exact: 3,
    }),
    choiceQuestion({
      code: "C2",
      label: "假设 Pro 版包含你刚才选的那 3 个功能，每月多少钱你会订阅？",
      name: "q_price_point",
      options: monthlyPriceValues,
      priceGroup: "monthly",
      compact: true,
    }),
    choiceQuestion({
      code: "C3",
      label: "什么价格会让你觉得「太贵了，不考虑」？",
      name: "q_price_too_high",
      options: highPriceValues,
      priceGroup: "high",
      compact: true,
    }),
    choiceQuestion({
      code: "C4",
      label: "比起按月订阅，你更接受哪种？",
      name: "q_billing_pref",
      options: [
        "按月订阅",
        "按年订阅（更便宜）",
        "一次性买断 —— 永久使用",
        "只在需要时单次购买 —— 例如看兽医前生成一次就诊资料包",
        "都不接受 —— 只用免费功能",
      ],
    }),
  );

  const missing = document.querySelector("#missing-questions");
  missing.append(
    choiceQuestion({
      code: "D1",
      label: "下面哪些功能是你希望有、但前面没有提到的？",
      hint: "最多选择 5 项。",
      name: "q_missing",
      options: missingFeatures,
      type: "checkbox",
      max: 5,
      required: false,
    }),
    choiceQuestion({
      code: "D2",
      label: "这些功能里，哪一个是你最想要的？",
      name: "q_missing_top1",
      options: missingFeatures,
    }),
    textQuestion({
      code: "D3",
      label: "有没有什么我们完全没想到的功能？",
      name: "q_missing_open",
      placeholder: "选填，最多 1000 字",
    }),
    choiceQuestion({
      code: "D4",
      label: "你会为刚才选出的那个最想要的功能单独付费吗？",
      name: "q_missing_pay",
      options: [
        "会，愿意每月多付一点",
        "只有它包含在 Pro 里我才会订",
        "不会，但有了会更常用",
        "不会，我不在意",
      ],
    }),
  );

  document.querySelectorAll(".question[data-max], .question[data-exact]").forEach(updateSelectionCounter);
  updatePriceLabels();
}

// 把 7 个章节拆成「每屏一题」，章节信息（主题色/图标/标题）下放到每一屏
function splitIntoScreens() {
  const chapters = [...document.querySelectorAll(".form-step")];
  const parent = chapters[0].parentNode;
  const anchor = formMessage;
  const screens = [];

  chapters.forEach((chapter, chapterIndex) => {
    const units = [...chapter.querySelectorAll(".question, .rating-question")];
    units.forEach((unit) => {
      const screen = document.createElement("section");
      screen.className = "form-step";
      screen.dataset.step = String(screens.length);
      screen.dataset.chapter = String(chapterIndex);
      screen.dataset.theme = chapter.dataset.theme;
      screen.dataset.title = chapter.dataset.title;
      screen.dataset.icon = chapter.dataset.icon;
      if (chapter.hasAttribute("data-pet-owner-step")) {
        screen.setAttribute("data-pet-owner-step", "");
      }
      screen.append(unit);
      screens.push(screen);
    });
  });

  // 筛选提示跟着筛选题走；同意勾选必须和邮箱题、提交按钮同屏
  screens.find((screen) => screen.querySelector('[name="q_has_pet"]'))?.append(skipNote);
  screens.at(-1).append(document.querySelector(".consent-row"), consentError);

  chapters.forEach((chapter) => chapter.remove());
  screens.forEach((screen) => parent.insertBefore(screen, anchor));
  steps = screens;
}

// 一屏若整题被禁用（非养宠人群）就跳过，取代原来写死的步骤下标
function isSkipped(step) {
  if (step.hidden) return true;
  const inputs = [...step.querySelectorAll("input, textarea")];
  return inputs.length > 0 && inputs.every((input) => input.disabled);
}

function findStep(from, direction) {
  let index = from;
  while (index >= 0 && index < steps.length) {
    if (!isSkipped(steps[index])) return index;
    index += direction;
  }
  return direction > 0 ? steps.length - 1 : 0;
}

function maybeAutoAdvance(input) {
  if (input.type !== "radio") return;
  const step = steps[currentStep];
  if (!step?.contains(input) || currentStep === steps.length - 1) return;
  clearTimeout(autoAdvanceTimer);
  autoAdvanceTimer = setTimeout(() => {
    if (steps[currentStep] !== step || !validateStep(step)) return;
    showStep(findStep(currentStep + 1, 1));
  }, 320);
}

function choiceQuestion({
  code,
  label,
  name,
  options,
  type = "radio",
  hint = "",
  min = type === "checkbox" ? 1 : 1,
  max,
  exact,
  required = true,
  ownerOnly = false,
  compact = false,
  priceGroup = "",
}) {
  const fieldset = document.createElement("fieldset");
  fieldset.className = "question";
  if (required) fieldset.dataset.requiredGroup = "";
  if (min !== undefined) fieldset.dataset.min = String(min);
  if (max !== undefined) fieldset.dataset.max = String(max);
  if (exact !== undefined) fieldset.dataset.exact = String(exact);
  if (ownerOnly) fieldset.dataset.petOwnerOnly = "";

  const legend = document.createElement("legend");
  legend.innerHTML =
    `<span class="q-code">${code}</span> ` +
    `<span data-i18n="${label.replaceAll('"', "&quot;")}">${t(label)}</span>`;
  fieldset.append(legend);

  if (hint) {
    const hintElement = document.createElement("span");
    hintElement.className = "question-hint";
    hintElement.dataset.i18n = hint;
    hintElement.textContent = t(hint);
    fieldset.append(hintElement);
  }

  if (max !== undefined || exact !== undefined) {
    const count = document.createElement("span");
    count.className = "selection-count";
    count.dataset.selectionCount = "";
    legend.prepend(count); // 置于最前，float 才会贴题干右上角而不是掉到末行
  }

  const choices = document.createElement("div");
  choices.className = type === "checkbox" ? "choice-list" : `choice-grid${compact ? " compact" : ""}`;
  if (priceGroup) choices.classList.add("price-grid");
  renderChoices(choices, name, options, type, priceGroup);
  fieldset.append(choices);

  const error = document.createElement("p");
  error.className = "field-error";
  if (exact !== undefined) {
    error.dataset.i18nTpl = "请正好选择 {n} 项。";
    error.dataset.i18nN = String(exact);
  } else if (max !== undefined) {
    error.dataset.i18nTpl = "最多选择 {n} 项。";
    error.dataset.i18nN = String(max);
  } else {
    error.dataset.i18n = "请完成这一题。";
  }
  applyI18nTo(error);
  fieldset.append(error);
  return fieldset;
}

// 第一题：语言。选项名永远用各语言的自称，不参与翻译。
function languageQuestion() {
  const fieldset = document.createElement("fieldset");
  fieldset.className = "question";
  fieldset.dataset.requiredGroup = "";
  fieldset.dataset.min = "1";

  const legend = document.createElement("legend");
  legend.innerHTML =
    '<span class="q-code">E0</span> ' +
    '<span data-i18n="你想用哪种语言填写？"></span>';
  fieldset.append(legend);

  const choices = document.createElement("div");
  choices.className = "choice-grid compact";
  LOCALES.forEach((locale, index) => {
    const label = document.createElement("label");
    label.className = "choice";

    const input = document.createElement("input");
    input.type = "radio";
    input.name = "q_lang";
    input.value = locale;
    input.id = `q_lang-${index}`;
    input.checked = locale === getLocale();

    const text = document.createElement("span");
    text.className = "choice-text";
    text.lang = locale;
    text.textContent = LOCALE_NAMES[locale];

    label.append(input, text);
    choices.append(label);
  });
  fieldset.append(choices);

  const error = document.createElement("p");
  error.className = "field-error";
  error.dataset.i18n = "请完成这一题。";
  fieldset.append(error);

  applyI18nTo(fieldset);
  return fieldset;
}

function renderChoices(container, name, options, type, priceGroup = "") {
  options.forEach((option, index) => {
    const label = document.createElement("label");
    label.className = "choice";

    const input = document.createElement("input");
    input.type = type;
    input.name = name;
    input.value = option;
    input.id = `${name}-${index}`;

    const text = document.createElement("span");
    text.className = "choice-text";
    if (priceGroup) {
      // 价格标签由 updatePriceLabels 负责，不参与通用翻译
      text.dataset.priceGroup = priceGroup;
      text.dataset.priceIndex = String(index);
      text.textContent = option;
    } else {
      text.dataset.i18n = option;
      text.textContent = t(option);
    }

    label.append(input, text);
    container.append(label);
  });
}

function ratingQuestion(name, label) {
  const fieldset = document.createElement("fieldset");
  fieldset.className = "rating-question";
  fieldset.dataset.requiredGroup = "";
  fieldset.dataset.min = "1";

  const legend = document.createElement("legend");
  legend.dataset.i18n = label;
  legend.textContent = t(label);
  fieldset.append(legend);

  const options = document.createElement("div");
  options.className = "rating-options";
  for (let value = 1; value <= 5; value += 1) {
    const option = document.createElement("label");
    option.className = "rating-option";
    option.innerHTML = `<input type="radio" name="${name}" value="${value}" /><i class="rating-bar" aria-hidden="true"></i><span>${value}</span>`;
    options.append(option);
  }
  fieldset.append(options);

  const scale = document.createElement("div");
  scale.className = "rating-scale";
  scale.innerHTML =
    `<span data-i18n="不重要">${t("不重要")}</span><span data-i18n="非常重要">${t("非常重要")}</span>`;
  fieldset.append(scale);
  return fieldset;
}

function textQuestion({ code, label, name, placeholder }) {
  const wrapper = document.createElement("label");
  wrapper.className = "question text-question";
  wrapper.htmlFor = name;
  wrapper.innerHTML = `
    <span class="question-label"><span class="q-code">${code}</span> <span data-i18n="${label}">${t(label)}</span></span>
    <textarea id="${name}" name="${name}" maxlength="1000"
      placeholder="${t(placeholder)}" data-i18n-placeholder="${placeholder}"></textarea>
    <span class="field-help" data-i18n="选填">${t("选填")}</span>
  `;
  return wrapper;
}

function updatePriceLabels() {
  const country = selectedValue("q_country");
  const market = monthlyPriceLabels[country] ? country : "other";
  document.querySelectorAll("[data-price-group]").forEach((label) => {
    const index = Number(label.dataset.priceIndex);
    const map = label.dataset.priceGroup === "monthly" ? monthlyPriceLabels : highPriceLabels;
    const value = (map[market] || map.other)[index];
    label.textContent = value === "不付费" || value === "不付費" ? t("不付费") : value;
  });
}

function updateScreening() {
  const screenedOut = isScreenedOut();
  skipNote.hidden = !screenedOut;
  document.querySelectorAll("[data-pet-owner-only]").forEach((container) => {
    container.hidden = screenedOut;
    container.querySelectorAll("input, textarea").forEach((input) => {
      input.disabled = screenedOut;
    });
  });
  document.querySelectorAll("[data-pet-owner-step]").forEach((container) => {
    container.querySelectorAll("input, textarea").forEach((input) => {
      input.disabled = screenedOut;
    });
  });
}

function isScreenedOut() {
  return selectedValue("q_has_pet") === "从来没养过";
}

function enforceExclusivePainOption(changedInput) {
  const noneValue = "以上都没发生过";
  const painInputs = [...form.querySelectorAll('input[name="q_pain_list"]')];
  if (changedInput.value === noneValue && changedInput.checked) {
    painInputs.filter((input) => input !== changedInput).forEach((input) => {
      input.checked = false;
    });
  } else if (changedInput.checked) {
    const noneInput = painInputs.find((input) => input.value === noneValue);
    if (noneInput) noneInput.checked = false;
  }
}

function updateSelectionCounter(question) {
  if (!question) return;
  const counter = question.querySelector("[data-selection-count]");
  if (!counter) return;
  const selected = question.querySelectorAll('input[type="checkbox"]:checked').length;
  const limit = question.dataset.exact || question.dataset.max;
  counter.textContent = `${selected} / ${limit}`;
}

function validateStep(step) {
  let firstInvalid = null;
  const questions = step.querySelectorAll("[data-required-group], [data-max], [data-exact]");

  questions.forEach((question) => {
    if (question.hidden) return;
    const inputs = [...question.querySelectorAll("input")].filter((input) => !input.disabled);
    if (!inputs.length) return;
    const selected = inputs.filter((input) => input.checked).length;
    const exact = Number(question.dataset.exact || 0);
    const max = Number(question.dataset.max || Number.POSITIVE_INFINITY);
    const min = question.hasAttribute("data-required-group")
      ? Number(question.dataset.min || 1)
      : 0;
    const valid = exact ? selected === exact : selected >= min && selected <= max;
    question.classList.toggle("is-invalid", !valid);
    if (!valid && !firstInvalid) firstInvalid = inputs[0];
  });

  const email = step.querySelector('input[type="email"]');
  if (email?.value && !email.checkValidity()) {
    email.closest(".question").classList.add("is-invalid");
    showMessage(t("请输入有效的邮箱地址，或留空后提交。"));
    firstInvalid ||= email;
  }

  if (firstInvalid) {
    firstInvalid.focus();
    firstInvalid.closest(".question, .rating-question")?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
    return false;
  }
  return true;
}

function showStep(index, scroll = true) {
  currentStep = Math.max(0, Math.min(index, steps.length - 1));
  steps.forEach((step, stepIndex) => step.classList.toggle("is-active", stepIndex === currentStep));

  const step = steps[currentStep];
  const visible = steps.filter((candidate) => !isSkipped(candidate));
  const chapter = Number(step.dataset.chapter || 0);

  stepTitle.textContent = t(step.dataset.title);
  stepIcon.querySelector("use").setAttribute("href", `#i-${step.dataset.icon || "globe"}`);
  surveyCard.dataset.theme = step.dataset.theme || "clay";
  surveyHead.classList.toggle("is-compact", currentStep > 0);
  updateSegments(visible, chapter, step);
  backButton.hidden = currentStep === 0;
  nextButton.hidden = currentStep === steps.length - 1;
  submitButton.hidden = currentStep !== steps.length - 1;
  submitButton.disabled = submitting;
  hideMessage();

  if (scroll) {
    window.scrollTo({ top: document.querySelector(".survey-card").offsetTop - 18, behavior: "smooth" });
  }
}

// 一段 = 一个章节；被跳过的章节整段隐藏，当前章节按章内进度填充
function updateSegments(visible, chapter, step) {
  const perChapter = new Map();
  visible.forEach((candidate) => {
    const key = Number(candidate.dataset.chapter || 0);
    if (!perChapter.has(key)) perChapter.set(key, []);
    perChapter.get(key).push(candidate);
  });

  segments.forEach((segment, index) => {
    const inChapter = perChapter.get(index);
    segment.hidden = !inChapter;
    if (!inChapter) return;
    const fill =
      index < chapter
        ? 100
        : index > chapter
          ? 0
          : ((inChapter.indexOf(step) + 1) / inChapter.length) * 100;
    segment.classList.toggle("is-current", index === chapter);
    segment.firstElementChild.style.width = `${fill}%`;
  });
}

function applyI18nTo(root) {
  const scope = root === document ? document : root;
  const all = (selector) => [
    ...(scope.matches?.(selector) ? [scope] : []),
    ...scope.querySelectorAll(selector),
  ];
  all("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  all("[data-i18n-tpl]").forEach((el) => {
    el.textContent = t(el.dataset.i18nTpl, { n: el.dataset.i18nN });
  });
  all("[data-i18n-placeholder]").forEach((el) => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
}

function applyLocale() {
  const locale = getLocale();
  document.documentElement.lang = locale;
  document.title = `PetTogether ${t("宠物照顾习惯调研")}`;
  applyI18nTo(document);
  updatePriceLabels();
  if (steps[currentStep]) stepTitle.textContent = t(steps[currentStep].dataset.title);
  const checked = form.querySelector(`input[name="q_lang"][value="${locale}"]`);
  if (checked) checked.checked = true;
}

function collectResponse() {
  const response = {
    q_country: selectedValue("q_country"),
    q_has_pet: selectedValue("q_has_pet"),
    q_pet_count: selectedValue("q_pet_count"),
    q_pet_types: selectedValues("q_pet_types"),
    q_cocare_count: selectedValue("q_cocare_count"),
    q_has_medication: selectedValue("q_has_medication"),
    q_current_tool: selectedValues("q_current_tool"),
    q_pain_list: selectedValues("q_pain_list"),
    q_pay_top3: selectedValues("q_pay_top3"),
    q_price_point: selectedValue("q_price_point"),
    q_price_too_high: selectedValue("q_price_too_high"),
    q_billing_pref: selectedValue("q_billing_pref"),
    q_missing: selectedValues("q_missing"),
    q_missing_top1: selectedValue("q_missing_top1"),
    q_missing_pay: selectedValue("q_missing_pay"),
    q_missing_open: form.elements.q_missing_open.value.trim(),
    q_email: form.elements.q_email.value.trim(),
  };
  for (const [name] of features) response[name] = Number(selectedValue(name) || 0);
  return response;
}

function selectedValue(name) {
  return form.querySelector(`input[name="${name}"]:checked:not(:disabled)`)?.value || "";
}

function selectedValues(name) {
  return [...form.querySelectorAll(`input[name="${name}"]:checked:not(:disabled)`)].map(
    (input) => input.value,
  );
}

async function configureFirebase() {
  const app = initializeApp(firebaseConfig);
  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(recaptchaEnterpriseSiteKey),
    isTokenAutoRefreshEnabled: true,
  });
  const auth = getAuth(app);
  submitSurveyResponseCall = httpsCallable(
    getFunctions(app, "asia-northeast1"),
    "submitSurveyResponse",
  );

  onAuthStateChanged(auth, (user) => {
    if (!user) return;
    authReady = true;
    submitButton.disabled = submitting;
  });

  try {
    if (!auth.currentUser) await signInAnonymously(auth);
  } catch (error) {
    console.error("Anonymous auth initialization failed", error);
    authReady = false;
    showMessage(t("无法建立匿名问卷会话，请刷新页面后重试。"));
  }
}

function setSubmitting(value) {
  submitting = value;
  submitButton.disabled = value;
  submitButton.querySelector("span").textContent = t(value ? "正在提交…" : "提交问卷");
}

function showMessage(message) {
  formMessage.textContent = message;
  formMessage.hidden = false;
  formMessage.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function hideMessage() {
  formMessage.hidden = true;
  formMessage.textContent = "";
}
