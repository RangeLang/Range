import { startHMR } from "./hmr.js";

const routes = __NEAT_ROUTES_JSON__;
const pageLoaders = { __NEAT_PAGE_LOADERS__ };
const pageFactories = new Map();

const mount = document.getElementById("app");
if (!mount) {
  throw new Error("Missing #app mount point.");
}

let currentRoute = null;
let currentPage = null;
let routeVersion = { value: 0 };

function routeForPath(pathname) {
  return routes.find((route) => route.path === pathname) ?? routes[0] ?? null;
}

function routeLabel(path) {
  if (path === "/") {
    return "Home";
  }
  const segment = path.split("/").filter(Boolean).pop() ?? "Route";
  return segment.charAt(0).toUpperCase() + segment.slice(1);
}

function renderNavigation() {
  const items = routes
    .map((route) => {
      const isActive = currentRoute && currentRoute.path === route.path;
      return `<a class="neat-nav-link${isActive ? " active" : ""}" href="${route.path}">${routeLabel(route.path)}</a>`;
    })
    .join("");
  return `<nav class="neat-nav">${items}</nav>`;
}

async function loadPageFactory(pageName) {
  if (pageFactories.has(pageName)) {
    return pageFactories.get(pageName);
  }

  const loader = pageLoaders[pageName];
  if (!loader) {
    return null;
  }

  const module = await loader();
  const factory = module.createPage || module.default;
  if (typeof factory !== "function") {
    throw new Error(`Page module '${pageName}' does not export createPage().`);
  }
  pageFactories.set(pageName, factory);
  return factory;
}

async function setRoute(pathname, options = {}) {
  const version = ++routeVersion.value;
  const next = routeForPath(pathname);
  currentRoute = next;

  if (!options.fromPopState && next) {
    const targetPath = next.path;
    if (window.location.pathname !== targetPath) {
      window.history.pushState({}, "", targetPath);
    }
  }

  if (!next) {
    currentPage = null;
    rerender();
    return;
  }

  const factory = await loadPageFactory(next.page);
  if (version !== routeVersion.value) {
    return;
  }
  currentPage = factory ? factory() : null;
  rerender();
}

function bindNavigation() {
  const links = mount.querySelectorAll(".neat-nav-link");
  links.forEach((link) => {
    link.onclick = async (event) => {
      event.preventDefault();
      const href = link.getAttribute("href") || "/";
      await setRoute(href);
    };
  });
}

function rerender() {
  if (!currentPage) {
    mount.innerHTML = `
      ${renderNavigation()}
      <main><h1>No route found</h1></main>
    `;
    bindNavigation();
    return;
  }

  mount.innerHTML = `
    ${renderNavigation()}
    ${currentPage.render()}
  `;
  bindNavigation();
  currentPage.bind(mount, rerender);
}

window.addEventListener("popstate", () => {
  void setRoute(window.location.pathname, { fromPopState: true });
});

startHMR({ versionPath: "./.hmr-version", intervalMS: 1000 });

void setRoute(window.location.pathname, { fromPopState: true });

console.log("Compiled __NEAT_APP_NAME__", routes);
