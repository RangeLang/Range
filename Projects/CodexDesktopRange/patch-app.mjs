import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import {
  createPackageWithOptions,
  extractAll,
  getRawHeader,
} from "@electron/asar";

const sourceApp = process.argv[2] ?? "/Applications/ChatGPT.app";
const targetApp = process.argv[3] ?? "/Applications/ChatGPT Range.app";
const projectDir = dirname(new URL(import.meta.url).pathname);
const grammar = JSON.parse(
  readFileSync(join(projectDir, "range.tmLanguage.json"), "utf8"),
);
const rangeDarkTheme = JSON.parse(
  readFileSync(join(projectDir, "range-codability-dark.json"), "utf8"),
);
const rangeLightTheme = JSON.parse(
  readFileSync(join(projectDir, "range-codability-light.json"), "utf8"),
);

function unpackedRoots(node, currentPath = "", parentUnpacked = false) {
  const isUnpacked = node.unpacked === true;
  const roots = [];
  if (isUnpacked && !parentUnpacked) {
    roots.push({ path: currentPath, directory: node.files != null });
  }
  if (node.files != null) {
    for (const [name, child] of Object.entries(node.files)) {
      roots.push(
        ...unpackedRoots(
          child,
          currentPath === "" ? name : `${currentPath}/${name}`,
          isUnpacked,
        ),
      );
    }
  }
  return roots;
}

function unpackedFiles(node, currentPath = "") {
  if (node.files == null) return node.unpacked === true ? [currentPath] : [];
  return Object.entries(node.files).flatMap(([name, child]) =>
    unpackedFiles(child, currentPath === "" ? name : `${currentPath}/${name}`),
  );
}

function globAlternatives(paths) {
  return paths.length === 1 ? paths[0] : `{${paths.join(",")}}`;
}

function fail(message) {
  throw new Error(message);
}

if (!existsSync(sourceApp)) fail(`Source app does not exist: ${sourceApp}`);
if (existsSync(targetApp)) {
  fail(`Target already exists; refusing to overwrite it: ${targetApp}`);
}

const tempRoot = mkdtempSync(join(tmpdir(), "codex-desktop-range-"));
const extractedDir = join(tempRoot, "app");
const packedAsar = join(tempRoot, "app.asar");

try {
  console.log(`Copying ${sourceApp} to ${targetApp}...`);
  execFileSync("/usr/bin/ditto", [sourceApp, targetApp]);

  const resourcesDir = join(targetApp, "Contents", "Resources");
  const asarPath = join(resourcesDir, "app.asar");
  const originalHeader = getRawHeader(asarPath).header;
  const originalUnpackedFiles = unpackedFiles(originalHeader).sort();
  extractAll(asarPath, extractedDir);

  const packagePath = join(extractedDir, "package.json");
  const appPackage = JSON.parse(readFileSync(packagePath, "utf8"));
  appPackage.name = "openai-codex-electron-range";
  appPackage.productName = "Codex Range";
  writeFileSync(packagePath, `${JSON.stringify(appPackage, null, 2)}\n`);

  const bootstrapPath = join(extractedDir, ".vite", "build", "early-bootstrap.js");
  const bootstrap = readFileSync(bootstrapPath, "utf8");
  const bootstrapMarker = "require(\"./src-";
  if (!bootstrap.startsWith(bootstrapMarker)) {
    fail("The installed early bootstrap has an unexpected shape");
  }
  const rangeProfileBootstrap =
    '(()=>{let p=require("node:path"),r=p.join(require("node:os").homedir(),' +
    '"Library","Application Support","Codex Range");' +
    'process.env.CODEX_ELECTRON_USER_DATA_PATH??=p.join(r,"Electron");' +
    'process.env.CODEX_HOME??=p.join(r,"Codex Home");' +
    'process.argv.includes("--use-mock-keychain")||process.argv.push("--use-mock-keychain");' +
    'require("electron").app.commandLine.appendSwitch("use-mock-keychain")})(),';
  writeFileSync(bootstrapPath, `${rangeProfileBootstrap}${bootstrap}`);

  const buildDir = join(extractedDir, ".vite", "build");
  const bootstrapBundles = readdirSync(buildDir).filter((name) =>
    /^bootstrap-.*\.js$/.test(name),
  );
  if (bootstrapBundles.length !== 1) {
    fail(`Expected one desktop bootstrap bundle, found ${bootstrapBundles.length}`);
  }
  const desktopBootstrapPath = join(buildDir, bootstrapBundles[0]);
  const desktopBootstrap = readFileSync(desktopBootstrapPath, "utf8");
  const singleInstanceGuard = "if(!(!$||a.app.requestSingleInstanceLock()))";
  if (!desktopBootstrap.includes(singleInstanceGuard)) {
    fail("The installed single-instance guard has an unexpected shape");
  }
  writeFileSync(
    desktopBootstrapPath,
    desktopBootstrap.replace(singleInstanceGuard, "if(!1)"),
  );

  const assetsDir = join(extractedDir, "webview", "assets");
  const providers = readdirSync(assetsDir).filter((name) =>
    /^shiki-highlight-provider-.*\.js$/.test(name),
  );
  if (providers.length !== 1) {
    fail(`Expected one Shiki provider, found ${providers.length}`);
  }

  const providerPath = join(assetsDir, providers[0]);
  const original = readFileSync(providerPath, "utf8");
  const declaration = "var D,O,k,A,j,M;";
  const languageList =
    "M=[`typescript`,`javascript`,`css`,`html`,`python`]";
  if (!original.includes(declaration) || !original.includes(languageList)) {
    fail(`The installed Shiki provider has an unexpected shape: ${providers[0]}`);
  }

  const compactGrammar = JSON.stringify(grammar);
  const patched = original
    .replace(declaration, "var D,O,k,A,j,M,R;")
    .replace(
      languageList,
      `R=Object.freeze(${compactGrammar}),M=[\`typescript\`,\`javascript\`,\`css\`,\`html\`,\`python\`,R]`,
    );
  if (patched === original || !patched.includes('"scopeName":"source.range"')) {
    fail("Range grammar injection did not change the provider");
  }
  writeFileSync(providerPath, patched);

  // The full-file preview uses Pierre's own Shiki instance rather than the
  // lightweight code-block provider above. Teach its filename resolver about
  // .range and return the embedded grammar from the language loader.
  const appInitialBundles = readdirSync(assetsDir).filter((name) =>
    /^app-initial-.*\.js$/.test(name),
  );
  if (appInitialBundles.length !== 1) {
    fail(`Expected one app-initial bundle, found ${appInitialBundles.length}`);
  }
  const appInitialPath = join(assetsDir, appInitialBundles[0]);
  const appInitialOriginal = readFileSync(appInitialPath, "utf8");
  const extensionMapMarker = 'D4r={"1c":`1c`';
  const languageLoaderMarker =
    "function n2r(e){return SI.get(e)??e2r(e)}";
  const themeLoaderMarker =
    "function Q2r(e){return JI.getResolvedTheme(e)??X2r(e)}";
  const fileThemeMarker =
    "getLocalHighlightTheme(){return this.workerManager?.getFileRenderOptions().theme??this.options.theme??UF}";
  const diffThemeMarker =
    "getLocalHighlightTheme(){return this.workerManager?.getDiffRenderOptions().theme??this.options.theme??UF}";
  const sidebarQuickChatTooltipMarker =
    "v=o.formatMessage({id:`sidebarElectron.quickChatNavLink`,defaultMessage:`Quick chat`,description:`Sidebar action for starting a lightweight chat in a compact popover, separate from a full Codex task`})";
  const sidebarNewChatHandlerMarker =
    'm=()=>{Qvc(a,{canStartProjectlessChat:a.get(XN),currentThreadKey:a.get(eA),localProjectActionsEnabled:a.get(YN),startNewConversation:p,startNewConversationInProject:d})}';
  const sidebarProjectlessNewChatHandler =
    'm=()=>{Qvc(a,{canStartProjectlessChat:a.get(XN),currentThreadKey:a.get(eA),localProjectActionsEnabled:a.get(YN),projectless:!0,startNewConversation:p,startNewConversationInProject:d})}';
  const sidebarQuickChatBlockMarker =
    'let C;t[21]!==i||t[22]!==y||t[23]!==l||t[24]!==a?(C=i?(0,V8.jsx)(`div`,{className:`pe-1`,children:(0,V8.jsx)(nz,{shortcut:l,tooltipContent:y,delayOpen:!0,children:(0,V8.jsx)(hR,{"aria-label":y,color:`ghost`,size:`compact`,uniform:!0,onClick:()=>{pws(a,{source:py.CODEX_QUICK_CHAT_SOURCE_SIDEBAR,surface:my.CODEX_QUICK_CHAT_SURFACE_POPOVER})},children:(0,V8.jsx)(GSi,{})})})}):null,t[21]=i,t[22]=y,t[23]=l,t[24]=a,t[25]=C):C=t[25];';
  const sidebarProjectMenuBlock =
    'let C,P=a.get(uCr).groups;t[21]!==y||t[22]!==P||t[23]!==p||t[24]!==d?(C=(0,V8.jsx)(`div`,{className:`pe-1`,children:(0,V8.jsxs)(cz,{align:`end`,contentClassName:`p-1.5`,contentWidth:`menuWide`,sideOffset:4,triggerButton:(0,V8.jsx)(hR,{"aria-label":`Choose a project for new chat`,color:`ghost`,size:`compact`,uniform:!0,children:(0,V8.jsx)(qz,{className:`icon-2xs`})}),children:[(0,V8.jsx)(pz.Item,{onSelect:()=>p({activeProject:null}),children:(0,V8.jsx)(Y,{id:`chatgptConversations.composer.projectSelector.none`,defaultMessage:`No project`,description:`Label in the composer project picker when no local or cloud project is selected`})}),P.length>0?(0,V8.jsx)(pz.Separator,{}):null,P.length>0?(0,V8.jsx)(pz.SectionLabel,{children:(0,V8.jsx)(Y,{id:`sidebarElectron.projectsNavLink`,defaultMessage:`Projects`,description:`Section label above project task groups in the sidebar`})}):null,...P.map(e=>(0,V8.jsx)(pz.Item,{leftIcon:(0,V8.jsx)(h$,{className:`icon-xs shrink-0`,fallbackIcon:(0,V8.jsx)(jz,{className:`icon-xs shrink-0`}),isRemoteProject:e.projectKind===`remote`,markerClassName:`size-4`,projectId:e.projectId}),onSelect:()=>d(e),children:e.label},`${e.projectKind}:${e.hostId??`local`}:${e.projectId}`))]})}),t[21]=y,t[22]=P,t[23]=p,t[24]=d,t[25]=C):C=t[25];';
  const sidebarModuleDependenciesMarker =
    'hX(),My(),V6(),iyc(),Mac(),_jc()';
  const sidebarModuleDependenciesWithProjectIcons =
    'hX(),My(),g$(),V6(),iyc(),Mac(),_jc()';
  const productModeSwitcherMarker =
    'if(n){let e;return t[4]===s?e=t[5]:(e=(0,K8.jsx)(`div`,{className:`-ms-2 flex h-8 min-w-0 items-center px-2 text-[17px] leading-6 text-default select-none`,children:s})';
  const staticCodexHeadingMarker = productModeSwitcherMarker.replace(
    "if(n){",
    'if(n||r===`codex`){',
  );
  const sidebarConversationSourceMarker =
    'O=o||s,k=D;a===`chatgpt`&&!g?k=`codex`:a===`chatgpt`&&!O&&(k=`chatgpt`);';
  const unifiedCodexConversationSource =
    `${sidebarConversationSourceMarker}a===\`codex\`&&(k=\`all\`);`;
  const sidebarRecentsLayoutMarker =
    'includeCodexProjects:s,mode:T,pinnedKeyAliases';
  const sidebarUnifiedRecentsLayout =
    'includeCodexProjects:s,mode:a===`codex`?`list`:T,pinnedKeyAliases';
  const homeWorkCapabilityMarker =
    'let y=v,b=yC()===bC,x=b?u:c';
  const homeWorkCapabilityEnabled =
    'let y=v,b=!0,x=b?u:c';
  const homeWorkSurfaceMarker =
    '{data:x}=uR(),S=yC()===bC,C=S&&!0';
  const homeWorkSurfaceEnabled =
    '{data:x}=uR(),S=!0,C=S&&!0';
  const homeModeDefaultMarker = 'let k=O,A=a;';
  const homeModeDefaultBuild = 'let k=!0,A=i??`work`;';
  const homeModeHiddenMarker = 'if(r===`hidden`)return null;';
  const homeModeVisible = 'if(!1)return null;';
  const homeModeTitlebarMarker = 'if(r===`titlebar`){';
  const homeModeInline = 'if(!1){';
  const homeModePositionMarker =
    'className:`@container/home-mode-toggle pointer-events-none absolute inset-x-0 top-0 z-30 flex h-toolbar items-center justify-center`';
  const homeModePositionGateway =
    'className:`@container/home-mode-toggle pointer-events-none absolute inset-x-0 z-30 flex h-32 items-center justify-center px-panel`,style:{top:`calc(50% - 16rem)`}';
  const homeBuildHeadingMarker =
    'id:`home.hero.workModeWhatShouldWeWorkOn`,defaultMessage:`What should we work on?`,description:`Primary heading on the home page in everyday work mode`';
  const homeBuildHeading =
    'id:`home.hero.workModeWhatShouldWeBuild`,defaultMessage:`What should we build?`,description:`Primary heading on the home page in Build mode`';
  const homeModeSetterMarker =
    'function gG(e,t){t===`chat`&&e.get(PS)||e.set(Qda,t)}';
  const homeModeSetterEnabled =
    'function gG(e,t){e.set(Qda,t)}';
  const homeModeInnerWrapperMarker =
    'children:(0,orc.jsx)(`div`,{className:`pointer-events-auto flex shrink-0 items-center no-drag`,children:n})';
  const homeModeInnerWrapperRelative =
    'children:(0,orc.jsx)(`div`,{className:`relative pointer-events-auto flex shrink-0 items-center no-drag`,children:n})';
  const homeModeRenderMarker =
    'let Kn;t[230]===o?Kn=t[231]:(Kn=o==null?null:(0,o6.jsx)(o6.Fragment,{children:(0,o6.jsx)(irc,{children:o})}),t[230]=o,t[231]=Kn);';
  const homeModeRenderWithRunLocation =
    'let Kn=o==null?null:(0,o6.jsx)(o6.Fragment,{children:(0,o6.jsx)(irc,{children:(0,o6.jsxs)(o6.Fragment,{children:[o,a===`work`&&cn!=null?(0,o6.jsx)(`div`,{className:`absolute z-40`,style:{top:`4.75rem`,left:`1.25rem`},children:cn}):null]})})});';
  const footerRunLocationMarker = 'let ln=cn,un=!Ze&&l,dn;';
  const footerRunLocationRemoved = 'let ln=null,un=!Ze&&l,dn;';
  const sidebarNavigationMarker =
    'A=i?(0,mG.jsx)(mG.Fragment,{children:(0,mG.jsxs)(mG.Fragment,{children:[';
  const contentNavigation =
    'A=i?(0,mG.jsx)(`div`,{className:`fixed top-0 z-40 flex h-toolbar items-center gap-1 no-drag`,style:{left:`calc(var(--codex-sidebar-preferred-width, 275px) + 0.5rem)`},children:(0,mG.jsxs)(mG.Fragment,{children:[';
  const workspaceMainPaneMarker =
    '(0,RG.jsx)(`div`,{className:IG.MainContentViewport';
  const workspaceContentPaneExpression =
    '(0,RG.jsx)(Ema,{contentPaneDefaultWidth:ge,contentPaneWidth:_e,contentPaneWidthRatio:ve,isContentPaneOpen:y,widthMode:ye,workspaceWidth:me,children:r?.children},`right-panel:${a.value.clientThreadId}`)';
  const contentPaneSideMarker =
    'M=_!=null&&!j&&v===`left`';
  const contentPaneSideSwapped =
    'M=!j&&!(_!=null&&v===`left`)';
  const threadPageHeaderMarker =
    'te=y==null&&f!=null&&S?(0,OG.jsx)(`div`,{className:J(`pointer-events-none w-full min-w-0 flex-1`,ypa),"data-app-shell-page-header":!0,children:f}):null';
  const threadPageHeaderRemoved = 'te=null';
  const shareHeaderButtonMarker =
    'function dGs(e){let t=(0,pGs.c)(17),';
  const shareHeaderButtonRemoved =
    'function dGs(e){return null;let t=(0,pGs.c)(17),';
  const dockedSidebarFadeMarker =
    'C={minWidth:_,width:_,opacity:S}';
  const dockedSidebarWithoutFade =
    'C={minWidth:_,width:_}';
  const floatingSidebarFadeMarker =
    'initial:!l&&{opacity:0,x:-8},animate:{opacity:1,x:0},exit:{opacity:0,x:l?0:-8}';
  const floatingSidebarWithoutFade =
    'initial:!l&&{x:-8},animate:{x:0},exit:{x:l?0:-8}';
  if (
    !appInitialOriginal.includes(extensionMapMarker) ||
    !appInitialOriginal.includes(languageLoaderMarker) ||
    !appInitialOriginal.includes(themeLoaderMarker) ||
    !appInitialOriginal.includes(fileThemeMarker) ||
    !appInitialOriginal.includes(diffThemeMarker) ||
    appInitialOriginal.split(sidebarQuickChatTooltipMarker).length !== 2 ||
    appInitialOriginal.split(sidebarNewChatHandlerMarker).length !== 2 ||
    appInitialOriginal.split(sidebarQuickChatBlockMarker).length !== 2 ||
    appInitialOriginal.split(sidebarModuleDependenciesMarker).length !== 2 ||
    appInitialOriginal.split(productModeSwitcherMarker).length !== 2 ||
    appInitialOriginal.split(sidebarConversationSourceMarker).length !== 2 ||
    appInitialOriginal.split(sidebarRecentsLayoutMarker).length !== 2 ||
    appInitialOriginal.split(homeWorkCapabilityMarker).length !== 2 ||
    appInitialOriginal.split(homeWorkSurfaceMarker).length !== 2 ||
    appInitialOriginal.split(homeModeDefaultMarker).length !== 2 ||
    appInitialOriginal.split(homeModeHiddenMarker).length !== 2 ||
    appInitialOriginal.split(homeModeTitlebarMarker).length !== 2 ||
    appInitialOriginal.split(homeModePositionMarker).length !== 2 ||
    appInitialOriginal.split(homeBuildHeadingMarker).length !== 2 ||
    appInitialOriginal.split(homeModeSetterMarker).length !== 2 ||
    appInitialOriginal.split(homeModeInnerWrapperMarker).length !== 2 ||
    appInitialOriginal.split(homeModeRenderMarker).length !== 2 ||
    appInitialOriginal.split(footerRunLocationMarker).length !== 2 ||
    appInitialOriginal.split(sidebarNavigationMarker).length !== 2 ||
    appInitialOriginal.split(workspaceMainPaneMarker).length !== 2 ||
    appInitialOriginal.split(workspaceContentPaneExpression).length !== 2 ||
    appInitialOriginal.split(contentPaneSideMarker).length !== 2 ||
    appInitialOriginal.split(threadPageHeaderMarker).length !== 2 ||
    appInitialOriginal.split(shareHeaderButtonMarker).length !== 2 ||
    appInitialOriginal.split(dockedSidebarFadeMarker).length !== 2 ||
    appInitialOriginal.split(floatingSidebarFadeMarker).length !== 2
  ) {
    fail(
      `The installed full-file highlighter has an unexpected shape: ${appInitialBundles[0]}`,
    );
  }
  const compactDarkTheme = JSON.stringify(rangeDarkTheme);
  const compactLightTheme = JSON.stringify(rangeLightTheme);
  const rangeThemeSelection =
    "{light:`range-codability-light`,dark:`range-codability-dark`}";
  let appInitialPatched = appInitialOriginal
    .replace(extensionMapMarker, 'D4r={range:`range`,"1c":`1c`')
    .replace(
      languageLoaderMarker,
      `function n2r(e){return e===\`range\`?{name:e,data:[${compactGrammar}]}:SI.get(e)??e2r(e)}`,
    )
    .replace(
      themeLoaderMarker,
      `function Q2r(e){return e===\`range-codability-dark\`?${compactDarkTheme}:e===\`range-codability-light\`?${compactLightTheme}:JI.getResolvedTheme(e)??X2r(e)}`,
    )
    .replace(
      fileThemeMarker,
      `getLocalHighlightTheme(){return this.computedLang===\`range\`?${rangeThemeSelection}:this.workerManager?.getFileRenderOptions().theme??this.options.theme??UF}`,
    )
    .replace(
      diffThemeMarker,
      `getLocalHighlightTheme(){return this.computedLang===\`range\`?${rangeThemeSelection}:this.workerManager?.getDiffRenderOptions().theme??this.options.theme??UF}`,
    )
    .replace(
      sidebarQuickChatTooltipMarker,
      "v=o.formatMessage({id:`sidebarElectron.newThread`,defaultMessage:`New chat`,description:`Starts a new chat from the sidebar`})",
    )
    .replace(
      sidebarNewChatHandlerMarker,
      sidebarProjectlessNewChatHandler,
    )
    .replace(
      sidebarQuickChatBlockMarker,
      sidebarProjectMenuBlock,
    )
    .replace(
      sidebarModuleDependenciesMarker,
      sidebarModuleDependenciesWithProjectIcons,
    )
    .replace(
      productModeSwitcherMarker,
      staticCodexHeadingMarker,
    )
    .replace(
      sidebarConversationSourceMarker,
      unifiedCodexConversationSource,
    )
    .replace(
      sidebarRecentsLayoutMarker,
      sidebarUnifiedRecentsLayout,
    )
    .replace(homeWorkCapabilityMarker, homeWorkCapabilityEnabled)
    .replace(homeWorkSurfaceMarker, homeWorkSurfaceEnabled)
    .replace(homeModeDefaultMarker, homeModeDefaultBuild)
    .replace(homeModeHiddenMarker, homeModeVisible)
    .replace(homeModeTitlebarMarker, homeModeInline)
    .replace(
      homeModePositionMarker,
      homeModePositionGateway,
    )
    .replace(homeBuildHeadingMarker, homeBuildHeading)
    .replace(homeModeSetterMarker, homeModeSetterEnabled)
    .replace(homeModeInnerWrapperMarker, homeModeInnerWrapperRelative)
    .replace(homeModeRenderMarker, homeModeRenderWithRunLocation)
    .replace(footerRunLocationMarker, footerRunLocationRemoved)
    .replace(sidebarNavigationMarker, contentNavigation)
    .replace(contentPaneSideMarker, contentPaneSideSwapped)
    .replace(threadPageHeaderMarker, threadPageHeaderRemoved)
    .replace(shareHeaderButtonMarker, shareHeaderButtonRemoved)
    .replace(dockedSidebarFadeMarker, dockedSidebarWithoutFade)
    .replace(floatingSidebarFadeMarker, floatingSidebarWithoutFade);
  const workspaceMainPaneStart = appInitialPatched.indexOf(
    workspaceMainPaneMarker,
  );
  const workspaceContentPaneStart = appInitialPatched.indexOf(
    workspaceContentPaneExpression,
    workspaceMainPaneStart,
  );
  if (
    workspaceMainPaneStart < 0 ||
    workspaceContentPaneStart < 0 ||
    appInitialPatched[workspaceContentPaneStart - 1] !== `,`
  ) {
    fail("The installed workspace panes are not adjacent siblings");
  }
  const workspaceMainPaneExpression = appInitialPatched.slice(
    workspaceMainPaneStart,
    workspaceContentPaneStart - 1,
  );
  const workspaceContentPaneEnd =
    workspaceContentPaneStart + workspaceContentPaneExpression.length;
  appInitialPatched =
    appInitialPatched.slice(0, workspaceMainPaneStart) +
    workspaceContentPaneExpression +
    `,` +
    workspaceMainPaneExpression +
    appInitialPatched.slice(workspaceContentPaneEnd);
  if (
    appInitialPatched === appInitialOriginal ||
    !appInitialPatched.includes('D4r={range:`range`') ||
    !appInitialPatched.includes('e===`range`?{name:e,data:[') ||
    !appInitialPatched.includes('e===`range-codability-dark`?') ||
    !appInitialPatched.includes('this.computedLang===`range`?{light:') ||
    !appInitialPatched.includes(
      'id:`sidebarElectron.newThread`,defaultMessage:`New chat`,description:`Starts a new chat from the sidebar`',
    ) ||
    !appInitialPatched.includes(sidebarProjectlessNewChatHandler) ||
    !appInitialPatched.includes(sidebarProjectMenuBlock) ||
    !appInitialPatched.includes(sidebarModuleDependenciesWithProjectIcons) ||
    !appInitialPatched.includes(staticCodexHeadingMarker) ||
    !appInitialPatched.includes(unifiedCodexConversationSource) ||
    !appInitialPatched.includes(sidebarUnifiedRecentsLayout) ||
    !appInitialPatched.includes(homeWorkCapabilityEnabled) ||
    !appInitialPatched.includes(homeWorkSurfaceEnabled) ||
    !appInitialPatched.includes(homeModeDefaultBuild) ||
    !appInitialPatched.includes(homeModeVisible) ||
    !appInitialPatched.includes(homeModeInline) ||
    !appInitialPatched.includes(homeModePositionGateway) ||
    !appInitialPatched.includes(homeBuildHeading) ||
    !appInitialPatched.includes(homeModeSetterEnabled) ||
    !appInitialPatched.includes(homeModeInnerWrapperRelative) ||
    !appInitialPatched.includes(homeModeRenderWithRunLocation) ||
    !appInitialPatched.includes(footerRunLocationRemoved) ||
    !appInitialPatched.includes(contentNavigation) ||
    !appInitialPatched.includes(
      `${workspaceContentPaneExpression},${workspaceMainPaneMarker}`,
    ) ||
    !appInitialPatched.includes(contentPaneSideSwapped) ||
    !appInitialPatched.includes(threadPageHeaderRemoved) ||
    !appInitialPatched.includes(shareHeaderButtonRemoved) ||
    !appInitialPatched.includes(dockedSidebarWithoutFade) ||
    !appInitialPatched.includes(floatingSidebarWithoutFade) ||
    !appInitialPatched.includes('"scopeName":"source.range"')
  ) {
    fail("Range grammar injection did not change the full-file highlighter");
  }
  writeFileSync(appInitialPath, appInitialPatched);

  // The stock thread summary is wrapped in a floating popover on narrow panes.
  // Reuse its native content as a full conversation-column screen instead,
  // selected from a compact Chat / Summary segmented control in the header.
  const localConversationBundles = readdirSync(assetsDir).filter((name) =>
    /^local-conversation-page-.*\.js$/.test(name),
  );
  if (localConversationBundles.length !== 1) {
    fail(
      `Expected one local conversation page bundle, found ${localConversationBundles.length}`,
    );
  }
  const localConversationPath = join(assetsDir, localConversationBundles[0]);
  const localConversationOriginal = readFileSync(localConversationPath, "utf8");
  const summaryToggleStartMarker = "function So(e){";
  const summaryToggleEndMarker = "function Co(e){";
  const summaryScreenStateMarker =
    "m=J(!1,r),h=ar(!1),g=J(Se,d)";
  const summaryScreenState =
    "m=J(!1,r),h=ar(!1),gt=Y(Pi).isPopoverOpen,g=J(Se,d)";
  const conversationScreenMarker =
    'let _e;t[58]===ie?_e=t[59]:(_e=(0,Q.jsx)(`div`,{className:`h-full min-h-0`,children:ie}),t[58]=ie,t[59]=_e);';
  const conversationSummaryScreen =
    'let _e=(0,Q.jsx)(`div`,{"data-range-summary-screen":gt,className:`h-full min-h-0 overflow-auto`,children:gt?(0,Q.jsx)(Oi,{onOpenBackgroundAgent:I,onOpenPullRequestSidePanel:B,onOpenSubagentsPanel:R}):ie});';
  const summaryToggleStart = localConversationOriginal.indexOf(
    summaryToggleStartMarker,
  );
  const summaryToggleEnd = localConversationOriginal.indexOf(
    summaryToggleEndMarker,
    summaryToggleStart,
  );
  if (
    summaryToggleStart < 0 ||
    summaryToggleEnd < 0 ||
    localConversationOriginal.split(summaryScreenStateMarker).length !== 2 ||
    localConversationOriginal.split(conversationScreenMarker).length !== 2
  ) {
    fail(
      `The installed thread summary UI has an unexpected shape: ${localConversationBundles[0]}`,
    );
  }
  const summarySegmentedControl =
    'function So(e){let{conversationId:n}=e,s=ne(mt),h=Y(Pi),g=h.isPopoverOpen,i=()=>s.set(Pi,e=>({...e,isPopoverOpen:!1})),a=()=>s.set(Pi,e=>({...e,isPopoverOpen:!0})),c={display:`inline-flex`,alignItems:`center`,gap:`2px`,padding:`2px`,borderRadius:`10px`,background:`var(--color-surface-secondary)`},l={border:0,borderRadius:`8px`,padding:`5px 10px`,fontSize:`13px`,lineHeight:`18px`,cursor:`pointer`,color:`var(--color-text-secondary)`,background:`transparent`},u={...l,color:`var(--color-text-primary)`,background:`var(--color-surface)`,boxShadow:`0 1px 2px rgb(0 0 0 / 0.10)`};return(0,Q.jsx)(o.HeaderAction,{actionId:`local-thread-summary-panel-toggle`,align:`end`,order:250,unifiedSlotPosition:`main`,children:(0,Q.jsxs)(`div`,{"aria-label":`Conversation view`,role:`tablist`,style:c,children:[(0,Q.jsx)(`button`,{"aria-selected":!g,onClick:i,role:`tab`,style:g?l:u,type:`button`,children:`Chat`}),(0,Q.jsx)(`button`,{"aria-selected":g,onClick:a,role:`tab`,style:g?u:l,type:`button`,children:`Summary`})]})})}';
  let localConversationPatched =
    localConversationOriginal.slice(0, summaryToggleStart) +
    summarySegmentedControl +
    localConversationOriginal.slice(summaryToggleEnd);
  localConversationPatched = localConversationPatched
    .replace(summaryScreenStateMarker, summaryScreenState)
    .replace(conversationScreenMarker, conversationSummaryScreen);
  if (
    !localConversationPatched.includes(summarySegmentedControl) ||
    !localConversationPatched.includes(summaryScreenState) ||
    !localConversationPatched.includes(conversationSummaryScreen)
  ) {
    fail("Thread summary screen injection did not apply");
  }
  writeFileSync(localConversationPath, localConversationPatched);

  const appInitialCssBundles = readdirSync(assetsDir).filter((name) =>
    /^app-initial-.*\.css$/.test(name),
  );
  if (appInitialCssBundles.length !== 1) {
    fail(`Expected one app-initial stylesheet, found ${appInitialCssBundles.length}`);
  }
  const appInitialCssPath = join(assetsDir, appInitialCssBundles[0]);
  const appInitialCssOriginal = readFileSync(appInitialCssPath, "utf8");
  const homeUtilityRailCssMarker =
    '._ComposerHomeUtilityBar_dqhd9_4{background-color:var(--color-background-composer-action-bar);padding-inline:var(--spacing)}';
  const transparentHomeUtilityRailCss =
    '._ComposerHomeUtilityBar_dqhd9_4{background-color:transparent;padding-inline:0}';
  if (appInitialCssOriginal.split(homeUtilityRailCssMarker).length !== 2) {
    fail(`The installed Home utility rail stylesheet has an unexpected shape: ${appInitialCssBundles[0]}`);
  }
  const appInitialCssPatched = appInitialCssOriginal.replace(
    homeUtilityRailCssMarker,
    transparentHomeUtilityRailCss,
  );
  if (!appInitialCssPatched.includes(transparentHomeUtilityRailCss)) {
    fail("Transparent Home utility rail injection did not apply");
  }
  writeFileSync(appInitialCssPath, appInitialCssPatched);

  const homeModeBundles = readdirSync(assetsDir).filter((name) =>
    /^home-composer-mode-toggle-.*\.js$/.test(name),
  );
  if (homeModeBundles.length !== 1) {
    fail(`Expected one home composer mode toggle, found ${homeModeBundles.length}`);
  }
  const homeModePath = join(assetsDir, homeModeBundles[0]);
  const homeModeOriginal = readFileSync(homeModePath, "utf8");
  const chatModePaddingMarker = 'p(C,`col-start-1 row-start-1 ps-11 pe-9`,F)';
  const chatModePaddingSecond = 'p(C,`col-start-2 row-start-1`,F)';
  const buildModePaddingMarker = 'p(C,`col-start-2 row-start-1 ps-9 pe-11`,G)';
  const buildModePaddingFirst = 'p(C,`col-start-1 row-start-1`,G)';
  const indicatorPositionsMarker =
    'w={chat:`calc((0% - 0px) * var(--mode-toggle-direction))`,work:`calc((100% - 17px) * var(--mode-toggle-direction))`}';
  const indicatorPositionsBuildFirst =
    'w={chat:`calc((100% - 17px) * var(--mode-toggle-direction))`,work:`calc((0% - 0px) * var(--mode-toggle-direction))`}';
  const buildModeLabelMarker =
    'id:`composer.home.modeToggle.work`,defaultMessage:`Work`,description:`Label for Work mode in the Home composer mode toggle`';
  const buildModeLabel =
    'id:`composer.home.modeToggle.build`,defaultMessage:`Build`,description:`Label for Build mode in the Home composer mode toggle`';
  const modeAriaMarker =
    'defaultMessage:`Composer mode`,description:`Accessible label for the toggle that switches the Home composer between Work and Chat modes`';
  const modeAriaBuild =
    'defaultMessage:`Conversation type`,description:`Accessible label for the toggle that switches the Home composer between Build and Chat`';
  const modeRootMarker =
    'p(`relative isolate inline-grid h-9 max-w-full min-w-0 grid-cols-2 gap-0 rounded-full select-none`,n)';
  const modeCardsRoot =
    'p(`relative isolate inline-grid h-32 w-full max-w-xl min-w-0 grid-cols-2 gap-3 select-none`,n)';
  const modeTrackMarker =
    'O=(0,S.jsx)(`span`,{className:`pointer-events-none absolute inset-x-px top-1/2 z-0 h-8.5 -translate-y-1/2 rounded-full bg-background-mode-toggle-track`,"aria-hidden":`true`})';
  const modeTrackHidden =
    'O=(0,S.jsx)(`span`,{className:`hidden`,"aria-hidden":`true`})';
  const modeIndicatorMarker =
    'A=p(`pointer-events-none relative z-10 col-start-1 row-start-1 rounded-full`,_.indicator)';
  const modeIndicatorHidden = 'A=p(`hidden`,_.indicator)';
  const chatCardStateMarker =
    'F=i===`chat`?`text-default`:`text-mode-toggle-inactive hover:text-default focus-visible:text-default`';
  const chatCardState =
    'F=i===`chat`?`border-heavy bg-surface shadow-sm text-default`:`border-light bg-surface-secondary text-secondary hover:border-default hover:bg-surface hover:text-default focus-visible:text-default`';
  const buildCardStateMarker =
    'G=i===`work`?`text-default`:`text-mode-toggle-inactive hover:text-default focus-visible:text-default`';
  const buildCardState =
    'G=i===`work`?`border-heavy bg-surface shadow-sm text-default`:`border-light bg-surface-secondary text-secondary hover:border-default hover:bg-surface hover:text-default focus-visible:text-default`';
  const modeButtonMarker =
    'C=`cursor-interaction relative z-10 inline-flex h-full min-w-0 items-center justify-center whitespace-nowrap rounded-full px-10 text-sm font-medium @max-xs/home-mode-toggle:px-2.5 disabled:cursor-not-allowed disabled:opacity-40`';
  const modeCardButton =
    'C=`cursor-interaction relative z-10 inline-flex h-full min-w-0 flex-col items-start justify-start gap-1 whitespace-normal rounded-2xl border px-5 py-4 text-start disabled:cursor-not-allowed disabled:opacity-40`';
  const chatCardContentMarker = 'onClick:z,children:B})';
  const chatCardContent =
    'onClick:z,children:(0,S.jsxs)(S.Fragment,{children:[(0,S.jsx)(`span`,{className:`text-base font-medium`,children:B}),(0,S.jsx)(`span`,{className:`text-xs font-normal text-secondary`,children:`Ask questions and explore ideas`})]})})';
  const buildCardContentMarker = 'onClick:Y,children:X})';
  const buildCardContent =
    'onClick:Y,children:(0,S.jsxs)(S.Fragment,{children:[(0,S.jsx)(`span`,{className:`text-base font-medium`,children:X}),(0,S.jsx)(`span`,{className:`text-xs font-normal text-secondary`,children:`Create with files, apps, and code`})]})})';
  for (const marker of [
    chatModePaddingMarker,
    buildModePaddingMarker,
    indicatorPositionsMarker,
    buildModeLabelMarker,
    modeAriaMarker,
    modeRootMarker,
    modeTrackMarker,
    modeIndicatorMarker,
    chatCardStateMarker,
    buildCardStateMarker,
    modeButtonMarker,
    chatCardContentMarker,
    buildCardContentMarker,
  ]) {
    if (homeModeOriginal.split(marker).length !== 2) {
      fail(`The installed home mode toggle has an unexpected shape: ${homeModeBundles[0]}`);
    }
  }
  const homeModePatched = homeModeOriginal
    .replace(chatModePaddingMarker, chatModePaddingSecond)
    .replace(buildModePaddingMarker, buildModePaddingFirst)
    .replace(indicatorPositionsMarker, indicatorPositionsBuildFirst)
    .replace(buildModeLabelMarker, buildModeLabel)
    .replace(modeAriaMarker, modeAriaBuild)
    .replace(modeRootMarker, modeCardsRoot)
    .replace(modeTrackMarker, modeTrackHidden)
    .replace(modeIndicatorMarker, modeIndicatorHidden)
    .replace(chatCardStateMarker, chatCardState)
    .replace(buildCardStateMarker, buildCardState)
    .replace(modeButtonMarker, modeCardButton)
    .replace(chatCardContentMarker, chatCardContent)
    .replace(buildCardContentMarker, buildCardContent);
  if (
    !homeModePatched.includes(indicatorPositionsBuildFirst) ||
    !homeModePatched.includes(buildModePaddingFirst) ||
    !homeModePatched.includes(chatModePaddingSecond) ||
    !homeModePatched.includes(buildModeLabel) ||
    !homeModePatched.includes(modeAriaBuild) ||
    !homeModePatched.includes(modeCardsRoot) ||
    !homeModePatched.includes(modeCardButton) ||
    !homeModePatched.includes(chatCardContent) ||
    !homeModePatched.includes(buildCardContent)
  ) {
    fail("Home mode gateway injection did not apply");
  }
  writeFileSync(homeModePath, homeModePatched);

  const runLocationBundles = readdirSync(assetsDir).filter((name) =>
    /^composer-action-bar-run-location-dropdown-.*\.js$/.test(name),
  );
  if (runLocationBundles.length !== 1) {
    fail(`Expected one Work run-location dropdown, found ${runLocationBundles.length}`);
  }
  const runLocationPath = join(assetsDir, runLocationBundles[0]);
  const runLocationOriginal = readFileSync(runLocationPath, "utf8");
  const runLocationLocalMarker =
    'id:`composer.runLocation.local.optionLabel`,defaultMessage:`On your computer`,description:`Option to run a task on the user\'s computer`';
  const runLocationLocalLabel =
    'id:`composer.runLocation.local.optionLabel.range`,defaultMessage:`Local`,description:`Option to run Build locally on the user\'s computer`';
  const runLocationCloudMarker =
    'id:`composer.runLocation.cloud`,defaultMessage:`In the cloud`,description:`Option to run a task in the cloud`';
  const runLocationCloudLabel =
    'id:`composer.runLocation.cloud.range`,defaultMessage:`Work`,description:`Option to run Build with ChatGPT Work in the cloud`';
  const runLocationTitleMarker =
    'id:`composer.runLocation.title.question`,defaultMessage:`Where should this chat run?`,description:`Header above the run location options in the composer action bar`';
  const runLocationTitle =
    'id:`composer.runLocation.title.question.range`,defaultMessage:`Where should Build run?`,description:`Header above the Build execution location options`';
  const runLocationTriggerMarker =
    'size:`composerSm`,uniform:!0,children:[k,A,j]';
  const runLocationTriggerLabeled =
    'size:`composerSm`,uniform:!1,children:[k,A,j,(0,D.jsx)(`span`,{children:m===`local`?`Local`:m===`cloud`?`Work`:`Run location`})]';
  for (const marker of [
    runLocationLocalMarker,
    runLocationCloudMarker,
    runLocationTitleMarker,
    runLocationTriggerMarker,
  ]) {
    if (runLocationOriginal.split(marker).length !== 2) {
      fail(`The installed run-location dropdown has an unexpected shape: ${runLocationBundles[0]}`);
    }
  }
  const runLocationPatched = runLocationOriginal
    .replace(runLocationLocalMarker, runLocationLocalLabel)
    .replace(runLocationCloudMarker, runLocationCloudLabel)
    .replace(runLocationTitleMarker, runLocationTitle)
    .replace(runLocationTriggerMarker, runLocationTriggerLabeled);
  if (!runLocationPatched.includes(runLocationTriggerLabeled)) {
    fail("Labeled Build run-location trigger injection did not apply");
  }
  writeFileSync(runLocationPath, runLocationPatched);

  const utilityBarBundles = readdirSync(assetsDir).filter((name) =>
    /^composer-utility-bar-.*\.js$/.test(name),
  );
  if (utilityBarBundles.length !== 1) {
    fail(`Expected one composer utility bar, found ${utilityBarBundles.length}`);
  }
  const utilityBarPath = join(assetsDir, utilityBarBundles[0]);
  const utilityBarOriginal = readFileSync(utilityBarPath, "utf8");
  const homeUtilityRailMarker =
    'n=(0,Q.jsx)(Ge,{isHidden:le,trailingControls:Tr,children:e})';
  const homeUtilityControls =
    'n=(0,Q.jsx)(`div`,{className:le?`hidden`:`flex w-fit max-w-full min-w-0 items-center gap-1 px-1`,children:e})';
  if (utilityBarOriginal.split(homeUtilityRailMarker).length !== 2) {
    fail(`The installed Home utility bar has an unexpected shape: ${utilityBarBundles[0]}`);
  }
  const utilityBarPatched = utilityBarOriginal.replace(
    homeUtilityRailMarker,
    homeUtilityControls,
  );
  if (!utilityBarPatched.includes(homeUtilityControls)) {
    fail("Compact Home utility controls injection did not apply");
  }
  writeFileSync(utilityBarPath, utilityBarPatched);

  const textEditorBundles = readdirSync(assetsDir).filter((name) =>
    /^text-file-editor-tab-content\.electron-.*\.js$/.test(name),
  );
  if (textEditorBundles.length === 0) {
    fail("Expected at least one text-file editor bundle");
  }
  const supportedExtensionsMarker =
    "bash.bat.bazel.bzl.c.c++.c++m.cc.cjs.cmd.cpp";
  const editorKeydownMarker =
    "onKeyDownCapture:e=>{let t=e.key.toLowerCase();(e.key===`Tab`||(e.metaKey||e.ctrlKey)&&(t===`y`||t===`z`))&&It(e)}";
  const editorToolbarMarker =
    "zt==null?(0,Y.jsx)(Al,{canRedo:Bt&&Ge.canRedo,canUndo:Bt&&Ge.canUndo,hasSaveError:!1,isSaving:!1,onRedo:()=>I.redo(),onToggleVim:void 0,onUndo:()=>I.undo(),vimMode:void 0}):null";
  const patchedTextEditorPaths = [];
  for (const textEditorBundle of textEditorBundles) {
    const textEditorPath = join(assetsDir, textEditorBundle);
    const textEditorOriginal = readFileSync(textEditorPath, "utf8");
    if (!textEditorOriginal.includes(supportedExtensionsMarker)) continue;
    if (
      !textEditorOriginal.includes(editorKeydownMarker) ||
      !textEditorOriginal.includes(editorToolbarMarker)
    ) {
      fail(`The installed editable file surface has an unexpected shape: ${textEditorBundle}`);
    }
    const textEditorPatched = textEditorOriginal
      .replace(
        supportedExtensionsMarker,
        "bash.bat.bazel.bzl.c.c++.c++m.cc.cjs.cmd.cpp.range",
      )
      .replace(
        editorKeydownMarker,
        "onKeyDownCapture:e=>{let t=e.key.toLowerCase();if((e.metaKey||e.ctrlKey)&&t===`s`){e.preventDefault(),He.current?.saveUntilClean();return}(e.key===`Tab`||(e.metaKey||e.ctrlKey)&&(t===`y`||t===`z`))&&It(e)}",
      )
      .replace(
        editorToolbarMarker,
        "zt==null?(0,Y.jsxs)(Y.Fragment,{children:[(0,Y.jsx)(Al,{canRedo:Bt&&Ge.canRedo,canUndo:Bt&&Ge.canUndo,hasSaveError:!1,isSaving:!1,onRedo:()=>I.redo(),onToggleVim:void 0,onUndo:()=>I.undo(),vimMode:void 0}),F.isReadOnly?null:(0,Y.jsx)(Sn,{\"aria-label\":\"Save file (Command-S)\",className:\"absolute right-4 bottom-16 z-10\",color:\"secondary\",disabled:!He.current?.hasUnsavedChanges,onClick:()=>He.current?.saveUntilClean(),size:\"small\",children:\"Save\"})]}):null",
      );
    if (textEditorPatched === textEditorOriginal) {
      fail(`Range extension injection did not change ${textEditorBundle}`);
    }
    if (
      !textEditorPatched.includes("He.current?.saveUntilClean()") ||
      !textEditorPatched.includes("Save file (Command-S)")
    ) {
      fail(`Editable save controls were not injected into ${textEditorBundle}`);
    }
    writeFileSync(textEditorPath, textEditorPatched);
    patchedTextEditorPaths.push(textEditorPath);
  }
  if (patchedTextEditorPaths.length === 0) {
    fail("No compatible text-file editor extension list was found");
  }

  const originalUnpackedRoots = unpackedRoots(originalHeader);
  const unpackDirectories = originalUnpackedRoots
    .filter((entry) => entry.directory)
    .map((entry) => entry.path);
  const unpackFiles = originalUnpackedRoots
    .filter((entry) => !entry.directory)
    .map((entry) => `**/${entry.path}`);
  await createPackageWithOptions(extractedDir, packedAsar, {
    unpack: globAlternatives(unpackFiles),
    unpackDir: globAlternatives(unpackDirectories),
  });
  const repackedUnpackedFiles = unpackedFiles(getRawHeader(packedAsar).header).sort();
  if (JSON.stringify(repackedUnpackedFiles) !== JSON.stringify(originalUnpackedFiles)) {
    const originalSet = new Set(originalUnpackedFiles);
    const repackedSet = new Set(repackedUnpackedFiles);
    const missing = originalUnpackedFiles.filter((path) => !repackedSet.has(path));
    const extra = repackedUnpackedFiles.filter((path) => !originalSet.has(path));
    fail(
      `Repacked ASAR did not preserve the original unpacked-file contract ` +
        `(missing ${missing.length}: ${missing.slice(0, 3).join(", ")}; ` +
        `extra ${extra.length}: ${extra.slice(0, 3).join(", ")})`,
    );
  }
  cpSync(packedAsar, asarPath);
  const targetUnpacked = `${asarPath}.unpacked`;
  rmSync(targetUnpacked, { recursive: true, force: true });
  cpSync(`${packedAsar}.unpacked`, targetUnpacked, { recursive: true });

  const { headerString } = getRawHeader(asarPath);
  const hash = createHash("sha256").update(headerString).digest("hex");
  const plistPath = join(targetApp, "Contents", "Info.plist");
  for (const [key, value] of [
    ["CFBundleIdentifier", "com.openai.codex.range"],
    ["CFBundleDisplayName", "ChatGPT Range"],
    ["CFBundleName", "ChatGPT Range"],
  ]) {
    execFileSync("/usr/libexec/PlistBuddy", [
      "-c",
      `Set :${key} ${value}`,
      plistPath,
    ]);
  }
  execFileSync("/usr/libexec/PlistBuddy", [
    "-c",
    `Set :ElectronAsarIntegrity:Resources/app.asar:hash ${hash}`,
    plistPath,
  ]);

  const macOSDir = join(targetApp, "Contents", "MacOS");
  const appExecutable = join(macOSDir, "ChatGPT");
  const appRuntime = join(macOSDir, "ChatGPT Range Runtime");
  renameSync(appExecutable, appRuntime);
  execFileSync("/usr/bin/xcrun", [
    "clang",
    "-Os",
    join(projectDir, "launcher.c"),
    "-o",
    appExecutable,
  ]);

  execFileSync("codesign", [
    "--force",
    "--deep",
    "--sign",
    "-",
    targetApp,
  ], { stdio: "inherit" });

  console.log(`Created ${targetApp}`);
  console.log(`Patched ${basename(providerPath)}`);
  console.log(`Patched ${basename(appInitialPath)}`);
  console.log(`Patched ${basename(appInitialCssPath)}`);
  console.log(`Patched ${basename(homeModePath)}`);
  console.log(`Patched ${basename(runLocationPath)}`);
  console.log(`Patched ${basename(utilityBarPath)}`);
  for (const path of patchedTextEditorPaths) {
    console.log(`Patched ${basename(path)}`);
  }
  console.log(`app.asar sha256 ${hash}`);
} catch (error) {
  if (existsSync(targetApp)) {
    rmSync(targetApp, { recursive: true, force: true });
  }
  throw error;
} finally {
  rmSync(tempRoot, { recursive: true, force: true });
}
