const routes = [{"page":"HomePage","path":"\/"},{"page":"AboutPage","path":"\/about"},{"path":"\/dashboard\/settings","page":"AboutPage"}];

function create_HomePage() {
  const __state = {
    homepage_count: 0
  };
  return {
    render() {
      return `<div class="vstack">
  <div class="vstack">
  <span>Neat</span>
  <span>Swift-shaped UI compiled for the browser.</span>
  </div>
  <div class="vstack">
  <span>Ship Faster</span>
  <span>Build with shared core components and styling.</span>
  </div>
  <div class="vstack">
  <span>Core Card</span>
  <span>This component is loaded from .neat/Core/V1/Components.</span>
  </div>
  <div style="background: #3b82f6;"><span>Count: ${__state.homepage_count}</span></div>
  <button data-neat-click="button-0">Add</button>
  </div>`;
    },
    bind(root, rerender) {
      const button_0 = root.querySelector('[data-neat-click="button-0"]');
      if (button_0) {
        button_0.onclick = () => {
          __state.homepage_count = __state.homepage_count + 1;
          rerender();
        };
      }
    }
  };
}

function create_AboutPage() {
  const __state = {};
  return {
    render() {
      return `<div class="vstack">
  <span>About</span>
  <span>This project was created with neat create.</span>
  </div>`;
    },
    bind(root, rerender) {
      return;
    }
  };
}

const pageFactories = { "HomePage": create_HomePage, "AboutPage": create_AboutPage };

const mount = document.getElementById("app");
if (!mount) {
  throw new Error("Missing #app mount point.");
}

let currentRoute = null;
let currentPage = null;

function routeForPath(pathname) {
  return routes.find((route) => route.path === pathname) ?? routes[0] ?? null;
}

function routeLabel(path) {
  if (window.NeatCore && typeof window.NeatCore.routeLabel === "function") {
    return window.NeatCore.routeLabel(path);
  }
  if (path === "/") {
    return "Home";
  }
  const segment = path.split("/").filter(Boolean).pop() ?? "Route";
  return segment.charAt(0).toUpperCase() + segment.slice(1);
}

function renderNavigation() {
  const items = routes.map((route) => {
    const isActive = currentRoute && currentRoute.path === route.path;
    return `<a class="neat-nav-link${isActive ? " active" : ""}" href="${route.path}">${routeLabel(route.path)}</a>`;
  }).join("");
  return `<nav class="neat-nav">${items}</nav>`;
}

function setRoute(pathname, options = {}) {
  const next = routeForPath(pathname);
  currentRoute = next;
  currentPage = next && pageFactories[next.page] ? pageFactories[next.page]() : null;

  if (!options.fromPopState && next) {
    const targetPath = next.path;
    if (window.location.pathname !== targetPath) {
      window.history.pushState({}, "", targetPath);
    }
  }
}

function bindNavigation() {
  const links = mount.querySelectorAll(".neat-nav-link");
  links.forEach((link) => {
    link.onclick = (event) => {
      event.preventDefault();
      const href = link.getAttribute("href") || "/";
      setRoute(href);
      rerender();
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
  setRoute(window.location.pathname, { fromPopState: true });
  rerender();
});

let hmr = { version: null };
async function pollHMR() {
  try {
    const res = await fetch(`./.hmr-version?ts=${Date.now()}`, { cache: "no-store" });
    if (!res.ok) {
      return;
    }
    const next = (await res.text()).trim();
    if (!next) {
      return;
    }
    if (hmr.version === null) {
      hmr.version = next;
      return;
    }
    if (next !== hmr.version) {
      window.location.reload();
    }
  } catch {
    // Ignore transient polling failures while recompiling.
  }
}

setInterval(pollHMR, 1000);
pollHMR();

setRoute(window.location.pathname, { fromPopState: true });
rerender();

console.log("Compiled NeatExample", routes);