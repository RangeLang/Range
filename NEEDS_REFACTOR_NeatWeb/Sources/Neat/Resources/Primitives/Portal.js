window.Neat = window.Neat || {};
window.Neat.components = window.Neat.components || {};

window.Neat.components["Portal"] = function (host) {
  if (!host || host._neatPortalMounted) {
    return;
  }

  var selector = host.getAttribute("data-portal-target") || "body";
  var target =
    selector === "body" ? document.body : document.querySelector(selector);

  if (!target && selector.charAt(0) === "#") {
    var fallback = document.createElement("div");
    fallback.id = selector.slice(1);
    document.body.appendChild(fallback);
    target = fallback;
  }

  if (!target) {
    return;
  }

  var root = host._neatPortalRoot;
  if (!root) {
    root = document.createElement("div");
    var id = host.getAttribute("data-neat-idx") || "";
    if (id) {
      root.setAttribute("data-neat-portal-root", id);
    }
    target.appendChild(root);
    host._neatPortalRoot = root;
  }

  while (host.firstChild) {
    root.appendChild(host.firstChild);
  }

  host._neatPortalMounted = true;
};
