window.Neat = window.Neat || {};
window.Neat.components = window.Neat.components || {};

window.Neat.components["Toggle"] = function (host) {
  if (host.neat && host.neat.props) {
    return;
  }

  function applyChecked(value) {
    var checked = !!value;
    host._neatChecked = checked;
    host.style.backgroundColor = checked ? "#111111" : "#cfcfcf";
  }

  var props = {};
  Object.defineProperty(props, 0, {
    configurable: true,
    enumerable: true,
    get: function () {
      return host._neatBinding || host._neatChecked || false;
    },
    set: function (val) {
      if (val && typeof val === "object" && "value" in val) {
        host._neatBinding = val;
        applyChecked(val.value);
      } else {
        host._neatBinding = null;
        applyChecked(val);
      }
    },
  });

  function toggle() {
    var next = host._neatBinding
      ? !host._neatBinding.value
      : !host._neatChecked;
    if (host._neatBinding) {
      host._neatBinding.value = next;
    } else {
      applyChecked(next);
    }
  }

  host.addEventListener("click", function () {
    toggle();
  });

  host.addEventListener("keydown", function (event) {
    if (event.key === " " || event.key === "Enter") {
      event.preventDefault();
      toggle();
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
