const fs = require('fs');
const path = require('path');

const SCREENS_DIR = path.join(__dirname, 'Screens');

const MANIFEST = [
  { file: 'screen_01_welcome.html', num: '1', title: 'Welcome', section: 'onboarding' },
  { file: 'screen_02_account.html', num: '2', title: 'Account', section: 'onboarding' },
  { file: 'screen_03_cycle_setup.html', num: '3', title: 'Cycle setup', section: 'onboarding' },
  { file: 'screen_04_baseline.html', num: '4', title: 'Baseline health', section: 'onboarding' },
  { file: 'screen_05_goals.html', num: '5', title: 'Goals', section: 'onboarding' },
  { file: 'screen_06_hormones.html', num: '6', title: 'Hormone preferences', section: 'onboarding' },
  { file: 'screen_07_notifications.html', num: '7', title: 'Notifications', section: 'onboarding' },
  { file: 'screen_08_dashboard.html', num: '8', title: 'Dashboard', section: 'home' },
  { file: 'screen_09_quick_checkin.html', num: '9', title: 'Quick check-in', section: 'home' },
  { file: 'screen_10_cycle_calendar.html', num: '10', title: 'Cycle calendar', section: 'home' },
  { file: 'screen_11_day_detail.html', num: '11', title: 'Day detail', section: 'home' },
  { file: 'screen_12_symptom_form.html', num: '12', title: 'Symptom form', section: 'home' },
  { file: 'screen_13_body_map.html', num: '13', title: 'Body map', section: 'home' },
  { file: 'screen_14_phase_correction.html', num: '14', title: 'Phase correction', section: 'home' },
  { file: 'screen_15_hormone_chart.html', num: '15', title: 'Hormone chart', section: 'hormones' },
  { file: 'screen_15_hormone_chart_landscape.html', num: '15L', title: 'Hormone chart (landscape)', section: 'hormones' },
  { file: 'screen_16_hormone_detail.html', num: '16', title: 'Hormone detail', section: 'hormones' },
  { file: 'screen_17_studies_library.html', num: '17', title: 'Studies library', section: 'hormones' },
  { file: 'screen_18_upload_study.html', num: '18', title: 'Upload study', section: 'hormones' },
  { file: 'screen_19_ocr_confirm.html', num: '19', title: 'OCR confirmation', section: 'hormones' },
  { file: 'screen_20_missing_data.html', num: '20', title: 'Missing data prompt', section: 'hormones' },
  { file: 'screen_21_confidence_explainer.html', num: '21', title: 'Confidence explainer', section: 'hormones' },
  { file: 'screen_22_body_calendar.html', num: '22', title: 'Body metrics calendar', section: 'body' },
  { file: 'screen_23_body_entry.html', num: '23', title: 'Body metrics entry', section: 'body' },
  { file: 'screen_24_activity_calendar.html', num: '24', title: 'Activity calendar', section: 'body' },
  { file: 'screen_25_activity_entry.html', num: '25', title: 'Activity entry', section: 'body' },
  { file: 'screen_26_medication_log.html', num: '26', title: 'Medication log', section: 'treatment' },
  { file: 'screen_27_add_medication.html', num: '27', title: 'Add medication', section: 'treatment' },
  { file: 'screen_28_insights_hub.html', num: '28', title: 'Insights hub', section: 'reports' },
  { file: 'screen_29_doctor_report.html', num: '29', title: 'Doctor report', section: 'reports' },
  { file: 'screen_30_share_preview.html', num: '30', title: 'Share/export preview', section: 'reports' },
  { file: 'screen_31_profile.html', num: '31', title: 'Profile', section: 'settings' },
  { file: 'screen_32_cycle_settings.html', num: '32', title: 'Cycle settings', section: 'settings' },
  { file: 'screen_33_hormone_prefs.html', num: '33', title: 'Hormone preferences', section: 'settings' },
  { file: 'screen_34_notifications.html', num: '34', title: 'Notifications', section: 'settings' },
  { file: 'screen_35_data_export.html', num: '35', title: 'Data export', section: 'settings' },
  { file: 'screen_36_privacy.html', num: '36', title: 'Privacy', section: 'settings' },
  { file: 'screen_37_help_about.html', num: '37', title: 'Help & about', section: 'settings' },
];

const SECTIONS = [
  { id: 'onboarding', label: 'Onboarding', range: '1\u20137' },
  { id: 'home', label: 'Home & logging', range: '8\u201314' },
  { id: 'hormones', label: 'Hormones & studies', range: '15\u201321' },
  { id: 'body', label: 'Body & activity', range: '22\u201325' },
  { id: 'treatment', label: 'Treatment', range: '26\u201327' },
  { id: 'reports', label: 'Reports', range: '28\u201330' },
  { id: 'settings', label: 'Settings', range: '31\u201337' },
];

// Read all screen files and escape for JS template literals
const screenData = {};
for (const entry of MANIFEST) {
  const filePath = path.join(SCREENS_DIR, entry.file);
  let html = fs.readFileSync(filePath, 'utf8');
  // Escape backticks and ${} for template literal embedding
  html = html.replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$\{/g, '\\${');
  screenData[entry.file] = { ...entry, html };
}

// Build the manifest JS string
let manifestJS = 'const SCREENS = [\n';
for (const entry of MANIFEST) {
  const d = screenData[entry.file];
  manifestJS += `  { num: ${JSON.stringify(d.num)}, title: ${JSON.stringify(d.title)}, section: ${JSON.stringify(d.section)}, file: ${JSON.stringify(d.file)}, html: \`${d.html}\` },\n`;
}
manifestJS += '];\n';

const sectionsJS = `const SECTIONS = ${JSON.stringify(SECTIONS)};\n`;

const outputHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lumen \u2014 Contact sheet</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;transition:background .3s,color .3s;}
body[data-theme="light"]{
  --bg:#F1EFE8;--surface:#FFFCF7;--ink:#3B2A20;--mut:#8A6F5E;
  --ac:#C25A36;--acs:#F3D9CC;--sg:#7B8F6B;--sgs:#E4EADD;
  --bd:rgba(59,42,32,.12);--in:#FAF6EF;
}
body[data-theme="dark"]{
  --bg:#1A1220;--surface:#241830;--ink:#F2E4D4;--mut:#A99BB8;
  --ac:#E8A87C;--acs:#3A2438;--sg:#9BAE85;--sgs:#28321F;
  --bd:rgba(242,228,212,.12);--in:#1F1428;
}
body{background:var(--bg);color:var(--ink);}
.header{position:sticky;top:0;z-index:100;background:var(--bg);border-bottom:1px solid var(--bd);padding:16px 24px;display:flex;align-items:center;justify-content:space-between;}
.header h1{font-size:18px;font-weight:500;letter-spacing:-0.3px;}
.header .subtitle{font-size:12px;color:var(--mut);margin-left:12px;font-weight:400;}
.toggle-btn{width:36px;height:36px;border-radius:50%;border:1px solid var(--bd);background:transparent;color:var(--ink);cursor:pointer;font-size:15px;display:flex;align-items:center;justify-content:center;transition:border-color .2s;}
.toggle-btn:hover{border-color:var(--ac);}
main{padding:24px;max-width:1600px;margin:0 auto;}
.section-heading{font-size:14px;font-weight:500;color:var(--mut);margin:32px 0 16px;padding-bottom:8px;border-bottom:1px solid var(--bd);}
.section-heading:first-child{margin-top:0;}
.section-heading span{font-weight:400;font-size:12px;margin-left:8px;color:var(--mut);opacity:.7;}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:20px;margin-bottom:8px;}
.cell{cursor:pointer;transition:transform .15s;}
.cell:hover{transform:translateY(-2px);}
.cell-frame{width:240px;height:512px;overflow:hidden;border-radius:29px;border:1px solid var(--bd);background:var(--surface);position:relative;}
.cell-frame.landscape{height:240px;}
.cell-frame iframe{border:none;pointer-events:none;transform-origin:top left;}
.cell-frame .placeholder{width:100%;height:100%;display:flex;align-items:center;justify-content:center;color:var(--mut);font-size:12px;}
.cell-label{margin-top:8px;font-size:12px;color:var(--mut);font-weight:400;text-align:center;}
.cell-label strong{font-weight:500;color:var(--ink);}

/* Lightbox */
.lb-overlay{position:fixed;inset:0;z-index:1000;display:flex;align-items:center;justify-content:center;opacity:0;pointer-events:none;transition:opacity .2s;}
.lb-overlay.open{opacity:1;pointer-events:auto;}
.lb-backdrop{position:absolute;inset:0;background:rgba(0,0,0,.55);backdrop-filter:blur(4px);}
.lb-content{position:relative;z-index:1;display:flex;flex-direction:column;align-items:center;}
.lb-close{position:absolute;top:-16px;right:-16px;width:36px;height:36px;border-radius:50%;border:1px solid var(--bd);background:var(--surface);color:var(--ink);cursor:pointer;font-size:18px;display:flex;align-items:center;justify-content:center;z-index:2;}
.lb-close:hover{background:var(--ac);color:#FFFCF7;}
.lb-frame-wrap{border-radius:36px;overflow:hidden;box-shadow:0 24px 80px rgba(0,0,0,.25);}
.lb-frame-wrap iframe{border:none;display:block;}
.lb-frame-wrap.landscape iframe{width:540px;height:380px;}
.lb-frame-wrap:not(.landscape) iframe{width:300px;height:640px;}
.lb-label{margin-top:12px;font-size:13px;color:var(--mut);font-weight:400;}
</style>
</head>
<body data-theme="light">
<div class="header">
  <div style="display:flex;align-items:baseline;">
    <h1>Lumen contact sheet</h1>
    <span class="subtitle">38 screens</span>
  </div>
  <button class="toggle-btn" id="theme-toggle" onclick="toggleTheme()">&#9790;</button>
</div>
<main id="main"></main>
<div class="lb-overlay" id="lightbox">
  <div class="lb-backdrop" onclick="closeLightbox()"></div>
  <div class="lb-content">
    <button class="lb-close" onclick="closeLightbox()">&times;</button>
    <div class="lb-frame-wrap" id="lb-frame-wrap"><iframe id="lb-iframe"></iframe></div>
    <div class="lb-label" id="lb-label"></div>
  </div>
</div>
<script>
${manifestJS}
${sectionsJS}

const LIGHT_VARS = {b:'#F1EFE8',f:'#FFFCF7','in':'#FAF6EF',ink:'#3B2A20',mut:'#8A6F5E',ac:'#C25A36',acs:'#F3D9CC',sg:'#7B8F6B',sgs:'#E4EADD',bd:'rgba(59,42,32,.12)'};
const DARK_VARS = {b:'#1A1220',f:'#241830','in':'#1F1428',ink:'#F2E4D4',mut:'#A99BB8',ac:'#E8A87C',acs:'#3A2438',sg:'#9BAE85',sgs:'#28321F',bd:'rgba(242,228,212,.12)'};

const THEME_CSS = \`
[data-theme="light"]{--b:#F1EFE8;--f:#FFFCF7;--in:#FAF6EF;--ink:#3B2A20;--mut:#8A6F5E;--ac:#C25A36;--acs:#F3D9CC;--sg:#7B8F6B;--sgs:#E4EADD;--bd:rgba(59,42,32,.12);
--s1-bg:#F1EFE8;--s1-frame:#FFFCF7;--s1-ink:#3B2A20;--s1-muted:#8A6F5E;--s1-accent:#C25A36;--s1-accent-soft:#F3D9CC;--s1-sage:#7B8F6B;--s1-sage-soft:#E4EADD;--s1-border:rgba(59,42,32,.12);
--p1:#F3D9CC;--p2:#FAEEDA;--p3:#E4EADD;--p4:#EEEDFE;--ovl:rgba(59,42,32,.45);}
[data-theme="dark"]{--b:#1A1220;--f:#241830;--in:#1F1428;--ink:#F2E4D4;--mut:#A99BB8;--ac:#E8A87C;--acs:#3A2438;--sg:#9BAE85;--sgs:#28321F;--bd:rgba(242,228,212,.12);
--s1-bg:#1A1220;--s1-frame:#241830;--s1-ink:#F2E4D4;--s1-muted:#A99BB8;--s1-accent:#E8A87C;--s1-accent-soft:#3A2438;--s1-sage:#9BAE85;--s1-sage-soft:#28321F;--s1-border:rgba(242,228,212,.12);
--p1:#4A1B0C;--p2:#412402;--p3:#28321F;--p4:#26215C;--ovl:rgba(0,0,0,.6);}
\`;

function normalizeScreen(html, screenKey, isThumbnail) {
  let processed = html.trim();

  // Detect Pattern B BEFORE stripping onclick (onclick contains setProperty)
  var isPatternB = processed.includes('setProperty');

  // Remove all onclick handlers (theme toggles)
  processed = processed.replace(/onclick="[^"]*"/g, '');

  if (isPatternB) {
    // Strip inline CSS custom property declarations from the FIRST div's style attribute only
    var firstStyleReplaced = false;
    processed = processed.replace(/style="([^"]*)"/, function(match, styleContent) {
      if (firstStyleReplaced) return match;
      firstStyleReplaced = true;
      var cleaned = styleContent.replace(/--[\\w-]+\\s*:\\s*[^;]+;?\\s*/g, '');
      return 'style="' + cleaned + '"';
    });
  }

  // Reduce overlay opacity for modal thumbnails
  if (isThumbnail) {
    if (screenKey && screenKey.includes('screen_09')) {
      processed = processed.replace(/rgba\\(59,42,32,\\.45\\)/g, 'rgba(59,42,32,.2)');
      processed = processed.replace(/rgba\\(0,0,0,\\.6\\)/g, 'rgba(0,0,0,.3)');
    }
    if (screenKey && screenKey.includes('screen_20')) {
      processed = processed.replace(/rgba\\(0,0,0,0\\.35\\)/g, 'rgba(0,0,0,.15)');
    }
  }

  // Inject postMessage listener for theme changes (works cross-origin, unlike contentDocument)
  var themeListener = '<scr' + 'ipt>window.addEventListener("message",function(e){if(e.data&&e.data.type==="theme"){var r=document.querySelector("[data-theme]");if(r){r.dataset.theme=e.data.theme;var v=e.data.vars;if(v){Object.keys(v).forEach(function(k){r.style.setProperty("--"+k,v[k])})}}});</scr' + 'ipt>';

  return '<!DOCTYPE html><html><head><meta charset="UTF-8"><style>' + THEME_CSS + ' body{margin:0;overflow:hidden;}</style></head><body style="margin:0;overflow:hidden">' + processed + themeListener + '</body></html>';
}

function currentTheme() {
  return document.body.dataset.theme || 'light';
}

function applyThemeToIframe(iframe) {
  var theme = currentTheme();
  var vars = theme === 'dark' ? DARK_VARS : LIGHT_VARS;
  // Use postMessage for reliable cross-frame communication
  try {
    if (iframe.contentWindow) {
      iframe.contentWindow.postMessage({type:'theme', theme:theme, vars:vars}, '*');
    }
  } catch(e) {}
}

function toggleTheme() {
  var next = currentTheme() === 'light' ? 'dark' : 'light';
  document.body.dataset.theme = next;
  document.getElementById('theme-toggle').textContent = next === 'light' ? '\\u263E' : '\\u2600';
  // Update all loaded iframes via postMessage
  document.querySelectorAll('.cell-frame iframe').forEach(applyThemeToIframe);
  // Update lightbox iframe if open
  var lbIframe = document.getElementById('lb-iframe');
  if (lbIframe && lbIframe.srcdoc) applyThemeToIframe(lbIframe);
}

// Build the grid
const main = document.getElementById('main');
SECTIONS.forEach(function(sec) {
  const heading = document.createElement('div');
  heading.className = 'section-heading';
  heading.innerHTML = sec.label + '<span>' + sec.range + '</span>';
  main.appendChild(heading);

  const grid = document.createElement('div');
  grid.className = 'grid';

  const sectionScreens = SCREENS.filter(function(s) { return s.section === sec.id; });
  sectionScreens.forEach(function(screen) {
    const cell = document.createElement('div');
    cell.className = 'cell';
    cell.dataset.screenIdx = SCREENS.indexOf(screen);

    const isLandscape = screen.file.includes('landscape');
    const frame = document.createElement('div');
    frame.className = 'cell-frame' + (isLandscape ? ' landscape' : '');

    const placeholder = document.createElement('div');
    placeholder.className = 'placeholder';
    placeholder.textContent = screen.num;
    frame.appendChild(placeholder);
    frame.dataset.lazy = '1';
    frame.dataset.screenIdx = SCREENS.indexOf(screen);

    const label = document.createElement('div');
    label.className = 'cell-label';
    label.innerHTML = '<strong>' + screen.num + '</strong> \\u2014 ' + screen.title;

    cell.appendChild(frame);
    cell.appendChild(label);
    cell.addEventListener('click', function() { openLightbox(SCREENS.indexOf(screen)); });
    grid.appendChild(cell);
  });

  main.appendChild(grid);
});

// Lazy loading
const observer = new IntersectionObserver(function(entries) {
  entries.forEach(function(entry) {
    if (entry.isIntersecting) {
      const container = entry.target;
      const idx = parseInt(container.dataset.screenIdx);
      const screen = SCREENS[idx];
      const isLandscape = screen.file.includes('landscape');
      const nativeW = isLandscape ? 540 : 300;
      const nativeH = isLandscape ? 380 : 640;
      const scale = 240 / nativeW;

      const iframe = document.createElement('iframe');
      iframe.style.width = nativeW + 'px';
      iframe.style.height = nativeH + 'px';
      iframe.style.transform = 'scale(' + scale + ')';
      iframe.style.transformOrigin = 'top left';
      iframe.srcdoc = normalizeScreen(screen.html, screen.file, true);
      iframe.onload = function() { applyThemeToIframe(iframe); };

      // Remove placeholder
      const ph = container.querySelector('.placeholder');
      if (ph) ph.remove();
      container.appendChild(iframe);
      observer.unobserve(container);
    }
  });
}, { rootMargin: '300px' });

document.querySelectorAll('[data-lazy]').forEach(function(el) { observer.observe(el); });

// Lightbox
function openLightbox(idx) {
  const screen = SCREENS[idx];
  const isLandscape = screen.file.includes('landscape');
  const lb = document.getElementById('lightbox');
  const wrap = document.getElementById('lb-frame-wrap');
  const iframe = document.getElementById('lb-iframe');
  const label = document.getElementById('lb-label');

  wrap.className = 'lb-frame-wrap' + (isLandscape ? ' landscape' : '');
  iframe.srcdoc = normalizeScreen(screen.html, screen.file, false);
  iframe.onload = function() { applyThemeToIframe(iframe); };
  label.textContent = 'Screen ' + screen.num + ' \\u2014 ' + screen.title;
  lb.classList.add('open');
  document.body.style.overflow = 'hidden';
}

function closeLightbox() {
  const lb = document.getElementById('lightbox');
  lb.classList.remove('open');
  document.body.style.overflow = '';
  document.getElementById('lb-iframe').srcdoc = '';
}

document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') closeLightbox();
});
</script>
</body>
</html>`;

fs.writeFileSync(path.join(__dirname, 'contact_sheet.html'), outputHTML, 'utf8');
console.log('contact_sheet.html generated (' + Math.round(outputHTML.length / 1024) + ' KB)');
