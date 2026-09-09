const { BigQuery } = require("@google-cloud/bigquery");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const projectId = "pettogether-analysis";
const datasetId = "surveydummy";
const tableId = "survey_responses";
const region = "asia-northeast1";
const bigquery = new BigQuery({ projectId });

const countries = new Set([
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
]);

const hasPetOptions = new Set([
  "是，我是主要照顾者",
  "是，但主要是别人在照顾",
  "以前养过，现在没有",
  "从来没养过",
]);

const petCountOptions = new Set(["1", "2", "3", "4 只以上"]);
const petTypeOptions = new Set([
  "狗",
  "猫",
  "兔子",
  "仓鼠",
  "鸟",
  "鱼",
  "爬虫",
  "其他动物",
]);
const cocareOptions = new Set([
  "只有我一个人",
  "2 人（伴侣或家人）",
  "3-4 人",
  "5 人以上",
  "会临时请宠物保姆或寄养",
]);
const medicationOptions = new Set(["有，长期用药", "有过，是短期疗程", "没有"]);
const currentToolOptions = new Set([
  "完全靠记忆",
  "手机备忘录",
  "家人之间发消息",
  "纸质本子",
  "日历 App 提醒",
  "专门的宠物 App",
  "其他方式",
]);
const painOptions = new Set([
  "宠物被喂两次 / 药吃两次",
  "该做的事没人做 —— 都以为对方做了",
  "想不起上次驱虫/疫苗是什么时候",
  "不知道家人今天有没有遛狗/喂药",
  "为了对账在聊天群里翻记录",
  "看兽医时说不清症状从何时开始",
  "因为照顾分工产生过摩擦",
  "找不到之前的化验单或病历",
  "以上都没发生过",
]);
const features = new Set([
  "谁负责什么·任务认领指派",
  "重复例行日程",
  "推送提醒",
  "跳过某次 + 撤销",
  "日历 + 活动图表",
  "二维码邀请 + 主人审批",
  "多宠物管理",
  "用药疗程管理",
  "服药依从性统计",
  "完整医疗档案",
  "疫苗/驱虫到期提醒",
  "就诊资料包 PDF",
  "AI 一句话添加任务",
  "多语言",
]);
const missingFeatures = new Set([
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
]);
const pricePointOptions = new Set(["不付费", "$1.99", "$2.99", "$4.99", "$6.99", "$9.99+"]);
const tooHighOptions = new Set(["$2.99", "$4.99", "$6.99", "$9.99", "$14.99", "$19.99+"]);
const billingOptions = new Set([
  "按月订阅",
  "按年订阅（更便宜）",
  "一次性买断 —— 永久使用",
  "只在需要时单次购买 —— 例如看兽医前生成一次就诊资料包",
  "都不接受 —— 只用免费功能",
]);
const missingPayOptions = new Set([
  "会，愿意每月多付一点",
  "只有它包含在 Pro 里我才会订",
  "不会，但有了会更常用",
  "不会，我不在意",
]);
const ratingFields = [
  "f_shared_tasks",
  "f_routines",
  "f_notifications",
  "f_skip_undo",
  "f_calendar_activity",
  "f_invite_approval",
  "f_multi_pet",
  "f_med_course",
  "f_med_adherence",
  "f_med_history",
  "f_vaccine_due",
  "f_vet_pack",
  "f_ai_parse",
  "f_multilang",
];

exports.submitSurveyResponse = onCall(
  {
    region,
    enforceAppCheck: true,
    cors: [
      "https://pettogether-analysis-3aefd.web.app",
      "https://pettogether-analysis-3aefd.firebaseapp.com",
    ],
    maxInstances: 10,
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth || request.auth.token.firebase?.sign_in_provider !== "anonymous") {
      throw new HttpsError("unauthenticated", "请刷新页面后再提交问卷。");
    }

    const response = validateResponse(request.data);
    const row = toBigQueryRow(request.auth.uid, response);

    try {
      await bigquery.query({
        query: insertQuery,
        location: region,
        params: row,
      });
      return { ok: true };
    } catch (error) {
      logger.error("Unable to store survey response in BigQuery", {
        code: error?.code,
        message: error?.message,
      });
      throw new HttpsError("internal", "提交暂时失败，请稍后再试。");
    }
  },
);

function validateResponse(value) {
  if (!isRecord(value)) {
    throw invalid("问卷数据格式不正确。");
  }

  const qCountry = requiredChoice(value.q_country, countries, "国家/地区");
  const qHasPet = requiredChoice(value.q_has_pet, hasPetOptions, "养宠情况");
  const screenedOut = qHasPet === "从来没养过";

  const response = {
    q_country: qCountry,
    q_has_pet: qHasPet,
    q_pet_count: "",
    q_pet_types: [],
    q_cocare_count: "",
    q_has_medication: "",
    q_current_tool: [],
    q_pain_list: [],
    q_pay_top3: [],
    q_price_point: "",
    q_price_too_high: "",
    q_billing_pref: "",
    q_missing: [],
    q_missing_top1: "",
    q_missing_pay: "",
    q_missing_open: optionalText(value.q_missing_open, 1000),
    q_email: optionalEmail(value.q_email),
  };

  for (const field of ratingFields) response[field] = 0;
  if (screenedOut) return response;

  response.q_pet_count = requiredChoice(value.q_pet_count, petCountOptions, "宠物数量");
  response.q_pet_types = requiredChoices(value.q_pet_types, petTypeOptions, "宠物类型", 1, 8);
  response.q_cocare_count = requiredChoice(value.q_cocare_count, cocareOptions, "共同照顾人数");
  response.q_has_medication = requiredChoice(value.q_has_medication, medicationOptions, "用药情况");
  response.q_current_tool = requiredChoices(value.q_current_tool, currentToolOptions, "当前记录方式", 1, 7);
  response.q_pain_list = requiredChoices(value.q_pain_list, painOptions, "经历过的情况", 1, 9);

  if (
    response.q_pain_list.includes("以上都没发生过") &&
    response.q_pain_list.length !== 1
  ) {
    throw invalid("“以上都没发生过”不能与其他选项同时选择。");
  }

  for (const field of ratingFields) {
    const rating = Number(value[field]);
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      throw invalid("请完成所有功能重要性评分。");
    }
    response[field] = rating;
  }

  response.q_pay_top3 = requiredChoices(value.q_pay_top3, features, "付费功能", 3, 3);
  response.q_price_point = requiredChoice(value.q_price_point, pricePointOptions, "订阅价格");
  response.q_price_too_high = requiredChoice(value.q_price_too_high, tooHighOptions, "过高价格");
  response.q_billing_pref = requiredChoice(value.q_billing_pref, billingOptions, "付费方式");
  response.q_missing = requiredChoices(value.q_missing || [], missingFeatures, "缺失功能", 0, 5);
  response.q_missing_top1 = requiredChoice(value.q_missing_top1, missingFeatures, "最想要的功能");
  response.q_missing_pay = requiredChoice(value.q_missing_pay, missingPayOptions, "额外付费意愿");

  return response;
}

function toBigQueryRow(uid, response) {
  const row = {
    respondent_id: uid,
    ...response,
  };
  for (const field of ["q_pet_types", "q_current_tool", "q_pain_list", "q_pay_top3", "q_missing"]) {
    row[field] = JSON.stringify(row[field]);
  }
  return row;
}

function requiredChoice(value, allowed, label) {
  if (typeof value !== "string" || !allowed.has(value)) {
    throw invalid(`请选择有效的${label}。`);
  }
  return value;
}

function requiredChoices(value, allowed, label, min, max) {
  if (!Array.isArray(value)) throw invalid(`请选择有效的${label}。`);
  const unique = [...new Set(value)];
  if (unique.length < min || unique.length > max || unique.some((item) => !allowed.has(item))) {
    throw invalid(`请选择有效的${label}。`);
  }
  return unique;
}

function optionalText(value, maxLength) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || value.trim().length > maxLength) {
    throw invalid("开放回答内容过长。");
  }
  return value.trim();
}

function optionalEmail(value) {
  if (value == null || value === "") return "";
  if (
    typeof value !== "string" ||
    value.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
  ) {
    throw invalid("邮箱格式不正确。");
  }
  return value.toLowerCase();
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function invalid(message) {
  return new HttpsError("invalid-argument", message);
}

const insertQuery = `
  INSERT INTO \`${projectId}.${datasetId}.${tableId}\`
  (
    respondent_id, submitted_at, q_country, q_has_pet, q_pet_count,
    q_pet_types, q_cocare_count, q_has_medication, q_current_tool, q_pain_list,
    f_shared_tasks, f_routines, f_notifications, f_skip_undo,
    f_calendar_activity, f_invite_approval, f_multi_pet, f_med_course,
    f_med_adherence, f_med_history, f_vaccine_due, f_vet_pack, f_ai_parse,
    f_multilang, q_pay_top3, q_price_point, q_price_too_high, q_billing_pref,
    q_missing, q_missing_top1, q_missing_pay, q_missing_open, q_email
  )
  SELECT
    @respondent_id, CURRENT_TIMESTAMP(), @q_country, @q_has_pet,
    NULLIF(@q_pet_count, ''), NULLIF(@q_pet_types, '[]'),
    NULLIF(@q_cocare_count, ''), NULLIF(@q_has_medication, ''),
    NULLIF(@q_current_tool, '[]'), NULLIF(@q_pain_list, '[]'),
    NULLIF(@f_shared_tasks, 0), NULLIF(@f_routines, 0),
    NULLIF(@f_notifications, 0), NULLIF(@f_skip_undo, 0),
    NULLIF(@f_calendar_activity, 0), NULLIF(@f_invite_approval, 0),
    NULLIF(@f_multi_pet, 0), NULLIF(@f_med_course, 0),
    NULLIF(@f_med_adherence, 0), NULLIF(@f_med_history, 0),
    NULLIF(@f_vaccine_due, 0), NULLIF(@f_vet_pack, 0),
    NULLIF(@f_ai_parse, 0), NULLIF(@f_multilang, 0),
    NULLIF(@q_pay_top3, '[]'), NULLIF(@q_price_point, ''),
    NULLIF(@q_price_too_high, ''), NULLIF(@q_billing_pref, ''),
    NULLIF(@q_missing, '[]'), NULLIF(@q_missing_top1, ''),
    NULLIF(@q_missing_pay, ''), NULLIF(@q_missing_open, ''),
    NULLIF(@q_email, '')
  WHERE NOT EXISTS (
    SELECT 1
    FROM \`${projectId}.${datasetId}.${tableId}\`
    WHERE respondent_id = @respondent_id
    LIMIT 1
  )
`;
