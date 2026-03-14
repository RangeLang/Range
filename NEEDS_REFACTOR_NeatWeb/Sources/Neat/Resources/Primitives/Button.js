window.Neat = window.Neat || {};
window.Neat.components = window.Neat.components || {};

window.Neat.components["Button"] = function (host) {
    if (host.neat && host.neat.props) {
        return;
    }

    var props = {};
    Object.defineProperty(props, 0, {
        configurable: true,
        enumerable: true,
        get: function () {
            return host.textContent;
        },
        set: function (val) {
            host.textContent = val;
        }
    });

    host.neat = host.neat || {};
    host.neat.props = host.neat.props || props;
    host.neat.update = host.neat.update || function () {};
};
