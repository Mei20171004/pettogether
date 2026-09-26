import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
import {
  getAuth, inMemoryPersistence, setPersistence, signInWithCustomToken, signOut,
} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js';
import {
  collection, doc, getDocFromServer, getDocsFromServer, getFirestore, query, where,
} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';

// Public Firebase Web App configuration. Authentication secrets stay in the
// native app and the callable Function; no token is stored in a URL or HTML.
const app = initializeApp({
  apiKey: 'AIzaSyCey_noKPeYR8ANxrdYQuYOxCx00no_ZB4',
  authDomain: 'pettogether-76452.firebaseapp.com',
  projectId: 'pettogether-76452',
  appId: '1:524031929167:web:0a3b87ae1e0257cb2df33a',
});
const auth = getAuth(app);
const db = getFirestore(app);

const copy = {
  zh: {
    eyebrow: '健康档案 · HISTORY', title: '健康历史报告',
    intro: '就诊与用药记录，按宠物整理在一起。',
    connecting: '正在连接 App', connectingDetail: '请稍候，正在确认你的登录身份。',
    appOnly: '请从 App 打开', appOnlyDetail: '前往 pettogether 的「健康」页面，选择此 Pro 菜单。',
    signingIn: '正在确认身份', signingInDetail: '正在安全地连接你的 Firebase 账号。',
    authFailed: '登录未完成', authFailedDetail: '请确认 App 已登录，然后重试。',
    accessDenied: '当前无法使用 Pro 报告', accessDeniedDetail: '请在 App 中检查订阅或 Free Coupon 状态。',
    loadFailed: '报告加载失败', loadFailedDetail: '请检查网络连接后重试。',
    retry: '重试', currentPet: '当前宠物', recordCount: '健康记录',
    medicationCount: '用药疗程', healthHistory: '健康历史',
    newestFirst: '最近记录在前', medications: '用药疗程',
    recordedInApp: '来自 App 的记录', footer: '资料来自你的家庭记录',
    noRecords: '这只宠物还没有健康记录。', noMedications: '这只宠物还没有用药疗程。',
    active: '进行中', ended: '已结束',
    vetVisit: '就诊', vaccination: '疫苗', deworming: '驱虫', labResult: '检查',
    surgery: '手术', symptom: '症状', weight: '体重', medication: '用药', note: '记录',
  },
  en: {
    eyebrow: 'HEALTH FILE · HISTORY', title: 'Health history',
    intro: 'Vet visits and medication records, organized by pet.',
    connecting: 'Connecting to the app', connectingDetail: 'Confirming your signed-in account.',
    appOnly: 'Open from the app', appOnlyDetail: 'In pettogether, choose this Pro menu from Health.',
    signingIn: 'Signing you in', signingInDetail: 'Securely connecting your Firebase account.',
    authFailed: 'Sign-in did not finish', authFailedDetail: 'Check that you are signed in to the app, then retry.',
    accessDenied: 'Pro report unavailable', accessDeniedDetail: 'Check your subscription or Free Coupon in the app.',
    loadFailed: 'Report could not load', loadFailedDetail: 'Check your connection and try again.',
    retry: 'Retry', currentPet: 'CURRENT PET', recordCount: 'health records',
    medicationCount: 'medication courses', healthHistory: 'Health history',
    newestFirst: 'Newest first', medications: 'Medication courses',
    recordedInApp: 'From your app records', footer: 'From your household records',
    noRecords: 'No health records for this pet yet.', noMedications: 'No medication courses for this pet yet.',
    active: 'Active', ended: 'Ended',
    vetVisit: 'Vet visit', vaccination: 'Vaccination', deworming: 'Deworming', labResult: 'Test result',
    surgery: 'Surgery', symptom: 'Symptom', weight: 'Weight', medication: 'Medication', note: 'Record',
  },
  ja: {
    eyebrow: '健康記録 · HISTORY', title: '健康履歴レポート',
    intro: '通院とお薬の記録を、ペットごとに確認できます。',
    connecting: 'アプリに接続中', connectingDetail: 'ログイン状態を確認しています。',
    appOnly: 'アプリから開いてください', appOnlyDetail: 'pettogether の「健康」からこの Pro メニューを選んでください。',
    signingIn: 'ログイン中', signingInDetail: 'Firebase アカウントに安全に接続しています。',
    authFailed: 'ログインできませんでした', authFailedDetail: 'アプリのログイン状態を確認して再試行してください。',
    accessDenied: 'Pro レポートを利用できません', accessDeniedDetail: 'アプリで購入または Free Coupon の状態を確認してください。',
    loadFailed: 'レポートを読み込めません', loadFailedDetail: '通信状態を確認して再試行してください。',
    retry: '再試行', currentPet: 'ペット', recordCount: '健康記録',
    medicationCount: '投薬コース', healthHistory: '健康履歴',
    newestFirst: '新しい順', medications: '投薬コース',
    recordedInApp: 'アプリの記録から', footer: 'ご家族の記録から作成',
    noRecords: 'このペットの健康記録はまだありません。', noMedications: 'このペットの投薬コースはまだありません。',
    active: '進行中', ended: '終了',
    vetVisit: '通院', vaccination: 'ワクチン', deworming: '駆虫', labResult: '検査',
    surgery: '手術', symptom: '症状', weight: '体重', medication: '投薬', note: '記録',
  },
  ko: {
    eyebrow: '건강 기록 · HISTORY', title: '건강 기록 보고서',
    intro: '진료와 복약 기록을 반려동물별로 확인하세요.',
    connecting: '앱에 연결 중', connectingDetail: '로그인 상태를 확인하고 있습니다.',
    appOnly: '앱에서 열어 주세요', appOnlyDetail: 'pettogether의 건강 화면에서 이 Pro 메뉴를 선택하세요.',
    signingIn: '로그인 중', signingInDetail: 'Firebase 계정에 안전하게 연결하고 있습니다.',
    authFailed: '로그인하지 못했습니다', authFailedDetail: '앱 로그인 상태를 확인한 뒤 다시 시도하세요.',
    accessDenied: 'Pro 보고서를 사용할 수 없습니다', accessDeniedDetail: '앱에서 구독 또는 Free Coupon 상태를 확인하세요.',
    loadFailed: '보고서를 불러오지 못했습니다', loadFailedDetail: '네트워크를 확인한 뒤 다시 시도하세요.',
    retry: '다시 시도', currentPet: '반려동물', recordCount: '건강 기록',
    medicationCount: '복약 과정', healthHistory: '건강 기록',
    newestFirst: '최신순', medications: '복약 과정',
    recordedInApp: '앱 기록 기준', footer: '가족 기록에서 가져옴',
    noRecords: '이 반려동물의 건강 기록이 없습니다.', noMedications: '이 반려동물의 복약 과정이 없습니다.',
    active: '진행 중', ended: '종료',
    vetVisit: '진료', vaccination: '예방접종', deworming: '구충', labResult: '검사',
    surgery: '수술', symptom: '증상', weight: '체중', medication: '복약', note: '기록',
  },
};

const byId = (id) => document.getElementById(id);
let language = 'zh';
let session = null;
let pets = [];
let signingIn = false;
let accessDeadlineTimer = null;
let reportRequest = 0;

function t(key) {
  return copy[language][key] || copy.zh[key] || key;
}

function applyLanguage() {
  document.documentElement.lang = language;
  for (const element of document.querySelectorAll('[data-i18n]')) {
    element.textContent = t(element.dataset.i18n);
  }
  byId('pet-select').setAttribute('aria-label', t('currentPet'));
}

function showState(title, detail, canRetry = false) {
  byId('report').hidden = true;
  byId('state-panel').hidden = false;
  byId('state-title').textContent = t(title);
  byId('state-detail').textContent = t(detail);
  byId('retry-button').hidden = !canRetry;
}

function clearState() {
  byId('state-panel').hidden = true;
  byId('report').hidden = false;
}

function expiresAtMillis(value) {
  return value && typeof value.toMillis === 'function' ? value.toMillis() : null;
}

function activeGrant(data) {
  if (!data || data.active !== true) return false;
  const expiry = expiresAtMillis(data.expiresAt);
  return expiry === null || expiry > Date.now();
}

async function checkProAccess() {
  const uid = session.uid;
  const householdId = session.householdId;
  const [entitlement, householdPro, redemption] = await Promise.all([
    getDocFromServer(doc(db, 'entitlements', uid)),
    getDocFromServer(doc(db, 'households', householdId, 'private', 'pro')),
    getDocFromServer(doc(db, 'freeCouponRedemptions', uid)),
  ]);
  const paid = entitlement.exists() ? entitlement.data() : null;
  const shared = householdPro.exists() ? householdPro.data() : null;
  let couponActive = false;
  const deadlines = [];

  if (activeGrant(paid)) {
    const expiry = expiresAtMillis(paid.expiresAt);
    if (expiry !== null) deadlines.push(expiry);
  }
  if (activeGrant(shared)) {
    const expiry = expiresAtMillis(shared.expiresAt);
    if (expiry !== null) deadlines.push(expiry);
  }
  if (redemption.exists()) {
    try {
      const definition = await getDocFromServer(doc(db, 'aiUsage', 'freecoupon'));
      if (definition.exists()) {
        const expiry = expiresAtMillis(definition.data().enddate);
        couponActive = redemption.data().coupon === definition.data().coupon &&
          expiry !== null && expiry > Date.now();
        if (couponActive) deadlines.push(expiry);
      }
    } catch (_) {
      // An old redemption may no longer be allowed to read the current code.
    }
  }
  const allowed = activeGrant(paid) || activeGrant(shared) ||
    shared?.legacy === true || couponActive;
  scheduleAccessCheck(deadlines);
  return allowed;
}

function scheduleAccessCheck(deadlines) {
  clearTimeout(accessDeadlineTimer);
  if (deadlines.length === 0) return;
  const delay = Math.max(1000, Math.min(Math.min(...deadlines) - Date.now() + 1000, 2147483647));
  accessDeadlineTimer = setTimeout(() => { void recheckAccess(); }, delay);
}

async function recheckAccess() {
  if (!session || !auth.currentUser) return;
  try {
    if (!(await checkProAccess())) {
      clearTimeout(accessDeadlineTimer);
      showState('accessDenied', 'accessDeniedDetail');
    }
  } catch (_) {
    showState('loadFailed', 'loadFailedDetail', true);
  }
}

function timestampMillis(value) {
  return expiresAtMillis(value) || 0;
}

function dateLabel(value) {
  const milliseconds = timestampMillis(value);
  if (!milliseconds) return '—';
  return new Intl.DateTimeFormat(language, { year: 'numeric', month: 'short', day: 'numeric' })
    .format(new Date(milliseconds));
}

function textElement(tag, className, value) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.textContent = value;
  return element;
}

function renderRecords(records) {
  const container = byId('records-list');
  container.replaceChildren();
  byId('record-count').textContent = String(records.length);
  if (records.length === 0) {
    container.append(textElement('p', 'empty', t('noRecords')));
    return;
  }
  records.sort((a, b) => timestampMillis(b.occurredAt) - timestampMillis(a.occurredAt));
  for (const record of records) {
    const row = textElement('article', 'record-row', '');
    row.append(textElement('time', 'record-date', dateLabel(record.occurredAt)));
    const body = textElement('div', 'record-body', '');
    body.append(textElement('h3', '', record.title || t(record.type || 'note')));
    const meta = [t(record.type || 'note'), record.clinicName, record.diagnosis]
      .filter((part) => typeof part === 'string' && part.trim());
    body.append(textElement('p', 'record-meta', meta.join(' · ')));
    if (typeof record.notes === 'string' && record.notes.trim()) {
      body.append(textElement('p', 'record-notes', record.notes.trim()));
    }
    row.append(body);
    container.append(row);
  }
}

function renderMedications(plans) {
  const container = byId('medications-list');
  container.replaceChildren();
  byId('medication-count').textContent = String(plans.length);
  if (plans.length === 0) {
    container.append(textElement('p', 'empty', t('noMedications')));
    return;
  }
  plans.sort((a, b) => Number(b.isActive) - Number(a.isActive) ||
    timestampMillis(b.createdAt) - timestampMillis(a.createdAt));
  for (const plan of plans) {
    const row = textElement('article', 'medication-row', '');
    const status = textElement('span', 'tag', plan.isActive ? t('active') : t('ended'));
    row.append(status);
    const body = textElement('div', 'medication-body', '');
    body.append(textElement('h3', '', plan.name || '—'));
    const meta = [plan.purpose, plan.sideEffects]
      .filter((part) => typeof part === 'string' && part.trim());
    if (meta.length) body.append(textElement('p', 'medication-meta', meta.join(' · ')));
    row.append(body);
    container.append(row);
  }
}

async function loadPet(petId) {
  const requestNumber = ++reportRequest;
  try {
    const base = ['households', session.householdId];
    const [records, medications] = await Promise.all([
      getDocsFromServer(query(collection(db, ...base, 'healthRecords'), where('petId', '==', petId))),
      getDocsFromServer(query(collection(db, ...base, 'medicationPlans'), where('petId', '==', petId))),
    ]);
    if (requestNumber !== reportRequest) return;
    renderRecords(records.docs.map((snapshot) => snapshot.data()));
    renderMedications(medications.docs.map((snapshot) => snapshot.data()));
    clearState();
  } catch (_) {
    if (requestNumber === reportRequest) showState('loadFailed', 'loadFailedDetail', true);
  }
}

async function loadReport() {
  const household = await getDocFromServer(doc(db, 'households', session.householdId));
  if (!household.exists()) throw new Error('Household unavailable');
  if (!(await checkProAccess())) {
    showState('accessDenied', 'accessDeniedDetail');
    return;
  }
  pets = (household.data().pets || []).filter((pet) =>
    pet && typeof pet.id === 'string' && typeof pet.name === 'string');
  const select = byId('pet-select');
  select.replaceChildren();
  for (const pet of pets) {
    const option = document.createElement('option');
    option.value = pet.id;
    option.textContent = pet.name;
    select.append(option);
  }
  const selected = pets.some((pet) => pet.id === session.petId) ? session.petId : pets[0]?.id;
  byId('account-label').textContent = auth.currentUser.email || auth.currentUser.uid;
  if (!selected) {
    renderRecords([]);
    renderMedications([]);
    clearState();
    return;
  }
  select.value = selected;
  await loadPet(selected);
}

window.pettogetherReceiveAuth = async (payload) => {
  if (signingIn) return;
  const { token, uid, householdId, petId, language: appLanguage } = payload || {};
  if (![token, uid, householdId, petId].every((value) =>
    typeof value === 'string' && value.length > 0)) {
    showState('authFailed', 'authFailedDetail', true);
    return;
  }
  signingIn = true;
  session = null;
  language = appLanguage === 'en' || appLanguage === 'ja' ||
    appLanguage === 'ko' ? appLanguage : 'zh';
  applyLanguage();
  showState('signingIn', 'signingInDetail');
  try {
    await setPersistence(auth, inMemoryPersistence);
    const credential = await signInWithCustomToken(auth, token);
    if (credential.user.uid !== uid) {
      await signOut(auth);
      throw new Error('User mismatch');
    }
    session = { uid, householdId, petId };
    window.PetTogetherBridge?.postMessage('signed-in');
    await loadReport();
  } catch (_) {
    if (session) {
      showState('loadFailed', 'loadFailedDetail', true);
    } else {
      window.PetTogetherBridge?.postMessage('auth-failed');
      showState('authFailed', 'authFailedDetail', true);
    }
  } finally {
    signingIn = false;
  }
};

window.pettogetherAuthError = () => {
  showState('authFailed', 'authFailedDetail', true);
};

byId('retry-button').addEventListener('click', () => {
  if (session && auth.currentUser) {
    showState('connecting', 'connectingDetail');
    void loadReport().catch(() => showState('loadFailed', 'loadFailedDetail', true));
  } else if (window.PetTogetherBridge) {
    showState('connecting', 'connectingDetail');
    window.PetTogetherBridge.postMessage('ready');
  }
});

byId('pet-select').addEventListener('change', async (event) => {
  showState('connecting', 'connectingDetail');
  try {
    if (!(await checkProAccess())) {
      showState('accessDenied', 'accessDeniedDetail');
      return;
    }
    await loadPet(event.target.value);
  } catch (_) {
    showState('loadFailed', 'loadFailedDetail', true);
  }
});

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) void recheckAccess();
});

applyLanguage();
if (window.PetTogetherBridge) {
  window.PetTogetherBridge.postMessage('ready');
} else {
  showState('appOnly', 'appOnlyDetail');
}
