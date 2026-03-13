window.Neat = window.Neat || {};
window.Neat.components = window.Neat.components || {};

window.Neat.components["TextField"] = function (host) {
  if (host.neat && host.neat.props) {
    return;
  }

  function applyValue(value) {
    if (value === undefined || value === null) {
      if (host.value !== "") {
        host.value = "";
      }
      return;
    }
    if (host.value !== value) {
      host.value = value;
    }
  }

  var props = {};
  Object.defineProperty(props, 1, {
    configurable: true,
    enumerable: true,
    get: function () {
      return host._neatBinding || host.value;
    },
    set: function (val) {
      if (val && typeof val === "object" && "value" in val) {
        host._neatBinding = val;
        applyValue(val.value);
      } else {
        host._neatBinding = null;
        applyValue(val);
      }
    },
  });

  host.addEventListener("input", function () {
    if (host._neatBinding) {
      host._neatBinding.value = host.value;
    }
  });

  host.neat = host.neat || {};
  host.neat.props = host.neat.props || props;
  host.neat.update = host.neat.update || function () {};

  if (host._pendingProps) {
    for (const key in host._pendingProps) {
      host.neat.props[key] = host._pendingProps[key];
    }
    delete host._pendingProps;
  }
};
